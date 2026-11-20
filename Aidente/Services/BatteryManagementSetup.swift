import AppKit
import Defaults
import Observation
import SwiftUI

@MainActor @Observable final class BatteryManagementSetup: NSObject, NSWindowDelegate {
    static let shared=BatteryManagementSetup()
    private(set) var enabling=false
    var onEnabled:(()->Void)?
    private var welcome:NSWindow?
    var ready:Bool { Defaults[.manageCharging] && ChargingHelperManager.shared.isInstalled && ChargingHelperManager.shared.registrationError == nil }

    /// Only a user action may enter this path; startup and LED browsing never install services.
    func enable(onAuthorized:()->Void = {}) async throws -> Bool {
        guard !enabling else { return false }
        enabling=true;defer { enabling=false }
        let helper=ChargingHelperManager.shared
        helper.refreshStatus()
        let needsRepair=helper.registrationError != nil
        if !helper.isInstalled || needsRepair || AidenteRuntime.isUIPreview {
            let alert=NSAlert()
            alert.messageText=AidenteL10n.t("启用电池管理","Enable Battery Management")
            alert.informativeText=AidenteL10n.t("查看电池无需授权。限充和 MagSafe 指示灯共用一个后台服务，需要 macOS 管理员授权安装。成功后才启用；取消则保持关闭。密码只在 macOS 系统窗口输入。","Battery viewing needs no authorization. Charge limits and MagSafe LEDs share one helper, installed with macOS administrator authorization. Management is enabled only after success. Cancel leaves it off. Enter your password only in the macOS dialog.")
            alert.addButton(withTitle:AidenteL10n.t("继续启用","Continue"));alert.addButton(withTitle:AidenteL10n.t("取消","Cancel"))
            let response:NSApplication.ModalResponse
            if let window=NSApp.keyWindow {
                response=await withCheckedContinuation { continuation in alert.beginSheetModal(for:window) { continuation.resume(returning:$0) } }
            } else { response=alert.runModal() }
            guard response == .alertFirstButtonReturn else { return false }
        }
        guard !AidenteRuntime.isUIPreview else { return false }
        do {
            if needsRepair { try await helper.repair() } else { try await helper.enableForUser() }
            onAuthorized()
            Defaults[.manageCharging]=true
            Defaults[.didCompleteBatterySetup]=true
            onEnabled?()
            return true
        } catch {
            if (error as NSError).code == NSUserCancelledError || error.localizedDescription.contains("(-128)") {
                helper.resumeConsoleSession()
                return false
            }
            throw error
        }
    }

    func showWelcomeIfNeeded() {
        guard !Defaults[.didCompleteBatterySetup] || (AidenteRuntime.isUIPreview && CommandLine.arguments.contains("--setup-preview")) else { return }
        let domain=AidenteRuntime.preferenceStore.persistentDomain(forName:"com.aidente.app") ?? [:]
        if !AidenteRuntime.isUIPreview && ["manageCharging","chargeLimit","menuBarIconStyle"].contains(where:{ domain[$0] != nil }) {
            Defaults[.didCompleteBatterySetup]=true;return
        }
        guard !AidenteRuntime.isUIPreview || CommandLine.arguments.contains("--setup-preview") else { return }
        showGuide()
    }

    func showGuide() {
        if let welcome {
            welcome.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = AidenteAppearanceRoot {
            BatteryUsageGuide(onClose: { [weak self] in self?.welcome?.close() })
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = AidenteL10n.t("Aidente 使用引导", "Aidente Guide")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)
        welcome = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Defaults[.didCompleteBatterySetup] = true
        welcome = nil
    }
}
