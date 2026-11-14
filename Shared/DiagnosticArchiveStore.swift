import Foundation

/// Only explicitly exported or user-selected ZIPs enter the local history.
/// Removing a record never removes a file. Trash uses the macOS recovery flow.
public final class DiagnosticArchiveStore {
    private let defaults: UserDefaults
    private let key: String
    public private(set) var urls: [URL]
    public init(defaults: UserDefaults, key: String = "diagnosticExportHistory") {
        self.defaults = defaults; self.key = key
        var seen = Set<String>()
        urls = (defaults.stringArray(forKey: key) ?? []).compactMap { path in
            guard path.hasPrefix("/"), seen.insert(path).inserted else { return nil }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            return url.pathExtension.lowercased() == "zip" ? url : nil
        }
    }
    public func register(_ url: URL) throws {
        let url = url.standardizedFileURL
        guard url.isFileURL, url.pathExtension.lowercased() == "zip",
              Self.isArchiveFile(url) else { throw CocoaError(.fileReadNoSuchFile) }
        urls.removeAll { $0 == url }; urls.insert(url, at: 0)
        if urls.count > 20 { urls.removeLast(urls.count - 20) }
        save()
    }
    public func forget(_ url: URL) {
        urls.removeAll { $0 == url.standardizedFileURL }; save()
    }
    @discardableResult public func trash(_ url: URL) throws -> URL? {
        let url = url.standardizedFileURL
        guard urls.contains(url), Self.isArchiveFile(url) else { throw CocoaError(.fileReadNoPermission) }
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        forget(url)
        return result as URL?
    }
    private static func isArchiveFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
    private func save() { defaults.set(urls.map(\.path), forKey: key) }
}
