import SwiftUI
import Defaults
import UserNotifications

struct BatteryUsageGuide: View {
    let onClose: () -> Void
    @State private var page = 0
    @State private var error: String?
    @State private var applying = false
    @State private var manage = Defaults[.manageCharging]
    @State private var login = Defaults[.launchAtLogin]
    @State private var dock = Defaults[.showDockIcon]
    @State private var notifications: Bool?
    @State private var notificationsAllowed = false
    @State private var loginNeedsApproval = false
    @State private var loginApprovalPresented = false
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
                        setupOptions
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
            HStack {
                if page > 0 {
                    Button(AidenteL10n.t("上一步", "Back")) { page -= 1 }
                }
                Spacer()
                if page < 2 {
                    Button(AidenteL10n.t("跳过", "Skip"), action: onClose)
                    Button(page == 0 ? AidenteL10n.t("应用并继续", "Apply and Continue") : AidenteL10n.t("下一步", "Next")) {
                        if page == 0 { Task { await applySetup() } }
                        else { page += 1 }
                    }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(AidenteL10n.t("完成", "Done"), action: onClose)
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }.disabled(applying || setup.enabling)
        }.padding(24).frame(width: 520, height: 390)
            .task {
                guard !AidenteRuntime.isUIPreview else { return }
                let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                notificationsAllowed = status == .authorized && !Defaults[.disableNotifications]
                    && Defaults[.showChargingStatusChangedNotification]
                loginNeedsApproval = login && LaunchAtLoginService.shared.requiresApproval
            }
    }

    private var setupOptions: some View {
        VStack(alignment: .leading, spacing: 13) {
            option("电池管理", "Battery management", subtitle: AidenteL10n.t(
                "限充和 MagSafe 指示灯共用一个后台服务，首次安装需要管理员授权。",
                "Charge limits and MagSafe LEDs share one service. Administrator authorization is needed to install it."), isOn: $manage)
            option("登录时启动", "Launch at login", subtitle: AidenteL10n.t(
                "登录此账户后自动打开 Aidente。", "Open Aidente automatically when you sign in."), isOn: $login)
            if login && loginNeedsApproval {
                Button(AidenteL10n.t("在系统设置中允许登录时启动", "Allow launch at login in System Settings")) {
                    LaunchAtLoginService.shared.openSettings()
                }.buttonStyle(.link)
            }
            option("在 Dock 中显示", "Show in Dock", subtitle: AidenteL10n.t(
                "独立于菜单栏图标，关闭后仍可从“应用程序”打开。", "Independent of the menu bar icon. You can reopen Aidente from Applications."), isOn: $dock)
            option("充电通知", "Charging notifications", subtitle: AidenteL10n.t(
                "可选，首次启用由 macOS 请求通知权限。", "Optional. macOS asks for notification permission the first time."), isOn: Binding(
                    get: { notifications ?? notificationsAllowed }, set: { notifications = $0 }))
        }.disabled(applying)
    }

    private func option(_ chinese: String, _ english: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AidenteL10n.t(chinese, english)).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.toggleStyle(.switch)
    }

    private func applySetup() async {
        guard !applying else { return }
        applying = true
        error = nil
        defer { applying = false }
        guard !AidenteRuntime.isUIPreview else { page += 1; return }
        do {
            if manage && !setup.ready {
                guard try await setup.enable() else {
                    manage = Defaults[.manageCharging]
                    error = AidenteL10n.t("已取消电池管理授权。可继续应用其他选项。", "Battery management authorization was canceled. You can still apply the other choices.")
                    return
                }
            } else if !manage && Defaults[.manageCharging] {
                try await setup.onDisable?()
            }
            if login != Defaults[.launchAtLogin] {
                try LaunchAtLoginService.shared.apply(login)
                Defaults[.launchAtLogin] = login
            }
            loginNeedsApproval = login && LaunchAtLoginService.shared.requiresApproval
            Defaults[.showDockIcon] = dock
            if let notifications {
                if notifications {
                    let center = UNUserNotificationCenter.current()
                    let status = await center.notificationSettings().authorizationStatus
                    let granted = status == .notDetermined
                        ? try await center.requestAuthorization(options: [.alert, .sound])
                        : status == .authorized
                    guard granted else {
                        self.notifications = false
                        Defaults[.showChargingStatusChangedNotification] = false
                        error = AidenteL10n.t("通知未获授权。其他已选设置已应用。", "Notifications were not authorized. The other choices were applied.")
                        return
                    }
                    Defaults[.disableNotifications] = false
                }
                Defaults[.showChargingStatusChangedNotification] = notifications
            }
            if loginNeedsApproval && !loginApprovalPresented {
                loginApprovalPresented = true
                error = AidenteL10n.t("其他设置已应用。登录时启动还需在系统设置中允许。", "Other choices were applied. Launch at login still needs approval in System Settings.")
                return
            }
            page += 1
        } catch {
            self.error = error.localizedDescription
        }
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
