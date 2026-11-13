import Foundation

public struct SleepControlPolicy {
    public private(set) var startedAt: Date?
    public private(set) var endAt: Date?
    public init() {}
    public mutating func start(minutes: Int?, now: Date) {
        startedAt = now
        endAt = minutes.map { now.addingTimeInterval(Double(max(1, min(10080, $0))) * 60) }
    }
    public mutating func stop() { startedAt = nil; endAt = nil }
    public mutating func active(now: Date, percentage: Int, threshold: Int, adapterConnected: Bool, stopOnUnplug: Bool) -> Bool {
        guard startedAt != nil else { return false }
        if let endAt, now >= endAt { stop(); return false }
        if percentage <= max(5, min(95, threshold)) || stopOnUnplug && !adapterConnected { stop(); return false }
        return true
    }
}
