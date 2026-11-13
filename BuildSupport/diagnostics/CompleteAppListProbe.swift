import AppKit
import Foundation

enum AidenteL10n { static func t(_ zh: String, _ en: String) -> String { zh } }
@main struct CompleteAppListProbe {
    static func main() throws {
        var previous: [String] = []
        for index in 0..<6 {
            let rows = AppEnergyUsageService.readTopApps(minimumCPU: 5, onlySignificant: false) ?? []
            let expected = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }.compactMap { $0.bundleURL?.standardizedFileURL.path }
            let ids = rows.map(\.id), missing = Set(expected).subtracting(ids)
            precondition(missing.isEmpty, "All running normal applications must be listed, including idle apps")
            if Set(previous) == Set(ids) { precondition(previous == ids, "Readings must not reorder stable application membership") }
            previous = ids
            let report: [String: Any] = ["index":index,"timestamp":ISO8601DateFormatter().string(from:Date()),"runningApplicationCount":expected.count,"rowCount":rows.count,"missing":Array(missing),"names":rows.map(\.name),"samplingCount":rows.filter(\.isSampling).count]
            print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self)); fflush(stdout)
            if index < 5 { Thread.sleep(forTimeInterval:2) }
        }
    }
}
