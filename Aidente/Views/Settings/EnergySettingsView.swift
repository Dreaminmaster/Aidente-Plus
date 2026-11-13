import AidenteShared
import Defaults
import SwiftUI

struct EnergySettingsView: View {
    private let service = EnergyModeService.shared
    @Default(.showAllRunningApps) private var showAll
    @Default(.energyUsageThreshold) private var threshold
    @Default(.includeBackgroundEnergyProcesses) private var includeBackground
    @Default(.compactEnergyWidget) private var compact
    @Default(.backgroundDashboardUpdates) private var backgroundUpdates
    @State private var installationError: String?
    @State private var advanced = false
    var body: some View {
        AidenteSettingsPage {
            AidenteControlRow("低电量模式", subtitle: "分别设置电池和电源适配器的节能行为。", icon: "battery.25percent", colors: []) {
                Picker("", selection: Binding(get: { service.lowPowerPreset }, set: { service.chooseLowPowerPreset($0) })) {
                    Text(AidenteL10n.t("始终关闭", "Never")).tag(0)
                    Text(AidenteL10n.t("始终开启", "Always")).tag(1)
                    Text(AidenteL10n.t("仅使用电池时", "Only on Battery")).tag(2)
                    Text(AidenteL10n.t("仅接通电源时", "Only on Power Adapter")).tag(3)
                    if service.lowPowerPreset == 4 { Text(AidenteL10n.t("自定义", "Custom")).tag(4) }
                }.labelsHidden().frame(width: 160).disabled(service.isBusy || AidenteRuntime.isUIPreview)
            }
            AidenteSettingToggle("后台仪表板更新", subtitle: "窗口关闭后继续记录趋势，每 15 秒读取一次。", icon: "arrow.clockwise.circle", colors: [], isOn: $backgroundUpdates)
            AidenteCard("使用大量能耗的 App", icon: "bolt", colors: []) {
                UtilitySurface {
                    VStack(spacing: 12) {
                        AidenteSettingToggle("显示所有运行中的 App", subtitle: "包括空闲应用，不限制四个；按名称固定排序。鼠标停留时固定名单，离开后更新。关闭后只显示超过用量门槛的 App。", icon: "list.bullet", colors: [], isOn: $showAll)
                        AidenteControlRow("显示能耗高于", subtitle: "根据近期 CPU 活动或进程估算功率筛选；低/中/高对应 1/5/20% CPU 或 0.01/0.05/0.20 W。平滑短暂波动，持续降低后移除；估算不等同 macOS 综合能量影响。", icon: "bolt", colors: []) {
                            Picker("", selection: $threshold) {
                                Text(AidenteL10n.t("低", "Low")).tag(1)
                                Text(AidenteL10n.t("中", "Medium")).tag(5)
                                Text(AidenteL10n.t("高", "High")).tag(20)
                            }.labelsHidden().frame(width: 130).disabled(showAll)
                        }
                        AidenteSettingToggle("包含后台进程", icon: "gearshape", colors: [], isOn: $includeBackground)
                    }
                }
            }
            DisclosureGroup(AidenteL10n.t("显示高级设置", "Show Advanced Settings"), isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(EnergySource.allCases, id: \.self) { source in
                        HStack {
                            Text(source == .battery ? AidenteL10n.t("使用电池", "On Battery") : AidenteL10n.t("接通电源", "On Power Adapter"))
                            Spacer()
                            if let reading = service.readings[source] {
                                Picker("", selection: Binding(get: { reading.mode ?? .automatic }, set: { service.choose($0, source: source) })) {
                                    ForEach(EnergyMode.allCases.filter { $0 != .high || reading.supportsHigh }, id: \.self) { mode in Text(mode.title).tag(mode) }
                                }.labelsHidden().frame(width: 150).disabled(service.isBusy || AidenteRuntime.isUIPreview)
                            }
                        }
                    }
                    Toggle(AidenteL10n.t("使用紧凑功耗小组件", "Compact Energy Mode Widget"), isOn: $compact).toggleStyle(.switch)
                    Text(AidenteL10n.t("修改需要已授权的控制服务。关闭管理或完全卸载时恢复先前保存的功耗设置。", "Changes require the authorized helper. Disabling management or uninstalling restores the saved energy settings.")).font(.caption).foregroundStyle(.secondary)
                    if !ChargingHelperManager.shared.isInstalled {
                        Button(AidenteL10n.t("安装或修复控制服务…", "Install or Repair Control Service…")) {
                            Task { do { try await ChargingHelperManager.shared.repair() } catch { installationError = error.localizedDescription } }
                        }.disabled(AidenteRuntime.isUIPreview)
                    }
                    Button(AidenteL10n.t("刷新状态", "Refresh")) { service.refresh() }
                }.padding(.top, 16)
            }
            if let error = installationError ?? service.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.onAppear { service.refresh() }
    }
}
