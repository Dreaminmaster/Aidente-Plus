import AppKit
import Defaults
import AidenteShared
import SwiftUI
import os.log

@MainActor
final class StatusBarManager: NSObject, NSWindowDelegate {
    private let panelLogger = Logger(subsystem: "com.aidente.app", category: "MenuPanel")
    private let statusItem: NSStatusItem
    private let viewModel: MenuViewModel
    private let displayState: MenuBarDisplayState
    private var statusHosting: NSHostingView<AnyView>?
    private let settingsWindowController: SettingsWindowController
    private var popoverPanel: StatusPopoverPanel?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var transitionObserver: ImmediateStateObserver?
    private var displayObservation: Task<Void, Never>?
    private var powerWidthObservation: Task<Void, Never>?
    private var previewWindow: NSWindow?
    private var dashboardWindow: NSWindow?

    init(
        viewModel: MenuViewModel,
        settingsWindowController: SettingsWindowController
    ) {
        self.viewModel = viewModel
        self.displayState = MenuBarDisplayState(viewModel: viewModel)
        self.settingsWindowController = settingsWindowController
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()

        PopoverEditorState.shared.requestOpen = { [weak self] in self?.showPopoverForPreview() }
        PopoverEditorState.shared.updateSize = { [weak self] in
            guard let self, let panel = self.popoverPanel else { return }
            let size = NSSize(width: 402, height: PopoverLayout.height(widgets: Defaults[.popoverWidgets], editing: PopoverEditorState.shared.isEditing, calibrating: viewModel.calibrationActive))
            panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        }
        setupPersistentHostingView()
        startDisplayObservation()
        startTransitionObservation()
    }

    private func makeDashboardRootView() -> some View {
        AidenteAppearanceRoot {
        DashboardPopoverView(
            viewModel: viewModel,
            onOpenSettings: { [weak self] tab in
                guard let self else { return }
                self.dismissMenu()
                self.previewWindow?.close()
                self.dashboardWindow?.close()
                self.settingsWindowController.showSettings(tab: tab)
            },
            onQuit: { [weak self] in
                self?.viewModel.quit()
            }
        )
        }
    }

    private func setupPersistentHostingView() {
        guard let button = statusItem.button else { return }

        let rootView = AnyView(StatusBarContentView(displayState: displayState).allowsHitTesting(false))
        let hosting = StatusItemHostingView(rootView: rootView)
        statusHosting = hosting

        button.subviews.forEach { $0.removeFromSuperview() }
        button.title = ""
        button.image = nil
        button.setAccessibilityLabel("Aidente")
        button.setAccessibilityIdentifier("AidenteStatusItem")
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor, constant: 1),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: BatteryIndicatorLayout.statusInset),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -BatteryIndicatorLayout.statusInset),
        ])
    }

    private func startTransitionObservation() {
        transitionObserver = ImmediateStateObserver(read: { [weak self] in
            guard let model = self?.viewModel else { return }
            _ = model.adapterConnected; _ = model.chargingMode; _ = model.displayPercentage
            _ = model.isLowPowerModeEnabled; _ = model.calibrationActive
            _ = model.heatProtectionActive; _ = model.sailingActive; _ = model.chargeLimitOverrideActive
        }, changed: { [weak self] in
            guard let self else { return }
            self.displayState.snapshot = MenuBarSnapshot(viewModel: self.viewModel)
            self.updateStatusItemLength()
            self.panelLogger.notice("STATUS_TRANSITION adapter=\(self.viewModel.adapterConnected, privacy: .public)")
        })
        transitionObserver?.start()
    }

    private func startDisplayObservation() {
        displayObservation = Task { [weak self] in
            for await _ in Defaults.updates(
                [.showDockIcon, .menuBarIconStyle, .menuBarMetrics, .menuBarHiddenMetricIcons, .menuBarItemSpacing,
                 .activeStatusItemsOnly, .menuBarUpdateInterval, .menuBarLowPowerColor, .appLanguage,
                 .showBatteryStateInStatusIcon, .menuBarReadoutStyle,
                 .batteryPercentageDisplayLocation, .chargingIndicatorStyle, .menuBarMainIconPosition], initial: true
            ) {
                guard let self else { return }
                self.powerWidthObservation?.cancel()
                self.powerWidthObservation = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self else { return }
                        self.displayState.snapshot = MenuBarSnapshot(viewModel: self.viewModel)
                        await Task.yield()
                        self.updateStatusItemLength()
                        // Read-only sampling: never enables or repairs charging control.
                        self.viewModel.requestMenuBarSample()
                        let seconds = max(2, min(20, Defaults[.menuBarUpdateInterval]))
                        try? await Task.sleep(for: .seconds(seconds))
                    }
                }
            }
        }
    }

    private func updateStatusItemLength() {
        let hasIcon = Defaults[.menuBarIconStyle] != .hidden || Defaults[.batteryPercentageDisplayLocation] != .hidden
        let hasMetrics = !MenuBarMetric.visible(from: Defaults[.menuBarMetrics], activeOnly: Defaults[.activeStatusItemsOnly], active: displayState.snapshot.activeMetrics).isEmpty
        let hasLegacyPower = Defaults[.menuBarReadoutStyle] != .batteryPercentage
        statusItem.isVisible = hasIcon || hasMetrics || hasLegacyPower
        if !AidenteRuntime.isUIPreview {
            let policy: NSApplication.ActivationPolicy = Defaults[.showDockIcon] || !statusItem.isVisible ? .regular : .accessory
            if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
            if !statusItem.isVisible && !Defaults[.popoverShowOnLaunch] { Defaults[.popoverShowOnLaunch] = true }
        }
        guard statusItem.isVisible, let hosting = statusHosting else { return }
        hosting.invalidateIntrinsicContentSize()
        hosting.layoutSubtreeIfNeeded()
        statusItem.length = max(24, ceil(hosting.fittingSize.width) + BatteryIndicatorLayout.statusInset * 2)
        statusItem.button?.toolTip = "Aidente · \(displayState.snapshot.percentage)%"
    }

    @objc private func openMenuBarSettings() {
        dismissMenu()
        settingsWindowController.showSettings(tab: .menuBar)
    }

    @objc private func openDashboard() { showDashboardWindow() }
    @objc private func quitFromQuickMenu() { viewModel.quit() }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            switch Defaults[.menuBarRightClick] {
            case .popover: break
            case .none: return
            case .toggleCharging:
                if viewModel.manageChargingEnabled && !AidenteRuntime.isUIPreview { viewModel.toggleManualPause() }
                return
            case .toggleLowPower:
                let service = EnergyModeService.shared
                service.chooseLowPowerPreset(service.readings.values.contains { $0.mode == .low } ? 0 : 1)
                return
            case .dashboard:
                settingsWindowController.showSettings(tab: .overview)
                return
            case .settings:
                openMenuBarSettings()
                return
            case .contextMenu:
                let menu = NSMenu()
                for (title, action) in [
                    (AidenteL10n.t("仪表盘", "Dashboard"), #selector(openDashboard)),
                    (AidenteL10n.t("菜单栏设置", "Menu Bar Settings"), #selector(openMenuBarSettings)),
                    (AidenteL10n.t("退出 Aidente", "Quit Aidente"), #selector(quitFromQuickMenu))
                ] {
                    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                    item.target = self
                    menu.addItem(item)
                }
                statusItem.menu = menu
                sender.performClick(nil)
                statusItem.menu = nil
                return
            }
        }

        panelLogger.notice("STATUS_CLICK existing=\(self.popoverPanel != nil) visible=\(self.popoverPanel?.isVisible ?? false) activeSpace=\(self.popoverPanel?.isOnActiveSpace ?? false) anchor=\(sender.window != nil)")
        if let panel = popoverPanel, panel.isVisible, panel.isOnActiveSpace {
            dismissMenu()
            return
        }

        if let dashboardWindow, dashboardWindow.isVisible {
            dashboardWindow.close()
            Task { [weak self, weak sender] in
                await Task.yield()
                guard let self, let sender else { return }
                self.presentPopover(relativeTo: sender)
            }
            return
        }

        presentPopover(relativeTo: sender)
    }

    private func presentPopover(relativeTo sender: NSStatusBarButton) {
        // Hidden or orphaned panels must not block every later click.
        dismissMenu()
        let anchorWindow = sender.window
        panelLogger.notice("PANEL_CREATE anchor=\(anchorWindow != nil)")
        let hosting = NSHostingController(rootView: makeDashboardRootView())
        // The nonactivating flag must be present at creation. Activating a regular app
        // here would leave another application's full-screen Space to show its windows.
        let panel = StatusPopoverPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = hosting
        panel.title = AidenteL10n.t("Aidente 菜单", "Aidente Menu")
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.dismissMenu() }
        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 15
        hosting.view.layer?.masksToBounds = true
        let size = NSSize(width: 402, height: PopoverLayout.height(widgets: Defaults[.popoverWidgets], editing: PopoverEditorState.shared.isEditing, calibrating: viewModel.calibrationActive))
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? anchorWindow?.screen ?? NSScreen.main
        let bounds = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fallback = NSRect(x: bounds.maxX - 36, y: bounds.maxY - NSStatusBar.system.thickness, width: 28, height: NSStatusBar.system.thickness)
        let candidate = anchorWindow?.convertToScreen(sender.convert(sender.bounds, to: nil))
        let anchor = candidate.flatMap { $0.width > 0 && $0.intersects(bounds) ? $0 : nil } ?? fallback
        let x = min(max(anchor.maxX - size.width, bounds.minX + 8), bounds.maxX - size.width - 8)
        let top = min(anchor.minY - 6, bounds.maxY - 24)
        panel.setFrame(NSRect(x: x, y: max(bounds.minY + 8, top - size.height), width: size.width, height: size.height), display: false)
        popoverPanel = panel
        viewModel.menuWillOpen()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let self, let panel, self.popoverPanel === panel else { return }
                self.dismissMenu()
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            MainActor.assumeIsolated {
                if let window = event.window, window !== panel,
                   window.sheetParent !== panel, window.parent !== panel,
                   panel?.attachedSheet == nil,
                   window !== self?.statusItem.button?.window, window.level < .popUpMenu {
                    self?.dismissMenu()
                }
            }
            return event
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        panelLogger.notice("PANEL_SHOWN visible=\(panel.isVisible) activeSpace=\(panel.isOnActiveSpace) key=\(panel.isKeyWindow)")
    }

    private func dismissMenu() {
        guard let panel = popoverPanel else { return }
        // Clear synchronously; a delayed close notification cannot leave a stale guard.
        popoverPanel = nil
        removeMenuMonitors()
        viewModel.menuDidClose()
        panel.close()
        panelLogger.notice("PANEL_CLOSED")
    }
    private func removeMenuMonitors() {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor); outsideClickMonitor = nil }
        if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor); localClickMonitor = nil }
    }

    func showDashboardWindow() {
        dismissMenu()
        settingsWindowController.showSettings(tab: .overview)
    }

    private func presentDashboardWindow() {
        guard dashboardWindow == nil else { return }

        let hostingController = NSHostingController(rootView: makeDashboardRootView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = AidenteL10n.t("Aidente 主菜单", "Aidente Dashboard")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 402, height: PopoverLayout.height(widgets: Defaults[.popoverWidgets], editing: PopoverEditorState.shared.isEditing, calibrating: viewModel.calibrationActive)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 15
        hostingController.view.layer?.masksToBounds = true

        dashboardWindow = window
        viewModel.menuWillOpen()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func showPopoverForPreview() {
        guard let button = statusItem.button else { return }
        presentPopover(relativeTo: button)
    }

    func showWindowForPreview() {
        guard previewWindow == nil else { return }

        let hostingController = NSHostingController(rootView: makeDashboardRootView())
        let panel = AidentePreviewPanel(contentViewController: hostingController)
        panel.styleMask = [.borderless]
        panel.setContentSize(NSSize(width: 402, height: PopoverLayout.height(widgets: Defaults[.popoverWidgets], editing: PopoverEditorState.shared.isEditing, calibrating: viewModel.calibrationActive)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        if let screen = NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.midX - 204,
                    y: visibleFrame.midY - 360
                )
            )
        } else {
            panel.center()
        }

        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 15
        hostingController.view.layer?.masksToBounds = true

        previewWindow = panel
        viewModel.menuWillOpen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let closedWindow = notification.object as? NSWindow else { return }
            if closedWindow === popoverPanel {
                popoverPanel = nil
                removeMenuMonitors()
                viewModel.menuDidClose()
            } else if closedWindow === dashboardWindow {
                dashboardWindow = nil
                viewModel.menuDidClose()
            } else if closedWindow === previewWindow {
                previewWindow = nil
                viewModel.menuDidClose()
            }
        }
    }

    deinit {
        displayObservation?.cancel()
        powerWidthObservation?.cancel()
    }
}

private final class AidentePreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct StatusBarContentView: View {
    let displayState: MenuBarDisplayState
    @Default(.batteryPercentageDisplayLocation) private var percentageLocation
    @Default(.menuBarReadoutStyle) private var readoutStyle
    @Default(.showBatteryStateInStatusIcon) private var showState
    @Default(.menuBarIconStyle) private var iconStyle
    @Default(.menuBarMetrics) private var metricIDs
    @Default(.menuBarMainIconPosition) private var mainPosition
    @Default(.menuBarHiddenMetricIcons) private var hiddenMetricIcons
    @Default(.menuBarItemSpacing) private var spacing
    @Default(.activeStatusItemsOnly) private var activeStatusOnly
    @Default(.menuBarLowPowerColor) private var lowPowerColor

    var body: some View {
        let snapshot = displayState.snapshot
        let visible = Set(MenuBarMetric.visible(from: metricIDs, activeOnly: activeStatusOnly, active: snapshot.activeMetrics).map(\.id))
        let showIcon = iconStyle != .hidden || percentageLocation != .hidden
        let items = MenuItemOrdering.layout(metrics: MenuBarMetric.selected(from: metricIDs).map(\.id), mainPosition: mainPosition, includeMain: showIcon || readoutStyle != .batteryPercentage)
        HStack(spacing: CGFloat(max(0, min(20, spacing)))) {
            ForEach(items, id: \.self) { item in
                if item == MenuItemOrdering.main {
                    HStack(spacing: 3) {
                        if showIcon {
                            BatteryIndicatorView(batteryLevel: snapshot.percentage, chargingMode: snapshot.chargingMode,
                                isLowPowerModeEnabled: lowPowerColor && snapshot.lowPower,
                                percentageDisplayLocation: readoutStyle == .systemPower ? .hidden : readoutStyle == .batteryAndPower ? .insideIcon : percentageLocation,
                                showState: showState, style: iconStyle, adapterConnected: snapshot.adapterConnected)
                        }
                        if readoutStyle != .batteryPercentage { Text(snapshot.power).font(.system(size: 10.5, weight: .semibold)).monospacedDigit() }
                    }
                } else if let metric = MenuBarMetric(rawValue: item), visible.contains(item) {
                    Group {
                        if hiddenMetricIcons.contains(metric.id) { Text(snapshot.values[metric.id] ?? "—") }
                        else { Label(snapshot.values[metric.id] ?? "—", systemImage: metric.icon) }
                    }.font(.system(size: 11)).monospacedDigit().help("\(metric.group) · \(metric.title)")
                }
            }
        }
        .fixedSize().lineLimit(1)
        .help(AidenteL10n.t("电量 \(snapshot.percentage)% · 系统功率 \(snapshot.power)",
                            "Battery \(snapshot.percentage)% · System power \(snapshot.power)"))
    }
}

/// SwiftUI content is display-only; the surrounding NSStatusBarButton receives every click.
private final class StatusItemHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class StatusPopoverPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
