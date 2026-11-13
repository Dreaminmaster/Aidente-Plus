import AidenteShared
import Foundation

@MainActor final class DashboardTrendStore {
    static let shared = DashboardTrendStore()
    private var writeTask: Task<Void, Never>?
    private var lastWrite = Date.distantPast
    private var suspended = false
    private let file = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("Aidente", isDirectory: true).appendingPathComponent("dashboard-trends.json")
    func load() -> [DashboardReading] {
        guard (!AidenteRuntime.isUIPreview || CommandLine.arguments.contains("--preview-real-history")),
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
              let data = try? Data(contentsOf: file),
              let readings = try? JSONDecoder().decode([DashboardReading].self, from: data) else { return [] }
        return DashboardReading.retained(readings, now: Date())
    }
    func persist(_ samples: [DashboardReading]) {
        guard !AidenteRuntime.isUIPreview, !suspended, !CompleteUninstaller.shared.isRunning,
              Date().timeIntervalSince(lastWrite) >= 60, writeTask == nil else { return }
        lastWrite = Date()
        let samples = DashboardReading.retained(samples, now: Date()), file = file
        writeTask = Task { [weak self] in
            await Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(samples) else { return }
                do {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: file, options: .atomic)
                } catch { /* Retain in-memory samples if the disk is unavailable. */ }
            }.value
            self?.writeTask = nil
        }
    }
    func prepareForUninstall() async { suspended = true; await writeTask?.value; writeTask = nil }
    func resumeAfterFailure() { suspended = false; lastWrite = .distantPast }
}
