import Defaults
import SwiftUI

struct DashboardSettingsView: View {
    @Default(.popoverWidgets) private var widgetIDs
    @Default(.appLanguage) private var appLanguage

    @Default(.showPowerSource) var showPowerSource
    @Default(.showTimeTillDischarge) var showTimeTillDischarge
    @Default(.showUptime) var showUptime
    @Default(.showBatteryMode) var showBatteryMode
    @Default(.showBatteryTemperature) var showBatteryTemperature
    @Default(.showBatteryCycleCount) var showBatteryCycleCount
    @Default(.showBatteryHealth) var showBatteryHealth
    @Default(.showInternalPower) var showInternalPower
    @Default(.showExternalPower) var showExternalPower
    @Default(.popoverMetricIDs) private var specIDs

    private func move(_ widget: PopoverWidget, direction: Int) {
        guard let index = widgetIDs.firstIndex(of: widget.id), widgetIDs.indices.contains(index + direction) else { return }
        widgetIDs.swapAt(index, index + direction)
    }

    @Default(.popoverShowOnLaunch) private var onLaunch
    @Default(.popoverShowPercentage) private var showPercentage
    @State private var showDetails = false
    var body: some View {
        AidenteSettingsPage {
            VStack(spacing: 8) {
                AidenteSettingToggle("启动时显示", icon: "eye", colors: [], isOn: $onLaunch)
                AidenteSettingToggle("显示百分比", icon: "percent", colors: [], isOn: $showPercentage)
            }
            Button(AidenteL10n.t("在编辑模式下打开", "Open in Edit Mode")) { PopoverEditorState.shared.beginEditing() }
                .buttonStyle(AidenteActionButtonStyle(colors: []))
            VStack(alignment: .leading, spacing: 12) {
                Text(AidenteL10n.t("布局预设", "Layout Presets")).font(.headline)
                HStack {
                    Button(AidenteL10n.t("简洁", "Minimalist")) { widgetIDs = PopoverWidget.minimalist }
                    Button(AidenteL10n.t("电池健康", "Battery Health")) { widgetIDs = PopoverWidget.healthFocused }
                    Button(AidenteL10n.t("详细", "Power User")) { widgetIDs = PopoverWidget.powerUser }
                    Button(AidenteL10n.t("仅充电控制", "Charge Controls Only")) { widgetIDs = [] }
                }.buttonStyle(.bordered)
                Text(AidenteL10n.t("显示顺序", "Display Order")).font(.headline).padding(.top, 8)
                if widgetIDs.isEmpty {
                    Text(AidenteL10n.t("目前仅显示充电控制。选择预设或在下方添加组件。", "Only charge controls are shown. Choose a preset or add widgets below."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(PopoverWidget.selected(from: widgetIDs)) { widget in
                    HStack {
                        Text(widget.title)
                        Spacer()
                        Button { move(widget, direction: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(widgetIDs.first == widget.id)
                            .accessibilityLabel(widget.title + AidenteL10n.t("上移", " Move Up"))
                        Button { move(widget, direction: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(widgetIDs.last == widget.id)
                            .accessibilityLabel(widget.title + AidenteL10n.t("下移", " Move Down"))
                        Button { widgetIDs.removeAll { $0 == widget.id } } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel(AidenteL10n.t("移除", "Remove ") + widget.title)
                    }.buttonStyle(.borderless)
                }
            }
            DisclosureGroup(AidenteL10n.t("组件与读数设置", "Widgets and Readings"), isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(PopoverWidget.allCases) { widget in
                        Toggle(widget.title, isOn: Binding(get: { widgetIDs.contains(widget.id) }, set: { enabled in
                            if enabled { if !widgetIDs.contains(widget.id) { widgetIDs.append(widget.id) } } else { widgetIDs.removeAll { $0 == widget.id } }
                        })).toggleStyle(.switch)
                    }
                    Divider()
                    Text(AidenteL10n.t("规格组件内容", "Specification Readings")).fontWeight(.semibold)
                    ForEach(MenuBarMetric.allCases.filter { !["calibration", "sailing", "heatProtection", "topUp"].contains($0.id) }) { metric in
                        Toggle(metric.group + " · " + metric.title, isOn: Binding(get: { specIDs.contains(metric.id) }, set: { enabled in
                            if enabled { if !specIDs.contains(metric.id) { specIDs.append(metric.id) } }
                            else { specIDs.removeAll { $0 == metric.id } }
                        })).toggleStyle(.checkbox)
                    }
                    Button(AidenteL10n.t("恢复默认布局", "Restore Default Layout")) { widgetIDs = PopoverWidget.defaultLayoutIDs }
                }.padding(.top, 14)
            }
        }
    }
}
