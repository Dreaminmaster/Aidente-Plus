import Observation
import Foundation

@MainActor @Observable final class AppListInteractionState {
    static let shared = AppListInteractionState()
    private var owners: Set<UUID> = []
    var isInteracting: Bool { !owners.isEmpty }
    func update(_ owner: UUID, active: Bool) {
        if active { owners.insert(owner) } else { owners.remove(owner) }
    }
}
