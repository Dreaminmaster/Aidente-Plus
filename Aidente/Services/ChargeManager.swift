import Defaults
import Foundation
import IOKit.pwr_mgt
import Observation
import UserNotifications
import os.log
import smc_power
import AidenteShared

typealias CalibrationStage = CalibrationProgress

extension CalibrationProgress {
    var title: String {
        switch self {
        case .idle: AidenteL10n.t("空闲", "Idle")
        case .chargingToFull: AidenteL10n.t("校准：充电至 100%", "Calibration: Charging to 100%")
        case .dischargingToLow: AidenteL10n.t("校准：正在放电", "Calibration: Discharging")
        case .rechargingToFull: AidenteL10n.t("校准：重新充电至 100%", "Calibration: Recharging to 100%")
        case .holdingAtFull: AidenteL10n.t("校准：满电保持", "Calibration: Holding at Full")
        case .restoringLimit: AidenteL10n.t("校准：恢复充电上限", "Calibration: Restoring Charge Limit")
        }
    }
}

enum ChargeOperationStatus: Equatable {
    case monitoring
    case charging
    case paused
    case sailing
    case discharging(target: Int)
    case topUp
    case heatProtection
    case sleeping
    case systemCalibration
    case calibration(CalibrationStage)

    var title: String {
        switch self {
        case .monitoring: AidenteL10n.t("只读监测")
        case .charging: AidenteL10n.t("正在充电")
        case .paused: AidenteL10n.t("充电已暂停")
        case .sailing: AidenteL10n.t("巡航中")
        case .discharging(let target):
            AidenteL10n.t("正在放电至 \(target)%", "Discharging to \(target)%")
        case .topUp: AidenteL10n.t("临时充至 100%")
        case .heatProtection: AidenteL10n.t("高温保护")
        case .sleeping: AidenteL10n.t("睡眠保护")
        case .systemCalibration: AidenteL10n.t("macOS 正在校准电池", "macOS Battery Calibration")
        case .calibration(let stage): stage.title
        }
    }
}

@MainActor
@Observable
class ChargeManager {
    var usesNativeChargeLimit: Bool { batteryService.usesNativeChargeLimit }
    var nativeChargeLimits: [Int] { batteryService.nativeChargeLimits }
    private let batteryService: BatteryService

    private var metricsObservation: Task<Void, Never>?
    private var settingsObservation: Task<Void, Never>?
    private var scheduleObservation: Task<Void, Never>?

    private var lastAdapterConnected: Bool?
    private var lastManageChargingEnabled: Bool?
    private var limitPolicy = ChargeLimitPolicy()
    private var lastLEDConfiguration: String?
    private var lastLimit: Int?
    private var lastAutomaticDischarge: Bool?
    private var lastNotifiedChargingState: Bool?
    private var heatProtectionPaused = false
    private var thermalPolicy = HeatProtectionPolicy()
    private var isSystemSleeping = false
    private var isDisablingControl = false
    private struct PowerRequest: Equatable {
        let charging: Bool
        let adapter: Bool
        let managed: Bool
        let stopWhileSleeping: Bool
        let resetOnDisconnect: Bool
        let followNaturalDrift: Bool
        let chargeCeiling: Int
        let rechargeBelow: Int
    }
    private var pendingPowerRequest: PowerRequest?
    private var appliedPowerRequest: PowerRequest?
    private var powerTask: Task<Void, Never>?
    private var verificationTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var lastPowerApplication = Date.distantPast

    private(set) var topUpActive = Defaults[.topUpActive]
    private(set) var forceDischargeActive = false
    private(set) var manualPauseActive = Defaults[.manualPauseActive]
    private(set) var calibrationStage =
        CalibrationStage(rawValue: Defaults[.calibrationStage]) ?? .idle
    private(set) var operationStatus: ChargeOperationStatus = .monitoring
    private(set) var safetyStopReason = Defaults[.lastDischargeSafetyStopReason]
    private var serviceControlError: String?
    private var chargingControlError: String?
    private var adapterControlError: String?

    var automationStateCode: String {
        switch operationStatus {
        case .monitoring: "Exit"
        case .charging: "Charging"
        case .paused, .sleeping: "Pause"
        case .sailing: "Sailing"
        case .discharging: "Discharging"
        case .topUp: "Topup"
        case .heatProtection: "HeatProtect"
        case .calibration, .systemCalibration: "Calibration"
        }
    }
    var chargeLimitOverrideActive: Bool { topUpActive }
    var controlDiagnostics: [String: String] {
        [
            "sleeping": String(isSystemSleeping),
            "requestedCharging": pendingPowerRequest.map { String($0.charging) } ?? "unknown",
            "requestedAdapter": pendingPowerRequest.map { String($0.adapter) } ?? "unknown",
            "appliedCharging": appliedPowerRequest.map { String($0.charging) } ?? "unverified",
            "appliedAdapter": appliedPowerRequest.map { String($0.adapter) } ?? "unverified",
            "reachedLimit": String(limitPolicy.reachedLimit),
            "automaticDischargeActive": String(limitPolicy.automaticDischargeActive),
        ]
    }
    private var powerFlowError: String?
    private var powerHoldVerified = false

    var controlError: String? {
        if !safetyStopReason.isEmpty { return safetyStopReason }
        guard let rawError =
            serviceControlError ?? chargingControlError ?? adapterControlError ?? powerFlowError
        else {
            return nil
        }
        return AidenteL10n.controlError(rawError)
    }
    var operationStatusTitle: String {
        if controlError != nil { return AidenteL10n.t("充电控制未生效") }
        if let request = pendingPowerRequest, request.managed, !request.charging,
           request.adapter, batteryService.adapterMetrics.adapterConnected, !powerHoldVerified {
            return AidenteL10n.t("暂停供电状态待确认", "Verifying charging hold and power flow")
        }
        if operationStatus == .monitoring, Defaults[.manageCharging],
           !AidenteRuntime.isUIPreview, !batteryService.adapterMetrics.adapterConnected {
            return AidenteL10n.t("电池供电 · 限充待命", "On Battery · Charge Limit Ready")
        }
        return operationStatus.title
    }
    private var sleepAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

    private let logger = Logger(
        subsystem: "com.aidente.app",
        category: "ChargeManager"
    )

    init(batteryService: BatteryService) {
        self.batteryService = batteryService
        startObservingMetrics()
        startObservingSettings()
        startScheduleMonitoring()
    }

    private func startObservingMetrics() {
        metricsObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.evaluate(controlState: self.batteryService.controlState)
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.batteryService.controlState
                    } onChange: {
                        Task { @MainActor in
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }

    private func startObservingSettings() {
        settingsObservation = Task { [weak self] in
            for await _ in Defaults.updates(
                [
                    .manageCharging, .sailingMode, .automaticDischarge,
                    .disableSleepUntilChargeLimit,
                    .enableHeatProtectionMode, .manageMagSafeLED, .useHardwarePercentage,
                    .chargeLimit, .sailingModeLimit, .heatProtectionLimit,
                    .heatProtectionMagSafeLEDState, .stopChargingWhenAppClosed,
                    .stopChargingWhileSleeping, .calibrationLowLevel,
                    .calibrationHoldMinutes, .ledBehavior, .blinkLEDWhileDischarging,
                ],
                initial: false
            ) {
                guard let self else { return }
                self.configureHelperDisconnectPolicy()
                self.evaluate(controlState: self.batteryService.controlState)
            }
        }
    }

    private func startScheduleMonitoring() {
        guard !AidenteRuntime.isUIPreview else { return }
        scheduleObservation = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if ConsoleSessionPolicy.currentUserIsActive && !SystemCalibrationService.shared.isActive {
                    for task in ScheduleStore.shared.takeDueTasks() { self.executeScheduledTask(task) }
                }
                self.evaluate(controlState: self.batteryService.controlState)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func executeScheduledTask(_ task: ScheduleTask) {
        guard Defaults[.manageCharging] || task.action == .enableLowPower || task.action == .disableLowPower else {
            ScheduleStore.shared.record(task, outcome: "failed", detail: AidenteL10n.t("充电控制尚未启用", "Charging management is disabled")); return
        }
        logger.info("Executing scheduled task: \(task.summary)")
        switch task.action {
        case .setChargeLimit:
            Defaults[.chargeLimit] = min(max(task.value, 20), 100)
            resumeNormalManagement()
        case .startCalibration:
            startCalibration()
        case .topUp:
            startTopUp()
        case .pauseCharging:
            Defaults[.chargeLimit] = max(20, batteryService.metrics.batteryPercentage)
            pauseCharging()
        case .dischargeTo:
            Defaults[.chargeLimit] = min(max(task.value, 20), 100)
            if task.value >= batteryService.metrics.batteryPercentage { resumeNormalManagement() }
            else { startDischarge(to: task.value) }
        case .enableLowPower, .disableLowPower:
            Task {
                do {
                    try await ApplicationActions.shared.energy(task.action == .enableLowPower ? .low : .automatic)
                    ScheduleStore.shared.record(task, outcome: "triggered")
                } catch { ScheduleStore.shared.record(task, outcome: "failed", detail: error.localizedDescription) }
            }
            return
        }
        ScheduleStore.shared.record(task, outcome: "triggered")
    }

    private func evaluate(controlState: BatteryControlState) {
        EnergyModeService.shared.activeSource = controlState.adapterConnected ? .adapter : .battery
        guard !isDisablingControl, ConsoleSessionPolicy.currentUserIsActive else { return }
        guard !AidenteRuntime.isUIPreview else {
            operationStatus = .monitoring
            return
        }

        var stateWasCleared = false

        if controlState.adapterConnected != lastAdapterConnected {
            logger.info("Adapter connection changed: \(controlState.adapterConnected)")
            lastAdapterConnected = controlState.adapterConnected
            clearCachedState()
            stateWasCleared = true
        }

        guard !isSystemSleeping else { return } // The daemon owns the sleep transition.

        guard Defaults[.manageCharging], controlState.adapterConnected else {
            if topUpActive, !controlState.adapterConnected {
                setTopUpActive(false)
            }
            if forceDischargeActive, !controlState.adapterConnected {
                forceDischargeActive = false
            }
            operationStatus = .monitoring
            clearControlErrors()
            resetToDefaults()
            return
        }

        guard !ChargingHelperManager.shared.isRunningFromDiskImage else {
            operationStatus = .monitoring
            serviceControlError =
                ChargingHelperManagerError.runningFromDiskImage.localizedDescription
            return
        }

        if lastManageChargingEnabled != true {
            safetyStopReason = ""
            Defaults[.lastDischargeSafetyStopReason] = ""
            lastManageChargingEnabled = true
            clearCachedState()
            stateWasCleared = true
        }

        let batteryPercentage = controlState.batteryPercentage
        let system = SystemCalibrationService.shared
        system.recordFullSample(full: FullChargeConfirmation.evaluate(
            percentage: batteryPercentage, hardwareFull: batteryService.metrics.isFullyCharged,
            isCharging: batteryService.metrics.isCharging, batteryPower: batteryService.metrics.batteryPower,
            sampleAge: batteryService.lastPowerSampleDate.map { Date().timeIntervalSince($0) }),
            date: batteryService.lastPowerSampleDate, percentage: batteryPercentage, isCharging: batteryService.metrics.isCharging)
        if system.isActive && !system.session.canContinue {
            operationStatus = .systemCalibration
            clearControlErrors()
            requestPower(charging: true, adapter: true, managed: true, reason: system.status)
            updateSleepAssertion(shouldPreventSleep: false)
            return
        }
        if system.session.canContinue {
            system.didContinue()
            if !topUpActive {
                if calibrationStage == .idle { Defaults[.calibrationOriginalLimit] = Defaults[.chargeLimit] }
                let continuing = (calibrationStage != .idle && !Defaults[.systemCalibrationRecovery]) || Defaults[.afterSystemCalibration] == .continueCalibration
                Defaults[.systemCalibrationRecovery] = !continuing
                setCalibrationStage(SystemCalibrationFollowUp.stage(current: calibrationStage, preference: Defaults[.afterSystemCalibration]))
                manualPauseActive = false; Defaults[.manualPauseActive] = false; forceDischargeActive = false
            }
        }
        advanceCalibrationIfNeeded(batteryPercentage: batteryPercentage)

        var desiredCharging = false
        var desiredAdapter = true
        var desiredLED: MagSafeLEDState?
        var chargingStateReason: String?
        let chargeLimit = Defaults[.chargeLimit]
        if lastLimit != chargeLimit || lastAutomaticDischarge != Defaults[.automaticDischarge] {
            limitPolicy = ChargeLimitPolicy()
            stateWasCleared = true
            lastLimit = chargeLimit
            lastAutomaticDischarge = Defaults[.automaticDischarge]
        }

        if manualPauseActive {
            desiredCharging = false
            desiredAdapter = true
            desiredLED = Defaults[.manageMagSafeLED] ? .green : nil
            chargingStateReason = AidenteL10n.t(
                "已手动暂停充电",
                "Charging paused manually"
            )
            operationStatus = .paused
        } else if calibrationStage != .idle {
            applyCalibrationPolicy(
                batteryPercentage: batteryPercentage,
                desiredCharging: &desiredCharging,
                desiredAdapter: &desiredAdapter,
                desiredLED: &desiredLED,
                reason: &chargingStateReason
            )
            operationStatus = .calibration(calibrationStage)
        } else if topUpActive {
            desiredCharging = true
            desiredAdapter = true
            desiredLED = Defaults[.manageMagSafeLED] ? (batteryPercentage >= 100 ? .green : .orange) : nil
            chargingStateReason = AidenteL10n.t(
                "正在临时将电池充至 100%",
                "Temporarily charging the battery to 100%"
            )
            operationStatus = .topUp
        } else if forceDischargeActive {
            let target = min(max(Defaults[.forcedDischargeTarget], 20), 100)
            desiredCharging = false
            if batteryPercentage > target {
                desiredAdapter = false
                operationStatus = .discharging(target: target)
                chargingStateReason = AidenteL10n.t(
                    "正在放电至 \(target)%",
                    "Discharging to \(target)%"
                )
            } else {
                forceDischargeActive = false
                manualPauseActive = false
                Defaults[.manualPauseActive] = false
                limitPolicy = ChargeLimitPolicy()
                desiredAdapter = true
                operationStatus = .paused
                chargingStateReason = AidenteL10n.t(
                    "已达到 \(target)% 的放电目标",
                    "The \(target)% discharge target has been reached"
                )
            }
        } else {
            let target = limitPolicy.evaluate(
                percentage: batteryPercentage, limit: chargeLimit,
                sailing: Defaults[.sailingMode], sailingRange: Defaults[.sailingModeLimit],
                automaticDischarge: Defaults[.automaticDischarge], initialize: stateWasCleared
            )
            desiredCharging = target.charging
            desiredAdapter = target.adapter
            desiredLED = Defaults[.manageMagSafeLED] ? (desiredCharging ? .orange : .green) : nil
            operationStatus = !desiredAdapter ? .discharging(target: chargeLimit)
                : desiredCharging ? .charging
                : Defaults[.sailingMode] && batteryPercentage < chargeLimit ? .sailing : .paused
            chargingStateReason = desiredCharging
                ? AidenteL10n.t("正在充电至 \(chargeLimit)%", "Charging to \(chargeLimit)%")
                : AidenteL10n.t("已请求停止充电并保持适配器连接", "Requested charging hold with adapter connected")
        }

        if calibrationStage == .idle {
            applyHeatProtectionIfNeeded(
                temperature: controlState.batteryTemperature,
                desiredCharging: &desiredCharging,
                desiredLED: &desiredLED,
                reason: &chargingStateReason
            )
        } else {
            heatProtectionPaused = false
            thermalPolicy.reset()
        }

        let capabilities = batteryService.deviceCapabilities
        if capabilities.magsafeLEDControl {
            let mode = Defaults[.ledBehavior] == .alwaysOff ? 1 : Defaults[.ledBehavior] == .offDuringSleep ? 2 : 0
            let enabled = Defaults[.manageMagSafeLED]
            let blink = Defaults[.blinkLEDWhileDischarging]
            let configuration = "\(enabled)-\(mode)-\(blink)"
            if configuration != lastLEDConfiguration {
                lastLEDConfiguration = configuration
                Task {
                    do { try await batteryService.configureLED(enabled: enabled, mode: mode, blink: blink) }
                    catch { lastLEDConfiguration = nil }
                }
            }
        }

        requestPower(charging: desiredCharging, adapter: desiredAdapter,
                     managed: true, reason: chargingStateReason)
        if let desiredLED, capabilities.hasMagSafe, capabilities.magsafeLEDControl {
            setLED(state: desiredLED)
        }

        let shouldPreventSleep = (Defaults[.disableSleepUntilChargeLimit] && desiredCharging)
            || calibrationStage != .idle || !desiredAdapter
        updateSleepAssertion(shouldPreventSleep: shouldPreventSleep)
    }

    private func advanceCalibrationIfNeeded(batteryPercentage: Int) {
        let next = calibrationStage.next(
            percentage: batteryPercentage,
            fullChargeConfirmed: FullChargeConfirmation.evaluate(
                percentage: batteryPercentage, hardwareFull: batteryService.metrics.isFullyCharged,
                isCharging: batteryService.metrics.isCharging,
                batteryPower: batteryService.metrics.batteryPower,
                sampleAge: batteryService.lastPowerSampleDate.map { Date().timeIntervalSince($0) }
            ), lowLevel: Defaults[.calibrationLowLevel],
            originalLimit: Defaults[.calibrationOriginalLimit]
        )
        guard next != calibrationStage else { return }
        setCalibrationStage(next)
        Defaults[.calibrationHoldUntil] = 0
        if next == .idle {
            let recovery = Defaults[.systemCalibrationRecovery]
            if !recovery { Defaults[.lastCalibrationCompleted] = Date().timeIntervalSince1970 }
            Defaults[.systemCalibrationRecovery] = false
            sendWorkflowNotification(
                title: recovery ? AidenteL10n.t("系统校准后已恢复上限", "Charge Limit Restored After macOS Calibration") : AidenteL10n.t("电池校准完成", "Battery Calibration Complete"),
                body: AidenteL10n.t("电池已恢复原充电上限。", "The original charge limit has been restored.")
            )
        }
    }

    private func applyCalibrationPolicy(
        batteryPercentage: Int,
        desiredCharging: inout Bool,
        desiredAdapter: inout Bool,
        desiredLED: inout MagSafeLEDState?,
        reason: inout String?
    ) {
        switch calibrationStage {
        case .idle:
            return
        case .chargingToFull, .rechargingToFull:
            desiredCharging = true
            desiredAdapter = true
            desiredLED = Defaults[.manageMagSafeLED] ? .orange : nil
            reason = calibrationStage.title
        case .dischargingToLow:
            desiredCharging = false
            desiredAdapter = false
            desiredLED = Defaults[.manageMagSafeLED] ? .blinkOrangeSlow : nil
            reason = AidenteL10n.t(
                "\(calibrationStage.title)，目标 \(Defaults[.calibrationLowLevel])%",
                "\(calibrationStage.title), target \(Defaults[.calibrationLowLevel])%"
            )
        case .holdingAtFull:
            desiredCharging = false
            desiredAdapter = true
            desiredLED = Defaults[.manageMagSafeLED] ? .green : nil
            reason = calibrationStage.title
        case .restoringLimit:
            desiredCharging = false
            desiredAdapter = batteryPercentage <= Defaults[.calibrationOriginalLimit]
            desiredLED = Defaults[.manageMagSafeLED] ? .blinkOrangeSlow : nil
            reason = AidenteL10n.t(
                "\(calibrationStage.title)，目标 \(Defaults[.calibrationOriginalLimit])%",
                "\(calibrationStage.title), target \(Defaults[.calibrationOriginalLimit])%"
            )
        }
    }

    private func applyHeatProtectionIfNeeded(
        temperature: Double,
        desiredCharging: inout Bool,
        desiredLED: inout MagSafeLEDState?,
        reason: inout String?
    ) {
        heatProtectionPaused = thermalPolicy.shouldPause(
            temperature: temperature, limit: Double(Defaults[.heatProtectionLimit]),
            enabled: Defaults[.enableHeatProtectionMode],
            chargingRequested: desiredCharging, now: Date()
        )
        guard heatProtectionPaused else { return }
        desiredCharging = false
        operationStatus = .heatProtection
        if !temperature.isFinite || temperature <= 0 {
            reason = AidenteL10n.t("正在等待有效的电池温度读数，暂缓充电", "Waiting for a valid battery temperature before charging")
        } else if temperature >= Double(Defaults[.heatProtectionLimit]) {
            reason = AidenteL10n.t("电池温度已达到设定上限，温控暂停中", "Battery temperature reached the configured limit; charging is paused")
        } else {
            reason = AidenteL10n.t("温度已回落，等待温控暂停窗口结束", "Battery has cooled; waiting for the thermal pause window to end")
        }
        if Defaults[.manageMagSafeLED] {
            desiredLED = Defaults[.heatProtectionMagSafeLEDState]
        }
    }

    private func setCalibrationStage(_ stage: CalibrationStage) {
        calibrationStage = stage
        Defaults[.calibrationStage] = stage.rawValue
        logger.info("Calibration stage changed to \(stage.rawValue)")
    }

    private func setTopUpActive(_ active: Bool) {
        topUpActive = active
        Defaults[.topUpActive] = active
    }

    private func clearCachedState() {
        lastLEDConfiguration = nil
        lastNotifiedChargingState = nil
        limitPolicy = ChargeLimitPolicy()
    }

    private func resetToDefaults() {
        limitPolicy = ChargeLimitPolicy()
        lastManageChargingEnabled = false
        updateSleepAssertion(shouldPreventSleep: false)
        guard Defaults[.manageCharging] || ChargingHelperManager.shared.isInstalled else { return }
        let capabilities = batteryService.deviceCapabilities
        // Pre-arm sleep protection even when the charger is currently unplugged.
        requestPower(charging: !manualPauseActive || !Defaults[.manageCharging],
                     adapter: true, managed: Defaults[.manageCharging])
        if capabilities.hasMagSafe, capabilities.magsafeLEDControl {
            setLED(state: .reset)
        }
    }

    private func requestPower(charging: Bool, adapter: Bool, managed: Bool, reason: String? = nil) {
        let normalLimit = calibrationStage == .idle && !topUpActive && !SystemCalibrationService.shared.isActive
        let standardCeiling = normalLimit ? min(100, max(20, Defaults[.chargeLimit])) : 100
        let ceiling = usesNativeChargeLimit && !adapter
            ? NativeChargePolicy.dischargeCeiling(standard: standardCeiling, phase: calibrationStage,
                lowLevel: Defaults[.calibrationLowLevel], originalLimit: Defaults[.calibrationOriginalLimit])
            : standardCeiling
        let range = normalLimit && Defaults[.sailingMode] ? max(2, Defaults[.sailingModeLimit]) : 2
        pendingPowerRequest = PowerRequest(
            charging: charging, adapter: adapter, managed: managed,
            stopWhileSleeping: Defaults[.stopChargingWhileSleeping],
            resetOnDisconnect: !Defaults[.stopChargingWhenAppClosed],
            followNaturalDrift: normalLimit && Defaults[.sailingMode] && !manualPauseActive && !heatProtectionPaused,
            chargeCeiling: ceiling, rechargeBelow: max(0, min(ceiling - 1, max(20, ceiling - range)))
        )
        guard powerTask == nil else { return }
        guard pendingPowerRequest != appliedPowerRequest
            || Date().timeIntervalSince(lastPowerApplication) >= 30 else { return }
        powerTask = Task { [weak self] in
            guard let self else { return }
            defer { powerTask = nil }
            while !Task.isCancelled, let request = pendingPowerRequest {
                do {
                    try await batteryService.applyPowerPolicy(
                        charging: request.charging, adapter: request.adapter, managed: request.managed,
                        stopWhileSleeping: request.stopWhileSleeping,
                        resetOnDisconnect: request.resetOnDisconnect, followNaturalDrift: request.followNaturalDrift,
                        chargeCeiling: request.chargeCeiling, rechargeBelow: request.rechargeBelow
                    )
                    let changed = appliedPowerRequest != request
                    appliedPowerRequest = request
                    lastPowerApplication = Date()
                    guard pendingPowerRequest == request else { continue }
                    clearControlErrors()
                    batteryService.scheduleSinglePoll()
                    if request.charging { sendChargingStateNotification(charging: true, reason: reason) }
                    if changed { schedulePowerVerification(request) }
                } catch {
                    appliedPowerRequest = nil
                    guard pendingPowerRequest == request else { continue }
                    if error.localizedDescription.contains("DISCHARGE_SAFETY_STOP") {
                        safetyStopReason = error.localizedDescription.contains("恢复未确认")
                            ? "电量读数异常，已停止主动策略。原设置尚未确认恢复，请修复控制服务。"
                            : "电量显示长时间未更新或安全读数不可用，已停止放电并恢复原设置。充电管理已关闭；请在读数恢复后手动启用。"
                        Defaults[.lastDischargeSafetyStopReason] = safetyStopReason
                        forceDischargeActive = false
                        manualPauseActive = false
                        Defaults[.manualPauseActive] = false
                        Defaults[.automaticDischarge] = false
                        setCalibrationStage(.idle)
                        Defaults[.systemCalibrationRecovery] = false
                        Defaults[.manageCharging] = false
                        verificationTask?.cancel()
                        updateSleepAssertion(shouldPreventSleep: false)
                    }
                    chargingControlError = AidenteL10n.t(
                        "充电控制未生效：\(error.localizedDescription)",
                        "Charging control did not take effect: \(error.localizedDescription)"
                    )
                    logger.error("POWER_REQUEST_FAILED \(error.localizedDescription, privacy: .public)")
                    lastNotifiedChargingState = nil
                }
                break
            }
        }
    }

    private func schedulePowerVerification(_ request: PowerRequest) {
        verificationTask?.cancel()
        powerFlowError = nil
        powerHoldVerified = false
        guard request.managed, !request.charging, request.adapter else { return }
        verificationTask = Task { [weak self] in
            var verification = ChargeHoldVerification()
            var lastSample: Date?
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                guard let self, pendingPowerRequest == request, !isSystemSleeping else { return }
                await batteryService.refreshPowerForVerification()
                guard !Task.isCancelled, pendingPowerRequest == request, !isSystemSleeping else { return }
                guard batteryService.adapterMetrics.adapterConnected else {
                    verification = ChargeHoldVerification()
                    powerHoldVerified = false
                    powerFlowError = nil
                    continue
                }
                guard let sampleDate = batteryService.lastPowerSampleDate,
                      sampleDate != lastSample, Date().timeIntervalSince(sampleDate) < 15 else {
                    verification = ChargeHoldVerification()
                    powerHoldVerified = false
                    continue
                }
                lastSample = sampleDate
                switch verification.sample(batteryPower: batteryService.metrics.batteryPower) {
                case .pending: powerHoldVerified = false
                case .held:
                    powerHoldVerified = true
                    powerFlowError = nil
                    sendChargingStateNotification(charging: false, reason: nil)
                case .charging:
                    powerHoldVerified = false
                    powerFlowError = AidenteL10n.t(
                        "已请求暂停，但电池仍持续充电；尚未实现限充保持。",
                        "Charging hold requested, but the battery is still charging."
                    )
                case .discharging:
                    powerHoldVerified = false
                    powerFlowError = AidenteL10n.t(
                        "已请求暂停且适配器已连接，但电池仍持续放电。可能受固件或适配器供电能力限制，尚未实现适配器供电保持。",
                        "Hold requested with AC connected, but the battery is still discharging. Firmware or adapter capacity may prevent an AC-powered hold."
                    )
                }
            }
        }
    }

    private func setLED(state: MagSafeLEDState) {
        logger.info("Setting MagSafe LED: \(String(describing: state))")
        Task {
            do {
                try await batteryService.manageMagsafeLED(target: state)
            } catch {
                logger.error("Failed to set LED to \(String(describing: state)): \(error)")
            }
        }
    }

    private func updateSleepAssertion(shouldPreventSleep: Bool) {
        SleepBehaviorService.shared.update(automatic: shouldPreventSleep,
            percentage: batteryService.metrics.batteryPercentage,
            adapterConnected: batteryService.adapterMetrics.adapterConnected)
    }

    private func sendChargingStateNotification(charging: Bool, reason: String?) {
        guard charging != lastNotifiedChargingState else { return }
        lastNotifiedChargingState = charging

        guard !Defaults[.disableNotifications],
            Defaults[.showChargingStatusChangedNotification]
        else { return }

        let content = UNMutableNotificationContent()
        content.title = AidenteL10n.t(
            charging ? "已恢复充电" : "已暂停充电",
            charging ? "Charging Resumed" : "Charging Paused"
        )
        if let reason {
            content.body = reason
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "chargingStateChanged",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Failed to deliver notification: \(error)")
            }
        }
    }

    private func sendWorkflowNotification(title: String, body: String) {
        guard !Defaults[.disableNotifications] else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "workflow-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func startTopUp() {
        guard !SystemCalibrationService.shared.isActive else { return }
        cancelCalibration(reevaluate: false)
        forceDischargeActive = false
        manualPauseActive = false
        Defaults[.manualPauseActive] = false
        setTopUpActive(true)
        evaluate(controlState: batteryService.controlState)
    }

    func stopTopUp() {
        guard !SystemCalibrationService.shared.isActive else { return }
        setTopUpActive(false)
        evaluate(controlState: batteryService.controlState)
    }

    func startCalibration() {
        guard !SystemCalibrationService.shared.isActive else { return }
        Defaults[.systemCalibrationRecovery] = false
        Defaults[.calibrationOriginalLimit] = Defaults[.chargeLimit]
        Defaults[.calibrationHoldUntil] = 0
        setTopUpActive(false)
        forceDischargeActive = false
        manualPauseActive = false
        Defaults[.manualPauseActive] = false
        setCalibrationStage(.chargingToFull)
        evaluate(controlState: batteryService.controlState)
    }

    func cancelCalibration(reevaluate: Bool = true) {
        guard !SystemCalibrationService.shared.isActive else { return }
        Defaults[.systemCalibrationRecovery] = false
        setCalibrationStage(.idle)
        Defaults[.calibrationHoldUntil] = 0
        if reevaluate {
            evaluate(controlState: batteryService.controlState)
        }
    }

    func pauseCharging() {
        guard !SystemCalibrationService.shared.isActive else { return }
        Defaults[.chargeLimit] = min(100, max(20, batteryService.metrics.batteryPercentage))
        setTopUpActive(false)
        forceDischargeActive = false
        cancelCalibration(reevaluate: false)
        manualPauseActive = true
        Defaults[.manualPauseActive] = true
        evaluate(controlState: batteryService.controlState)
    }

    func resumeNormalManagement() {
        guard !SystemCalibrationService.shared.isActive else { return }
        setTopUpActive(false)
        forceDischargeActive = false
        cancelCalibration(reevaluate: false)
        manualPauseActive = false
        Defaults[.manualPauseActive] = false
        evaluate(controlState: batteryService.controlState)
    }

    func startDischarge(to target: Int) {
        guard !SystemCalibrationService.shared.isActive else { return }
        let target = min(100, max(20, target))
        Defaults[.chargeLimit] = target
        if target >= batteryService.metrics.batteryPercentage { resumeNormalManagement(); return }
        setTopUpActive(false)
        cancelCalibration(reevaluate: false)
        manualPauseActive = false
        Defaults[.manualPauseActive] = false
        Defaults[.forcedDischargeTarget] = min(max(target, 20), 100)
        forceDischargeActive = true
        evaluate(controlState: batteryService.controlState)
    }

    func toggleChargeLimitOverride() {
        topUpActive ? stopTopUp() : startTopUp()
    }

    func toggleForceDischarge() {
        if forceDischargeActive {
            resumeNormalManagement()
        } else {
            startDischarge(to: Defaults[.chargeLimit])
        }
    }

    func consoleSessionChanged(active: Bool) {
        powerTask?.cancel()
        verificationTask?.cancel()
        updateSleepAssertion(shouldPreventSleep: false)
        appliedPowerRequest = nil
        pendingPowerRequest = nil
        if active {
            ChargingHelperManager.shared.resumeConsoleSession()
            clearControlErrors()
            clearCachedState()
            checkControlService()
            evaluate(controlState: batteryService.controlState)
        } else {
            ChargingHelperManager.shared.disconnect()
        }
    }

    func prepareForSleep() {
        wakeTask?.cancel()
        isSystemSleeping = true
        verificationTask?.cancel()
    }

    func resumeFromSleep() {
        appliedPowerRequest = nil
        wakeTask?.cancel()
        wakeTask = Task {
            await batteryService.refreshAfterWake()
            guard !Task.isCancelled else { return }
            isSystemSleeping = false
            checkControlService()
        }
    }

    func configureHelperDisconnectPolicy() {
        guard !AidenteRuntime.isUIPreview else { return }
        guard Defaults[.manageCharging] else { return }
        let resetOnDisconnect = !Defaults[.stopChargingWhenAppClosed]
        Task {
            do {
                try batteryService.setResetOnDisconnect(resetOnDisconnect)
            } catch {
                logger.warning(
                    "Could not update helper disconnect policy: \(error.localizedDescription)"
                )
            }
        }
    }

    func checkControlService() {
        guard !AidenteRuntime.isUIPreview else { return }
        guard Defaults[.manageCharging] else {
            clearControlErrors()
            return
        }
        guard !ChargingHelperManager.shared.isRunningFromDiskImage else {
            serviceControlError =
                ChargingHelperManagerError.runningFromDiskImage.localizedDescription
            return
        }

        Task {
            do {
                try await batteryService.checkChargingHelper()
                clearControlErrors()
                evaluate(controlState: batteryService.controlState)
            } catch {
                serviceControlError = AidenteL10n.t(
                    "后台控制服务未连接：\(error.localizedDescription)",
                    "Background control service is not connected: \(error.localizedDescription)"
                )
            }
        }
    }

    func recheckSystemCalibration() { evaluate(controlState: batteryService.controlState) }

    func retryControlAfterRepair() {
        appliedPowerRequest = nil
        clearControlErrors()
        clearCachedState()
        evaluate(controlState: batteryService.controlState)
        checkControlService()
    }

    // Wait for command acceptance; physical charge-hold verification continues
    // independently using fresh power samples and is never implied here.
    func waitForControlRequest() async throws {
        while let task = powerTask { await task.value }
        if let error = controlError { throw XPCError.commandFailed(error) }
    }

    func prepareForCompleteUninstall() async {
        isDisablingControl = true
        scheduleObservation?.cancel(); scheduleObservation = nil
        settingsObservation?.cancel(); settingsObservation = nil
        metricsObservation?.cancel(); metricsObservation = nil
        wakeTask?.cancel()
        verificationTask?.cancel()
        let inFlight = powerTask
        inFlight?.cancel()
        await inFlight?.value
        powerTask = nil
        pendingPowerRequest = nil
        updateSleepAssertion(shouldPreventSleep: false)
    }

    func resumeAfterUninstallFailure(serviceRemoved: Bool) {
        appliedPowerRequest = nil
        clearCachedState()
        if serviceRemoved {
            Defaults[.manageCharging] = false
            appliedPowerRequest = nil
            clearControlErrors()
            operationStatus = .monitoring
            // Keep tasks stopped after partial cleanup so they cannot recreate
            // deleted preferences or submit new policies while the user retries.
            return
        }
        isDisablingControl = false
        startObservingMetrics()
        startObservingSettings()
        startScheduleMonitoring()
    }

    func disableChargingManagement() async throws {
        guard !isDisablingControl else { return }
        isDisablingControl = true
        defer { isDisablingControl = false }
        powerTask?.cancel()
        await powerTask?.value
        // A routine on/off toggle restores the original policy through the
        // already-authorized service. Full removal is a separate App action.
        try await batteryService.restorePowerDefaults()
        Defaults[.manageCharging] = false
        pendingPowerRequest = nil
        appliedPowerRequest = nil
        verificationTask?.cancel()
        powerFlowError = nil
        powerHoldVerified = false
        clearControlErrors()
        operationStatus = .monitoring
        updateSleepAssertion(shouldPreventSleep: false)
    }

    private func clearControlErrors() {
        serviceControlError = nil
        chargingControlError = nil
        adapterControlError = nil
    }

    func handleAutomationURL(_ url: URL) {
        guard !AidenteRuntime.isUIPreview, ConsoleSessionPolicy.currentUserIsActive, !SystemCalibrationService.shared.isActive else { return }
        let action = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?
            .first(where: { $0.name == "value" })?
            .value
            .flatMap(Int.init)

        switch action {
        case "set-limit":
            if let value {
                Defaults[.chargeLimit] = min(max(value, 20), 100)
                resumeNormalManagement()
            }
        case "top-up":
            startTopUp()
        case "calibrate":
            startCalibration()
        case "pause":
            pauseCharging()
        case "discharge":
            startDischarge(to: value ?? Defaults[.chargeLimit])
        case "resume":
            resumeNormalManagement()
        default:
            logger.warning("Ignored unknown automation URL: \(url.absoluteString)")
        }
    }

    func stop() {
        wakeTask?.cancel()
        powerTask?.cancel()
        verificationTask?.cancel()
        metricsObservation?.cancel()
        metricsObservation = nil
        settingsObservation?.cancel()
        settingsObservation = nil
        scheduleObservation?.cancel()
        scheduleObservation = nil
        updateSleepAssertion(shouldPreventSleep: false)
    }
}
