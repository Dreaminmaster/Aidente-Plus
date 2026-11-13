import Foundation

/// A stale user-visible gauge must not turn a bounded discharge into an
/// unbounded wait. Raw capacity is a safety budget, not a substitute UI percent.
public struct DischargeSafetyPolicy: Codable, Equatable {
    private struct Session: Codable, Equatable {
        var target: Int
        var startingDisplay: Int
        var startingRaw: Double
        var lastDisplay: Int
        var lastDisplayChange: Date
    }
    private var session: Session?
    private var blockedTarget: Int?
    public init() {}
    public var isBlocked: Bool { blockedTarget != nil }
    public mutating func reset() { session = nil; blockedTarget = nil }
    /// True means stop and restore the captured system policy, never "complete".
    public mutating func mustStop(managed: Bool, dischargeRequested: Bool, target: Int,
                                  displayed: Int, raw: Double, now: Date) -> Bool {
        guard managed && dischargeRequested else { reset(); return false }
        if blockedTarget == target { return true }
        if blockedTarget != nil { reset() }
        guard raw.isFinite, (1...100).contains(raw), (0...100).contains(displayed) else {
            blockedTarget = target
            return true
        }
        guard displayed > target else { reset(); return false }
        if session?.target != target {
            session = Session(target: target, startingDisplay: displayed, startingRaw: raw,
                lastDisplay: displayed, lastDisplayChange: now)
        }
        guard var active = session else { return false }
        if displayed != active.lastDisplay {
            active.lastDisplay = displayed
            active.lastDisplayChange = now
            session = active
        }
        let requestedDrop = Double(max(1, active.startingDisplay - target))
        let consumed = active.startingRaw - raw
        if now.timeIntervalSince(active.lastDisplayChange) >= 120 && consumed >= requestedDrop {
            blockedTarget = target
            return true
        }
        return false
    }
}
