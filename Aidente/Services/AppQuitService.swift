import AppKit
import Observation

/// A quit request is asynchronous and can be declined by an application's save dialog.
/// Keep the original process identities so a later retry cannot kill a relaunched app.
@Observable @MainActor final class AppQuitService {
    static let shared = AppQuitService()
    enum State: Equatable { case requesting, stillRunning, rejected }
    private(set) var states: [String: State] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var targets: [String: [NSRunningApplication]] = [:]

    func request(path: String, force: Bool = false) {
        guard !AidenteRuntime.isUIPreview else { return }
        tasks[path]?.cancel()
        let apps = force ? (targets[path] ?? []) : NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == path && !$0.isTerminated }
        guard !apps.isEmpty else { states[path] = nil; return }
        targets[path] = apps
        states[path] = .requesting
        var accepted = true
        for app in apps where !app.isTerminated {
            if !(force ? app.forceTerminate() : app.terminate()) { accepted = false }
        }
        tasks[path] = Task { [weak self] in
            for _ in 0..<24 {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                if apps.allSatisfy({ $0.isTerminated }) {
                    self?.states[path] = nil; self?.targets[path] = nil; self?.tasks[path] = nil
                    return
                }
            }
            self?.states[path] = accepted ? .stillRunning : .rejected
            self?.tasks[path] = nil
        }
    }

    func showApplication(path: String) {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == path && !$0.isTerminated }?
            .activate(options: [.activateAllWindows])
    }
}
