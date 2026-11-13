import ApplicationServices
import Defaults
import SwiftUI

struct SleepSettingsView: View {
    var nativeLimitOnly = false
    @Default(.disableSleepUntilChargeLimit) private var untilLimit
    @Default(.stopChargingWhileSleeping) private var stopSleeping
    @Default(.stopChargingWhenAppClosed) private var stopClosed
    @Default(.preventDisplaySleep) private var preventDisplay
    @Default(.muteWhileDisplaySleeps) private var mute
    @Default(.lockWhenLidClosed) private var lock
    @Default(.sleepResumePercentage) private var percentage
    @Default(.sleepStopOnUnplug) private var stopUnplug
    @State private var showAdvanced = false
    private let service = SleepBehaviorService.shared
    var body: some View {
        AidenteSettingsPage {
            AidenteCard("防止睡眠期间过充电", icon: "minus.circle", colors: []) {
                UtilitySurface {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(AidenteL10n.t("选择 Aidente 在睡眠和充电时的行为方式", "Choose how Aidente handles sleep while charging")).font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { untilLimit ? 2 : stopSleeping ? 1 : 0 }, set: { value in
                            untilLimit = value == 2; stopSleeping = value == 1
                        })) {
                            Text(AidenteL10n.t("像以前一样继续", "Continue as Before")).tag(0)
                            Text(AidenteL10n.t("睡眠时暂停充电", "Pause Charging During Sleep")).tag(1)
                            Text(AidenteL10n.t("达到上限前阻止睡眠", "Prevent Sleep Until Charge Limit")).tag(2)
                        }.labelsHidden().disabled(nativeLimitOnly)
                        if nativeLimitOnly {
                            Text("系统原生限充在睡眠期间由 macOS 维护；不支持 Aidente 的睡眠精确暂停策略。其他睡眠工具仍可单独使用。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Label(AidenteL10n.t("睡眠时系统检查频率会降低，电量可能略微超过上限。", "During sleep, reduced polling can allow a small overshoot."), systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            AidenteCard("手动睡眠控制", icon: "moon.zzz", colors: []) {
                UtilitySurface {
                    VStack(spacing: 12) {
                        HStack { Label(AidenteL10n.t("在以下电量时重新允许睡眠", "Allow Sleep Below"), systemImage: "battery.25percent"); Spacer(); Text("\(percentage)%").fontWeight(.semibold) }
                        Slider(value: Binding(get: { Double(percentage) }, set: { percentage = Int($0) }), in: 5...95, step: 1)
                        HStack { Text("5%"); Spacer(); Text("95%") }.font(.caption).foregroundStyle(.secondary)
                        AidenteSettingToggle("拔下充电器时重新允许睡眠", icon: "powerplug", colors: [], isOn: $stopUnplug)
                    }
                }
                UtilitySurface { SleepControlWidget() }
            }
            DisclosureGroup(AidenteL10n.t("显示高级设置", "Show Advanced Settings"), isExpanded: $showAdvanced) {
                VStack(spacing: 14) {
                    AidenteSettingToggle("阻止显示器睡眠和屏幕保护", icon: "display", colors: [], isOn: $preventDisplay)
                    AidenteSettingToggle("阻止睡眠期间，显示器关闭时静音", icon: "speaker.slash", colors: [], isOn: $mute)
                    AidenteSettingToggle("退出后保持充电状态", icon: "power", colors: [], isOn: $stopClosed)
                    AidenteSettingToggle("无外接屏幕时合盖锁屏", subtitle: "此选项需要辅助功能权限", icon: "lock", colors: [], isOn: Binding(
                        get: { lock }, set: { enabled in
                            guard !AidenteRuntime.isUIPreview else { return }
                            if !enabled { lock = false }
                            else if AXIsProcessTrusted() { lock = true }
                            else { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
                        }))
                Text(AidenteL10n.t("仅合盖锁屏选项需要辅助功能授权，用于发送系统锁屏快捷键。普通限充和监测不需要。阻止闲置睡眠不能保证绕过系统强制睡眠或所有机型的合盖行为。", "Only lid-close locking requires Accessibility, to send the system lock shortcut. Monitoring and charging do not. Preventing idle sleep does not override forced sleep or every model’s lid behavior."))
                    .font(.caption).foregroundStyle(.secondary)
                if let error = service.error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(.top, 14)
            }
        }
    }
}
struct SleepControlWidget: View {
    private let service = SleepBehaviorService.shared
    @State private var custom = 60
    @State private var customOpen = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(service.manualActive ? AidenteL10n.t("正在阻止睡眠", "Preventing Sleep") : AidenteL10n.t("睡眠", "Sleep"), systemImage: "moon")
                Spacer(); Text(service.remaining).monospacedDigit()
                if service.manualActive { Button(AidenteL10n.t("停止", "Stop")) { service.stopManual() } }
                else {
                    Menu(AidenteL10n.t("阻止", "Prevent")) {
                        ForEach([30,60,180], id: \.self) { minutes in
                            Button("\(minutes) min") { service.prevent(minutes: minutes) }
                        }
                        Button("∞") { service.prevent(minutes: nil) }
                        Button(AidenteL10n.t("自定义…", "Custom…")) { customOpen = true }
                    }
                }
            }
            if customOpen { HStack {
                Stepper("\(custom) min", value: $custom, in: 1...10080)
                Button(AidenteL10n.t("自定义时长", "Start Custom Duration")) { service.prevent(minutes: custom) }
            }.font(.caption) }
            if let error = service.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.disabled(AidenteRuntime.isUIPreview)
    }
}
