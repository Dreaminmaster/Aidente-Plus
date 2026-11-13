import Foundation

/// Exact allowlist for the current account. No recursive scan of Library, Downloads or other homes.
public struct UninstallPlan {
    public static let preferenceDomains = ["com.aidente.app", "com.iadente.app", "com.aidente.app.preview", "com.aidente.app.control"]
    public let home: URL
    public init(home: URL) { self.home = home.standardizedFileURL.resolvingSymlinksInPath() }

    public var userData: [URL] {
        var paths = ["Library/Application Support/Aidente", "Library/Logs/Aidente"]
        for domain in Self.preferenceDomains {
            paths += ["Library/Preferences/\(domain).plist", "Library/Caches/\(domain)",
                      "Library/Saved Application State/\(domain).savedState",
                      "Library/HTTPStorages/\(domain)", "Library/HTTPStorages/\(domain).binarycookies",
                      "Library/WebKit/\(domain)"]
        }
        return paths.map { home.appendingPathComponent($0) }
    }

    public func byHostPreferences(in entries: [URL]) -> [URL] {
        let directory = home.appendingPathComponent("Library/Preferences/ByHost")
        return entries.filter { url in
            guard url.deletingLastPathComponent().standardizedFileURL.path == directory.path else { return false }
            return Self.preferenceDomains.contains { domain in
                let prefix = domain + "."
                let name = url.lastPathComponent
                guard name.hasPrefix(prefix), name.hasSuffix(".plist") else { return false }
                return UUID(uuidString: String(name.dropFirst(prefix.count).dropLast(6))) != nil
            }
        }
    }

    public static func updateBackups(in entries: [URL], application: URL) -> [URL] {
        let parent = application.deletingLastPathComponent().standardizedFileURL
        return entries.filter { url in
            guard url.deletingLastPathComponent().standardizedFileURL.path == parent.path,
                  url.pathExtension == "app" else { return false }
            let name = url.deletingPathExtension().lastPathComponent
            return [".Aidente.backup-", ".Aidente.update-"].contains { prefix in
                name.hasPrefix(prefix) && UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
            }
        }
    }

    public static func diagnosticTemporaryFiles(in entries: [URL], temporaryDirectory: URL) -> [URL] {
        let parent = temporaryDirectory.standardizedFileURL
        return entries.filter { url in
            let prefix = "Aidente-Diagnostics-"
            return url.deletingLastPathComponent().standardizedFileURL.path == parent.path
                && url.lastPathComponent.hasPrefix(prefix)
                && UUID(uuidString: String(url.lastPathComponent.dropFirst(prefix.count))) != nil
        }
    }

    public static func entryExists(_ url: URL, fileManager: FileManager = .default) throws -> Bool {
        do { _ = try fileManager.attributesOfItem(atPath: url.path); return true }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return false }
    }

    /// A symlink at the leaf can be trashed as a link. A symlink in its parents is rejected.
    public func validateUserTarget(_ target: URL, fileManager: FileManager = .default) throws {
        let path = target.standardizedFileURL.path
        guard path.hasPrefix(home.path + "/Library/"), userData.contains(where: { $0.path == target.standardizedFileURL.path })
                || !byHostPreferences(in: [target.standardizedFileURL]).isEmpty else {
            throw CocoaError(.fileWriteNoPermission)
        }
        var parent = target.deletingLastPathComponent().standardizedFileURL
        while parent.path != home.path {
            guard parent.path.hasPrefix(home.path + "/") else { throw CocoaError(.fileWriteNoPermission) }
            if try Self.entryExists(parent, fileManager: fileManager) {
                let metadata = try fileManager.attributesOfItem(atPath: parent.path)
                guard metadata[.type] as? FileAttributeType == .typeDirectory else {
                    throw CocoaError(.fileWriteNoPermission)
                }
            }
            parent.deleteLastPathComponent()
        }
    }
}

public enum UninstallSequence {
    /// Removing the app last keeps the repair UI available on every earlier failure.
    public static func run(removeService: () async throws -> Void,
                           removeLoginItem: () async throws -> Void,
                           removeUserData: () async throws -> Void,
                           trashApplication: () async throws -> Void) async throws {
        try await removeService()
        try await removeLoginItem()
        try await removeUserData()
        try await trashApplication()
    }
}
