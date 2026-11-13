import Observation

/// State transitions bypass periodic value refreshes and coalesce in the next actor turn.
@MainActor public final class ImmediateStateObserver {
    private let read: () -> Void
    private let changed: () -> Void
    private var active = false
    public init(read: @escaping () -> Void, changed: @escaping () -> Void) { self.read = read; self.changed = changed }
    public func start() { guard !active else { return }; active = true; observe() }
    public func stop() { active = false }
    private func observe() {
        guard active else { return }
        withObservationTracking { read() } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                self.changed()
                self.observe()
            }
        }
    }
}
