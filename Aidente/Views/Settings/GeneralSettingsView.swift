import AppKit
import Defaults
import SwiftUI
import UserNotifications

struct GeneralSettingsView: View {
    let onOpenMainMenu: () -> Void
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var requestingNotifications = false
    @State private var notificationError: String?
    @Default(.appLanguage) var appLanguage
    @Default(.launchAtLogin) var launchAtLogin
    @Default(.showDockIcon) private var showDockIcon
    @Default(.batteryPercentageDisplayLocation) var batteryPercentageDisplayLocation
    @Default(.menuBarReadoutStyle) var menuBarReadoutStyle
    @Default(.showBatteryStateInStatusIcon) var showBatteryStateInStatusIcon
    @Default(.disableNotifications) var disableNotifications
    @Default(.showChargingStatusChangedNotification) var showChargingStatusChangedNotification
    @Default(.interfaceMaterialStyle) var interfaceMaterialStyle

    @Default(.restoreWindowLayout) private var restoreLayout
    var body: some View {
        AidenteSettingsPage {
            AidenteSettingToggle(AidenteL10n.t("在 Dock 中显示", "Show in Dock"),
                subtitle: AidenteL10n.t("也可在 Dock 右键选择“隐藏 Dock 图标”。固定或最近使用的图标由 macOS 管理，可将剩余图标拖出 Dock 移除。", "You can also right-click and choose Hide Dock Icon. macOS manages pinned and recent icons. Drag any remaining shortcut out of the Dock to remove it."),
                icon: "dock.rectangle", colors: [], isOn: $showDockIcon)
            AidenteCard(
                "语言",
                subtitle: "切换菜单栏和设置界面的显示语言。",
                icon: "character.bubble.fill",
                colors: AidenteTheme.generalColors
            ) {
                Picker(AidenteL10n.t("语言"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title)
                            .tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .id(appLanguage)
            }

            AidenteCard(
                "界面材质",
                subtitle: "选择菜单浮层和设置窗口的透明与虚化程度。",
                icon: "square.on.square",
                colors: AidenteTheme.dashboardColors
            ) {
                Picker(AidenteL10n.t("界面材质"), selection: $interfaceMaterialStyle) {
                    ForEach(InterfaceMaterialStyle.allCases) { style in
                        Label(style.title, systemImage: style.icon)
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .id(appLanguage)

                Label(AidenteL10n.t("材质应用于整个窗口、侧栏和菜单面板", "Material applies immediately to this window and the menu panel"), systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: interfaceMaterialStyle.icon)
                        .foregroundStyle(AidenteTheme.violet)
                    Text(interfaceMaterialStyle.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if interfaceMaterialStyle == .liquidGlass {
                        Text("macOS 26 / 27")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AidenteTheme.sky)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(AidenteTheme.sky.opacity(0.12))
                            )
                    }
                }
            }

            AidenteCard(
                "启动",
                subtitle: "让电池保护在登录后自动开始工作。",
                icon: "power.circle.fill",
                colors: AidenteTheme.generalColors
            ) {
                AidenteSettingToggle(
                    "登录时启动 Aidente",
                    subtitle: "登录当前账户后自动显示菜单栏图标",
                    icon: "arrow.up.forward.app.fill",
                    colors: AidenteTheme.generalColors,
                    isOn: $launchAtLogin
                )
            }

            AidenteSettingToggle("重新启动时恢复窗口布局", icon: "macwindow", colors: [], isOn: $restoreLayout)

            AidenteCard(
                "主菜单呼出",
                subtitle: "菜单栏图标被系统折叠时，仍然可以打开完整主菜单。",
                icon: "macwindow.on.rectangle",
                colors: AidenteTheme.dashboardColors
            ) {
                AidenteNotice(
                    text: "双击“应用程序”文件夹、启动台或聚焦搜索中的 Aidente 图标，即可打开独立主菜单窗口。",
                    icon: "cursorarrow.click.2",
                    colors: AidenteTheme.dashboardColors
                )

                Button(action: onOpenMainMenu) {
                    Label(AidenteL10n.t("打开主菜单"), systemImage: "macwindow")
                }
                .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.dashboardColors))
            }

            AidenteCard(
                AidenteL10n.t("通知设置", "Notification Settings"),
                subtitle: AidenteL10n.t("先开启总开关，再选择需要的通知。", "Enable notifications, then choose which events to receive."),
                icon: "bell.badge.fill",
                colors: AidenteTheme.automationColors
            ) {
                AidenteSettingToggle(
                    AidenteL10n.t("允许 Aidente 通知", "Allow Aidente Notifications"),
                    subtitle: AidenteL10n.t("总开关：关闭后，充电状态和任务通知均不发送。", "Master switch: off silences both charging and workflow notifications."),
                    icon: "bell.fill",
                    colors: [],
                    isOn: Binding(get: { !disableNotifications }, set: { disableNotifications = !$0 })
                )

                Text(AidenteL10n.t(disableNotifications ? "全部通知已暂停。":"通知已开启；可在下方单独关闭充电状态提醒。",disableNotifications ? "All notifications are paused.":"Notifications are on; charging reminders can be disabled below."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                AidenteRowDivider()

                AidenteSettingToggle(
                    AidenteL10n.t("充电状态通知", "Charging Status Notifications"),
                    subtitle: AidenteL10n.t("仅控制暂停、恢复充电的提醒；不影响任务通知。", "Notify when charging pauses or resumes; workflow notifications are separate."),
                    icon: "bolt.badge.clock.fill",
                    colors: AidenteTheme.automationColors,
                    isOn: $showChargingStatusChangedNotification,
                    isEnabled: !disableNotifications
                )
                    .padding(.leading, 18)
                if AidenteRuntime.isUIPreview {
                    Text(AidenteL10n.t("预览中不会请求系统通知权限。", "Preview does not request notification permission."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if notificationStatus == .denied {
                    Text(AidenteL10n.t("macOS 已拒绝通知权限。请在系统设置的「通知」中允许 Aidente。", "macOS has denied notification access. Allow Aidente in System Settings → Notifications."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if notificationStatus == .notDetermined {
                    Button(AidenteL10n.t("请求系统通知授权…", "Request Notification Permission…")) {
                        Task { await requestNotifications() }
                    }.buttonStyle(.link).disabled(requestingNotifications)
                    if requestingNotifications { ProgressView().controlSize(.small) }
                } else {
                    Text(notificationStatus == nil
                         ? AidenteL10n.t("正在检查 macOS 通知权限…", "Checking macOS notification permission…")
                         : AidenteL10n.t("macOS 已允许通知。", "macOS allows notifications."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let notificationError { Text(notificationError).font(.caption).foregroundStyle(.red) }
            }
        }
        .onChange(of: launchAtLogin) { _, newValue in
            if !AidenteRuntime.isUIPreview { LaunchAtLoginService.shared.setLaunchAtLogin(newValue) }
        }
        .task { await refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshNotificationStatus() }
        }
    }

    private func refreshNotificationStatus() async {
        guard !AidenteRuntime.isUIPreview else { return }
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func requestNotifications() async {
        guard !requestingNotifications else { return }
        requestingNotifications = true
        notificationError = nil
        defer { requestingNotifications = false }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            notificationError = error.localizedDescription
        }
        await refreshNotificationStatus()
    }
}
