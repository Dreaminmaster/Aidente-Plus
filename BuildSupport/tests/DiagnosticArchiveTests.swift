import Foundation
import AidenteShared

@main struct DiagnosticArchiveTests {
    static func main() throws {
        let suite = "com.aidente.tests.diagnostic-archives." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Aidente-Archive-Fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("Fixture诊断.zip")
        try Data("test fixture, contains no user data".utf8).write(to: archive)
        let other = root.appendingPathComponent("untracked.zip")
        try Data("untracked".utf8).write(to: other)
        let store = DiagnosticArchiveStore(defaults: defaults)
        var count = 0
        func check(_ value: Bool, _ label: String) { precondition(value, label); count += 1 }
        check(store.urls.isEmpty, "New history is empty")
        try store.register(archive); try store.register(archive)
        check(store.urls == [archive], "Repeated export does not duplicate the row")
        let restored = DiagnosticArchiveStore(defaults: defaults)
        check(restored.urls == [archive], "Restart preserves the saved location")
        do { _ = try restored.trash(other); preconditionFailure("Unregistered file was accepted") }
        catch { check(FileManager.default.fileExists(atPath: other.path), "Unregistered file cannot be trashed") }
        restored.forget(archive)
        check(FileManager.default.fileExists(atPath: archive.path), "Removing a record leaves the ZIP intact")
        try restored.register(archive)
        let trashed = try restored.trash(archive)
        check(!FileManager.default.fileExists(atPath: archive.path), "Trash removes original path")
        check(restored.urls.isEmpty, "Successful trash removes the history record")
        guard let trashed else { preconditionFailure("Trash destination unavailable") }
        check(FileManager.default.fileExists(atPath: trashed.path), "Trash is recoverable")
        try FileManager.default.moveItem(at: trashed, to: archive)
        check(FileManager.default.fileExists(atPath: archive.path), "Fixture can be restored from Trash")
        let folder = root.appendingPathComponent("directory.zip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do { try restored.register(folder); preconditionFailure("Directory accepted") }
        catch { check(restored.urls.isEmpty, "A .zip directory is not an archive file") }
        let link = root.appendingPathComponent("symlink.zip")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        do { try restored.register(link); preconditionFailure("Symlink accepted") }
        catch { check(FileManager.default.fileExists(atPath: other.path), "A symlink cannot register an unrelated target") }
        for i in 0..<22 {
            let file = root.appendingPathComponent("\(i).zip"); try Data().write(to: file); try restored.register(file)
        }
        check(restored.urls.count == 20, "History remains bounded")
        check(FileManager.default.fileExists(atPath: root.appendingPathComponent("0.zip").path), "History eviction never removes files")
        print("PASS: \(count) diagnostic history, Trash recovery and file-boundary checks")
    }
}
