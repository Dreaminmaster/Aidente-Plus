import AppKit

enum AidenteRuntime { static let isUIPreview = false }
@main struct AppQuitIntegrationTests {
    @MainActor static func main() async throws {
        let path = CommandLine.arguments[1]
        let url = URL(fileURLWithPath: path)
        func launch(decline: Bool) async throws -> NSRunningApplication {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.createsNewApplicationInstance = true
            configuration.arguments = decline ? ["--decline"] : []
            return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
        let service = AppQuitService.shared
        let cooperative = try await launch(decline: false)
        defer { if !cooperative.isTerminated { cooperative.forceTerminate() } }
        try await Task.sleep(for: .milliseconds(500))
        service.request(path: path)
        try await Task.sleep(for: .seconds(2))
        precondition(cooperative.isTerminated && service.states[path] == nil, "Normal quit must complete and clear pending state")
        print("PASS normal quit acknowledged")
        let declined = try await launch(decline: true)
        defer { if !declined.isTerminated { declined.forceTerminate() } }
        try await Task.sleep(for: .milliseconds(500))
        service.request(path: path)
        precondition(service.states[path] == .requesting)
        try await Task.sleep(for: .seconds(7))
        precondition(!declined.isTerminated && service.states[path] != nil && service.states[path] != .requesting, "Declined quit must remain visible as still running")
        print("PASS declined quit reported without automatic force")
        service.request(path: path, force: true)
        try await Task.sleep(for: .seconds(2))
        precondition(declined.isTerminated && service.states[path] == nil)
        print("PASS explicit force quit clears the original process")
        let relaunched = try await launch(decline: true)
        defer { if !relaunched.isTerminated { relaunched.forceTerminate() } }
        try await Task.sleep(for: .milliseconds(500))
        service.request(path: path, force: true)
        try await Task.sleep(for: .milliseconds(500))
        precondition(!relaunched.isTerminated, "Stale force request must not kill a relaunched process")
        print("PASS stale request cannot terminate a relaunched application")
    }
}
