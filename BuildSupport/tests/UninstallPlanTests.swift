import AidenteShared
import Foundation

enum FixtureFailure: Error { case fail }

@main struct UninstallPlanTests {
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("aidente-uninstall-test-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let plan = UninstallPlan(home: root)
        var checks = 0
        func check(_ condition: Bool, _ title: String) {
            precondition(condition, title); checks += 1
        }
        check(plan.userData.count == Set(plan.userData).count, "Allowlist has no duplicate paths")
        check(plan.userData.contains(root.appendingPathComponent("Library/Application Support/Aidente")), "History and updater data included")
        check(!plan.userData.contains(where: { $0.path.contains("apphousekitchen") }), "Official AlDente excluded")
        check(!plan.userData.contains(where: { $0.path.contains("Downloads") }), "Downloads excluded")
        for url in plan.userData { try plan.validateUserTarget(url) }
        let byHost = root.appendingPathComponent("Library/Preferences/ByHost")
        let valid = byHost.appendingPathComponent("com.aidente.app.12345678-1234-1234-1234-123456789ABC.plist")
        let invalid = byHost.appendingPathComponent("com.aidente.app.personal-notes.plist")
        let official = byHost.appendingPathComponent("com.apphousekitchen.aldente-pro.12345678-1234-1234-1234-123456789ABC.plist")
        check(plan.byHostPreferences(in: [valid, invalid, official]) == [valid], "ByHost matches only exact domain plus UUID")
        try plan.validateUserTarget(valid)
        for candidate in [invalid, official, root.appendingPathComponent("Downloads/Aidente.zip"), URL(fileURLWithPath: "/Library/Preferences/com.aidente.app.plist")] {
            do { try plan.validateUserTarget(candidate); preconditionFailure("Unsafe target accepted") }
            catch { checks += 1 }
        }
        let support = root.appendingPathComponent("Library/Application Support")
        let outside = root.appendingPathComponent("Outside")
        try manager.createDirectory(at: support.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: support, withDestinationURL: outside)
        do { try plan.validateUserTarget(support.appendingPathComponent("Aidente")); preconditionFailure("Redirected parent accepted") }
        catch { checks += 1 }
        try manager.removeItem(at: support)
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        let leaf = support.appendingPathComponent("Aidente")
        try manager.createSymbolicLink(at: leaf, withDestinationURL: outside)
        try plan.validateUserTarget(leaf)
        check(manager.fileExists(atPath: outside.path), "Leaf-link validation never touches destination")

        check(!(try UninstallPlan.entryExists(root.appendingPathComponent("missing"))), "Missing entries are skipped")
        try manager.removeItem(at: leaf)
        try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: support.path)
        do {
            _ = try UninstallPlan.entryExists(support.appendingPathComponent("hidden"))
            preconditionFailure("Unreadable parents must not be treated as missing files")
        } catch { checks += 1 }
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: support.path)

        let app = URL(fileURLWithPath: "/Applications/Aidente.app")
        let backup = URL(fileURLWithPath: "/Applications/.Aidente.backup-12345678-1234-1234-1234-123456789ABC.app")
        let staged = URL(fileURLWithPath: "/Applications/.Aidente.update-12345678-1234-1234-1234-123456789ABC.app")
        check(UninstallPlan.updateBackups(in: [app, backup, staged, URL(fileURLWithPath: "/Applications/AlDente.app")], application: app) == [backup, staged], "Only UUID-tagged Aidente update backups selected")
        check(UninstallPlan.updateBackups(in: [URL(fileURLWithPath: "/Applications/.Aidente.backup-personal.app")], application: app).isEmpty, "Similar personal filenames excluded")
        let temporary = root.appendingPathComponent("Temporary")
        let diagnostic = temporary.appendingPathComponent("Aidente-Diagnostics-12345678-1234-1234-1234-123456789ABC")
        check(UninstallPlan.diagnosticTemporaryFiles(in: [diagnostic, temporary.appendingPathComponent("Aidente-Diagnostics-personal.zip")], temporaryDirectory: temporary) == [diagnostic], "Only UUID-tagged temporary diagnostics selected")

        for failureAt in 0...4 {
            var events: [Int] = []
            func step(_ index: Int) throws {
                events.append(index)
                if index == failureAt { throw FixtureFailure.fail }
            }
            do {
                try await UninstallSequence.run(removeService: { try step(0) }, removeLoginItem: { try step(1) },
                    removeUserData: { try step(2) }, trashApplication: { try step(3) })
                check(failureAt == 4, "Only full success completes")
            } catch { check(failureAt < 4, "Failures surface") }
            let expected = failureAt == 4 ? [0, 1, 2, 3] : Array(0...failureAt)
            check(events == expected, "Failure stops all later cleanup; application is always last")
        }
        print("PASS: \(checks) uninstall path and sequence checks (temporary fixtures only)")
    }
}
