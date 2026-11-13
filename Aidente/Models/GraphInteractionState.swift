import Observation

@MainActor @Observable final class GraphInteractionState {
    static let shared = GraphInteractionState()
    var isInspecting = false
}
