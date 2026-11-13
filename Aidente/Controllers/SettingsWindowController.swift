import AppKit
import Defaults
import SwiftUI
import smc_power

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    private var layoutName = ""
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
        updateService: UpdateService
    ) {
        self.viewModel = viewModel
        self.capabilities = capabilities
        self.chargeManager = chargeManager
        self.diagnosticCenter = diagnosticCenter
        self.updateService = updateService
        super.init()
    }

    func showSettings(tab: SettingsTab = .general) {
        navigation.tab = tab
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            viewModel: viewModel,
            capabilities: capabilities,
            chargeManager: chargeManager,
            diagnosticCenter: diagnosticCenter,
            updateService: updateService,
            navigation: navigation,
            onSelection: { _ in }
        )
        let hostingController = NSHostingController(rootView: AidenteAppearanceRoot { settingsView })

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = AidenteL10n.t("Aidente 设置", "Aidente Settings")
        newWindow.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView,
        ]
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.contentView?.wantsLayer = true
        newWindow.contentView?.layer?.cornerRadius = 14
        newWindow.contentView?.layer?.masksToBounds = true
        newWindow.setContentSize(NSSize(width: 1100, height: 700))
        newWindow.minSize = NSSize(width: 700, height: 620)
        layoutName = savedName(for: tab)
        if Defaults[.restoreWindowLayout] {
            if !restoreFrame(newWindow, name: layoutName) { newWindow.center() }
        } else { newWindow.center() }

        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    private func savedName(for tab: SettingsTab) -> String {
        // Every page shares one frame. Changing a tab must never move its sidebar.
        (AidenteRuntime.isUIPreview ? "Preview" : "Aidente") + "MainSettings"
    }
    private func persistFrame() {
        guard let window, !layoutName.isEmpty, Defaults[.restoreWindowLayout], !CompleteUninstaller.shared.isRunning else { return }
        AidenteRuntime.preferenceStore.set(NSStringFromRect(window.frame), forKey: "windowLayout." + layoutName)
    }
    private func restoreFrame(_ window: NSWindow, name: String) -> Bool {
        guard let value = AidenteRuntime.preferenceStore.string(forKey: "windowLayout." + name) else { return false }
        var frame = NSRectFromString(value)
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite), frame.width >= 700, frame.height >= 620,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main else { return false }
        frame.size.width = min(frame.width, screen.visibleFrame.width)
        frame.size.height = min(frame.height, screen.visibleFrame.height)
        frame.origin.x = max(screen.visibleFrame.minX, min(frame.minX, screen.visibleFrame.maxX - frame.width))
        frame.origin.y = max(screen.visibleFrame.minY, min(frame.minY, screen.visibleFrame.maxY - frame.height))
        window.setFrame(frame, display: true)
        return true
    }
    nonisolated func windowDidMove(_ notification: Notification) { MainActor.assumeIsolated { persistFrame() } }
    nonisolated func windowDidResize(_ notification: Notification) { MainActor.assumeIsolated { persistFrame() } }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            persistFrame()
            window = nil
        }
    }
}
