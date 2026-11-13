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
            AidenteCard("睡眠期间的充电行为", icon: "minus.circle", colors: []) {
                UtilitySurface {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(AidenteL10n.t("选择 Aidente 在睡眠和充电时的行为方式", "Choose how Aidente handles sleep while charging")).font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { untilLimit ? 2 : stopSleeping ? 1 : 0 }, set: { value in
                            untilLimit = value == 2; stopSleeping = value == 1
                        })) {
                            Text(AidenteL10n.t("保持当前充电策略", "Keep Charging Policy")).tag(0)
                            Text(AidenteL10n.t("睡眠时暂停充电", "Pause Charging During Sleep")).tag(1)
                            Text(AidenteL10n.t("达到上限前阻止睡眠", "Prevent Sleep Until Charge Limit")).tag(2)
                        }.labelsHidden().disabled(nativeLimitOnly)
                        if nativeLimitOnly {
                            Text("系统原生限充在睡眠期间由 macOS 维护；不支持 Aidente 的睡眠精确暂停策略。其他睡眠工具仍可单独使用。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(untilLimit
                            ? AidenteL10n.t("在低于上限且正在充电时阻止闲置睡眠，达到上限后恢复。手动强制睡眠和部分机型的合盖行为仍由系统决定。", "Prevents idle sleep while charging below the limit, then releases it. Forced sleep and lid behavior remain controlled by macOS.")
                            : stopSleeping
                            ? AidenteL10n.t("进入睡眠前暂停充电，唤醒后恢复正常管理。适合希望正常睡眠、睡眠期间不继续充电的情况。", "Pauses charging before sleep and resumes normal management after wake.")
                            : AidenteL10n.t("允许正常睡眠，后台继续维持现有充电上限；系统在睡眠时可能降低检查频率。", "Allows normal sleep while the helper maintains the charge limit; macOS may reduce checks during sleep."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(AidenteL10n.t("更改选项后仍会核对真实充电功率；“待确认”表示正在等待读数，并不表示已经确认暂停。", "Power readings are still verified after changes. Verifying means waiting for evidence, not a confirmed pause."))
                            .font(.caption).foregroundStyle(.secondary)
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
