import Foundation

/// Pure workflow transitions. The caller must supply a fresh, confirmed full-charge sample.
public enum CalibrationProgress: String {
    case idle, chargingToFull, dischargingToLow, rechargingToFull, holdingAtFull, restoringLimit

    public func next(percentage: Int, fullChargeConfirmed: Bool,
                     lowLevel: Int, originalLimit: Int) -> Self {
        switch self {
        case .chargingToFull where fullChargeConfirmed: return .dischargingToLow
        case .dischargingToLow where percentage <= min(20, max(5, lowLevel)): return .rechargingToFull
        case .rechargingToFull where fullChargeConfirmed: return .restoringLimit
        // Migrate a persisted legacy timed-hold phase without starting a timer again.
        case .holdingAtFull: return fullChargeConfirmed ? .restoringLimit : .rechargingToFull
        case .restoringLimit where percentage <= originalLimit: return .idle
        default: return self
        }
    }
}

public enum FullChargeConfirmation {
    public static func evaluate(percentage: Int, hardwareFull: Bool, isCharging: Bool,
                                batteryPower: Double, sampleAge: TimeInterval?) -> Bool {
        guard let sampleAge, sampleAge >= 0, sampleAge <= 10,
              batteryPower.isFinite else { return false }
        return percentage >= 100 && hardwareFull && !isCharging && abs(batteryPower) <= 0.5
    }
}
