import Foundation

/// A stale user-visible gauge must not turn a bounded discharge into an
/// unbounded wait. Raw capacity is a safety budget, not a substitute UI percent.
public struct DischargeSafetyPolicy: Codable, Equatable {
    public enum StopReason: String, Codable {
        case invalidReading, capacityBudget, stalled, previousStop
    }
    private struct Session: Codable, Equatable {
        var target: Int
        var startingDisplay: Int
        var startingRaw: Double
        var lastDisplay: Int
        var lastDisplayChange: Date
        // Optional for recovery snapshots produced by older versions.
        var progressRaw: Double?
        var progressAt: Date?
    }
    private var session: Session?
    private var blockedTarget: Int?
    public private(set) var stopReason: StopReason?
    public init() {}
    public var isBlocked: Bool { blockedTarget != nil }
    public mutating func reset() { session = nil; blockedTarget = nil; stopReason = nil }
    /// True means stop and restore the captured system policy, never "complete".
    public mutating func mustStop(managed: Bool, dischargeRequested: Bool, target: Int,
                                  displayed: Int, raw: Double, now: Date) -> Bool {
        guard managed && dischargeRequested else { reset(); return false }
        if blockedTarget == target {
            if stopReason == nil { stopReason = .previousStop }
            return true
        }
        if blockedTarget != nil { reset() }
        guard raw.isFinite, (1...100).contains(raw), (0...100).contains(displayed) else {
            blockedTarget = target
            stopReason = .invalidReading
            return true
        }
        guard displayed > target else { reset(); return false }
        if session?.target != target {
            session = Session(target: target, startingDisplay: displayed, startingRaw: raw,
                lastDisplay: displayed, lastDisplayChange: now, progressRaw: raw, progressAt: now)
        }
        guard var active = session else { return false }
        let displayProgress = displayed < active.lastDisplay
        let rawProgress = (active.progressRaw ?? active.startingRaw) - raw >= 0.25
        if displayProgress {
            active.lastDisplay = displayed
            active.lastDisplayChange = now
        }
        if active.progressAt == nil || displayProgress || rawProgress {
            active.progressAt = now
            active.progressRaw = raw
        }
        session = active
        let requestedDrop = Double(max(1, active.startingDisplay - target))
        let consumed = active.startingRaw - raw
        let exhaustedBudget = now.timeIntervalSince(active.lastDisplayChange) >= 120 && consumed >= requestedDrop
        let noProgress = now.timeIntervalSince(active.progressAt ?? now) >= 300
        if exhaustedBudget || noProgress {
            blockedTarget = target
            stopReason = exhaustedBudget ? .capacityBudget : .stalled
            return true
        }
        return false
    }
}
