import Foundation

/// Progress is observed capacity loss, never a fabricated replacement for the
/// macOS percentage or a new coordinate for hardware charge control.
public struct DischargeProgress: Equatable {
    private var target: Int?
    private var baseline: Int?
    private var lastDate: Date?
    public private(set) var consumedMilliampHours: Int?
    public private(set) var watts: Double?
    public init() {}
    public mutating func update(requested: Bool, target: Int, capacity: Int?,
                                batteryPower: Double, date: Date?, now: Date) {
        guard requested else { self = Self(); return }
        if self.target != target { self = Self(); self.target = target }
        guard let date, now.timeIntervalSince(date) >= -1,
              now.timeIntervalSince(date) < 15,
              batteryPower.isFinite else { watts = nil; return }
        guard date != lastDate else { return }
        lastDate = date
        watts = batteryPower
        guard let capacity, capacity >= 0 else {
            consumedMilliampHours = nil
            return
        }
        if baseline == nil { baseline = capacity }
        // A recharge or capacity-model correction must not inflate discharge
        // progress. A later session starts a new baseline.
        consumedMilliampHours = max(0, (baseline ?? capacity) - capacity)
    }
}

public enum ChargeTrackMotion: Equatable {
    case stopped, charging, discharging
    public static func observed(isCharging: Bool, batteryPower: Double, fresh: Bool) -> Self {
        switch ObservedBatteryFlow.resolve(reportsCharging: isCharging, watts: batteryPower, fresh: fresh) {
        case .charging: return .charging
        case .discharging: return .discharging
        case .held, .unconfirmed: return .stopped
        }
    }
}

public enum ObservedBatteryFlow: Equatable {
    case unconfirmed, held, charging, discharging

    public static func resolve(reportsCharging: Bool, watts: Double, fresh: Bool) -> Self {
        guard fresh, watts.isFinite else { return .unconfirmed }
        if watts > 1 { return .charging }
        if watts < -1, !reportsCharging { return .discharging }
        return reportsCharging ? .unconfirmed : .held
    }
}
