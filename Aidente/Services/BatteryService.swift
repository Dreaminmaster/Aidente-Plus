import Foundation
import AidenteShared
import Observation
import os.log
import smc_power

enum XPCError: LocalizedError {
    case helperUnavailable
    case timeout
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            AidenteL10n.t("充电控制服务不可用", "Charging control service is unavailable")
        case .timeout:
            AidenteL10n.t(
                "充电控制服务连接超时",
                "Charging control service connection timed out"
            )
        case .commandFailed(let message):
            AidenteL10n.t(
                "控制命令失败：\(message)",
                "Control command failed: \(message)"
            )
        }
    }
}

final class XPCCommandReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

@MainActor
@Observable
class BatteryService {
    private(set) var nativeChargeLimits: [Int] = []
    var usesNativeChargeLimit: Bool { !nativeChargeLimits.isEmpty }
    var metrics = BatteryMetrics()
    var adapterMetrics = AdapterMetrics()
    private(set) var componentPower: ComponentPowerReading?
    private(set) var controlState = BatteryControlState()
    private(set) var deviceCapabilities = DeviceCapabilities(
        chargingControl: false,
        adapterControl: false,
        hasMagSafe: false,
        magsafeLEDControl: false
    )

    private let xpcManager = SMCReaderConnection(
        serviceName: "com.aidente.app.reader"
    )
    private let ioKitService = IOKitService()

    private var ioKitMonitorTask: Task<Void, Never>?
    private var smcPollTask: Task<Void, Never>?
    private var fastPollingRequested = false
    private var backgroundPollingRequested = false
    private var delayedPollTask: Task<Void, Never>?

    private let logger = Logger(
        subsystem: "com.aidente.app",
        category: "BatteryService"
    )

    init() {
        logger.info("BatteryService initialized")
        xpcManager.connect()
        startIOKitMonitoring()
    }

    private var lastTemperatureSampleDate: Date?
    private(set) var lastPowerSampleDate: Date?

    func loadCapabilities() async {
        do {
            let capabilities: DeviceCapabilities = try await withCheckedThrowingContinuation { continuation in
                let result = XPCCommandReply(continuation)
                guard let helper = xpcManager.getHelper(errorHandler: { error in
                    result.finish(.failure(error))
                }) else {
                    result.finish(.failure(XPCError.helperUnavailable))
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    result.finish(.failure(XPCError.timeout))
                }
                helper.getCapabilities { chargingControl, adapterControl, hasMagSafe, magsafeLEDControl in
                    result.finish(.success(DeviceCapabilities(
                        chargingControl: chargingControl,
                        adapterControl: adapterControl,
                        hasMagSafe: hasMagSafe,
                        magsafeLEDControl: magsafeLEDControl
                    )))
                }
            }
            let nativeCSV: String = try await withCheckedThrowingContinuation { continuation in
                let result = XPCCommandReply(continuation)
                guard let helper = xpcManager.getHelper(errorHandler: { result.finish(.failure($0)) }) else {
                    result.finish(.failure(XPCError.helperUnavailable)); return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) { result.finish(.failure(XPCError.timeout)) }
                helper.nativeChargeLimits { result.finish(.success($0)) }
            }
            self.nativeChargeLimits = nativeCSV.split(separator: ",").compactMap { Int($0) }.filter { (80...100).contains($0) }.sorted()
            self.deviceCapabilities = capabilities
            logger.info(
            "Capabilities loaded: charging=\(capabilities.chargingControl), adapter=\(capabilities.adapterControl), magSafe=\(capabilities.hasMagSafe)"
            )
        } catch {
            logger.error("Capability refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshAfterWake() async {
        ioKitService.refreshMetrics()
        await Task.yield()
        await loadCapabilities()
        scheduleSinglePoll(delay: .seconds(1))
    }

    private func startIOKitMonitoring() {
        logger.info("Starting IOKit monitoring in main app")
        ioKitMonitorTask = Task {
            for await (newBatteryMetrics, newAdapterMetrics) in self.ioKitService.metricsStream() {
                guard !Task.isCancelled else { break }
                self.handleIOKitUpdate(newBatteryMetrics, adapterUpdate: newAdapterMetrics)
            }
        }
    }

    func enableFastPolling() { fastPollingRequested = true; updatePolling() }
    func setBackgroundPolling(_ enabled: Bool) { backgroundPollingRequested = enabled; updatePolling() }
    private func updatePolling() {
        smcPollTask?.cancel(); smcPollTask = nil
        guard (fastPollingRequested || backgroundPollingRequested), !CompleteUninstaller.shared.isRunning else { return }
        smcPollTask = Task {
            while !Task.isCancelled {
                await self.pollSMCOnce()
                do { try await Task.sleep(for: .seconds(self.fastPollingRequested ? 1 : 15)) } catch { return }
            }
        }
    }

    func scheduleSinglePoll(delay: Duration = .seconds(3)) {
        delayedPollTask?.cancel()
        delayedPollTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self.pollSMCOnce()
        }
    }

    func disableFastPolling() { fastPollingRequested = false; updatePolling() }

    private func fetchSMCBatteryData() async -> SMCBatteryReading? {
        try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SMCBatteryReading, Error>) in
            let result = XPCCommandReply(continuation)
            guard let helper = xpcManager.getHelper(errorHandler: { result.finish(.failure($0)) }) else {
                result.finish(.failure(XPCError.helperUnavailable)); return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { result.finish(.failure(XPCError.timeout)) }
            helper.readBatteryMetrics { voltage, current, power in
                result.finish(.success(SMCBatteryReading(batteryVoltage: voltage, batteryCurrent: current, batteryPower: power)))
            }
        }
    }

    private func fetchSMCAdapterData() async -> SMCAdapterReading? {
        try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SMCAdapterReading, Error>) in
            let result = XPCCommandReply(continuation)
            guard let helper = xpcManager.getHelper(errorHandler: { result.finish(.failure($0)) }) else {
                result.finish(.failure(XPCError.helperUnavailable)); return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { result.finish(.failure(XPCError.timeout)) }
            helper.readAdapterMetrics { voltage, current, power in
                result.finish(.success(SMCAdapterReading(adapterVoltage: voltage, adapterCurrent: current, adapterPower: power)))
            }
        }
    }

    func refreshPowerForVerification() async {
        await pollSMCOnce()
    }

    private func fetchTemperature() async -> Double {
        (try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
            let result = XPCCommandReply<Double>(continuation)
            guard let helper = xpcManager.getHelper(errorHandler: { _ in result.finish(.success(.nan)) }) else {
                result.finish(.success(.nan)); return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { result.finish(.success(.nan)) }
            helper.readBatteryTemperature { result.finish(.success($0)) }
        }) ?? .nan
    }

    private func fetchComponentPower() async -> ComponentPowerReading? {
        let json = (try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let result = XPCCommandReply(continuation)
            guard let helper = xpcManager.getHelper(errorHandler: { result.finish(.failure($0)) }) else {
                result.finish(.failure(XPCError.helperUnavailable)); return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { result.finish(.failure(XPCError.timeout)) }
            helper.readComponentPower { result.finish(.success($0)) }
        }) ?? ""
        guard json.utf8.count < 2048 else { return nil }
        return try? JSONDecoder().decode(ComponentPowerReading.self, from: Data(json.utf8))
    }

    private func pollSMCOnce() async {
        let sampleDate = Date()
        async let componentData = fetchComponentPower()
        async let temperatureData = fetchTemperature()
        async let batteryData = fetchSMCBatteryData()
        async let adapterData = fetchSMCAdapterData()

        guard let batteryReading = await batteryData, let adapterReading = await adapterData else {
            componentPower = nil
            logger.error("No helper available for SMC battery polling")
            return
        }

        guard batteryReading.batteryVoltage.isFinite, batteryReading.batteryVoltage > 0.1 else { componentPower = nil; return }
        let temperature = await temperatureData
        guard !Task.isCancelled, lastPowerSampleDate.map({ $0 <= sampleDate }) ?? true else { return }
        componentPower = await componentData
        var updatedBattery = metrics
        if temperature.isFinite {
            updatedBattery.batteryTemperature = temperature
            lastTemperatureSampleDate = sampleDate
        } else if lastTemperatureSampleDate.map({ sampleDate.timeIntervalSince($0) > 30 }) ?? true {
            updatedBattery.batteryTemperature = 0
        }
        updatedBattery.batteryVoltage = batteryReading.batteryVoltage
        updatedBattery.batteryCurrent = batteryReading.batteryCurrent
        updatedBattery.batteryPower = batteryReading.batteryPower

        var updatedAdapter = adapterMetrics
        updatedAdapter.adapterVoltage = adapterReading.adapterVoltage
        updatedAdapter.adapterCurrent = adapterReading.adapterCurrent
        updatedAdapter.adapterPower = adapterReading.adapterPower

        // SMC reports faster than IOKit can update, so refine isCharging
        // using the actual power flow direction.
        if updatedAdapter.adapterConnected {
            updatedBattery.isCharging = batteryReading.batteryPower > 0
        }

        if updatedBattery != metrics {
            metrics = updatedBattery
        }
        if updatedAdapter != adapterMetrics {
            adapterMetrics = updatedAdapter
        }
        lastPowerSampleDate = sampleDate
        updateControlState(from: updatedBattery, adapter: updatedAdapter)
    }

    private func handleIOKitUpdate(_ newBatteryMetrics: BatteryMetrics, adapterUpdate: AdapterMetrics) {
        logger.debug("Received IOKit update")
        let connectionChanged = adapterUpdate.adapterConnected != adapterMetrics.adapterConnected

        var updatedBattery = newBatteryMetrics
        if newBatteryMetrics.batteryTemperature > 0 { lastTemperatureSampleDate = Date() }
        else if lastTemperatureSampleDate.map({ Date().timeIntervalSince($0) <= 30 }) ?? false {
            updatedBattery.batteryTemperature = metrics.batteryTemperature
        }
        updatedBattery.batteryVoltage = metrics.batteryVoltage
        updatedBattery.batteryCurrent = metrics.batteryCurrent
        updatedBattery.batteryPower = metrics.batteryPower

        if updatedBattery != metrics {
            metrics = updatedBattery
        }

        var updatedAdapter = adapterUpdate
        updatedAdapter.adapterVoltage = adapterMetrics.adapterVoltage
        updatedAdapter.adapterCurrent = adapterMetrics.adapterCurrent
        updatedAdapter.adapterPower = adapterMetrics.adapterPower

        if updatedAdapter != adapterMetrics {
            adapterMetrics = updatedAdapter
        }

        updateControlState(from: updatedBattery, adapter: updatedAdapter)
        if connectionChanged {
            logger.notice("POWER_CONNECTION_EVENT connected=\(updatedAdapter.adapterConnected, privacy: .public)")
            scheduleSinglePoll(delay: .zero)
        }
    }

    private func updateControlState(from metrics: BatteryMetrics, adapter: AdapterMetrics) {
        let newState = BatteryControlState(
            powerSampleDate: lastPowerSampleDate,
            batteryPercentage: metrics.batteryPercentage,
            hardwareBatteryPercentage: metrics.hardwareBatteryPercentage,
            adapterConnected: adapter.adapterConnected,
            batteryTemperature: metrics.batteryTemperature
        )
        if newState != controlState {
            controlState = newState
        }
    }

    func readLastSystemFullCharge() async throws -> Double {
        guard !AidenteRuntime.isUIPreview, ChargingHelperManager.shared.isInstalled else { return 0 }
        return try await withCheckedThrowingContinuation { continuation in
            let result = XPCCommandReply<Double>(continuation)
            guard let helper = ChargingHelperManager.shared.getHelper(errorHandler: { result.finish(.failure($0)) }) else { result.finish(.failure(XPCError.helperUnavailable)); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { result.finish(.failure(XPCError.timeout)) }
            helper.readLastFullCharge { result.finish(.success($0)) }
        }
    }

    func restorePowerDefaults() async throws {
        try await ChargingHelperManager.shared.prepareForControl()
        try await performControlCommand { helper, reply in
            helper.restoreDefaults(reply: reply)
        }
    }

    func manageBatteryCharging(enabled: Bool) async throws {
        try await performControlCommand { helper, reply in
            helper.manageBatteryCharging(enabled: enabled, reply: reply)
        }
    }

    func applyPowerPolicy(charging: Bool, adapter: Bool, managed: Bool,
                          stopWhileSleeping: Bool, resetOnDisconnect: Bool, followNaturalDrift: Bool,
                          chargeCeiling: Int, rechargeBelow: Int) async throws {
        try await ChargingHelperManager.shared.prepareForControl()
        do {
            try await performControlCommand { helper, reply in
                helper.applyPowerPolicy(charging: charging, adapter: adapter, managed: managed,
                                        stopWhileSleeping: stopWhileSleeping,
                                        resetOnDisconnect: resetOnDisconnect, followNaturalDrift: followNaturalDrift,
                                        chargeCeiling: chargeCeiling, rechargeBelow: rechargeBelow, reply: reply)
            }
        } catch {
            ChargingHelperManager.shared.recoverAfterTransportFailure(error)
            throw error
        }
    }

    func configureLED(enabled: Bool, mode: Int, blink: Bool) async throws {
        try await performControlCommand { helper, reply in
            helper.configureLED(enabled: enabled, mode: mode, blink: blink, reply: reply)
        }
    }

    func setEnergyMode(_ mode: EnergyMode, source: EnergySource) async throws {
        guard !AidenteRuntime.isUIPreview else { return }
        try await ChargingHelperManager.shared.prepareForControl()
        try await performControlCommand { helper, reply in
            helper.setEnergyMode(mode: mode.rawValue, source: source.rawValue, reply: reply)
        }
    }

    func manageExternalPower(enabled: Bool) async throws {
        try await performControlCommand { helper, reply in
            helper.manageExternalPower(enabled: enabled, reply: reply)
        }
    }

    func manageMagsafeLED(target: MagSafeLEDState) async throws {
        try await performControlCommand { helper, reply in
            helper.manageMagsafeLED(target: target.rawValue, reply: reply)
        }
    }

    func checkChargingHelper() async throws {
        try await ChargingHelperManager.shared.prepareForControl()
        try await performControlCommand { helper, reply in
            helper.ping(reply: reply)
        }
    }

    private func performControlCommand(
        _ command: @escaping @Sendable (
            AidenteControlProtocol,
            @escaping @Sendable (Bool, String?) -> Void
        ) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let commandReply = XPCCommandReply(continuation)
            guard
                let helper = ChargingHelperManager.shared.getHelper(errorHandler: { error in
                    commandReply.finish(.failure(error))
                })
            else {
                commandReply.finish(.failure(XPCError.helperUnavailable))
                return
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 8) {
                commandReply.finish(.failure(XPCError.timeout))
            }

            command(helper) { success, errorMessage in
                if success {
                    commandReply.finish(.success(()))
                } else {
                    commandReply.finish(
                        .failure(
                            XPCError.commandFailed(
                                errorMessage ?? AidenteL10n.t("未知错误", "Unknown error")
                            )
                        )
                    )
                }
            }
        }
    }

    func setResetOnDisconnect(_ enabled: Bool) throws {
        let helper = try getChargingHelper()
        helper.setResetOnDisconnect(enabled)
    }

    private func getChargingHelper() throws -> AidenteControlProtocol {
        let logger = self.logger
        guard
            let helper = ChargingHelperManager.shared.getHelper(errorHandler: { error in
                logger.error("Charging helper XPC error: \(error.localizedDescription)")
            })
        else {
            throw XPCError.helperUnavailable
        }
        return helper
    }

    func stop() {
        logger.info("BatteryService stopping")
        fastPollingRequested = false; backgroundPollingRequested = false
        ioKitMonitorTask?.cancel()
        ioKitMonitorTask = nil
        smcPollTask?.cancel()
        smcPollTask = nil
        delayedPollTask?.cancel()
        delayedPollTask = nil
        xpcManager.disconnect()
    }
}
