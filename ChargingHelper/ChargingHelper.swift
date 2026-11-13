import Foundation
import AidenteShared
import os.log
import smc_power
import IOKit
import IOKit.pwr_mgt
import Darwin
import SMCKit

private enum Constants {
    static let subsystem = "com.aidente.app.control"
    // IOMessage.h: iokit_common_msg values. The SDK's C function-like macros
    // are not imported by Swift.
    static let canSleep: UInt32 = 0xe0000270
    static let willSleep: UInt32 = 0xe0000280
    static let willNotSleep: UInt32 = 0xe0000290
    static let didWake: UInt32 = 0xe0000300
}

final class ChargingHelper: NSObject, AidenteControlProtocol {
    private var battery: SMCBattery
    private let adapter: SMCAdapter
    private let logger = Logger(
        subsystem: Constants.subsystem,
        category: "ChargingHelper"
    )
    private(set) var resetOnDisconnect = true
    private let queue = DispatchQueue(label: "com.aidente.app.control.power")
    private var policy: ChargingPowerPolicy?
    private var firmwarePolicy = FirmwarePowerPolicy()
    private var nativePolicy = NativeChargePolicy()
    private var hasControlledPower = false
    private var sleeping = false
    private var ledPolicyConfigured = false
    private var ledEnabled = false
    private var ledMode = 0
    private var ledBlink = true
    private var requestedLED: UInt8 = 0
    private var clients = 0
    private var lastClientPID: pid_t?
    private var policyOwnerUID: UInt32?
    private var disconnectGeneration = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var powerConnection: io_connect_t = 0
    private var watchdog: DispatchSourceTimer?
    private let controlDefaults = UserDefaults(suiteName: "com.aidente.app.control") ?? .standard
    private lazy var energyModes = EnergyModeController(defaults: controlDefaults)
    private let firmwareSnapshotKey = "firmwareLimitBeforeAidente"
    private let nativeSnapshotKey = "nativeLimitBeforeAidente"
    private let nativePreferencesKey = "nativePreferencesBeforeAidente"
    private let dischargeSafetyKey = "dischargeSafetyState"
    private lazy var dischargeSafety: DischargeSafetyPolicy = {
        guard let data = controlDefaults.data(forKey: dischargeSafetyKey),
              let stored = try? JSONDecoder().decode(DischargeSafetyPolicy.self, from: data) else { return DischargeSafetyPolicy() }
        return stored
    }()
    private lazy var nativeLimit = try? NativeChargeLimit()

    init(battery: SMCBattery, adapter: SMCAdapter) {
        self.battery = battery
        self.adapter = adapter
        super.init()
        logger.info(
            "Initialized (charging=\(battery.capabilities.inhibitChargeControl), discharge=\(battery.capabilities.forceDischargeControl), magSafe=\(adapter.capabilities.magSafeControl))"
        )
        logger.notice("CONTROL_KEYS charging=\(battery.chargingControlKey, privacy: .public) discharge=\(battery.dischargeControlKey, privacy: .public)")
        startPowerMonitoring()
    }

    private func startPowerMonitoring() {
        powerConnection = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(), &notificationPort,
            { context, _, message, argument in
                guard let context else { return }
                let helper = Unmanaged<ChargingHelper>.fromOpaque(context).takeUnretainedValue()
                helper.powerEvent(message, argument: argument)
            }, &notifier
        )
        if powerConnection != 0, let notificationPort {
            IONotificationPortSetDispatchQueue(notificationPort, queue)
        } else {
            logger.error("POWER_MONITOR_REGISTRATION_FAILED")
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15, leeway: .seconds(3))
        timer.setEventHandler { [weak self] in self?.reconcile(reason: "watchdog") }
        timer.resume()
        watchdog = timer
    }

    // Runs on the same serial queue as every SMC write. Acknowledge sleep only
    // after the write and readback, not after enqueueing an asynchronous XPC call.
    private func powerEvent(_ message: UInt32, argument: UnsafeMutableRawPointer?) {
        switch message {
        case Constants.canSleep:
            IOAllowPowerChange(powerConnection, Int(bitPattern: argument))
        case Constants.willSleep:
            sleeping = true
            policy?.sleeping = true
            reconcile(reason: "willSleep")
            IOAllowPowerChange(powerConnection, Int(bitPattern: argument))
        case Constants.didWake, Constants.willNotSleep:
            sleeping = false
            // Keep the sleep hold until the app submits a fresh policy. A dark
            // wake must not resume charging from a stale pre-sleep percentage.
            do { battery = try SMCBattery.probe() }
            catch { logger.error("Wake capability probe failed: \(error.localizedDescription, privacy: .public)") }
            reconcile(reason: "didWake")
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.reconcile(reason: "wakeRecheck")
            }
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.resetAfterDisconnectIfNeeded()
            }
        default: break
        }
    }

    func clientConnected(pid: pid_t) {
        queue.sync {
            // Release a previous account before the new owner overwrites its policy.
            reconcile(reason: "clientConnected")
            clients += 1
            disconnectGeneration += 1
            lastClientPID = pid
        }
    }

    func clientDisconnected() {
        queue.async {
            self.clients = max(0, self.clients - 1)
            self.disconnectGeneration += 1
            let generation = self.disconnectGeneration
            self.queue.asyncAfter(deadline: .now() + 5) {
                guard self.clients == 0, generation == self.disconnectGeneration else { return }
                // A transient XPC interruption at sleep must not undo the hold.
                self.resetAfterDisconnectIfNeeded()
            }
        }
    }

    private func resetAfterDisconnectIfNeeded() {
        guard clients == 0, resetOnDisconnect, !sleeping, hasControlledPower else { return }
        if let pid = lastClientPID, kill(pid, 0) == 0 || errno == EPERM {
            return // The GUI is alive but suspended or reconnecting.
        }
        resetOnQueue()
    }

    func applyPowerPolicy(charging: Bool, adapter: Bool, managed: Bool,
                          stopWhileSleeping: Bool, resetOnDisconnect: Bool, followNaturalDrift: Bool,
                          chargeCeiling: Int, rechargeBelow: Int,
                          reply: @escaping @Sendable (Bool, String?) -> Void) {
        let caller = NSXPCConnection.current()?.effectiveUserIdentifier ?? getuid()
        queue.async {
            guard ConsoleSessionPolicy.mayControl(caller: caller, console: ConsoleSessionPolicy.consoleUID) else {
                reply(false, "当前账户不在活动控制台，请切回后重试。")
                return
            }
            guard (1...100).contains(chargeCeiling), rechargeBelow >= 0,
                  rechargeBelow < chargeCeiling else {
                reply(false, "Invalid firmware charge interval")
                return
            }
            var request = ChargingPowerPolicy()
            request.charging = charging
            request.adapter = adapter
            request.managed = managed
            request.stopWhileSleeping = stopWhileSleeping
            request.followNaturalDrift = followNaturalDrift
            request.sleeping = self.sleeping
            request.chargeCeiling = chargeCeiling
            request.rechargeBelow = rechargeBelow
            self.policyOwnerUID = caller
            self.policy = request
            self.hasControlledPower = true
            self.resetOnDisconnect = resetOnDisconnect
            do {
                if managed && stopWhileSleeping && self.powerConnection == 0 {
                    throw NSError(domain: "AidenteControl", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "无法注册系统睡眠通知，请修复控制服务"
                    ])
                }
                try self.applyEffectivePolicy()
                reply(true, nil)
            } catch {
                self.logger.error("POWER_POLICY_FAILED \(error.localizedDescription, privacy: .public)")
                if case SMCError.notPrivileged = error {
                    reply(false, "FIRMWARE_ACCESS_DENIED: system firmware denied charge-control access")
                } else {
                    reply(false, error.localizedDescription)
                }
            }
        }
    }

    private func applyEffectivePolicy() throws {
        guard let policy else { return }
        let target = policy.effective
        if battery.usesFirmwareChargeLimit {
            let controller = FirmwareChargeLimitController(registers: SMCFirmwareLimitRegisters())
            if target.adapter, battery.capabilities.forceDischargeControl,
               try battery.getForceDischarging() {
                try battery.setForceDischarging(false)
            }
            if policy.managed {
                // A root-owned preference survives daemon upgrades and crashes;
                // turning management off must restore the user's original limit.
                if controlDefaults.data(forKey: firmwareSnapshotKey) == nil {
                    let snapshot = try JSONEncoder().encode(controller.read())
                    controlDefaults.set(snapshot, forKey: firmwareSnapshotKey)
                    guard controlDefaults.synchronize() else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                let percentage = try SMCBattery.firmwarePercentageExact()
                let externalConnected = try SMCBattery.externalPowerConnected()
                let previous = try controller.read()
                switch firmwarePolicy.target(policy: policy, percentage: percentage,
                                             externalConnected: externalConnected) {
                case .unlimited:
                    var unlimited = previous
                    unlimited.activation = 0
                    try controller.replace(with: unlimited)
                case .interval(let lower, let upper):
                    try controller.set(lower: lower, upper: upper)
                }
                let applied = try controller.read()
                if applied != previous {
                    let rawPercentage = String(format: "%.4f", percentage)
                    logger.notice("FIRMWARE_INTERVAL_APPLIED raw=\(rawPercentage, privacy: .public) lower=\(applied.lower) upper=\(applied.upper) activation=\(applied.activation) sleeping=\(policy.sleeping) chargingRequested=\(target.charging) externalConnected=\(externalConnected)")
                }
            } else {
                try restoreFirmwareLimit()
            }
            if battery.capabilities.forceDischargeControl {
                if try battery.getForceDischarging() == target.adapter {
                    try battery.setForceDischarging(!target.adapter)
                }
                guard try battery.getForceDischarging() == !target.adapter else {
                    throw SMCBatteryError.stateVerificationFailed
                }
            } else if !target.adapter {
                throw SMCBatteryError.unsupportedCapability
            }
        } else if !battery.capabilities.inhibitChargeControl, let nativeLimit {
            let controller = NativeChargeTransaction(registers: PowerUIChargeRegisters(client: nativeLimit))
            guard policy.managed else {
                try restoreNativeLimit(); nativePolicy.reset(); clearDischargeSafety(); return
            }
            let percentage = try SMCBattery.macOSPercentage()
            let beforeSafety = dischargeSafety
            let raw = policy.adapter ? Double.nan : ((try? SMCBattery.firmwarePercentageExact()) ?? .nan)
            let safetyStop = dischargeSafety.mustStop(managed: policy.managed,
                dischargeRequested: !policy.adapter, target: policy.chargeCeiling,
                displayed: percentage, raw: raw, now: Date())
            if dischargeSafety != beforeSafety {
                controlDefaults.set(try JSONEncoder().encode(dischargeSafety), forKey: dischargeSafetyKey)
                guard controlDefaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            }
            if safetyStop {
                self.policy = nil
                nativePolicy.reset()
                do { try restoreNativeLimit() }
                catch {
                    // Keep the recovery snapshot. If restoring its precise value
                    // fails, separately ask the agent to unregister the drain.
                    do { try nativeLimit.disable() }
                    catch { logger.fault("DISCHARGE_EMERGENCY_RELEASE_FAILED \(error.localizedDescription, privacy: .public)") }
                    throw NSError(domain: "AidenteControl", code: 6, userInfo: [NSLocalizedDescriptionKey:
                        "DISCHARGE_SAFETY_STOP: 电量读数异常，已停止主动策略；原设置恢复未确认，请修复控制服务。"])
                }
                logger.error("DISCHARGE_SAFETY_STOP display=\(percentage) target=\(policy.chargeCeiling)")
                throw NSError(domain: "AidenteControl", code: 6, userInfo: [NSLocalizedDescriptionKey:
                    "DISCHARGE_SAFETY_STOP: 电量显示长时间未更新或安全读数不可用，已停止放电并恢复接管前设置。"])
            }
            let externalConnected = try SMCBattery.externalPowerConnected()
            guard let limit = nativePolicy.target(policy: policy, percentage: percentage,
                                                   externalConnected: externalConnected) else { return }
            if controlDefaults.data(forKey: nativePreferencesKey) == nil {
                // Snapshot only the two preferences we own while managing, and
                // their effective result. Missing keys must remain missing on restore.
                controlDefaults.set(try JSONEncoder().encode(controller.snapshot()), forKey: nativePreferencesKey)
                guard controlDefaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            }
            let previous = try controller.snapshot()
            try controller.set(limit)
            if try controller.snapshot() != previous {
                logger.notice("NATIVE_POLICY_APPLIED display=\(percentage) target=\(limit) chargingRequested=\(target.charging) dischargeRequested=\(!target.adapter) sleeping=\(policy.sleeping)")
            }
        } else {
            try battery.applyPowerState(charging: target.charging, adapter: target.adapter)
        }
    }

    private func clearDischargeSafety() {
        dischargeSafety.reset()
        controlDefaults.removeObject(forKey: dischargeSafetyKey)
        controlDefaults.synchronize()
    }

    private func restoreNativeLimit() throws {
        if let data = controlDefaults.data(forKey: nativePreferencesKey) {
            guard let nativeLimit else { throw SMCBatteryError.unsupportedCapability }
            let original = try JSONDecoder().decode(NativeChargeSnapshot.self, from: data)
            try NativeChargeTransaction(registers: PowerUIChargeRegisters(client: nativeLimit)).replace(original)
            controlDefaults.removeObject(forKey: nativePreferencesKey)
            guard controlDefaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        }
        guard let data = controlDefaults.data(forKey: nativeSnapshotKey) else { return }
        let original = try JSONDecoder().decode(NativeChargeLimit.State.self, from: data)
        guard let nativeLimit else { throw SMCBatteryError.unsupportedCapability }
        try nativeLimit.restore(original)
        controlDefaults.removeObject(forKey: nativeSnapshotKey)
        guard controlDefaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    }

    private func restoreFirmwareLimit() throws {
        guard let data = controlDefaults.data(forKey: firmwareSnapshotKey) else { return }
        let original = try JSONDecoder().decode(FirmwareChargeLimitState.self, from: data)
        try FirmwareChargeLimitController(registers: SMCFirmwareLimitRegisters()).replace(with: original)
        controlDefaults.removeObject(forKey: firmwareSnapshotKey)
        controlDefaults.synchronize()
    }

    private func reconcile(reason: String) {
        do {
            if let owner = policyOwnerUID,
               !ConsoleSessionPolicy.mayControl(caller: owner, console: ConsoleSessionPolicy.consoleUID) {
                if resetOnDisconnect { try restoreOnQueue() }
                else if var hold = policy {
                    hold.charging = false; hold.adapter = true; hold.followNaturalDrift = false
                    nativePolicy.reset(); firmwarePolicy.reset()
                    policy = hold
                    try applyEffectivePolicy()
                }
                // Release per-user temporary power modes and LED overrides.
                try energyModes.restore()
                ledPolicyConfigured = false
                policyOwnerUID = nil
                logger.notice("CONSOLE_SESSION_RELEASED reset=\(self.resetOnDisconnect)")
            }
            try applyEffectivePolicy()
            try applyLEDPolicy()
            if let policy, reason != "watchdog" {
                logger.notice("POWER_EVENT \(reason, privacy: .public) charging=\(policy.effective.charging) adapter=\(policy.effective.adapter)")
            }
        } catch {
            logger.error("POWER_RECONCILE_FAILED \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func configureLED(enabled: Bool, mode: Int, blink: Bool, reply: @escaping @Sendable (Bool, String?) -> Void) {
        let caller = NSXPCConnection.current()?.effectiveUserIdentifier ?? getuid()
        queue.async {
            guard ConsoleSessionPolicy.mayControl(caller: caller, console: ConsoleSessionPolicy.consoleUID) else {
                reply(false, "当前账户不在活动控制台，请切回后重试。")
                return
            }
            guard (0...2).contains(mode) else { reply(false, "Invalid LED policy"); return }
            self.ledPolicyConfigured = true; self.ledEnabled = enabled; self.ledMode = mode; self.ledBlink = blink
            do { try self.applyLEDPolicy(); reply(true, nil) } catch { reply(false, error.localizedDescription) }
        }
    }
    private func applyLEDPolicy() throws {
        guard adapter.capabilities.magSafeControl, ledPolicyConfigured else { return }
        let target = MagSafePolicy.target(enabled: ledEnabled, mode: ledMode, sleeping: sleeping,
            discharging: policy.map { !$0.effective.adapter } ?? false,
            blinkDuringDischarge: ledBlink, requested: requestedLED)
        if let state = MagSafeLEDState(rawValue: target), try adapter.getMagSafeLEDState() != state {
            try adapter.setMagSafeLEDState(state)
        }
    }

    func setEnergyMode(mode: Int, source: String, reply: @escaping @Sendable (Bool, String?) -> Void) {
        let caller = NSXPCConnection.current()?.effectiveUserIdentifier ?? getuid()
        queue.async {
            guard ConsoleSessionPolicy.mayControl(caller: caller, console: ConsoleSessionPolicy.consoleUID) else {
                reply(false, "当前账户不在活动控制台，请切回后重试。")
                return
            }
            guard let mode = EnergyMode(rawValue: mode), let source = EnergySource(rawValue: source) else {
                reply(false, "Invalid energy mode or power source"); return
            }
            do { try self.energyModes.set(mode: mode, source: source); reply(true, nil) }
            catch { reply(false, error.localizedDescription) }
        }
    }

    func ping(reply: @escaping @Sendable (Bool, String?) -> Void) {
        reply(true, nil)
    }

    func readLastFullCharge(reply: @escaping @Sendable (Double) -> Void) {
        queue.async {
            let file = URL(fileURLWithPath: "/private/var/root/Library/Preferences/com.apple.powerd.batterygauging.plist")
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue <= 131072,
                  let data = try? Data(contentsOf: file),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let date = GaugingMetadata.lastFullCharge(in: values, now: Date()) else { reply(0); return }
            // Read-only, fixed path, whitelisted timestamp only. Never reset or
            // modify Apple's gauging policy, and never return the entire file.
            reply(date.timeIntervalSince1970)
        }
    }

    func manageBatteryCharging(enabled: Bool, reply: @escaping @Sendable (Bool, String?) -> Void) {
        let caller = NSXPCConnection.current()?.effectiveUserIdentifier ?? getuid()
        queue.sync {
            guard ConsoleSessionPolicy.mayControl(caller: caller, console: ConsoleSessionPolicy.consoleUID) else {
                reply(false, "当前账户不在活动控制台，请切回后重试。")
                return
            }
        hasControlledPower = true
        do {
            guard battery.capabilities.inhibitChargeControl else {
                reply(false, "当前设备不支持充电控制")
                return
            }
            let currentlyInhibited = try battery.getChargingInhibited()
            if currentlyInhibited != !enabled {
                try battery.setChargingInhibited(!enabled)
                logger.debug("SMC set charging inhibited to: \(!enabled)")
            }
            let appliedValue = try battery.getChargingInhibited()
            guard appliedValue == !enabled else {
                reply(false, "SMC 没有接受充电暂停状态")
                return
            }
            reply(true, nil)
        } catch {
            logger.error("manageBatteryCharging failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
        }
    }

    func manageExternalPower(enabled: Bool, reply: @escaping @Sendable (Bool, String?) -> Void) {
        let caller = NSXPCConnection.current()?.effectiveUserIdentifier ?? getuid()
        queue.sync {
            guard ConsoleSessionPolicy.mayControl(caller: caller, console: ConsoleSessionPolicy.consoleUID) else {
                reply(false, "当前账户不在活动控制台，请切回后重试。")
                return
            }
        hasControlledPower = true
        do {
            guard battery.capabilities.forceDischargeControl else {
                reply(false, "当前设备不支持适配器控制")
                return
            }
            let currentlyDischarging = try battery.getForceDischarging()
            if currentlyDischarging != !enabled {
                try battery.setForceDischarging(!enabled)
                logger.debug("SMC set force discharging to: \(!enabled)")
            }
            let appliedValue = try battery.getForceDischarging()
            guard appliedValue == !enabled else {
                reply(false, "SMC 没有接受适配器控制状态")
                return
            }
            reply(true, nil)
        } catch {
            logger.error("manageExternalPower failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
        }
    }

    func manageMagsafeLED(target: UInt8, reply: @escaping @Sendable (Bool, String?) -> Void) {
        let caller = NSXPCConnection.current()?.effectiveUserIdentifier ?? getuid()
        queue.sync {
            guard ConsoleSessionPolicy.mayControl(caller: caller, console: ConsoleSessionPolicy.consoleUID) else {
                reply(false, "当前账户不在活动控制台，请切回后重试。")
                return
            }
        do {
            guard adapter.capabilities.magSafeControl else {
                reply(false, "当前设备不支持 MagSafe 指示灯控制")
                return
            }
            guard let ledState = MagSafeLEDState(rawValue: target) else {
                reply(false, "无效的 MagSafe 指示灯状态：\(target)")
                return
            }
            requestedLED = ledState.rawValue
            try applyLEDPolicy()
            reply(true, nil)
        } catch {
            logger.error("manageMagsafeLED failed: \(error.localizedDescription)")
            reply(false, error.localizedDescription)
        }
        }
    }

    func setResetOnDisconnect(_ enabled: Bool) {
        let caller = NSXPCConnection.current()?.effectiveUserIdentifier ?? getuid()
        queue.sync {
            guard ConsoleSessionPolicy.mayControl(caller: caller, console: ConsoleSessionPolicy.consoleUID) else { return }
        resetOnDisconnect = enabled
        logger.info("Reset on disconnect: \(enabled)")
        }
    }

    func resetToDefaults() {
        let caller = NSXPCConnection.current()?.effectiveUserIdentifier ?? getuid()
        queue.sync {
            guard ConsoleSessionPolicy.mayControl(caller: caller, console: ConsoleSessionPolicy.consoleUID) else { return }
            resetOnQueue()
        }
    }

    func restoreDefaults(reply: @escaping @Sendable (Bool, String?) -> Void) {
        let caller = NSXPCConnection.current()?.effectiveUserIdentifier ?? getuid()
        queue.async {
            guard ConsoleSessionPolicy.mayControl(caller: caller, console: ConsoleSessionPolicy.consoleUID) else {
                reply(false, "当前账户不在活动控制台，请切回后重试。")
                return
            }
            do {
                try self.restoreOnQueue()
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    private func resetOnQueue() {
        do { try restoreOnQueue() }
        catch { logger.error("resetToDefaults failed: \(error.localizedDescription)") }
    }

    private func restoreOnQueue() throws {
        try energyModes.restore()
        try restoreNativeLimit()
        ledPolicyConfigured = false; ledEnabled = false; requestedLED = 0
        policy = nil
        policyOwnerUID = nil
        firmwarePolicy.reset()
        nativePolicy.reset()
        if battery.capabilities.forceDischargeControl {
            try battery.setForceDischarging(false)
        }
        if battery.usesFirmwareChargeLimit {
            try restoreFirmwareLimit()
        } else if controlDefaults.data(forKey: firmwareSnapshotKey) != nil {
            throw SMCBatteryError.unsupportedCapability
        } else if battery.capabilities.inhibitChargeControl {
            try battery.setChargingInhibited(false)
        }
        if adapter.capabilities.magSafeControl {
            do { try adapter.setMagSafeLEDState(.reset) }
            catch { logger.warning("LED reset failed after restoring power: \(error.localizedDescription)") }
        }
        logger.info("SMC keys reset to defaults")
        hasControlledPower = false
        // A crash/exit must not forget a blocked discharge before the GUI has
        // received the error. A deliberate managed=false request clears it.
        if !dischargeSafety.isBlocked { clearDischargeSafety() }
    }
}
