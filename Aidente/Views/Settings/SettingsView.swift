import AppKit
import Defaults
import SwiftUI
import smc_power

enum SettingsTab: String, CaseIterable, Identifiable {
    case shortcuts = "Shortcuts"
    case overview = "Overview"
    case sleep = "Sleep"
    case energy = "Energy"
    case otherAppearance = "OtherAppearance"
    case general = "General"
    case menuBar = "MenuBar"
    case dashboard = "Dashboard"
    case charging = "Charging"
    case automation = "Automation"
    case advanced = "Advanced"
    case diagnostics = "Diagnostics"
    case about = "About"

    var id: String { rawValue }

    init?(urlValue: String) {
        guard let tab = Self.allCases.first(where: {
            $0.rawValue.lowercased() == urlValue.lowercased()
        }) else {
            return nil
        }
        self = tab
    }
    
    var title: String {
        switch self {
        case .shortcuts: AidenteL10n.t("快捷指令", "Shortcuts")
        case .overview: AidenteL10n.t("仪表板", "Dashboard")
        case .sleep: AidenteL10n.t("睡眠行为", "Sleep Behavior")
        case .energy: AidenteL10n.t("能源使用", "Energy Use")
        case .otherAppearance: AidenteL10n.t("其他", "Other")
        case .menuBar: AidenteL10n.t("菜单栏", "Menu Bar")
        case .general: AidenteL10n.t("通用")
        case .dashboard: AidenteL10n.t("弹出窗口", "Popover")
        case .charging: AidenteL10n.t("充电控制", "Charge Control")
        case .automation: AidenteL10n.t("定时设置", "Schedule")
        case .advanced: AidenteL10n.t("高级")
        case .diagnostics: AidenteL10n.t("诊断")
        case .about: AidenteL10n.t("关于")
        }
    }

    var icon: String {
        switch self {
        case .shortcuts: return "square.stack.3d.up"
        case .overview: return "square.grid.2x2"
        case .sleep: return "moon"
        case .energy: return "leaf"
        case .otherAppearance: return "lightbulb"
        case .menuBar: return "menubar.rectangle"
        case .general:
            return "gearshape.fill"
        case .dashboard:
            return "square.grid.2x2"
        case .charging:
            return "battery.100.bolt"
        case .automation:
            return "calendar.badge.clock"
        case .advanced:
            return "slider.horizontal.3"
        case .diagnostics:
            return "waveform.badge.magnifyingglass"
        case .about:
            return "heart.text.square.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .shortcuts, .overview, .sleep, .energy, .otherAppearance: AidenteTheme.generalColors
        case .menuBar: AidenteTheme.generalColors
        case .general: AidenteTheme.generalColors
        case .dashboard: AidenteTheme.dashboardColors
        case .charging: AidenteTheme.chargingColors
        case .automation: AidenteTheme.automationColors
        case .advanced: AidenteTheme.advancedColors
        case .diagnostics: AidenteTheme.dashboardColors
        case .about: AidenteTheme.aboutColors
        }
    }
}

@Observable final class SettingsNavigation { var tab: SettingsTab = .overview }

struct SettingsView: View {
    @Default(.manageCharging) private var managementEnabled
    @Default(.appLanguage) private var appLanguage
    @Bindable var navigation: SettingsNavigation
    var onSelection: (SettingsTab) -> Void

    private let viewModel: MenuViewModel
    private let capabilities: DeviceCapabilities
    private let chargeManager: ChargeManager
    private let diagnosticCenter: DiagnosticCenter
    private let updateService: UpdateService

    init(
        viewModel: MenuViewModel,
        capabilities: DeviceCapabilities,
        chargeManager: ChargeManager,
        diagnosticCenter: DiagnosticCenter,
        updateService: UpdateService,
        navigation: SettingsNavigation,
        onSelection: @escaping (SettingsTab) -> Void
    ) {
        self.viewModel = viewModel
        self.capabilities = capabilities
        self.chargeManager = chargeManager
        self.diagnosticCenter = diagnosticCenter
        self.updateService = updateService
        self.navigation = navigation
        self.onSelection = onSelection
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        navigationRow(.overview)
                        Divider().padding(.vertical, 10)
                        group("电池保养", "Battery Care", [.charging, .sleep, .energy])
                        group("自动化", "Automation", [.automation, .shortcuts])
                        group("外观", "Appearance", [.dashboard, .menuBar, .otherAppearance])
                    }.padding(.horizontal, 16).padding(.top, 42)
                }.scrollIndicators(.never)
                VStack(spacing: 12) {
                    Text(chargeManager.controlError != nil ? chargeManager.operationStatusTitle
                         : managementEnabled ? viewModel.operationStatusText : AidenteL10n.t("只读监测", "Monitoring"))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button { viewModel.quit() } label: { Image(systemName: "power").frame(width: 20, height: 20) }
                            .help(AidenteL10n.t("退出 Aidente", "Quit Aidente"))
                            .accessibilityLabel(AidenteL10n.t("退出 Aidente", "Quit Aidente"))
                        Spacer()
                        Button { navigation.tab = .about } label: { Image(systemName: "questionmark.circle").frame(width: 20, height: 20) }
                            .help(AidenteL10n.t("关于与帮助", "About and Help"))
                        Menu {
                            ForEach([SettingsTab.general, .advanced, .diagnostics, .about]) { tab in
                                Button(tab.title) { navigation.tab = tab }
                            }
                            Divider()
                            Button(AidenteL10n.t("退出 Aidente", "Quit Aidente")) { viewModel.quit() }
                        } label: { Image(systemName: "gearshape").frame(width: 20, height: 20) }
                            .menuStyle(.borderlessButton).fixedSize().help(AidenteL10n.t("设置", "Settings"))
                    }.buttonStyle(AidenteActionButtonStyle(colors: []))
                }.padding(12)
            }.frame(width: 199).background(.regularMaterial)
            Divider()
            detailContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AidenteWindowBackdrop())
        }
        .frame(minWidth: 700, minHeight: 620)
        .ignoresSafeArea()
        .tint(.accentColor)
        .disabled(CompleteUninstaller.shared.isRunning)
        .onChange(of: navigation.tab) { _, tab in onSelection(tab) }
        .onChange(of: appLanguage) { _, _ in updateWindowTitle() }
    }

    private func group(_ cn: String, _ en: String, _ tabs: [SettingsTab]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AidenteL10n.t(cn, en)).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6).padding(.bottom, 4)
            ForEach(tabs) { tab in navigationRow(tab) }
        }.padding(.bottom, 10)
    }
    private func navigationRow(_ tab: SettingsTab) -> some View {
        Button { navigation.tab = tab } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon).font(.system(size: 16)).frame(width: 20)
                Text(tab.title).font(.system(size: 13, weight: navigation.tab == tab ? .semibold : .regular))
                Spacer(minLength: 0)
            }.foregroundStyle(navigation.tab == tab ? Color.accentColor : Color.primary)
                .padding(.horizontal, 10).frame(height: 32)
                .background(navigation.tab == tab ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(navigation.tab == tab ? .isSelected : [])
    }

    @ViewBuilder private var detailContent: some View {
        switch navigation.tab {
        case .shortcuts: ShortcutsSettingsView()
        case .overview: FullDashboardView(viewModel: viewModel)
        case .sleep: SleepSettingsView()
        case .energy: EnergySettingsView()
        case .otherAppearance: LEDSettingsView(onOpenChargeSettings: { navigation.tab = .charging })
        case .menuBar: MenuBarSettingsView(viewModel: viewModel)
        case .general: GeneralSettingsView()
        case .dashboard: DashboardSettingsView()
        case .charging: ChargingSettingsView(capabilities: capabilities, chargeManager: chargeManager)
        case .automation: AutomationSettingsView()
        case .advanced: AdvancedSettingsView()
        case .diagnostics: DiagnosticsSettingsView(diagnosticCenter: diagnosticCenter)
        case .about: AboutSettingsView(updateService: updateService)
        }
    }

    private func updateWindowTitle() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.title = AidenteL10n.t(
                "Aidente 设置",
                "Aidente Settings"
            )
        }
    }
}
