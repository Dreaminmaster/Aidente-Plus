import Foundation
import AidenteShared

/// Called only on the helper's serialized queue after the existing pinned XPC checks.
final class EnergyModeController {
    private let defaults: UserDefaults
    private let runner: (([String]) throws -> String)?
    private let snapshotKey = "energyModesBeforeAidente"
    init(defaults: UserDefaults, runner: (([String]) throws -> String)? = nil) { self.defaults = defaults; self.runner = runner }
    private func run(_ arguments: [String]) throws -> String {
        if let runner { return try runner(arguments) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); timeout.cancel()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AidenteEnergy", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: output, as: UTF8.self)])
        }
        return String(decoding: output, as: UTF8.self)
    }
    func set(mode: EnergyMode, source: EnergySource) throws {
        let readings = EnergyModePolicy.parse(try run(["-g", "custom"]))
        guard let reading = readings[source] else { throw CocoaError(.featureUnsupported) }
        let arguments = try EnergyModePolicy.arguments(mode: mode, source: source, reading: reading)
        if reading.mode == mode { return }
        var saved = try defaults.data(forKey: snapshotKey).map { try JSONDecoder().decode([String: EnergyModeReading].self, from: $0) } ?? [:]
        if saved[source.rawValue] == nil {
            saved[source.rawValue] = reading
            defaults.set(try JSONEncoder().encode(saved), forKey: snapshotKey)
            guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
        }
        do {
            _ = try run(arguments)
            guard EnergyModePolicy.parse(try run(["-g", "custom"]))[source]?.mode == mode else { throw CocoaError(.fileReadCorruptFile) }
        } catch {
            // Preserve the original snapshot until readback confirms restoration.
            _ = try? run([source.argument, reading.key, String(reading.value)])
            throw error
        }
    }
    func restore() throws {
        guard let data = defaults.data(forKey: snapshotKey) else { return }
        let saved = try JSONDecoder().decode([String: EnergyModeReading].self, from: data)
        for (name, reading) in saved {
            guard let source = EnergySource(rawValue: name), let mode = reading.mode else { throw CocoaError(.coderReadCorrupt) }
            _ = try run(EnergyModePolicy.arguments(mode: mode, source: source, reading: reading))
            guard EnergyModePolicy.parse(try run(["-g", "custom"]))[source]?.mode == mode else { throw CocoaError(.fileReadCorruptFile) }
        }
        defaults.removeObject(forKey: snapshotKey)
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    }
}
