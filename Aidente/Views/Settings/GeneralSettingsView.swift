import AppKit
import Defaults
import SwiftUI

struct GeneralSettingsView: View {
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
                subtitle: AidenteL10n.t("保留 Dock 图标与应用菜单，方便重新打开和退出。", "Keep the Dock icon and app menu available for reopening and quitting."),
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

                Label(AidenteL10n.t("材质已实时应用到当前窗口与菜单面板", "Material applies immediately to this window and the menu panel"), systemImage: "checkmark.circle")
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

                Button {
                    if let url = URL(string: "aidente://dashboard") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(AidenteL10n.t("打开主菜单"), systemImage: "macwindow")
                }
                .buttonStyle(AidenteActionButtonStyle(colors: AidenteTheme.dashboardColors))
            }

            AidenteCard(
                "通知",
                subtitle: "控制 Aidente 何时向你报告充电状态。",
                icon: "bell.badge.fill",
                colors: AidenteTheme.automationColors
            ) {
                AidenteSettingToggle(
                    "关闭全部通知",
                    icon: "bell.slash.fill",
                    colors: [AidenteTheme.coral, AidenteTheme.amber],
                    isOn: $disableNotifications
                )

                AidenteRowDivider()

                AidenteSettingToggle(
                    "充电状态变化时通知",
                    subtitle: "暂停或恢复充电时发送系统通知",
                    icon: "bolt.badge.clock.fill",
                    colors: AidenteTheme.automationColors,
                    isOn: $showChargingStatusChangedNotification
                )
                    .disabled(disableNotifications)
                    .opacity(disableNotifications ? 0.48 : 1)
            }
        }
        .onChange(of: launchAtLogin) { _, newValue in
            if !AidenteRuntime.isUIPreview { LaunchAtLoginService.shared.setLaunchAtLogin(newValue) }
        }
    }
}
