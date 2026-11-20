import SwiftUI

/// Lives inside the nonactivating panel. It has no separate menu window or
/// tracking session that can close when the main app has not been activated.
struct PopoverWidgetPicker: View {
    @Binding var ids: [String]
    @Binding var isPresented: Bool
    private var available: [PopoverWidget] { PopoverWidget.allCases.filter { !ids.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AidenteL10n.t("添加小组件", "Add Widgets")).font(.caption.weight(.semibold))
                Spacer()
                Button { isPresented = false } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel(AidenteL10n.t("关闭添加列表", "Close Widget Picker"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    widgetSection(AidenteL10n.t("组件", "Widgets"), graphs: false)
                    widgetSection(AidenteL10n.t("曲线", "Graphs"), graphs: true)
                    if available.isEmpty {
                        Text(AidenteL10n.t("所有组件均已添加", "All widgets have been added")).font(.caption).foregroundStyle(.secondary)
                    }
                    Divider().padding(.vertical, 3)
                    Text(AidenteL10n.t("布局预设", "Layout Presets")).font(.caption2).foregroundStyle(.secondary)
                    preset(AidenteL10n.t("简洁布局", "Minimalist"), ids: PopoverWidget.minimalist)
                    preset(AidenteL10n.t("健康优先布局", "Health Focused"), ids: PopoverWidget.healthFocused)
                    preset(AidenteL10n.t("详细布局", "Power User"), ids: PopoverWidget.powerUser)
                    preset(AidenteL10n.t("恢复紧凑布局", "Restore Compact Layout"), ids: [])
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 190)
        }
        .padding(10)
        .background(AidenteReliefSurface(cornerRadius: 12))
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AidenteL10n.t("组件添加列表", "Widget Picker"))
    }
    @ViewBuilder private func widgetSection(_ title: String, graphs: Bool) -> some View {
        let items = available.filter { $0.isGraph == graphs }
        if !items.isEmpty {
            Text(title).font(.caption2).foregroundStyle(.secondary).padding(.top, 3)
            ForEach(items) { widget in
                Button {
                    if !ids.contains(widget.id) { ids.append(widget.id) }
                    isPresented = false
                } label: {
                    HStack {
                        Text(widget.title).font(.caption)
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(.tint)
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.accessibilityLabel(AidenteL10n.t("添加 ", "Add ") + widget.title)
            }
        }
    }
    private func preset(_ title: String, ids value: [String]) -> some View {
        Button { ids = value; isPresented = false } label: {
            HStack { Text(title).font(.caption); Spacer() }.padding(.vertical, 5).contentShape(Rectangle())
        }
    }
}
