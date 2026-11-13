import Defaults
import AidenteShared
import SwiftUI
import os.log
import smc_power

struct ChargingSettingsView: View {
    @Default(.appLanguage) private var appLanguage

    @Default(.manageCharging) var manageCharging
    @Default(.chargeLimit) var chargeLimit
    @Default(.allowBelow80) private var below80
    @Default(.lastCalibrationCompleted) private var lastCalibration
    @Default(.afterSystemCalibration) private var afterSystemCalibration
    @Default(.sailingMode) var sailingMode
    @Default(.sailingModeLimit) var sailingModeLimit
    @Default(.automaticDischarge) var automaticDischarge
    @Default(.disableSleepUntilChargeLimit) var disableSleepUntilChargeLimit
    @Default(.enableHeatProtectionMode) var enableHeatProtectionMode
    @Default(.heatProtectionLimit) var heatProtectionLimit
    @Default(.manageMagSafeLED) var manageMagSafeLED
    @Default(.heatProtectionMagSafeLEDState) var heatProtectionMagSafeLEDState
    @Default(.stopChargingWhenAppClosed) var stopChargingWhenAppClosed
    @Default(.stopChargingWhileSleeping) var stopChargingWhileSleeping
    @Default(.calibrationLowLevel) var calibrationLowLevel
    @State private var helperManager = ChargingHelperManager.shared
    @State private var installError: String?
    @State private var discardSystemSession = false

    private let capabilities: DeviceCapabilities
    private let chargeManager: ChargeManager

    private let logger = Logger(
        subsystem: "com.aidente.app",
        category: "ChargingSettingsView"
    )

    init(capabilities: DeviceCapabilities, chargeManager: ChargeManager) {
        self.capabilities = capabilities
        self.chargeManager = chargeManager
    }

    private var hasChargingControl: Bool {
        capabilities.chargingControl
    }

    private var hasAdapterControl: Bool {
        capabilities.adapterControl
    }

    private var hasMagSafe: Bool {
        capabilities.hasMagSafe
    }

    private var hasAnyControl: Bool {
        hasChargingControl || hasAdapterControl
    }

    private var sailingResumePercentage: Int {
        chargeLimit - sailingModeLimit
    }

    var body: some View {
        AidenteSettingsPage {
            if chargeManager.usesNativeChargeLimit {
                AidenteCard("系统充电策略", subtitle: "由 macOS 执行上限，Aidente 管理暂停、回充和保护策略。", icon: "info.circle", colors: []) {
                    Text("普通限充和暂停会在当前电量保持，降低设置不会自动触发放电；只有手动放电、自动放电或校准会向较低电量运行。低于 80% 的策略通过已授权的后台服务执行。此机的保持供电与睡眠行为仍需分别实测确认。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                AidenteControlRow("充电上限", subtitle: "限制最高充电量，减少电池长期处于满电状态的时间。", icon: "battery.25percent", colors: []) {
                    HStack(spacing: 4) {
                        TextField("", value: Binding(get: { chargeLimit }, set: { chargeLimit = min(100, max(below80 ? 20 : 80, $0)) }), format: .number)
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(width: 48)
                            .accessibilityLabel(AidenteL10n.t("充电上限", "Charge Limit")).disabled(SystemCalibrationService.shared.isActive)
                        Text("%")
                    }
                }
                AidenteSettingToggle("允许低于 80% 的充电上限", icon: "exclamationmark.triangle", colors: [], isOn: $below80)
                    .onChange(of: below80) { _, enabled in if !enabled && chargeLimit < 80 { chargeLimit = 80 } }
                AidenteSettingToggle("自动放电", subtitle: "接入电源或降低上限时，若高出目标超过 1%，主动放电至目标；默认关闭。", icon: "bolt.badge.a", colors: [], isOn: $automaticDischarge)
            }
            VStack(spacing: 12) {
                AidenteSettingToggle("航海模式", subtitle: "允许电量在上限附近自然浮动，减少频繁微量补电。", icon: "paperplane.fill", colors: [], isOn: $sailingMode)
                UtilitySurface {
                    if sailingMode {
                        VStack(spacing: 12) {
                            HStack { Text(AidenteL10n.t("恢复充电电量", "Resume Charging At")); Spacer(); Text("\(max(20, sailingResumePercentage))%").fontWeight(.semibold) }
                            Slider(value: Binding(get: { Double(sailingModeLimit) }, set: { sailingModeLimit = Int($0) }), in: 2...20, step: 1)
                            Text(AidenteL10n.t("允许电量在 \(max(20, sailingResumePercentage))%–\(chargeLimit)% 之间浮动", "Battery may sail between \(max(20, sailingResumePercentage))% and \(chargeLimit)%")).font(.caption).foregroundStyle(.secondary)
                        }
                    } else { Text(AidenteL10n.t("航海模式已关闭。", "Sailing Mode is off.")).frame(maxWidth: .infinity).padding(.vertical, 4) }
                }
            }
            VStack(spacing: 12) {
                AidenteSettingToggle("过热保护", subtitle: "温度超过阈值时暂停充电，并通过五分钟迟滞避免频繁切换。", icon: "flame", colors: [], isOn: $enableHeatProtectionMode)
                UtilitySurface {
                    if enableHeatProtectionMode {
                        VStack(spacing: 12) {
                            HStack { Text(AidenteL10n.t("温度上限", "Temperature Limit")); Spacer(); Text("\(heatProtectionLimit)°C").fontWeight(.semibold) }
                            Slider(value: Binding(get: { Double(heatProtectionLimit) }, set: { heatProtectionLimit = Int($0) }), in: 30...50, step: 1)
                        }
                    } else { Text(AidenteL10n.t("过热保护已关闭。", "Heat Protection is off.")).frame(maxWidth: .infinity).padding(.vertical, 4) }
                }
            }
            VStack(spacing: 12) {
                AidenteControlRow("校准模式", subtitle: "完全充满 → 放电 → 再完全充满 → 恢复原上限。", icon: "slider.vertical.3", colors: []) {
                    Button(AidenteL10n.t(chargeManager.calibrationStage == .idle ? "开始校准" : "取消校准")) {
                        chargeManager.calibrationStage == .idle ? chargeManager.startCalibration() : chargeManager.cancelCalibration()
                    }.buttonStyle(AidenteActionButtonStyle(colors: [])).disabled(!manageCharging || AidenteRuntime.isUIPreview || SystemCalibrationService.shared.isActive)
                }
                UtilitySurface {
                    VStack(spacing: 16) {
                        HStack(alignment: .center) {
                            calibrationStep("battery.100percent", "100%", .green)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            calibrationStep("battery.25percent", "\(calibrationLowLevel)%", .orange)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            calibrationStep("battery.100percent", "100%", .green)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            calibrationStep("battery.75percent", "\(chargeLimit)%", .orange)
                        }
                        Divider()
                        HStack {
                            Text(AidenteL10n.t("放电目标", "Discharge Target"))
                            Spacer()
                            Stepper("\(calibrationLowLevel)%", value: $calibrationLowLevel, in: 5...20).fixedSize()
                        }
                    }
                }
                HStack { Spacer(); Text(lastCalibration > 0 ? AidenteL10n.t("上次校准：", "Last calibration: ") + Date(timeIntervalSince1970: lastCalibration).formatted(date: .numeric, time: .omitted) : AidenteL10n.t("尚无 Aidente 校准记录", "No Aidente calibration recorded")).font(.caption).foregroundStyle(.secondary) }
            }
            AidenteCard("macOS 校准后", subtitle: "凭新近系统证据识别校准，连续确认完全充满后执行所选动作；系统标志未释放时不会重复触发。", icon: "slider.horizontal.2.arrow.trianglehead.counterclockwise", colors: []) {
                Picker("", selection: $afterSystemCalibration) {
                    Text(AidenteL10n.t("放电至充电上限", "Discharge to Charge Limit")).tag(AfterSystemCalibration.dischargeToLimit)
                    Text(AidenteL10n.t("继续 Aidente 校准", "Continue Aidente Calibration")).tag(AfterSystemCalibration.continueCalibration)
                }.labelsHidden()
                Text(SystemCalibrationService.shared.status).font(.caption).foregroundStyle(.secondary)
                Button(AidenteL10n.t("重新检查系统校准状态", "Check System Calibration")) { Task { await SystemCalibrationService.shared.refresh() } }.disabled(SystemCalibrationService.shared.checking)
                if SystemCalibrationService.shared.canDiscardStaleSession {
                    Button(AidenteL10n.t("解除过期跟随状态…", "Dismiss Stale Follow-up…")) { discardSystemSession = true }
                }
            }
            UtilitySurface {
                VStack(spacing: 10) {
                    AidenteSettingToggle("管理充电", subtitle: "首次启用或升级需管理员授权安装后台服务，无需开发者账号", icon: "switch.2", colors: [], isOn: Binding(get: { manageCharging && helperManager.isInstalled && helperManager.registrationError == nil }, set: { toggleManageCharging($0) }))
                        .disabled(helperManager.isBusy || AidenteRuntime.isUIPreview || helperManager.isRunningFromDiskImage)
                    HStack {
                        Text(AidenteRuntime.isUIPreview ? AidenteL10n.t("界面预览 · 不会控制充电", "UI Preview · No charging control") : chargeManager.operationStatusTitle).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(AidenteL10n.t("修复控制服务", "Repair Control Service")) { repairControlService() }
                            .disabled(helperManager.isBusy || AidenteRuntime.isUIPreview || helperManager.isRunningFromDiskImage)
                    }
                    if let error = chargeManager.controlError { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
        }
        .confirmationDialog(AidenteL10n.t("恢复普通限充？这不会中断 macOS 自身的校准。", "Resume normal charge limiting? This cannot interrupt macOS calibration."), isPresented: $discardSystemSession) {
            Button(AidenteL10n.t("恢复普通限充", "Resume Normal Charge Limiting")) { SystemCalibrationService.shared.discardStaleSession() }
        }
        .animation(.easeInOut(duration: 0.16), value: sailingMode)
        .animation(.easeInOut(duration: 0.16), value: enableHeatProtectionMode)
        .alert(AidenteL10n.t("无法启用充电控制服务"), isPresented: Binding(get: { installError != nil }, set: { if !$0 { installError = nil } })) {
            Button(AidenteL10n.t("好")) { installError = nil }
        } message: { Text(installError ?? "") }
    }
    private func calibrationStep(_ icon: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 25)).foregroundStyle(color)
            Text(label).font(.caption).monospacedDigit()
        }.frame(maxWidth: .infinity).padding(.vertical, 5)
    }

    private func toggleManageCharging(_ enabled: Bool) {
        Task {
            do {
                if enabled {
                    guard try await BatteryManagementSetup.shared.enable() else { return }
                    await PowerMetadataService.shared.refreshSystemFullCharge()
                } else {
                    try await chargeManager.disableChargingManagement()
                }
            } catch {
                logger.error("Failed to \(enabled ? "install" : "uninstall") charging helper: \(error)")
                installError = error.localizedDescription
            }
        }
    }

    private func checkApprovalStatus() {
        helperManager.refreshStatus()
        if helperManager.helperStatus == .installed {
            toggleManageCharging(true)
        }
    }

    private func repairControlService() {
        Task {
            do {
                try await helperManager.repair()
                if helperManager.helperStatus == .installed {
                    manageCharging = true
                    chargeManager.retryControlAfterRepair()
                    await PowerMetadataService.shared.refreshSystemFullCharge()
                }
            } catch {
                logger.error("Failed to repair charging helper: \(error)")
                installError = error.localizedDescription
            }
        }
    }
}
