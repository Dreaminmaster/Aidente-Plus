import Foundation
import Darwin
import SMCKit
import AidenteShared

/// Read-only, bounded sensor whitelist. No control registers or arbitrary keys.
public enum ComponentPowerSensors {
    private static let chip: String = {
        var count = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &count, nil, 0) == 0, count > 0, count < 256 else { return "" }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &count, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }()
    private static func watts(_ name: String) -> Double? {
        guard let value: Float = try? SMCKit.shared.read(FourCharCode(stringLiteral: name)),
              value.isFinite, value >= 0, value <= 1000 else { return nil }
        return Double(value)
    }
    public static func read() -> ComponentPowerReading {
        // Base M5 PZC0 includes GPU: label SoC, never CPU. See audit provenance.
        // Unverified chip families stay unavailable instead of inheriting M5 rail meanings.
        let soc = chip == "Apple M5" ? watts("PZC0") : nil
        // Published M5 mapping is PBwo. PBLR exists here but its meaning is not verified.
        let display = chip == "Apple M5" ? watts("PBwo") : nil
        return ComponentPowerReading(soc: soc, display: display, usb: nil)
    }
}
