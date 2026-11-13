import AidenteShared
import Defaults
import Foundation
import OSLog

@MainActor final class ApplicationActions {
    static let shared = ApplicationActions()
    private let logger = Logger(subsystem: "com.aidente.app", category: "Automation")
    private var handler: ((String, Int?) async throws -> Void)?
    private var query: ((String) -> String)?
    func configure(handler: @escaping (String, Int?) async throws -> Void, query: @escaping (String) -> String) {
        self.handler = handler; self.query = query
    }
    func waitUntilReady() async throws {
        for _ in 0..<250 {
            if handler != nil { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw XPCError.commandFailed("Aidente is not ready")
    }
    func execute(_ command: String, value: Int? = nil) async throws {
        try await waitUntilReady()
        logger.notice("AUTOMATION_COMMAND \(command, privacy: .public)")
        guard ConsoleSessionPolicy.currentUserIsActive else { throw XPCError.commandFailed("当前账户不在活动控制台") }
        guard !CompleteUninstaller.shared.isRunning else { throw XPCError.commandFailed("Uninstall is in progress") }
        guard !AidenteRuntime.isUIPreview else { return }
        try await handler?(command, value)
    }
    func read(_ name: String) async throws -> String {
        try await waitUntilReady()
        logger.notice("AUTOMATION_QUERY \(name, privacy: .public)")
        let value = query?(name) ?? ""
        if name == "temperature", (Double(value) ?? 0) <= 0 { throw XPCError.commandFailed("Battery temperature is unavailable") }
        return value
    }
    func energy(_ mode: EnergyMode) async throws {
        await EnergyModeService.shared.refreshNow()
        let before = EnergyModeService.shared.readings
        for source in EnergySource.allCases {
            guard let reading = before[source] else { throw XPCError.helperUnavailable }
            _ = try EnergyModePolicy.arguments(mode: mode, source: source, reading: reading)
        }
        var changed: [EnergySource] = []
        do {
            for source in EnergySource.allCases { try await EnergyModeService.shared.set(mode, source: source); changed.append(source) }
        } catch {
            for source in changed.reversed() {
                if let original = before[source]?.mode { try? await EnergyModeService.shared.set(original, source: source) }
            }
            throw error
        }
    }
}
