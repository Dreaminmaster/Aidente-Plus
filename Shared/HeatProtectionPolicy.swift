import Foundation

/// Five-minute pause windows, followed by a minimum five-minute charging window.
public struct HeatProtectionPolicy {
    private enum Window {
        case idle
        case paused(until: Date)
        case charging(until: Date)
    }
    private var window: Window = .idle
    public init() {}
    public mutating func reset() { window = .idle }
    public mutating func shouldPause(temperature: Double, limit: Double,
                                    enabled: Bool, chargingRequested: Bool, now: Date) -> Bool {
        guard enabled && chargingRequested else { reset(); return false }
        // A configured thermal guard cannot approve charging without a valid reading.
        guard temperature.isFinite, temperature > 0, limit.isFinite else {
            // Missing startup data is a temporary hold, not evidence of heat.
            // Keep any genuine thermal window, but do not manufacture one.
            return true
        }
        switch window {
        case .paused(let until) where now < until: return true
        case .charging(let until) where now < until: return false
        case .idle where temperature < limit: return false
        default:
            if temperature >= limit {
                window = .paused(until: now.addingTimeInterval(300))
                return true
            }
            window = .charging(until: now.addingTimeInterval(300))
            return false
        }
    }
}
