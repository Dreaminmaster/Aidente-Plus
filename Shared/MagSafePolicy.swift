import Foundation
public enum MagSafePolicy {
    /// Raw SMC LED values: reset 0, off 1, green 3, orange 4, slow blink 6.
    public static func target(enabled: Bool, mode: Int, sleeping: Bool, discharging: Bool,
                              blinkDuringDischarge: Bool, requested: UInt8) -> UInt8 {
        guard enabled else { return 0 }
        if mode == 1 || mode == 2 && sleeping { return 1 }
        if discharging { return blinkDuringDischarge ? 6 : 4 }
        return requested
    }
}
