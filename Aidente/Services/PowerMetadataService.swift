import Defaults
import Foundation
import Observation

@MainActor @Observable final class PowerMetadataService {
    static let shared = PowerMetadataService()
    private(set) var systemLastFullCharge: Date?
    var readSystemFullCharge: (() async throws -> Double)?
    private(set) var condition = "—"
    private(set) var batteryFirmware = "—"
    private var task: Task<Void, Never>?
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let values = await Task.detached(priority: .utility) { Self.read() }.value
                guard !Task.isCancelled, !CompleteUninstaller.shared.isRunning else { return }
                if let values { self?.condition = values.0; self?.batteryFirmware = values.1 }
                await self?.refreshSystemFullCharge()
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
    func refreshSystemFullCharge() async {
        guard !AidenteRuntime.isUIPreview, !CompleteUninstaller.shared.isRunning,
              let read = readSystemFullCharge, let timestamp = try? await read(),
              timestamp > 978307200, timestamp <= Date().timeIntervalSince1970 + 300 else { return }
        systemLastFullCharge = Date(timeIntervalSince1970: timestamp)
    }
    nonisolated private static func read() -> (String, String)? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPPowerDataType", "-detailLevel", "basic"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 5)
        timer.setEventHandler { if process.isRunning { process.terminate() } }; timer.resume()
        defer { timer.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 1_048_576,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["SPPowerDataType"] as? [[String: Any]],
              let battery = items.first(where: { $0["sppower_battery_health_info"] != nil }) else { return nil }
        let health = battery["sppower_battery_health_info"] as? [String: Any]
        let model = battery["sppower_battery_model_info"] as? [String: Any]
        // Whitelist only these two values. Never retain, log or export the report,
        // which also contains identifiers unrelated to the user-facing feature.
        return (health?["sppower_battery_health"] as? String ?? "—", model?["sppower_battery_firmware_version"] as? String ?? "—")
    }
}
