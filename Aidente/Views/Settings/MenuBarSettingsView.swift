import AidenteShared
import Defaults
import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct MenuBarSettingsView: View {
    let viewModel: MenuViewModel
    @Default(.menuBarIconStyle) private var iconStyle
    @Default(.menuBarMetrics) private var metricIDs
    @Default(.menuBarMainIconPosition) private var mainPosition
    @Default(.menuBarHiddenMetricIcons) private var hiddenMetricIcons
    @Default(.menuBarItemSpacing) private var itemSpacing
    @Default(.menuBarUpdateInterval) private var updateInterval
    @Default(.menuBarRightClick) private var rightClick
    @Default(.activeStatusItemsOnly) private var activeOnly
    @Default(.menuBarLowPowerColor) private var lowPowerColor
    @Default(.batteryPercentageDisplayLocation) private var percentageLocation
    @Default(.showBatteryStateInStatusIcon) private var stateColors
    @Default(.menuBarReadoutStyle) private var legacyReadout
    @Default(.chargingIndicatorStyle) private var indicatorStyle
    @State private var cardDrag = CardDragState()
    @State private var showIconOptions = true
    @State private var animatedOrder: [String] = []

    private var orderedItems: [String] { MenuItemOrdering.layout(metrics: selected.map(\.id), mainPosition: mainPosition, includeMain: iconStyle != .hidden || percentageLocation != .hidden) }
    private var renderedItems: [String] { animatedOrder.isEmpty ? orderedItems : animatedOrder }
    private var orderBinding: Binding<[String]> { Binding(get: { renderedItems }, set: { items in
        withAnimation(.easeInOut(duration: 0.24)) { animatedOrder = items }
        applyOrder(items)
    }) }
    private var selected: [MenuBarMetric] { MenuBarMetric.selected(from: metricIDs) }
    private var groups: [String] {
        MenuBarMetric.allCases.reduce(into: []) { result, metric in
            if !result.contains(metric.group) { result.append(metric.group) }
        }
    }

    var body: some View {
        AidenteSettingsPage {
            AidenteCard("已选菜单栏项目", subtitle: "拖动调整读数顺序；点击读数切换其图标，点击减号移除。", icon: "menubar.rectangle", colors: []) {
                Text(AidenteL10n.t("拖动整张卡片调整顺序，主图标也可移动；点击读数切换图标，减号移除。", "Drag a whole card to reorder, including the main icon. Click a reading to toggle its icon; minus removes it.")).font(.caption).foregroundStyle(.secondary)
                UtilitySurface {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(renderedItems, id: \.self) { item in
                                FreeReorderCard(id: item, drag: $cardDrag, move: { source, target in
                                    orderBinding.wrappedValue = MenuItemOrdering.moving(source, onto: target, in: renderedItems)
                                }) {
                                VStack(spacing: 5) {
                                    if item == MenuItemOrdering.main {
                                        BatteryIndicatorView(batteryLevel: viewModel.displayPercentage, chargingMode: viewModel.chargingMode,
                                            isLowPowerModeEnabled: lowPowerColor && viewModel.isLowPowerModeEnabled,
                                            percentageDisplayLocation: percentageLocation, showState: stateColors, style: iconStyle, adapterConnected: viewModel.adapterConnected)
                                            .frame(minHeight: 20)
                                        Text(AidenteL10n.t("主图标", "Main Icon")).font(.system(size: 9)).foregroundStyle(.secondary)
                                    } else if let metric = MenuBarMetric(rawValue: item) {
                                        HStack(spacing: 5) {
                                            Button { toggleMetricIcon(metric) } label: {
                                                HStack(spacing: 5) {
                                                    if !hiddenMetricIcons.contains(metric.id) { Image(systemName: metric.icon) }
                                                    Text(MenuBarSnapshot(viewModel: viewModel).values[metric.id] ?? "—").monospacedDigit()
                                                }
                                            }.buttonStyle(.plain).help(AidenteL10n.t("点击显示或隐藏读数图标", "Click to show or hide the reading icon"))
                                            Button { applyOrder(orderedItems.filter { $0 != item }) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                                                .buttonStyle(.borderless).accessibilityLabel(AidenteL10n.t("移除", "Remove") + " " + metric.title)
                                        }.frame(minHeight: 20)
                                        Text(metric.title).font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                                    .contextMenu {
                                        Button(AidenteL10n.t("左移", "Move Left")) { moveItem(item, -1) }.disabled(orderedItems.first == item)
                                        Button(AidenteL10n.t("右移", "Move Right")) { moveItem(item, 1) }.disabled(orderedItems.last == item)
                                        if item != MenuItemOrdering.main { Button(AidenteL10n.t("移除", "Remove")) { applyOrder(orderedItems.filter { $0 != item }) } }
                                    }
                                }
                            }
                            if iconStyle == .hidden && selected.isEmpty { Text(AidenteL10n.t("从下方目录添加项目", "Add items from the catalog below")).font(.caption).foregroundStyle(.secondary) }
                        }.frame(minHeight: 40).padding(.vertical, 4)
                            .animation(.easeInOut(duration: 0.24), value: renderedItems)
                    }.scrollIndicators(.visible).scrollClipDisabled()
                    .onPreferenceChange(CardFramesPreference.self) { cardDrag.frames = $0 }
                }
            }
            AidenteCard("菜单栏项目目录", icon: "book", colors: []) {
                UtilitySurface {
                    VStack(alignment: .leading, spacing: 20) {
                        DisclosureGroup(AidenteL10n.t("主图标样式与选项", "Main Icon Style and Options"), isExpanded: $showIconOptions) {
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
                        HStack {
                            Text(AidenteL10n.t("接电标记样式", "Plugged-in Indicator"))
                            Spacer()
                            Picker("", selection: $indicatorStyle) { ForEach(ChargingIndicatorStyle.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 190)
                        }
                        Text(AidenteL10n.t("自动：充电用闪电，暂停保持用插头。也可固定图案；实际充电状态以状态说明为准。", "Automatic uses a bolt while charging and a plug while holding. A fixed glyph is cosmetic; the status text reports the actual state.")).font(.caption).foregroundStyle(.secondary)
                        AidenteSettingToggle("低电量模式颜色", icon: "paintpalette", colors: [], isOn: $lowPowerColor)
                        AidenteSettingToggle("用颜色显示电池状态", icon: "paintpalette.fill", colors: [], isOn: $stateColors)
                        }
                        Divider()
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
        }.onAppear { animatedOrder = orderedItems; viewModel.menuWillOpen() }
        .onDisappear { cardDrag.item = nil; viewModel.menuDidClose() }
        .task(id: orderedItems) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) { animatedOrder = orderedItems }
        }
    }
    private func applyOrder(_ items: [String]) {
        if let position = items.firstIndex(of: MenuItemOrdering.main) { mainPosition = position }
        metricIDs = items.filter { MenuBarMetric(rawValue: $0) != nil }
    }
    private func moveItem(_ item: String, _ offset: Int) {
        guard let index = orderedItems.firstIndex(of: item), orderedItems.indices.contains(index + offset) else { return }
        applyOrder(MenuItemOrdering.moving(item, onto: orderedItems[index + offset], in: orderedItems))
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
        mainPosition = 0; iconStyle = .status; metricIDs = []; hiddenMetricIcons = []; percentageLocation = .nextToIcon
        lowPowerColor = true; stateColors = true; itemSpacing = 5; updateInterval = 5
        legacyReadout = .batteryPercentage; rightClick = .popover
    }

}
