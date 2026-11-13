import AppKit
import SwiftUI

struct ShortcutsSettingsView: View {
    private let actions = ["设置充电上限", "充满电", "暂停充电", "恢复充电管理", "开始放电", "开始电池校准", "停止电池校准", "启用低功耗模式", "关闭低功耗模式", "启用高功耗模式", "关闭高功耗模式", "设置 MagSafe 指示灯", "暂时阻止睡眠", "恢复系统睡眠", "获取电池电量", "获取充电上限", "获取电池温度", "获取充电状态"]
    @State private var search = ""
    @State private var urls = false
    var body: some View {
        AidenteSettingsPage {
            AidenteCard("Apple 快捷指令", icon: "square.stack.3d.up", colors: []) {
                Text(AidenteL10n.t("在快捷指令中搜索 Aidente，将以下动作加入你的工作流程。", "Search for Aidente in Shortcuts to add these actions to your workflows.")).font(.callout).foregroundStyle(.secondary)
                Button(AidenteL10n.t("打开快捷指令", "Open Shortcuts")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                }.buttonStyle(AidenteActionButtonStyle(colors: []))
                TextField(AidenteL10n.t("查找动作", "Find an Action"), text: $search).textFieldStyle(.roundedBorder)
                UtilitySurface {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                        ForEach(actions.filter { search.isEmpty || AidenteL10n.t($0).localizedCaseInsensitiveContains(search) }, id: \.self) { action in
                            Label(AidenteL10n.t(action), systemImage: action.contains("获取") ? "info.circle" : action.contains("睡眠") ? "moon" : action.contains("功耗") ? "leaf" : "bolt.circle")
                                .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text(AidenteL10n.t("充电动作需要先启用管理；不支持高功耗或 MagSafe 的设备会返回错误。", "Enable charging management before using control actions. High Power and MagSafe require supported hardware.")).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(AidenteL10n.t("URL 兼容入口", "URL Compatibility"), isExpanded: $urls) {
                Text("aidente://set-limit?value=80\naidente://top-up\naidente://calibrate\naidente://pause\naidente://discharge?value=70\naidente://resume")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(.top, 12)
            }
        }
    }
}
