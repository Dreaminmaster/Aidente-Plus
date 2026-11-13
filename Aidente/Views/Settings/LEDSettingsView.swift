import Defaults
import SwiftUI

struct LEDSettingsView: View {
    var onOpenChargeSettings: () -> Void = {}
    @Default(.manageCharging) private var chargingManaged
    @Default(.interfaceAppearance) private var appearance
    @State private var error: String?
    @Default(.manageMagSafeLED) private var managed
    @Default(.ledBehavior) private var behavior
    @Default(.blinkLEDWhileDischarging) private var blink
    var body: some View {
        AidenteSettingsPage {
            AidenteControlRow("界面外观", subtitle: "跟随 macOS，或只为 Aidente 固定浅色、深色；立即应用到菜单、仪表板和设置窗口。", icon: "circle.lefthalf.filled", colors: []) {
                Picker(AidenteL10n.t("界面外观", "Appearance"), selection: $appearance) {
                    ForEach(InterfaceAppearance.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 160)
            }

            if !chargingManaged {
                HStack(spacing: 8) {
                    Text(AidenteL10n.t("管理指示灯需要先启用管理充电。", "LED control requires charging management."))
                    Button(AidenteL10n.t("前往充电控制", "Open Charge Control"), action: onOpenChargeSettings).buttonStyle(.link)
                }.font(.caption)
            }
            AidenteCard("MagSafe 指示灯", subtitle: "在支持的机型上控制充电、放电和睡眠指示。", icon: "lightbulb", colors: AidenteTheme.automationColors) {
                AidenteSettingToggle("由 Aidente 管理指示灯", subtitle: "开启后可让灯光表示充电状态、一直关闭，或仅睡眠时关闭。关闭此开关会将灯光控制交还 macOS。", icon: "lightbulb", colors: [], isOn: $managed)
                AidenteControlRow("指示灯模式", subtitle: "指示充电上限：保持时显示绿色，充电时显示橙色；始终关闭：一直熄灯；睡眠时关闭：仅在睡眠时熄灯。只控制灯光，不改变充电上限。", icon: "lightbulb", colors: []) {
                    Picker(AidenteL10n.t("指示灯模式", "LED Setting"), selection: $behavior) {
                        ForEach(LEDBehavior.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 180).disabled(!managed)
                }
                AidenteSettingToggle("放电时闪烁橙灯", subtitle: "主动放电期间使用闪烁橙灯；关闭后使用常亮橙灯。始终关闭和睡眠关闭模式优先。", icon: "lightbulb.max", colors: [], isOn: $blink).disabled(!managed)
                Text(AidenteL10n.t("睡眠时关闭由后台服务执行。设备或固件不提供 LED 控制时，设置不会强制生效。", "Off During Sleep is applied by the helper. Unsupported hardware or firmware cannot be forced to accept LED control."))
                    .font(.caption).foregroundStyle(.secondary)
                if let error {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).foregroundStyle(.red)
                        Button(AidenteL10n.t("前往充电控制", "Open Charge Control"), action: onOpenChargeSettings).buttonStyle(.link)
                    }.font(.caption)
                }
            }.disabled(!chargingManaged)
        }
        .onChange(of: managed) { _, _ in apply() }
        .onChange(of: behavior) { _, _ in apply() }
        .onChange(of: blink) { _, _ in apply() }
    }
    private func apply() {
        guard !AidenteRuntime.isUIPreview else { return }
        Task { do { try await ApplicationActions.shared.execute("led-policy"); error = nil } catch { self.error = error.localizedDescription } }
    }
}
