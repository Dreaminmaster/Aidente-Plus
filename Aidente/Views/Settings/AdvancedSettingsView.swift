import SwiftUI

struct AdvancedSettingsView: View {
    var body: some View {
        AidenteSettingsPage {
            AidenteCard("电量读取方式", subtitle: "充电策略与 macOS 菜单栏保持一致。", icon: "sensor.fill", colors: AidenteTheme.advancedColors) {
                Text(AidenteL10n.t("限充、巡航、放电和校准统一使用 macOS 显示电量。硬件电量可作为独立菜单栏项目查看，不改变控制依据。", "Charge limits, sailing, discharge and calibration use the macOS battery percentage. Hardware percentage is available as a separate menu bar readout."))
                Text(AidenteL10n.t("硬件寄存器仍使用硬件电量边界；固件与 macOS 百分比的映射需要逐机验证。", "Firmware boundaries still use hardware capacity; mapping to the macOS percentage needs per-machine validation."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
