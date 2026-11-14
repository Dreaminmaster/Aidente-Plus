import Foundation

/// Progress is observed capacity loss, never a fabricated replacement for the
/// macOS percentage or a new coordinate for hardware charge control.
public struct DischargeProgress: Equatable {
    private var target: Int?
    private var baseline: Int?
    private var lastDate: Date?
    public private(set) var consumedMilliampHours = 0
    public private(set) var watts: Double?
    public init() {}
    public mutating func update(requested: Bool, target: Int, capacity: Int,
                                batteryPower: Double, date: Date?, now: Date) {
        guard requested else { self = Self(); return }
        if self.target != target { self = Self(); self.target = target }
        guard let date, now.timeIntervalSince(date) >= -1,
              now.timeIntervalSince(date) < 15,
              capacity > 0, batteryPower.isFinite else { watts = nil; return }
        guard date != lastDate else { return }
        lastDate = date
        watts = batteryPower
        if baseline == nil { baseline = capacity }
        // A recharge or capacity-model correction must not inflate discharge
        // progress. A later session starts a new baseline.
        consumedMilliampHours = max(0, (baseline ?? capacity) - capacity)
    }
}

public enum ChargeTrackMotion: Equatable {
    case stopped, charging, discharging
    public static func observed(isCharging: Bool, batteryPower: Double, fresh: Bool) -> Self {
        guard fresh, batteryPower.isFinite else { return .stopped }
        if isCharging { return .charging }
        return batteryPower < -1 ? .discharging : .stopped
    }
}
