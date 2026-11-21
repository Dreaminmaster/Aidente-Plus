import Foundation
import ServiceManagement
import os.log

class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private let logger = Logger(
        subsystem: "com.aidente.app",
        category: "LaunchAtLoginService"
    )

    private init() {}

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try apply(enabled)
        } catch {
            logger.error(
                "Failed to \(enabled ? "enable" : "disable") launch at login: \(error)"
            )
        }
    }

    func apply(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        switch (enabled, service.status) {
        case (true, .enabled), (true, .requiresApproval),
             (false, .notRegistered), (false, .notFound):
            return
        case (true, _):
            try service.register()
        case (false, _):
            try service.unregister()
        }
    }

    var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    func unregisterForUninstall() async throws {
        let service = SMAppService.mainApp
        if service.status != .notRegistered && service.status != .notFound {
            try await service.unregister()
        }
        guard service.status == .notRegistered || service.status == .notFound else {
            throw NSError(domain: "com.aidente.app.uninstall", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Login-item removal was not confirmed."])
        }
    }

    var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }
}
