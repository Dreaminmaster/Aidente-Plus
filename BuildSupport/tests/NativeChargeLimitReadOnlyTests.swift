import Foundation
import IOKit.ps

/// Live API contract check. It never sends an accepted write or changes power.
@main struct NativeChargeLimitReadOnlyTests {
    static func main() throws {
        let ups = [kIOPSTypeKey: kIOPSUPSType, kIOPSTransportTypeKey: kIOPSInternalType]
        let macBattery: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 4230, kIOPSMaxCapacityKey: 4500]
        precondition(!SystemBatteryReading.isInternalBattery(ups))
        precondition(SystemBatteryReading.isInternalBattery(macBattery))
        precondition(SystemBatteryReading.isInternalBattery([kIOPSTransportTypeKey: kIOPSInternalType]))
        precondition(SystemBatteryReading.percentage(in: macBattery) == 94)
        precondition(SystemBatteryReading.percentage(in: [kIOPSMaxCapacityKey: 100]) == nil)
        precondition(SystemBatteryReading.percentage(current: 0, maximum: 100) == 0)
        precondition(SystemBatteryReading.percentage(current: 96, maximum: 0) == nil)
        precondition(SystemBatteryReading.percentage(current: .nan, maximum: 100) == nil)
        let client = try NativeChargeLimit()
        let limits = try client.availableLimits()
        precondition(!limits.isEmpty && limits.allSatisfy { (80...100).contains($0) })
        let original = try client.read()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NativeChargeLimit.State.self, from: encoded)
        precondition(decoded == original)
        for invalid in [-1, 0, 79, 101, 256] {
            do { try client.set(invalid); fatalError("Unsupported limit was accepted") }
            catch { /* Invalid input must be rejected before sending a write. */ }
            let after = try client.read()
            precondition(after == original)
        }
        print("7 native read-only checks passed; limits=\(limits), state=\(original)")
        print("8 internal battery selection and percentage checks passed")
    }
}
