import AidenteShared
import AppKit
import Observation

@MainActor @Observable final class EnergyModeService {
    static let shared = EnergyModeService()
    var activeSource: EnergySource = .battery
    var isNonAutomaticActive: Bool { readings[activeSource]?.mode.map { $0 != .automatic } ?? false }
    private(set) var readings: [EnergySource: EnergyModeReading] = [:]
    private(set) var isBusy = false
    private(set) var error: String?
    private var apply: ((EnergyMode, EnergySource) async throws -> Void)?
    func configure(_ action: @escaping (EnergyMode, EnergySource) async throws -> Void) { apply = action; refresh() }
    func refresh() { Task { await refreshNow() } }
    func refreshNow() async {
            let text = await Task.detached {
                let process = Process(); let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); process.arguments = ["-g", "custom"]
                process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return "" }
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : ""
            }.value
            self.readings = EnergyModePolicy.parse(text)
    }
    func set(_ mode: EnergyMode, source: EnergySource) async throws {
        guard !isBusy, !CompleteUninstaller.shared.isRunning else { throw XPCError.commandFailed("An operation is in progress") }
        guard let reading = readings[source], let apply else { throw XPCError.commandFailed("Energy control is not available") }
        _ = try EnergyModePolicy.arguments(mode: mode, source: source, reading: reading)
        guard !AidenteRuntime.isUIPreview else { return }
        isBusy = true; defer { isBusy = false; refresh() }
        do { try await apply(mode, source); error = nil }
        catch { self.error = error.localizedDescription; throw error }
    }
    var lowPowerPreset: Int {
        guard let battery = readings[.battery]?.mode, let adapter = readings[.adapter]?.mode,
              battery != .high, adapter != .high else { return 4 }
        return battery == .low ? (adapter == .low ? 1 : 2) : (adapter == .low ? 3 : 0)
    }
    func chooseLowPowerPreset(_ preset: Int) {
        guard (0...3).contains(preset), !isBusy, !AidenteRuntime.isUIPreview, !CompleteUninstaller.shared.isRunning else { return }
        Task {
            isBusy = true
            defer { isBusy = false; refresh() }
            let before = readings
            let desired: [EnergySource: EnergyMode] = [.battery: preset == 1 || preset == 2 ? .low : .automatic,
                .adapter: preset == 1 || preset == 3 ? .low : .automatic]
            var changed: [EnergySource] = []
            do {
                guard let apply else { throw XPCError.helperUnavailable }
                for source in EnergySource.allCases {
                    guard let reading = before[source], let mode = desired[source] else { throw XPCError.helperUnavailable }
                    _ = try EnergyModePolicy.arguments(mode: mode, source: source, reading: reading)
                }
                for source in EnergySource.allCases { try await apply(desired[source]!, source); changed.append(source) }
                error = nil
            } catch {
                if let apply { for source in changed.reversed() { if let original = before[source]?.mode { try? await apply(original, source) } } }
                self.error = error.localizedDescription
            }
        }
    }
    func choose(_ mode: EnergyMode, source: EnergySource) { Task { do { try await set(mode, source: source) } catch { self.error = error.localizedDescription } } }
}
