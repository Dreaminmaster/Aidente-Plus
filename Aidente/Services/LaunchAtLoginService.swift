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
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error(
                "Failed to \(enabled ? "enable" : "disable") launch at login: \(error)"
            )
        }
    }

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
