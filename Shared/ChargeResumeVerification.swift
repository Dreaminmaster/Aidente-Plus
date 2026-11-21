import Foundation

/// A successful control write is an intent. Confirm real input power before
/// reporting that a below-target battery has resumed charging.
public struct ChargeResumeVerification {
    public enum Result: Equatable { case pending, charging, notCharging, discharging, targetReached }
    private var flow = ChargeHoldVerification()
    public init() {}
    public mutating func sample(percentage: Int, target: Int, batteryPower: Double, isCharging: Bool) -> Result {
        guard (0...100).contains(percentage), (1...100).contains(target) else { flow = .init(); return .pending }
        if percentage >= target { flow = .init(); return .targetReached }
        // A charging flag alone cannot confirm resumed input power. Treat a
        // flag-only or contradictory reading as a pending sample.
        let observed = ObservedBatteryFlow.resolve(reportsCharging: isCharging, watts: batteryPower, fresh: true)
        switch flow.sample(batteryPower: observed == .unconfirmed ? .nan : batteryPower) {
        case .pending: return .pending
        case .charging: return .charging
        case .held: return .notCharging
        case .discharging: return .discharging
        }
    }
}
