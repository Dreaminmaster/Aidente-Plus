import Foundation

/// A stale user-visible gauge must not turn a bounded discharge into an
/// unbounded wait. Raw capacity is a safety budget, not a substitute UI percent.
public struct DischargeSafetyPolicy: Codable, Equatable {
    public static let nativeStartGrace: TimeInterval = 8 * 60
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
        var startingCurrentMAh: Double?
        var startingFullMAh: Double?
        var progressCurrentMAh: Double?
        var waitingForCurrentSince: Date?
        var suspendedAt: Date?
    }
    private var session: Session?
    private var blockedTarget: Int?
    public private(set) var stopReason: StopReason?
    public init() {}
    public var isBlocked: Bool { blockedTarget != nil }
    public mutating func reset() { session = nil; blockedTarget = nil; stopReason = nil }
    /// True means stop and restore the captured system policy, never "complete".
    public mutating func mustStop(managed: Bool, dischargeRequested: Bool, target: Int,
                                  displayed: Int, raw: Double, now: Date,
                                  capacity: (current: Double, full: Double)? = nil,
                                  nativeCurrentAmps: Double? = nil,
                                  suspended: Bool = false) -> Bool {
        guard managed && dischargeRequested else { reset(); return false }
        if suspended {
            if session?.target == target, session?.suspendedAt == nil {
                session?.suspendedAt = now
            }
            return false
        }
        if blockedTarget == target {
            if stopReason == nil { stopReason = .previousStop }
            return true
        }
        if blockedTarget != nil { reset() }
        // A valid macOS reading at or below the target ends the discharge.
        // Raw capacity is needed to guard continued draining above that target.
        let validDisplay = (0...100).contains(displayed)
        if validDisplay && displayed <= target { reset(); return false }
        guard validDisplay, raw.isFinite, (1...100).contains(raw) else {
            blockedTarget = target
            stopReason = .invalidReading
            return true
        }
        let current = nativeCurrentAmps.flatMap { $0.isFinite ? $0 : nil }
        if session?.target != target {
            session = Session(target: target, startingDisplay: displayed, startingRaw: raw,
                lastDisplay: displayed, lastDisplayChange: now, progressRaw: raw, progressAt: now,
                startingCurrentMAh: capacity?.current, startingFullMAh: capacity?.full,
                progressCurrentMAh: capacity?.current,
                waitingForCurrentSince: current.map { $0 >= -0.08 } == true ? now : nil)
        }
        guard var active = session else { return false }
        if let suspendedAt = active.suspendedAt {
            // The firmware was holding during sleep. Preserve the original
            // capacity budget and count only awake time towards time limits.
            let sleepDuration = max(0, now.timeIntervalSince(suspendedAt))
            active.lastDisplayChange.addTimeInterval(sleepDuration)
            active.progressAt = active.progressAt?.addingTimeInterval(sleepDuration)
            active.waitingForCurrentSince = active.waitingForCurrentSince?.addingTimeInterval(sleepDuration)
            active.suspendedAt = nil
        }
        let displayProgress = displayed < active.lastDisplay
        let consumed: Double
        let rawProgress: Bool
        if let capacity, let startingCurrent = active.startingCurrentMAh,
           let startingFull = active.startingFullMAh, startingFull > 0 {
            // Firmware can revise the full-capacity estimate during a single
            // discharge. Measure both usage and progress against a fixed scale.
            let progressCurrent = active.progressCurrentMAh ?? startingCurrent
            consumed = (startingCurrent - capacity.current) / startingFull * 100
            rawProgress = (progressCurrent - capacity.current) / startingFull * 100 >= 0.25
        } else {
            consumed = active.startingRaw - raw
            rawProgress = (active.progressRaw ?? active.startingRaw) - raw >= 0.25
        }
        if displayProgress {
            active.lastDisplay = displayed
            active.lastDisplayChange = now
        }
        if active.progressAt == nil || displayProgress || rawProgress {
            active.progressAt = now
            active.progressRaw = raw
            active.progressCurrentMAh = capacity?.current
        }
        // Native firmware may delay the start. Give it this window only
        // before negative current or independent progress is observed.
        if let requestTime = active.waitingForCurrentSince {
            let elapsed = now.timeIntervalSince(requestTime)
            let started = current.map { $0 < -0.08 } == true || displayProgress || rawProgress
            if elapsed < Self.nativeStartGrace && (started || current == nil) {
                if started { active.progressAt = now }
                active.waitingForCurrentSince = nil
            }
        }
        session = active
        let requestedDrop = Double(max(1, active.startingDisplay - target))
        let exhaustedBudget = now.timeIntervalSince(active.lastDisplayChange) >= 120 && consumed >= requestedDrop
        let noProgress = if let requestTime = active.waitingForCurrentSince {
            now.timeIntervalSince(requestTime) >= Self.nativeStartGrace
        } else {
            now.timeIntervalSince(active.progressAt ?? now) >= 300
        }
        if exhaustedBudget || noProgress {
            blockedTarget = target
            stopReason = exhaustedBudget ? .capacityBudget : .stalled
            return true
        }
        return false
    }
}
