import Foundation
import Observation
import AidenteShared

@MainActor @Observable final class TestPowerState {
    var connected = false
    var charging = false
    var watts = 0.0
}
@main struct ImmediateStateObserverTests {
    @MainActor static func main() async {
        let state = TestPowerState()
        var transitions: [(Bool,Bool)] = []
        let observer = ImmediateStateObserver(read: { _ = state.connected; _ = state.charging }, changed: { transitions.append((state.connected,state.charging)) })
        observer.start()
        precondition(transitions.isEmpty)
        state.connected = true
        try? await Task.sleep(for: .milliseconds(20))
        precondition(transitions.count == 1 && transitions.last!.0, "Plug event bypasses periodic refresh")
        state.watts = 30
        try? await Task.sleep(for: .milliseconds(20))
        precondition(transitions.count == 1, "Ordinary watts preserve configured refresh cadence")
        state.connected = false; state.charging = false; state.connected = true; state.charging = true
        try? await Task.sleep(for: .milliseconds(20))
        precondition(transitions.count == 2 && transitions.last!.0 && transitions.last!.1, "Burst changes coalesce to settled state")
        state.connected = false
        try? await Task.sleep(for: .milliseconds(20))
        precondition(transitions.count == 3 && !transitions.last!.0, "Observation rearms after each transition")
        observer.stop(); state.connected = true
        try? await Task.sleep(for: .milliseconds(20))
        precondition(transitions.count == 3, "Stopped observer cannot publish late callbacks")
        print("PASS: 5 event-driven status refresh checks")
    }
}
