import AidenteShared
import Foundation
import Defaults
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import os.log
import smc_power

@MainActor
class IOKitService {
    private var powerSourceNotification: CFRunLoopSource?
    private var notificationPort: IONotificationPortRef?
    private var interestNotification: io_object_t = 0
    private var batteryService: io_service_t = 0
    private var observedFull = false
    var onConnection: ((PowerConnectionSnapshot) -> Void)?
    private var fullRefresh: Task<Void,Never>?
    private var lastConnection: PowerConnectionSnapshot?

    private var continuation: AsyncStream<(BatteryMetrics, AdapterMetrics)>.Continuation?

    private let logger = Logger(
        subsystem: "com.aidente.app",
        category: "IOKitService"
    )

    func metricsStream() -> AsyncStream<(BatteryMetrics, AdapterMetrics)> {
        AsyncStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stop()
                }
            }

            self.startNotifications()
        }
    }

    private func startNotifications() {
        logger.info("Starting IOKit monitoring")

        batteryService = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        if batteryService == 0 {
            logger.error("Failed to get AppleSmartBattery service")
        }

        guard batteryService != 0 else { return }

        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notificationPort else {
            logger.error("Failed to create IONotificationPort")
            return
        }

        let notificationSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), notificationSource, .commonModes)

        let context = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(self).toOpaque()
        )

        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<IOKitService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerNotificationReceived() }
        }, context)?.takeRetainedValue() {
            powerSourceNotification = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        let callback: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            let monitor = Unmanaged<IOKitService>.fromOpaque(refcon)
                .takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.powerNotificationReceived()
            }
        }

        let result = IOServiceAddInterestNotification(
            notificationPort,
            batteryService,
            kIOGeneralInterest,
            callback,
            context,
            &interestNotification
        )

        if result == KERN_SUCCESS {
            logger.info("IORegistry interest notification registered for AppleSmartBattery")
        } else {
            logger.error("Failed to register interest notification: \(result)")
        }

        powerNotificationReceived()
    }

    private func powerNotificationReceived() {
        let providingAC = IOPSCopyPowerSourcesInfo().flatMap { snapshot in
            IOPSGetProvidingPowerSourceType(snapshot.takeRetainedValue())?.takeUnretainedValue() as String?
        }.map { $0 == kIOPSACPowerValue }
        let connected: Bool? = getPropertyValue(batteryService, key: "ExternalConnected")
        let charging: Bool = getPropertyValue(batteryService, key: "IsCharging") ?? false
        let state = PowerConnectionSnapshot.resolve(
            externalConnected: connected, providingAC: providingAC ?? lastConnection?.connected ?? false,
            charging: charging
        )
        if state != lastConnection { lastConnection=state;onConnection?(state) }
        // Let the status item paint before enumerating capabilities, adapter profiles and health.
        guard fullRefresh == nil else { return }
        fullRefresh=Task { @MainActor [weak self] in
            try? await Task.sleep(for:.milliseconds(25))
            guard !Task.isCancelled else { return };self?.fullRefresh=nil;self?.emitMetrics()
        }
    }

    private func stop() {
        fullRefresh?.cancel();fullRefresh=nil
        if let source = powerSourceNotification {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceNotification = nil
        }
        if interestNotification != 0 {
            IOObjectRelease(interestNotification)
            interestNotification = 0
        }
        if let notificationPort {
            let source = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        if batteryService != 0 {
            IOObjectRelease(batteryService)
            batteryService = 0
        }
        continuation = nil
    }

    func refreshMetrics() {
        guard batteryService != 0 else { return }
        emitMetrics()
    }

    private func emitMetrics() {
        logger.debug("IOKit notification triggered")

        let powerInfo = SystemBatteryReading.powerSource()
        guard let displayedPercent = try? SMCBattery.macOSPercentage(powerSource: powerInfo) else {
            logger.error("No valid internal battery percentage; skipping this battery snapshot")
            return
        }
        var batteryMetrics = BatteryMetrics()
        var adapterMetrics = AdapterMetrics()

        let capacitySnapshot = SystemBatteryReading.registrySnapshot(service: batteryService)
        let rawCapacity = SystemBatteryReading.rawCapacity(in: capacitySnapshot)
        batteryMetrics.batteryPercentage = displayedPercent
        batteryMetrics.hardwareBatteryPercentage = rawCapacity.map {
            Int(min(100, Double($0.current) / Double($0.full) * 100))
        } ?? displayedPercent
        batteryMetrics.hasHardwarePercentage = rawCapacity != nil

        batteryMetrics.isFullyCharged = getPropertyValue(batteryService, key: "FullyCharged") ?? false
        batteryMetrics.condition = powerInfo?[kIOPSBatteryHealthConditionKey] as? String ?? powerInfo?[kIOPSBatteryHealthKey] as? String ?? "—"
        let full = batteryMetrics.isFullyCharged && batteryMetrics.batteryPercentage >= 100
        if full && !observedFull && !CompleteUninstaller.shared.isRunning { Defaults[.lastObservedFullCharge] = Date().timeIntervalSince1970 }
        observedFull = full
        let registryConnection: Bool? = getPropertyValue(batteryService, key: "ExternalConnected")
        let systemPowerSource = powerInfo?[kIOPSPowerSourceStateKey] as? String
        let registryCharging: Bool? = getPropertyValue(batteryService, key: "IsCharging")
        let connection = PowerConnectionSnapshot.resolve(
            externalConnected: registryConnection,
            providingAC: systemPowerSource.map { $0 == kIOPSACPowerValue } ?? lastConnection?.connected ?? false,
            charging: (powerInfo?[kIOPSIsChargingKey] as? Bool) ?? registryCharging ?? false
        )
        batteryMetrics.isCharging = connection.charging
        if batteryMetrics.isCharging {
            batteryMetrics.timeRemaining = getTimeToFull(powerInfo: powerInfo) ?? -1
        } else {
            batteryMetrics.timeRemaining = getTimeRemaining(powerInfo: powerInfo) ?? -1
        }

        batteryMetrics.rawCurrentCapacityMilliampHours = rawCapacity?.current
        batteryMetrics.rawFullCapacityMilliampHours = rawCapacity?.full
        let capacities = getBatteryCapacities(
            rawCapacity: rawCapacity,
            snapshot: capacitySnapshot,
            displayedPercentage: batteryMetrics.batteryPercentage
        )
        batteryMetrics.currentCapacityMilliampHours = capacities.current
        batteryMetrics.estimatedFullChargeCapacityMilliampHours = capacities.full
        batteryMetrics.designCapacityMilliampHours = capacities.design
        batteryMetrics.batteryHealth =
            capacities.design > 0
            ? Double(capacities.full) * 100 / Double(capacities.design)
            : 0

        batteryMetrics.externalConnected = connection.connected

        let adapterSpecification = getAdapterSpecification()
        let adapterDetails = (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]) ?? getRegistryAdapterDetails() ?? [:]
        adapterMetrics.name = adapterDetails["Name"] as? String ?? ""
        adapterMetrics.manufacturer = adapterDetails["Manufacturer"] as? String ?? ""
        adapterMetrics.firmwareVersion = adapterDetails["FwVersion"] as? String ?? ""
        adapterMetrics.maximumSupportedPower = adapterSpecification.maximumPower
        adapterMetrics.protocolName = adapterSpecification.protocolName
        adapterMetrics.powerProfiles = adapterSpecification.profiles
        adapterMetrics.adapterConnected = batteryMetrics.externalConnected

        if let temp = getBatteryTemperature(powerInfo: powerInfo) {
            batteryMetrics.batteryTemperature = temp
        }

        batteryMetrics.cycleCount =
            getPropertyValue(batteryService, key: "CycleCount") ?? 0

        logger.debug(
            "IOKit metrics: battery=\(batteryMetrics.batteryPercentage)%, hardwareBattery=\(batteryMetrics.hardwareBatteryPercentage)%, health=\(batteryMetrics.batteryHealth)%, currentCapacity=\(batteryMetrics.currentCapacityMilliampHours)mAh, estimatedFullCapacity=\(batteryMetrics.estimatedFullChargeCapacityMilliampHours)mAh, designCapacity=\(batteryMetrics.designCapacityMilliampHours)mAh, charging=\(batteryMetrics.isCharging), temp=\(batteryMetrics.batteryTemperature)°C, cycles=\(batteryMetrics.cycleCount), timeRemaining=\(batteryMetrics.timeRemaining), externalConnected=\(batteryMetrics.externalConnected), adapterConnected=\(adapterMetrics.adapterConnected)"
        )

        continuation?.yield((batteryMetrics, adapterMetrics))
    }

    private nonisolated func getPropertyValue<T>(_ service: io_service_t, key: String) -> T? {
        if let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0),
           let value = prop.takeRetainedValue() as? T { return value }
        let nested = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
        return nested?[key] as? T
    }

    private func getTimeRemaining(powerInfo: [String: Any]?) -> Int? {
        guard let timeToEmpty = powerInfo?[kIOPSTimeToEmptyKey] as? Int,
              timeToEmpty > 0,
              timeToEmpty != Int(kIOPSTimeRemainingUnknown) else {
            return nil
        }

        return timeToEmpty
    }

    private func getTimeToFull(powerInfo: [String: Any]?) -> Int? {
        guard let timeToFull = powerInfo?[kIOPSTimeToFullChargeKey] as? Int,
              timeToFull > 0,
              timeToFull != Int(kIOPSTimeRemainingUnknown) else {
            return nil
        }

        return timeToFull
    }

    private func getAdapterSpecification() -> (
        maximumPower: Double,
        protocolName: String,
        profiles: [AdapterPowerProfile]
    ) {
        let registryDetails = getRegistryAdapterDetails()
        var maximumPower = 0.0

        // Apple documents the Watts value returned by
        // IOPSCopyExternalPowerAdapterDetails as the attached adapter wattage.
        if let unmanagedDetails = IOPSCopyExternalPowerAdapterDetails() {
            let details = unmanagedDetails.takeRetainedValue() as NSDictionary
            if let watts = details["Watts"] as? NSNumber, watts.doubleValue > 0 {
                maximumPower = watts.doubleValue
            }
        }

        if maximumPower <= 0,
           let watts = registryDetails?["Watts"] as? NSNumber {
            maximumPower = watts.doubleValue
        }

        let activeIndex = (registryDetails?["UsbHvcHvcIndex"] as? NSNumber)?.intValue
        let menu = registryDetails?["UsbHvcMenu"] as? [[String: Any]] ?? []
        var profiles = menu.compactMap { item -> AdapterPowerProfile? in
            guard let voltageMillivolts = (item["MaxVoltage"] as? NSNumber)?.doubleValue,
                  let currentMilliamps = (item["MaxCurrent"] as? NSNumber)?.doubleValue,
                  voltageMillivolts > 0, currentMilliamps > 0 else {
                return nil
            }
            let voltage = voltageMillivolts / 1_000
            let current = currentMilliamps / 1_000
            let index = (item["Index"] as? NSNumber)?.intValue
            return AdapterPowerProfile(
                voltage: voltage,
                current: current,
                power: voltage * current,
                isActive: index == activeIndex
            )
        }
        profiles.sort { $0.voltage < $1.voltage }

        if maximumPower <= 0 {
            maximumPower = profiles.map(\.power).max() ?? 0
        }

        let description = (registryDetails?["Description"] as? String)?
            .lowercased() ?? ""
        let isWireless = (registryDetails?["IsWireless"] as? NSNumber)?.boolValue ?? false
        let protocolName: String
        if isWireless {
            protocolName = "Wireless"
        } else if !profiles.isEmpty || description.contains("pd") {
            protocolName = "USB PD"
        } else {
            protocolName = ""
        }

        return (maximumPower, protocolName, profiles)
    }

    private func getRegistryAdapterDetails() -> [String: Any]? {
        if let details: [String: Any] = getPropertyValue(
            batteryService,
            key: "AdapterDetails"
        ) {
            return details
        }

        let rawDetails: [[String: Any]] = getPropertyValue(
            batteryService,
            key: "AppleRawAdapterDetails"
        ) ?? []
        return rawDetails.max { lhs, rhs in
            let left = (lhs["Watts"] as? NSNumber)?.doubleValue ?? 0
            let right = (rhs["Watts"] as? NSNumber)?.doubleValue ?? 0
            return left < right
        }
    }

    private func getBatteryTemperature(powerInfo: [String: Any]?) -> Double? {
        if let powerInfo,
            let temp = powerInfo[kIOPSTemperatureKey] as? Int,
            temp > 0
        {
            return decikelvinToCelsius(temp)
        }

        guard
            let temp: Int = getPropertyValue(
                batteryService,
                key: "Temperature"
            ),
            temp > 0, temp <= 5000
        else {
            return nil
        }

        return decikelvinToCelsius(temp)
    }

    private nonisolated func decikelvinToCelsius(_ decikelvin: Int) -> Double? {
        let celsius = (Double(decikelvin) / 10.0) - 273.15
        return (0...80).contains(celsius) ? celsius : nil
    }

    private func getBatteryCapacities(
        rawCapacity: SystemBatteryReading.RawCapacity?,
        snapshot: [String: Any]?,
        displayedPercentage: Int
    ) -> (current: Int, full: Int, design: Int) {
        let nested = snapshot?["BatteryData"] as? [String: Any]
        func value(_ key: String) -> Int? {
            (snapshot?[key] as? Int) ?? (nested?[key] as? Int)
        }
        let fullCapacity: Int =
            rawCapacity?.full ?? value("AppleRawMaxCapacity")
            ?? value("NominalChargeCapacity") ?? value("FullChargeCapacity")
            ?? 0
        let designCapacity = value("DesignCapacity") ?? 0

        let estimatedCurrentCapacity =
            fullCapacity > 0
            ? Int(exactly: (Double(fullCapacity) * Double(displayedPercentage) / 100).rounded()) ?? 0
            : 0
        let currentCapacity = rawCapacity?.current ?? value("AppleRawCurrentCapacity") ?? estimatedCurrentCapacity

        return (currentCapacity, fullCapacity, designCapacity)
    }
}
