import AppKit
import Defaults
import SwiftUI
import AidenteShared

@Observable @MainActor final class PopoverEditorState {
    static let shared = PopoverEditorState()
    var isEditing = false
    var isAddingWidget = false
    private var trackedMenu: NSMenu?
    private var lastMenuTrackingInterval: ClosedRange<TimeInterval>?
    var isTrackingNativeMenu: Bool { trackedMenu != nil }
    var requestOpen: (() -> Void)?
    var updateSize: (() -> Void)?
    func beginEditing() { isEditing = true; requestOpen?() }

    func track(_ menu: NSMenu, at point: NSPoint, in anchor: NSView) {
        guard trackedMenu == nil else { return }
        let started = ProcessInfo.processInfo.systemUptime
        trackedMenu = menu
        defer {
            lastMenuTrackingInterval = started...ProcessInfo.processInfo.systemUptime
            trackedMenu = nil
        }
        menu.popUp(positioning: nil, at: point, in: anchor)
    }

    func consumeMenuEscape(_ event: NSEvent?) -> Bool {
        if let trackedMenu {
            trackedMenu.cancelTracking()
            return true
        }
        // AppKit can forward the same key to the panel after the menu exits.
        // A fresh Esc must still close the parent panel.
        guard let event, event.type == .keyDown, event.keyCode == 53 else { return false }
        return lastMenuTrackingInterval?.contains(event.timestamp) == true
    }
}

@MainActor enum PopoverLayout {
    static func visibleWidgets(_ ids: [String], editing: Bool, calibrating: Bool = false) -> [PopoverWidget] {
        var result = PopoverWidget.selected(from: ids).filter {
            $0 != .energyMode || editing || !Defaults[.compactEnergyWidget] || EnergyModeService.shared.isNonAutomaticActive
        }
        if calibrating && !result.contains(.careActions) { result.insert(.careActions, at: 0) }
        return result
    }
    static func height(widgets: [String], editing: Bool, adding: Bool = false, calibrating: Bool = false) -> CGFloat {
        return min(620, 134 + (editing ? 64 : 0) + (adding && editing ? 240 : 0) + CGFloat(visibleWidgets(widgets, editing: editing, calibrating: calibrating).count) * 140)
    }
}

struct DashboardPopoverView: View {
    @Environment(\.colorScheme) private var scheme
    let viewModel: MenuViewModel
    let onOpenSettings: (SettingsTab) -> Void
    let onQuit: () -> Void
    var drawsBackdrop = true
    @Default(.interfaceAppearance) private var appearance
    @Default(.popoverWidgets) private var widgetIDs
    @Default(.chargeLimit) private var limit
    @Default(.allowBelow80) private var below80
    @Default(.sailingMode) private var sailing
    @Default(.sailingModeLimit) private var sailingRange
    @Default(.popoverShowPercentage) private var showPercentage
    @Default(.automaticDischarge) private var automaticDischarge
    @Default(.popoverMetricIDs) private var specIDs
    @Default(.compactEnergyWidget) private var compactEnergyWidget
    @Default(.showDockIcon) private var showDockIcon
    @State private var draft = 80.0
    @State private var editingLimit = false
    @State private var enteringLimit = false
    @State private var typedLimit = ""
    @FocusState private var limitFieldIsFocused: Bool
    @State private var dragged: String?
    private let editor = PopoverEditorState.shared
    private var canControl: Bool { viewModel.manageChargingEnabled && !AidenteRuntime.isUIPreview && !viewModel.systemCalibrationActive }
    private var canEditLimit: Bool {
        !viewModel.chargeLimitOverrideActive && !viewModel.calibrationActive && !viewModel.systemCalibrationActive
    }
    private var typedTarget: Int? { ChargeLimitInput.parse(typedLimit, allowBelow80: below80) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Button {
                        typedLimit = String(viewModel.effectiveChargeLimit)
                        enteringLimit = true
                    } label: {
                        Text(AidenteL10n.t("上限：", "Limit: ") + "\(editingLimit ? Int(draft.rounded()) : viewModel.effectiveChargeLimit)%")
                            .fontWeight(.semibold).monospacedDigit()
                    }.popover(isPresented: $enteringLimit) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(below80 ? "20–100%" : "80–100%").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                TextField(AidenteL10n.t("充电上限", "Charge Limit"), text: $typedLimit)
                                    .focused($limitFieldIsFocused)
                                    .frame(width: 58).onSubmit { commitTypedLimit() }
                                Text("%")
                                Button(AidenteL10n.t("取消", "Cancel")) { enteringLimit = false }
                                    .keyboardShortcut(.cancelAction)
                                Button(AidenteL10n.t("好", "OK")) { commitTypedLimit() }
                                    .keyboardShortcut(.defaultAction).disabled(typedTarget == nil)
                            }
                        }.padding(12)
                            .onAppear { limitFieldIsFocused = true }
                    }.disabled(!canEditLimit).help(AidenteL10n.t("输入目标百分比", "Enter a target percentage"))
                    Spacer(minLength: 0)
                    Button { viewModel.toggleForceDischarge() } label: {
                        HStack(spacing: 16) {
                            Text(AidenteL10n.t(viewModel.dischargeRequested ? "停止" : "放电", viewModel.dischargeRequested ? "Stop" : "Discharge"))
                            Image(systemName: viewModel.dischargeRequested ? "stop.circle" : "minus.circle").font(.system(size: 16))
                        }
                    }.disabled(!canControl || (!viewModel.dischargeRequested && (!viewModel.adapterConnected || viewModel.displayPercentage <= limit)))
                        .help(!viewModel.adapterConnected && !viewModel.dischargeRequested
                              ? AidenteL10n.t("接通电源后可主动放电至设定上限。", "Connect power to discharge to the charge limit.")
                              : AidenteL10n.t(automaticDischarge
                            ? "自动放电已开启。停止会同时关闭自动放电，避免立即重新开始。"
                            : "将电池放电至设定的充电上限；放电期间点击停止。",
                            automaticDischarge
                            ? "Automatic discharge is on. Stop also turns it off to prevent an immediate restart."
                            : "Discharge to the charge limit; click Stop to end it."))
                    Button { viewModel.toggleChargeLimitOverride() } label: {
                        HStack(spacing: 12) {
                            Text(AidenteL10n.t(viewModel.chargeLimitOverrideActive ? "停止" : "充满", viewModel.chargeLimitOverrideActive ? "Stop" : "Top Up"))
                            Image(systemName: "plus.circle").font(.system(size: 16))
                        }
                    }.disabled(!canControl || (!viewModel.chargeLimitOverrideActive && (!viewModel.adapterConnected || viewModel.effectiveChargeLimit == 100)))
                        .help(!viewModel.adapterConnected && !viewModel.chargeLimitOverrideActive
                              ? AidenteL10n.t("接通电源后可临时充满。", "Connect power to top up.")
                              : AidenteL10n.t("充至 100%，保持至拔掉电源。", "Charge to 100% and hold until unplugged."))
                    Button { onOpenSettings(.overview) } label: {
                        Image(systemName: "square.grid.2x2").font(.system(size: 16))
                    }.accessibilityLabel(AidenteL10n.t("打开设置", "Open Settings"))
                }.buttonStyle(PopoverHeaderButtonStyle())
                PopoverChargeSlider(value: $draft, percentage: viewModel.displayPercentage,
                    showPercentage: showPercentage, adapterConnected: viewModel.adapterConnected, chargingMode: viewModel.chargingMode, motion: viewModel.trackMotion, sailing: viewModel.sailingActive,
                    minimum: below80 ? 20 : 80,
                    sailingLower: sailing && !viewModel.calibrationActive && !viewModel.chargeLimitOverrideActive ? max(20, (editingLimit ? Int(draft.rounded()) : limit) - sailingRange) : nil,
                    enabled: canEditLimit,
                    onEditing: { editing in
                        editingLimit = editing
                        if !editing { limit = min(100, max(below80 ? 20 : 80, Int(draft.rounded()))); draft = Double(limit) }
                    })

            }.padding(16)
            if editor.isEditing {
                HStack {
                    Text(AidenteL10n.t("编辑小组件", "Edit Widgets")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        editor.isAddingWidget.toggle()
                    } label: {
                        Label(AidenteL10n.t("添加", "Add"), systemImage: editor.isAddingWidget ? "chevron.up" : "plus")
                    }.accessibilityLabel(AidenteL10n.t("添加小组件", "Add Widgets"))
                    Button(AidenteL10n.t("完成", "Done")) { editor.isEditing = false }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
            if editor.isEditing && editor.isAddingWidget {
                PopoverWidgetPicker(ids: $widgetIDs, isPresented: Binding(
                    get: { editor.isAddingWidget }, set: { editor.isAddingWidget = $0 }
                ))
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
            if editor.isEditing && widgetIDs.isEmpty {
                Text(AidenteL10n.t("从“添加”中选择小组件，拖动可调整顺序。", "Choose widgets from Add, then drag to reorder them."))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            if !PopoverLayout.visibleWidgets(widgetIDs, editing: editor.isEditing, calibrating: viewModel.calibrationActive).isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(PopoverLayout.visibleWidgets(widgetIDs, editing: editor.isEditing, calibrating: viewModel.calibrationActive)) { widget in
                            VStack(alignment: .leading, spacing: 8) {
                                if editor.isEditing && widgetIDs.contains(widget.id) {
                                    HStack {
                                        Text(widget.title).font(.caption)
                                        Spacer()
                                        Button { move(widget, -1) } label: { Image(systemName: "chevron.up") }.disabled(widgetIDs.first == widget.id)
                                        Button { move(widget, 1) } label: { Image(systemName: "chevron.down") }.disabled(widgetIDs.last == widget.id)
                                        Button { widgetIDs.removeAll { $0 == widget.id } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }.accessibilityLabel(AidenteL10n.t("移除", "Remove") + " " + widget.title)
                                    }.buttonStyle(.borderless)
                                }
                                if editor.isEditing && widget == .specifications {
                                    DisclosureGroup(AidenteL10n.t("选择显示的规格", "Choose Specification Rows")) {
                                        ForEach(MenuBarMetric.allCases.filter { !["calibration", "sailing", "heatProtection", "topUp"].contains($0.id) }) { metric in
                                            Toggle(metric.title, isOn: Binding(get: { specIDs.contains(metric.id) }, set: { chosen in
                                                if chosen { if !specIDs.contains(metric.id) { specIDs.append(metric.id) } }
                                                else { specIDs.removeAll { $0 == metric.id } }
                                            })).toggleStyle(.checkbox)
                                        }
                                    }
                                }
                                if editor.isEditing && widget == .energyMode {
                                    Toggle(AidenteL10n.t("紧凑模式（仅启用功耗模式时显示）", "Compact (only visible while a power mode is active)"), isOn: $compactEnergyWidget)
                                        .toggleStyle(.checkbox)
                                }
                                widgetView(widget)
                            }.padding(12).background {
                                if widget != .powerFlow { AidenteReliefSurface(cornerRadius: 15) }
                            }
                                .modifier(WidgetEditingDrag(enabled: editor.isEditing, widget: widget, ids: $widgetIDs, dragged: $dragged))
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 12)
                }.scrollIndicators(.automatic)
            }
            Divider()
            HStack(spacing: 12) {
                Text(viewModel.operationStatusText).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).help(viewModel.operationStatusText + AidenteL10n.t("；长按此状态文字编辑小组件。", "; hold this status text to edit widgets."))
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.5) { editor.isEditing = true }
                Spacer(minLength: 4)
                Button {
                    editor.isEditing.toggle()
                } label: {
                    Label(AidenteL10n.t(editor.isEditing ? "完成" : "自定义", editor.isEditing ? "Done" : "Customize"),
                          systemImage: editor.isEditing ? "checkmark" : "slider.horizontal.3")
                }.accessibilityLabel(AidenteL10n.t("自定义弹出窗口", "Customize Popover"))
                DashboardMenuButton(symbol: "ellipsis.circle", label: AidenteL10n.t("小组件与外观选项", "Widgets and Appearance"), populate: populateOptionsMenu)
                    .frame(width: 24, height: 24)
            }.buttonStyle(.borderless).font(.system(size: 11))
                .padding(.horizontal, 16).frame(height: 41)
        }
        .frame(width: 402, height: PopoverLayout.height(widgets: widgetIDs, editing: editor.isEditing, adding: editor.isAddingWidget, calibrating: viewModel.calibrationActive))
        .background { if drawsBackdrop { AidenteMaterialLayer() } }
        .tint(.accentColor)
        .disabled(CompleteUninstaller.shared.isRunning)
        .onAppear { draft = Double(viewModel.effectiveChargeLimit) }
        .onDisappear { editingLimit = false; draft = Double(viewModel.effectiveChargeLimit) }
        .onChange(of: canEditLimit) { _, enabled in
            if !enabled {
                editingLimit = false
                enteringLimit = false
                draft = Double(viewModel.effectiveChargeLimit)
            }
        }
        .onChange(of: viewModel.effectiveChargeLimit) { _, value in if !editingLimit { draft = Double(value) } }
        .onChange(of: widgetIDs) { _, _ in editor.updateSize?() }
        .onChange(of: editor.isEditing) { _, editing in
            if !editing { editor.isAddingWidget = false }
            editor.updateSize?()
        }
        .onChange(of: editor.isAddingWidget) { _, _ in editor.updateSize?() }
        .onChange(of: compactEnergyWidget) { _, _ in editor.updateSize?() }
        .onChange(of: EnergyModeService.shared.isNonAutomaticActive) { _, _ in editor.updateSize?() }
        .onChange(of: viewModel.calibrationActive) { _, _ in editor.updateSize?() }
        .contextMenu {
            Button(AidenteL10n.t("编辑小组件", "Edit Widgets")) { editor.isEditing = true }
            Button(AidenteL10n.t("充电控制", "Charge Control")) { onOpenSettings(.charging) }
            Divider()
            Button(AidenteL10n.t("退出 Aidente", "Quit Aidente"), action: onQuit)
        }
    }
    private func populateOptionsMenu(_ menu: NSMenu, _ target: DashboardMenuButton.Coordinator) {
        let heading = NSMenuItem(title: AidenteL10n.t("小组件", "Widgets"), action: nil, keyEquivalent: "")
        menu.addItem(heading)
        for widget in PopoverWidget.allCases {
            menu.addItem(target.item(widget.title, checked: widgetIDs.contains(widget.id)) {
                if widgetIDs.contains(widget.id) { widgetIDs.removeAll { $0 == widget.id } }
                else { widgetIDs.append(widget.id) }
            })
        }
        menu.addItem(.separator())
        let appearanceItem = NSMenuItem(title: AidenteL10n.t("界面外观", "Appearance"), action: nil, keyEquivalent: "")
        let appearances = NSMenu()
        for style in InterfaceAppearance.allCases {
            appearances.addItem(target.item(style.title, checked: appearance == style) { appearance = style })
        }
        appearanceItem.submenu = appearances
        menu.addItem(appearanceItem)
        menu.addItem(target.item(AidenteL10n.t("在 Dock 中显示", "Show in Dock"), checked: showDockIcon) { showDockIcon.toggle() })
        menu.addItem(target.item(AidenteL10n.t("弹出窗口设置…", "Popover Settings…")) { onOpenSettings(.dashboard) })
        menu.addItem(target.item(AidenteL10n.t("菜单栏样式…", "Menu Bar Appearance…")) { onOpenSettings(.menuBar) })
        menu.addItem(target.item(AidenteL10n.t("充电器指示灯…", "Charger LED…")) { onOpenSettings(.otherAppearance) })
        menu.addItem(.separator())
        menu.addItem(target.item(AidenteL10n.t("退出 Aidente", "Quit Aidente"), action: onQuit))
    }

    private func commitTypedLimit() {
        guard canEditLimit, let typedTarget else { return }
        enteringLimit = false
        limit = typedTarget
        draft = Double(limit)
    }
    private func move(_ widget: PopoverWidget, _ offset: Int) {
        guard let i = widgetIDs.firstIndex(of: widget.id), widgetIDs.indices.contains(i + offset) else { return }
        widgetIDs.swapAt(i, i + offset)
    }
    @ViewBuilder private func widgetView(_ widget: PopoverWidget) -> some View {
        switch widget {
        case .sleepControl: SleepControlWidget()
        case .energyMode: EnergyModeWidget()
        case .specifications: SpecificationsWidget(viewModel: viewModel)
        case .powerFlow:
            PowerSankeyView(powerSource: viewModel.powerSource, isCharging: viewModel.isCharging, batteryPower: viewModel.batteryPower, adapterPower: viewModel.adapterPower, systemPower: viewModel.systemPower, components: viewModel.componentPower)
        case .batterySpecs:
            VStack(spacing: 8) {
                dashboardValue(AidenteL10n.t("电池健康", "Battery Health"), viewModel.batteryHealthText)
                dashboardValue(AidenteL10n.t("循环次数", "Cycles"), viewModel.cycleCountText)
                dashboardValue(AidenteL10n.t("温度", "Temperature"), viewModel.batteryTemperatureText)
            }
        case .capacityHistory: PopoverCapacityWidget(viewModel: viewModel)
        case .energyApps: EnergyAppsWidget(viewModel: viewModel)
        case .careActions:
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.calibrationActive {
                    Label(viewModel.operationStatusText, systemImage: "slider.vertical.3").font(.caption)
                    Button(AidenteL10n.t("取消校准", "Stop Calibration")) { viewModel.toggleCalibration() }
                } else {
                    HStack {
                        Button(AidenteL10n.t(viewModel.manualPauseActive ? "恢复充电" : "暂停充电")) { viewModel.toggleManualPause() }
                        Spacer()
                        Button(AidenteL10n.t("开始校准", "Start Calibration")) { viewModel.toggleCalibration() }
                    }
                }
            }.disabled(!canControl || viewModel.systemCalibrationActive)
        case .protection: PopoverStatusExplanation(viewModel: viewModel)
        case .batteryLevelGraph, .temperatureGraph, .powerGraph, .cycleGraph:
            PopoverTrendWidget(kind: widget, viewModel: viewModel)
        case .settingsLinks:
            HStack {
                Button(AidenteL10n.t("仪表板", "Dashboard")) { onOpenSettings(.overview) }
                Spacer()
                Button(AidenteL10n.t("菜单栏", "Menu Bar")) { onOpenSettings(.menuBar) }
            }
        }
    }
}

struct EnergyAppsWidget: View {
    let viewModel: MenuViewModel
    @State private var quitting: AppEnergyUsageSnapshot?
    @State private var showingQuitConfirmation = false
    @State private var forceQuit = false
    private let quitService = AppQuitService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceHoverMotion
    @State private var hoveredApp: String?
    @State private var hoveringList = false
    @State private var interactionID = UUID()
    @Default(.showAllRunningApps) private var showAll
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(showAll ? AidenteL10n.t("运行中的 App", "Running Apps") : AidenteL10n.t("高能耗 App", "Significant Energy")).font(.caption.weight(.semibold))
                if !viewModel.energyAppScopeIsUpdating {
                    Text("\(viewModel.topEnergyApps.count)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                DashboardMenuButton(symbol: "line.3.horizontal.decrease", label: AidenteL10n.t("App 列表显示范围", "App List Scope")) { menu, target in
                    menu.addItem(target.item(AidenteL10n.t("所有运行中的 App", "All Running Apps"), checked: showAll) { showAll = true })
                    menu.addItem(target.item(AidenteL10n.t("仅高能耗 App", "Significant Energy Only"), checked: !showAll) { showAll = false })
                }.frame(width: 28, height: 24)
                    .help(AidenteL10n.t("按名称固定排序，不按功率换位；鼠标停留时固定名单，离开后更新。所有运行中的 App 包括空闲应用，后台进程可在能源使用设置中选择。", "Names stay in alphabetical order. Hover holds the list while readings update. All Running Apps includes idle apps; background processes are optional in Energy Use settings."))
            }
            Text(AidenteL10n.t("App 功率为进程能耗估算，不等于电脑总功率，也不作为整机分流。", "App watts are process estimates, not total Mac power or a hardware power breakdown."))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !viewModel.energyAppScopeIsUpdating && viewModel.topEnergyApps.count > 6 {
                Text(AidenteL10n.t("按名称排序 · 向下滚动查看全部", "Sorted by name · scroll to see all")).font(.caption2).foregroundStyle(.secondary)
            }
            if viewModel.energyAppScopeIsUpdating {
                Text(AidenteL10n.t("正在更新 App 列表…", "Updating the app list…")).font(.caption).foregroundStyle(.secondary)
            } else if viewModel.topEnergyApps.isEmpty {
                Text(viewModel.hasEnergyUsageSample ? (showAll ? AidenteL10n.t("没有运行中的 App", "No running apps") : AidenteL10n.t("没有使用大量能耗的 App", "No apps using significant energy")) : AidenteL10n.t("正在采集近期 App 用量…", "Sampling recent app activity…")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.topEnergyApps) { app in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundlePath)).resizable().frame(width: 22, height: 22)
                        Text(app.name).lineLimit(1).help(app.name)
                        Spacer()
                        Text(app.measurementText).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(Color.primary.opacity(0.82))
                            .help(app.estimatedWatts == nil ? "暂未取得完整进程能量采样，显示近期平滑后的 CPU 活动；短暂波动不会立即增删条目。" : "由系统进程能量计数计算的近期平滑功率估算，不包含可完整归属的所有 GPU、屏幕或外设能耗。暂缺读数最多保留6秒；持续低用量后移除。")
                        if !app.isBackground {
                            if let state = quitService.states[app.bundlePath] {
                                if state == .requesting {
                                    ProgressView().controlSize(.mini).frame(width: 32)
                                        .help(AidenteL10n.t("已发送退出请求，正在等待应用关闭。", "Quit requested; waiting for the app to close."))
                                } else {
                                    Menu {
                                        Text(AidenteL10n.t("应用仍在运行，可能正在等待保存或取消了退出。", "The app is still running; it may be waiting for you to save or may have declined quitting."))
                                        Button(AidenteL10n.t("查看应用", "Show App")) { quitService.showApplication(path: app.bundlePath) }
                                        Button(AidenteL10n.t("重试退出", "Retry Quit")) { quitService.request(path: app.bundlePath) }
                                        Button(AidenteL10n.t("强制退出…", "Force Quit…"), role: .destructive) {
                                            quitting = app; forceQuit = true; showingQuitConfirmation = true
                                        }
                                    } label: { Image(systemName: "exclamationmark.circle") }
                                        .menuStyle(.borderlessButton).fixedSize()
                                        .accessibilityLabel(AidenteL10n.t("仍在运行：", "Still running: ") + app.name)
                                }
                            } else if hoveredApp == app.bundlePath {
                                Button {
                                    quitting = app; forceQuit = false; showingQuitConfirmation = true
                                } label: { Text(AidenteL10n.t("退出", "Quit")).font(.caption2).frame(width: 32) }
                                    .buttonStyle(.borderless)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .accessibilityLabel(AidenteL10n.t("退出 ", "Quit ") + app.name)
                                    .disabled(AidenteRuntime.isUIPreview)
                            }
                        }
                    }.frame(maxWidth: .infinity)
                    // The trailing move transition must stay inside this row, including on removal.
                    .clipped()
                    .contentShape(Rectangle())
                    .contextMenu {
                        if !app.isBackground {
                            Button(AidenteL10n.t("退出", "Quit")) {
                                quitting = app; forceQuit = false; showingQuitConfirmation = true
                            }.disabled(AidenteRuntime.isUIPreview)
                        }
                    }
                    .animation(reduceHoverMotion ? nil : .easeInOut(duration: 0.2), value: hoveredApp == app.bundlePath)
                    .onHover { hovering in hoveredApp = hovering ? app.bundlePath : nil }
                }
            }
        }.frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .onHover { hovering in
            hoveringList = hovering
            AppListInteractionState.shared.update(interactionID, active: hovering || showingQuitConfirmation)
        }
        .onChange(of: showAll) { _, _ in viewModel.refreshEnergyUsage() }
        .onChange(of: showingQuitConfirmation) { _, value in AppListInteractionState.shared.update(interactionID, active: hoveringList || value) }
        .onDisappear { AppListInteractionState.shared.update(interactionID, active: false) }
        .alert(forceQuit ? AidenteL10n.t("强制退出 App？", "Force quit app?") : AidenteL10n.t("退出 App？", "Quit app?"),
               isPresented: $showingQuitConfirmation, presenting: quitting) { app in
            Button(forceQuit ? AidenteL10n.t("强制退出", "Force Quit") : AidenteL10n.t("退出", "Quit"), role: forceQuit ? .destructive : nil) {
                quitService.request(path: app.bundlePath, force: forceQuit)
            }
            Button(AidenteL10n.t("取消", "Cancel"), role: .cancel) { }
        } message: { app in
            Text(app.name + "\n" + (forceQuit
                ? AidenteL10n.t("未保存的内容会丢失。", "Unsaved changes will be lost.")
                : AidenteL10n.t("应用可能要求你保存内容。若未退出，列表会提供查看和重试入口。", "The app may ask you to save. If it stays open, the list will offer Show App and Retry.")))
        }
    }
}

func dashboardValue(_ label: String, _ value: String) -> some View {
    HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 12))
}

struct WidgetReorderDelegate: DropDelegate {
    let target: String
    @Binding var ids: [String]
    @Binding var dragged: String?
    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target, let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target) else { return }
        withAnimation { ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
}

struct SailingRangeOverlay: View {
    let lower: Int
    let upper: Int
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 18)
            let start = CGFloat(max(20, min(100, lower)) - 20) / 80
            let end = CGFloat(max(20, min(100, upper)) - 20) / 80
            Path { path in
                path.move(to: CGPoint(x: 9 + width * start, y: geometry.size.height / 2))
                path.addLine(to: CGPoint(x: 9 + width * end, y: geometry.size.height / 2))
            }.stroke(.primary.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
        }
    }
}

/// Charge level and target are separate: the fill is live battery level, the handle is the limit.
private struct PopoverChargeSlider: View {
    @Binding var value: Double
    let percentage: Int
    let showPercentage: Bool
    let adapterConnected: Bool
    let chargingMode: ChargingMode
    var motion: ChargeTrackMotion = .stopped
    let sailing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let minimum: Int
    let sailingLower: Int?
    let enabled: Bool
    let onEditing: (Bool) -> Void

    @State private var dragOrigin: Double?

    private func setTarget(_ target: Double) {
        value = min(100, max(Double(minimum), target.rounded()))
    }
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let targetX = min(width - 4, max(4, width * value / 100))
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Color.primary.opacity(0.25), Color.primary.opacity(0.16)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.7))
                Capsule().fill(LinearGradient(colors: [Color(red:0.12,green:0.46,blue:0.65),Color(red:0.09,green:0.35,blue:0.51)], startPoint: .top, endPoint: .bottom))
                    .overlay(ChargeTrackGlow(motion: motion, reducedMotion: reduceMotion).allowsHitTesting(false))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.23), lineWidth: 0.6))
                    .frame(width: width * CGFloat(max(0, min(100, percentage))) / 100)
                    .animation(reduceMotion ? nil : .easeInOut(duration:0.35), value: percentage)
                if let lower = sailingLower {
                    Path { path in
                        path.move(to: CGPoint(x: width * CGFloat(lower) / 100, y: 2))
                        path.addLine(to: CGPoint(x: width * CGFloat(lower) / 100, y: 18))
                    }.stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                }
                if showPercentage {
                    Text("\(percentage)%").font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(percentage >= 15 ? Color.white : Color.primary).padding(.leading, 7)
                }
                HStack(spacing: 8) {
                    if adapterConnected && motion != .discharging {
                        HStack(spacing: 2) {
                            Image(systemName:"powerplug.portrait.fill")
                            if motion != .charging { Image(systemName:"pause.fill").font(.system(size:8)) }
                        }
                    } else { Image(systemName:"battery.50percent") }
                    if sailing { Image(systemName:"location.north.fill").rotationEffect(.degrees(40)) }
                }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: width * CGFloat(max(0,min(100,percentage))) / 100)
                    .opacity(percentage >= 15 ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration:0.12), value: adapterConnected)
                    .animation(reduceMotion ? nil : .easeInOut(duration:0.35), value: percentage)
                RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.75), lineWidth: 0.5))
                    .frame(width: 7, height: 24).shadow(color: .black.opacity(dragOrigin == nil ? 0.25 : 0.4), radius: 2, y: 1)
                    .position(x: targetX, y: 10)
            }
            .opacity(enabled ? 1 : 0.55)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                guard enabled else { return }
                if dragOrigin == nil {
                    // Grabbing the handle preserves its offset; clicking the track seeks directly.
                    dragOrigin = abs(event.startLocation.x - targetX) <= 12 ? value : Double(event.startLocation.x / width) * 100
                    onEditing(true)
                }
                setTarget((dragOrigin ?? value) + Double(event.translation.width / width) * 100)
            }.onEnded { _ in
                defer { dragOrigin = nil }
                if enabled && dragOrigin != nil { onEditing(false) }
            })
        }.frame(height: 20)
        .onDisappear { dragOrigin = nil }
        .onChange(of: enabled) { _, enabled in if !enabled { dragOrigin = nil } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AidenteL10n.t("充电上限", "Charge Limit"))
        .accessibilityValue(AidenteL10n.t("上限\(Int(value))%，当前电量\(percentage)%", "Limit \(Int(value))%, battery \(percentage)%"))
        .accessibilityHint(AidenteL10n.t("拖动白色滑块调整目标，蓝色填充表示当前电量。", "Drag the white handle to set the limit. The blue fill shows current charge."))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            onEditing(true)
            switch direction {
            case .increment: setTarget(value + 1)
            case .decrement: setTarget(value - 1)
            @unknown default: break
            }
            onEditing(false)
        }
    }
}

private struct PopoverHeaderButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(AidenteReliefSurface(cornerRadius: 30, pressed: configuration.isPressed))
            .opacity(enabled ? 1 : 0.35)
    }
}

private struct WidgetEditingDrag: ViewModifier {
    let enabled: Bool
    let widget: PopoverWidget
    @Binding var ids: [String]
    @Binding var dragged: String?
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.onDrag { dragged = widget.id; return NSItemProvider(object: widget.id as NSString) }
                .onDrop(of: [.text], delegate: WidgetReorderDelegate(target: widget.id, ids: $ids, dragged: $dragged))
        } else { content }
    }
}

/// An AppKit menu anchored to the actual button, including in a nonactivating panel.
private struct DashboardMenuButton: NSViewRepresentable {
    let symbol: String
    let label: String
    let populate: (NSMenu, Coordinator) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(populate: populate) }

    func makeNSView(context: Context) -> MenuButton {
        let button = MenuButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.target = context.coordinator
        button.action = #selector(Coordinator.open(_:))
        return button
    }

    func updateNSView(_ button: MenuButton, context: Context) {
        context.coordinator.populate = populate
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.isEnabled = context.environment.isEnabled
    }

    final class MenuButton: NSButton {
        private var tracking: NSTrackingArea?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area)
            tracking = area
        }
        override func mouseEntered(with event: NSEvent) {
            contentTintColor = .controlAccentColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.13).cgColor
        }
        override func mouseExited(with event: NSEvent) {
            contentTintColor = nil
            layer?.backgroundColor = nil
        }
    }

    @MainActor final class Coordinator: NSObject {
        private final class Choice: NSObject {
            let action: () -> Void
            init(_ action: @escaping () -> Void) { self.action = action }
        }
        var populate: (NSMenu, Coordinator) -> Void
        init(populate: @escaping (NSMenu, Coordinator) -> Void) { self.populate = populate }

        func item(_ title: String, checked: Bool = false, action: @escaping () -> Void) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(select(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Choice(action)
            item.state = checked ? .on : .off
            return item
        }

        @objc func select(_ item: NSMenuItem) {
            let action = (item.representedObject as? Choice)?.action
            DispatchQueue.main.async { action?() }
        }

        @objc func open(_ button: NSButton) {
            let editor = PopoverEditorState.shared
            guard !editor.isTrackingNativeMenu, let window = button.window else { return }
            let menu = NSMenu()
            populate(menu, self)
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
            let opensAbove = anchor.minY - screen.minY < menu.size.height + 6
                && screen.maxY - anchor.maxY > anchor.minY - screen.minY
            let upperY = anchor.maxY + menu.size.height + 3
            let screenPoint = NSPoint(
                x: max(screen.minX + 6, anchor.maxX - menu.size.width),
                y: opensAbove ? min(screen.maxY - 3, upperY) : anchor.minY - 3
            )
            editor.track(menu, at: button.convert(window.convertPoint(fromScreen: screenPoint), from: nil), in: button)
        }
    }
}
