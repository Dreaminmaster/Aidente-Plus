import AidenteShared
import Defaults
import SwiftUI
import UniformTypeIdentifiers
import OSLog

struct DashboardSettingsView: View {
    @Default(.popoverWidgets) private var widgetIDs
    @Default(.popoverMetricIDs) private var specIDs
    @Default(.popoverShowOnLaunch) private var onLaunch
    @Default(.popoverShowPercentage) private var showPercentage
    @Default(.compactEnergyWidget) private var compactEnergy
    @State private var cardDrag = CardDragState()
    @State private var animatedWidgets: [String] = []
    private var renderedWidgets: [String] { animatedWidgets.isEmpty ? widgetIDs : animatedWidgets }
    private var widgetOrder: Binding<[String]> { Binding(get: { renderedWidgets }, set: { ids in
        withAnimation(.easeInOut(duration: 0.24)) { animatedWidgets = ids }
        widgetIDs = ids
    }) }
    @State private var showDetails = false
    private var available: [PopoverWidget] { PopoverWidget.allCases.filter { !widgetIDs.contains($0.id) } }
    var body: some View {
        AidenteSettingsPage {
            AidenteSettingToggle("启动时显示", icon: "eye", colors: [], isOn: $onLaunch)
            AidenteSettingToggle("显示百分比", icon: "percent", colors: [], isOn: $showPercentage)
            Button(AidenteL10n.t("在编辑模式下打开", "Open in Edit Mode")) { PopoverEditorState.shared.beginEditing() }
                .buttonStyle(.bordered)
            HStack {
                Text(AidenteL10n.t("布局预设", "Layout Presets")).font(.headline)
                Spacer()
                Menu(AidenteL10n.t("选择布局", "Choose Layout")) {
                    Button(AidenteL10n.t("简洁", "Minimalist")) { widgetIDs = PopoverWidget.minimalist }
                    Button(AidenteL10n.t("电池健康", "Battery Health")) { widgetIDs = PopoverWidget.healthFocused }
                    Button(AidenteL10n.t("详细", "Power User")) { widgetIDs = PopoverWidget.powerUser }
                    Button(AidenteL10n.t("仅充电控制", "Charge Controls Only")) { widgetIDs = [] }
                }.fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                Label(AidenteL10n.t("显示顺序 · 拖动卡片调整", "Display Order · Drag Cards to Reorder"), systemImage: "arrow.up.arrow.down").font(.headline)
                if widgetIDs.isEmpty {
                    Text(AidenteL10n.t("尚未添加组件，请从下方组件库点“添加”。", "No widgets yet. Add one from the catalog below.")).foregroundStyle(.secondary)
                }
                ForEach(PopoverWidget.selected(from: renderedWidgets)) { widget in
                    FreeReorderCard(id: widget.id, drag: $cardDrag, move: { source, target in
                        widgetOrder.wrappedValue = MenuItemOrdering.moving(source, onto: target, in: renderedWidgets)
                    }) {
                    HStack(spacing: 10) {
                        WidgetLayoutPreview(widget: widget)
                        Spacer(minLength: 0)
                        Menu {
                            Button(AidenteL10n.t("上移", "Move Up")) { move(widget, -1) }.disabled(widgetIDs.first == widget.id)
                            Button(AidenteL10n.t("下移", "Move Down")) { move(widget, 1) }.disabled(widgetIDs.last == widget.id)
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                        Button { widgetIDs.removeAll { $0 == widget.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel(AidenteL10n.t("移除 ", "Remove ") + widget.title)
                    }.padding(12).background(AidenteReliefSurface(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))

                    }
                }
            }
            .onPreferenceChange(CardFramesPreference.self) { cardDrag.frames = $0 }
            .animation(.easeInOut(duration: 0.24), value: renderedWidgets)
            VStack(alignment: .leading, spacing: 12) {
                Label(AidenteL10n.t("添加组件", "Add Widgets"), systemImage: "plus.circle").font(.headline)
                Text(AidenteL10n.t("移除的组件会立即回到这里，可随时重新添加。", "Removed widgets return here and can be added again.")).font(.caption).foregroundStyle(.secondary)
                ForEach(available) { widget in
                    HStack {
                        WidgetLayoutPreview(widget: widget)
                        Spacer()
                        Button { widgetIDs.append(widget.id) } label: { Label(AidenteL10n.t("添加", "Add"), systemImage: "plus") }
                            .buttonStyle(.bordered).accessibilityLabel(AidenteL10n.t("添加 ", "Add ") + widget.title)
                    }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                }
                if available.isEmpty { Text(AidenteL10n.t("已添加全部组件", "All widgets added")).foregroundStyle(.secondary) }
            }
            AidenteSettingToggle("仅功耗模式激活时显示组件", subtitle: "开启：当前电源处于低/高功耗模式时才显示；关闭：始终保留控制入口。", icon: "leaf", colors: [], isOn: $compactEnergy)
            DisclosureGroup(AidenteL10n.t("规格组件内容", "Specification Readings"), isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(MenuBarMetric.allCases.filter { !["calibration", "sailing", "heatProtection", "topUp"].contains($0.id) }) { metric in
                        Toggle(metric.group + " · " + metric.title, isOn: Binding(get: { specIDs.contains(metric.id) }, set: { enabled in
                            if enabled { if !specIDs.contains(metric.id) { specIDs.append(metric.id) } }
                            else { specIDs.removeAll { $0 == metric.id } }
                        })).toggleStyle(.checkbox)
                    }
                }.padding(.top, 12)
            }
        }.onAppear { animatedWidgets = widgetIDs }
        .onDisappear { cardDrag.item = nil }
        .task(id: widgetIDs) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) { animatedWidgets = widgetIDs }
        }
    }
    private func move(_ widget: PopoverWidget, _ offset: Int) {
        guard let index = widgetIDs.firstIndex(of: widget.id), widgetIDs.indices.contains(index + offset) else { return }
        widgetIDs.swapAt(index, index + offset)
    }
}

private struct WidgetLayoutPreview: View {
    let widget: PopoverWidget
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.055))
                if widget.isGraph {
                    Path { p in p.move(to: CGPoint(x: 6, y: 29)); p.addLines([CGPoint(x: 16, y: 18), CGPoint(x: 25, y: 23), CGPoint(x: 36, y: 10), CGPoint(x: 47, y: 12)]) }
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                } else if widget == .powerFlow {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 21)).foregroundStyle(.secondary)
                } else { Image(systemName: widget.previewIcon).font(.system(size: 21)).foregroundStyle(.secondary) }
            }.frame(width: 54, height: 40).accessibilityHidden(true)
            Text(widget.title).font(.callout)
        }.frame(minHeight: 44)
    }
}
private extension PopoverWidget {
    var previewIcon: String {
        switch self {
        case .sleepControl: "moon"
        case .energyMode: "leaf"
        case .specifications, .batterySpecs: "list.bullet.rectangle"
        case .energyApps: "app.dashed"
        case .careActions: "battery.100.bolt"
        case .protection: "text.bubble"
        case .settingsLinks: "gearshape"
        default: "chart.xyaxis.line"
        }
    }
}
private struct WidgetReorderDropDelegate: DropDelegate {
    let target: String
    @Binding var values: [String]
    @Binding var dragged: String?
    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target, let source = values.firstIndex(of: dragged), let destination = values.firstIndex(of: target) else { return }
        Logger(subsystem: "com.aidente.app", category: "LayoutDrag").notice("WIDGET_DRAG_ENTER \(target, privacy: .public)")
        withAnimation(.easeInOut(duration: 0.18)) { values.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
}
