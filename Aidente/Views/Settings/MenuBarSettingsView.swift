import Defaults
import SwiftUI

struct MenuBarSettingsView: View {
    let viewModel: MenuViewModel
    @Default(.menuBarIconStyle) private var iconStyle
    @Default(.menuBarMetrics) private var metricIDs
    @Default(.menuBarHiddenMetricIcons) private var hiddenMetricIcons
    @Default(.menuBarItemSpacing) private var itemSpacing
    @Default(.menuBarUpdateInterval) private var updateInterval
    @Default(.menuBarRightClick) private var rightClick
    @Default(.activeStatusItemsOnly) private var activeOnly
    @Default(.menuBarLowPowerColor) private var lowPowerColor
    @Default(.batteryPercentageDisplayLocation) private var percentageLocation
    @Default(.showBatteryStateInStatusIcon) private var stateColors
    @Default(.menuBarReadoutStyle) private var legacyReadout
    @State private var draggedMetric: String?

    private var selected: [MenuBarMetric] { MenuBarMetric.selected(from: metricIDs) }
    private var groups: [String] {
        MenuBarMetric.allCases.reduce(into: []) { result, metric in
            if !result.contains(metric.group) { result.append(metric.group) }
        }
    }

    var body: some View {
        AidenteSettingsPage {
            AidenteCard("已选菜单栏项目", subtitle: "拖动调整读数顺序；点击读数切换其图标，点击减号移除。", icon: "menubar.rectangle", colors: []) {
                UtilitySurface {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            if iconStyle != .hidden || percentageLocation != .hidden {
                                BatteryIndicatorView(batteryLevel: viewModel.displayPercentage, chargingMode: viewModel.chargingMode,
                                    isLowPowerModeEnabled: lowPowerColor && viewModel.isLowPowerModeEnabled,
                                    percentageDisplayLocation: percentageLocation, showState: stateColors, style: iconStyle, adapterConnected: viewModel.adapterConnected)
                                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                            }
                            ForEach(selected) { metric in
                                VStack(spacing: 5) {
                                    HStack(spacing: 5) {
                                        Button { toggleMetricIcon(metric) } label: {
                                            HStack(spacing: 5) {
                                                if !hiddenMetricIcons.contains(metric.id) { Image(systemName: metric.icon) }
                                                Text(MenuBarSnapshot(viewModel: viewModel).values[metric.id] ?? "—").monospacedDigit()
                                            }
                                        }.buttonStyle(.plain).help(AidenteL10n.t("点击显示或隐藏读数图标", "Click to show or hide the reading icon"))
                                        Button { metricIDs.removeAll { $0 == metric.id } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.borderless).accessibilityLabel(AidenteL10n.t("移除", "Remove") + " " + metric.title)
                                    }
                                    Text(metric.title).font(.system(size: 9)).foregroundStyle(.secondary)
                                }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                    .onDrag { draggedMetric = metric.id; return NSItemProvider(object: metric.id as NSString) }
                                    .onDrop(of: [.text], delegate: MetricReorderDropDelegate(target: metric.id, values: $metricIDs, dragged: $draggedMetric))
                                    .contextMenu {
                                        Button(AidenteL10n.t("左移", "Move Left")) { move(metric, -1) }.disabled(metricIDs.first == metric.id)
                                        Button(AidenteL10n.t("右移", "Move Right")) { move(metric, 1) }.disabled(metricIDs.last == metric.id)
                                        Button(AidenteL10n.t("移除", "Remove")) { metricIDs.removeAll { $0 == metric.id } }
                                    }
                            }
                            if iconStyle == .hidden && selected.isEmpty { Text(AidenteL10n.t("从下方目录添加项目", "Add items from the catalog below")).font(.caption).foregroundStyle(.secondary) }
                        }.frame(minHeight: 40).padding(.vertical, 4)
                    }.scrollIndicators(.visible)
                }
            }
            AidenteCard("菜单栏项目目录", icon: "book", colors: []) {
                UtilitySurface {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(AidenteL10n.t("主图标样式（选择一个）", "Main Icon Style (Choose One)")).font(.caption).foregroundStyle(.secondary)
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 6) {
                                ForEach(MenuBarIconStyle.allCases) { style in
                                    Button {
                                        iconStyle = style
                                        if percentageLocation != .hidden { percentageLocation = style.defaultPercentageLocation }
                                    } label: {
                                        VStack(spacing: 8) {
                                            Group {
                                                if style == .hidden { Image(systemName: "eye.slash").font(.system(size: 18)) }
                                                else { BatteryIndicatorView(batteryLevel: viewModel.displayPercentage, chargingMode: viewModel.chargingMode, percentageDisplayLocation: style.defaultPercentageLocation, showState: true, style: style, adapterConnected: viewModel.adapterConnected) }
                                            }.frame(width: 68, height: 33)
                                                .background(iconStyle == style ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(iconStyle == style ? Color.accentColor.opacity(0.7) : .clear))
                                            Text(style.title).font(.system(size: 10)).frame(width: 80)
                                        }.foregroundStyle(iconStyle == style ? Color.accentColor : .primary)
                                    }.buttonStyle(.plain).accessibilityAddTraits(iconStyle == style ? .isSelected : [])
                                }
                            }.padding(.vertical, 3)
                        }
                        Divider()
                        Text(AidenteL10n.t("主图标选项", "Main Icon Options")).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(AidenteL10n.t("显示百分比", "Show Percentage"))
                            Spacer()
                            Toggle(AidenteL10n.t("显示百分比", "Show Percentage"), isOn: Binding(
                                get: { percentageLocation != .hidden },
                                set: { percentageLocation = $0 ? iconStyle.defaultPercentageLocation : .hidden }
                            )).labelsHidden().toggleStyle(.switch)
                        }
                        AidenteSettingToggle("低电量模式颜色", icon: "paintpalette", colors: [], isOn: $lowPowerColor)
                        AidenteSettingToggle("用颜色显示电池状态", icon: "paintpalette.fill", colors: [], isOn: $stateColors)
                        ForEach(groups, id: \.self) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group).font(.caption).foregroundStyle(.secondary)
                                ScrollView(.horizontal) {
                                    HStack(spacing: 6) {
                                        ForEach(MenuBarMetric.allCases.filter { $0.group == group }) { metric in
                                            Button { toggle(metric) } label: {
                                                VStack(spacing: 6) {
                                                    Image(systemName: metric.icon).font(.system(size: 17)).frame(height: 20)
                                                    Text(metric.title).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center)
                                                }.frame(width: 74, height: 58)
                                                    .background(metricIDs.contains(metric.id) ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                                                    .foregroundStyle(metricIDs.contains(metric.id) ? Color.accentColor : .primary)
                                            }.buttonStyle(.plain).accessibilityAddTraits(metricIDs.contains(metric.id) ? .isSelected : []).help(AidenteL10n.t("点击添加或移除", "Click to add or remove"))
                                        }
                                    }.padding(.vertical, 2)
                                }
                            }
                        }
                        HStack {
                            Toggle(AidenteL10n.t("仅显示激活的状态项目", "Active Status Items Only"), isOn: $activeOnly).toggleStyle(.checkbox)
                            Spacer()
                            Button { reset() } label: { Image(systemName: "arrow.counterclockwise") }.help(AidenteL10n.t("重置", "Reset"))
                            Button { iconStyle = .hidden; percentageLocation = .hidden; metricIDs = []; hiddenMetricIcons = []; legacyReadout = .batteryPercentage } label: { Image(systemName: "trash") }.help(AidenteL10n.t("全部清除", "Clear All"))
                        }.buttonStyle(.borderless)
                    }
                }
            }
            VStack(spacing: 14) {
                AidenteControlRow("菜单栏项目间距", icon: "space", colors: []) {
                    Text("\(itemSpacing)").monospacedDigit().frame(width: 20)
                    Slider(value: Binding(get: { Double(itemSpacing) }, set: { itemSpacing = Int($0) }), in: 0...20, step: 1).frame(width: 160)
                }
                AidenteControlRow("菜单栏更新间隔", icon: "timer", colors: []) {
                    Text("\(updateInterval) s").monospacedDigit().frame(width: 30)
                    Slider(value: Binding(get: { Double(updateInterval) }, set: { updateInterval = Int($0) }), in: 2...20, step: 1).frame(width: 160)
                }
                AidenteControlRow("菜单栏右击", icon: "menubar.arrow.up.rectangle", colors: []) {
                    Picker("", selection: $rightClick) { ForEach(MenuBarRightClick.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 150)
                }
            }
        }.onAppear { viewModel.menuWillOpen() }.onDisappear { viewModel.menuDidClose() }
    }
    private func toggleMetricIcon(_ metric: MenuBarMetric) {
        if hiddenMetricIcons.contains(metric.id) { hiddenMetricIcons.removeAll { $0 == metric.id } }
        else { hiddenMetricIcons.append(metric.id) }
    }
    private func toggle(_ metric: MenuBarMetric) {
        if metricIDs.contains(metric.id) { metricIDs.removeAll { $0 == metric.id } } else { metricIDs.append(metric.id) }
    }
    private func move(_ metric: MenuBarMetric, _ offset: Int) {
        guard let index = metricIDs.firstIndex(of: metric.id), metricIDs.indices.contains(index + offset) else { return }
        metricIDs.swapAt(index, index + offset)
    }
    private func reset() {
        iconStyle = .status; metricIDs = []; hiddenMetricIcons = []; percentageLocation = .nextToIcon
        lowPowerColor = true; stateColors = true; itemSpacing = 5; updateInterval = 5
        legacyReadout = .batteryPercentage; rightClick = .popover
    }

}

private struct MetricReorderDropDelegate: DropDelegate {
    let target: String
    @Binding var values: [String]
    @Binding var dragged: String?
    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target,
              let source = values.firstIndex(of: dragged), let destination = values.firstIndex(of: target) else { return }
        withAnimation { values.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
}
