import SwiftUI

struct AdvancedSettingsView: View {
    var onNavigate: (SettingsTab) -> Void
    var body: some View {
        AidenteSettingsPage {
            AidenteCard("高级设置", subtitle: "打开对应页面直接调整。", icon: "slider.horizontal.3", colors: []) {
                UtilitySurface {
                    VStack(spacing: 16) {
                        destination("睡眠与合盖", detail: "显示器睡眠、静音、合盖锁屏", icon: "moon", tab: .sleep)
                        Divider()
                        destination("功耗与后台进程", detail: "按电池/电源选择模式与 App 用量范围", icon: "leaf", tab: .energy)
                        Divider()
                        destination("充电控制", detail: "睡眠、退出后的充电策略与校准", icon: "battery.100.bolt", tab: .charging)
                        Divider()
                        destination("诊断", detail: "查看读数、控制服务和日志", icon: "waveform.path.ecg", tab: .diagnostics)
                    }
                }
            }
            DisclosureGroup(AidenteL10n.t("关于电量读取", "About Battery Readings")) {
                Text(AidenteL10n.t("限充、航海、放电和校准统一使用 macOS 显示电量。硬件电量可作为独立菜单栏项目查看，不改变控制依据。", "Charging policies use the macOS battery percentage. Hardware percentage is an optional readout."))
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }
    private func destination(_ title: String, detail: String, icon: String, tab: SettingsTab) -> some View {
        Button { onNavigate(tab) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) { Text(AidenteL10n.t(title)); Text(AidenteL10n.t(detail)).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
