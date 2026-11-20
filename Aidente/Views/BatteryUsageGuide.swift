import SwiftUI

struct BatteryUsageGuide: View {
    let onClose: () -> Void
    @State private var page = 0
    @State private var error: String?
    private let setup = BatteryManagementSetup.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(AidenteL10n.t("Aidente 使用引导", "Aidente Guide"), systemImage: "battery.100percent")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch page {
                    case 0:
                        section("查看电池", "View your battery",
                                "点击菜单栏的电池图标打开面板，再点一次收起。查看电量、温度和历史曲线无需管理员授权。",
                                "Click the battery icon in the menu bar to open the panel, and click it again to close it. Battery level, temperature and history are available without administrator access.")
                        section("按需启用管理", "Enable controls when needed",
                                "限充和 MagSafe 指示灯共用一个后台服务。选择启用后，macOS 才会在需要安装或修复服务时请求管理员授权。",
                                "Charge limits and MagSafe LEDs share a background service. When you enable management, macOS asks for administrator authorization if the service needs installation or repair.")
                    case 1:
                        section("设置充电上限", "Set a charge limit",
                                "拖动白色滑块或点击“上限”输入百分比。蓝条表示当前电量。若电量已高于上限，通常会暂停充电。仅在你点击“放电”或启用自动放电时，Aidente 才会请求主动降到目标。",
                                "Drag the white handle or click Limit to enter a percentage. The blue bar shows your current level. Above the limit, charging normally pauses. Click Discharge or enable automatic discharge to request active discharge to the target.")
                        section("临时充满", "Charge to full",
                                "“充满”临时以 100% 为目标。点击“停止”或拔掉充电器后恢复原上限。",
                                "Top Up temporarily targets 100%. Click Stop or unplug the adapter to restore your saved limit.")
                    default:
                        section("确认实际状态", "Verify charging status",
                                "以状态说明和电池功率为准。待确认表示系统还未验证电流变化。曲线悬停可查看采样时间，App 功耗为估算值。",
                                "Use the status explanation and battery power to verify the result. Pending means the change in power flow is unconfirmed. Hover over a chart for the sample time. App power readings are estimates.")
                        section("系统覆盖和机型差异", "System overrides and Mac compatibility",
                                "macOS 可能暂时充满以校正电量读数。主动放电和指示灯功能取决于硬件与系统。异常时到“设置 → 充电控制”查看状态，或在“关于”重看引导。",
                                "macOS may temporarily charge to full to calibrate its gauge. Active discharge and LED features depend on hardware and macOS. See Settings → Charge Control for status, or reopen this guide from About.")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
                .id(page)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if page == 2 && !setup.ready {
                Button(AidenteL10n.t("启用电池管理", "Enable Battery Management")) {
                    Task {
                        error = nil
                        do { if try await setup.enable() { onClose() } }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(setup.enabling)
            }
            HStack {
                if page > 0 {
                    Button(AidenteL10n.t("上一步", "Back")) { page -= 1 }
                }
                Spacer()
                if page < 2 {
                    Button(AidenteL10n.t("跳过", "Skip"), action: onClose)
                    Button(AidenteL10n.t("下一步", "Next")) { page += 1 }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(AidenteL10n.t("完成", "Done"), action: onClose)
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }.disabled(setup.enabling)
        }.padding(24).frame(width: 520, height: 390)
    }

    private func section(_ chineseTitle: String, _ englishTitle: String,
                         _ chineseBody: String, _ englishBody: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AidenteL10n.t(chineseTitle, englishTitle)).font(.headline)
            Text(AidenteL10n.t(chineseBody, englishBody))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
