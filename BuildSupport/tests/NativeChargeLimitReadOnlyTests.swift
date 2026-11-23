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
        let rawCurrent = "AppleRawCurrentCapacity"
        let rawFull = "AppleRawMaxCapacity"
        let older = SystemBatteryReading.rawCapacity(in: [rawCurrent: 4260, rawFull: 4460])
        precondition(older?.current == 4260 && older?.full == 4460)
        let nested = SystemBatteryReading.rawCapacity(in: [
            rawCurrent: 4250,
            "BatteryData": [rawCurrent: 4230, rawFull: 4478]
        ])
        precondition(nested?.current == 4230 && nested?.full == 4478)
        let split = SystemBatteryReading.rawCapacity(in: [
            rawCurrent: 4223,
            "BatteryData": [rawFull: 4468]
        ])
        precondition(split?.current == 4223 && split?.full == 4468)
        let aliases = SystemBatteryReading.rawCapacity(in: [
            "BatteryData": ["RemainingCapacity": 4197, "FullChargeCapacity": 4468]
        ])
        precondition(aliases?.current == 4197 && aliases?.full == 4468)
        precondition(SystemBatteryReading.rawCapacity(in: [rawCurrent: true, rawFull: 100]) == nil)
        precondition(SystemBatteryReading.rawCapacity(in: [rawCurrent: 100, rawFull: 0]) == nil)
        precondition(SystemBatteryReading.rawCapacity(in: [rawCurrent: 0, rawFull: 4468])?.current == 0)
        precondition(SystemBatteryReading.rawCapacity(in: ["CurrentCapacity": 97, "MaxCapacity": 100]) == nil)
        precondition(SystemBatteryReading.packTemperature(in: ["Temperature": 2529]) == 25.29)
        precondition(SystemBatteryReading.packTemperature(in: ["Temperature": 0, "VirtualTemperature": 2512]) == 25.12)
        precondition(SystemBatteryReading.packTemperature(in: ["Temperature": true, "VirtualTemperature": 80_000]) == nil)
        let registered = NativeChargeRegistration.parse("""
            Battery level limits:
            (
                { Terminated = 0; chargeSocLimitOwner = 679; chargeSocLimitSoc = 97; chargeSocLimitReason = manualChargeLimit; chargeSocLimitDrain = 1; chargeSocLimitIsEOC = 1; },
                { Terminated = 0; chargeSocLimitOwner = 0; chargeSocLimitSoc = 97; chargeSocLimitReason = manualChargeLimit; chargeSocLimitDrain = 1; chargeSocLimitIsEOC = 1; },
                { Terminated = 1; chargeSocLimitSoc = 95; },
                { Terminated = 0; chargeSocLimitSoc = 80; chargeSocLimitReason = optimizedCharging; chargeSocLimitDrain = 0; chargeSocLimitIsEOC = 0; },
                { Terminated = 0; chargeSocLimitSoc = 80; chargeSocLimitReason = optimizedCharging; chargeSocLimitDrain = 0; }
            )
            """)
        precondition(registered?.map(\.percentage) == [97, 80, 80])
        precondition(registered?.map(\.allowsDrain) == [true, false, false])
        precondition(registered?.map(\.isEndOfCharge) == [true, false, nil])
        precondition(NativeChargeRegistration.parse("No battery level limits set\n") == [])
        precondition(NativeChargeRegistration.parse("Unexpected output") == nil)
        precondition(NativeChargeRegistration.parse("Battery level limits: ({ Terminated = 0; chargeSocLimitSoc = 101; })") == nil)
        precondition(NativeChargeRegistration.parse("Battery level limits: ({ chargeSocLimitSoc = 95; })") == nil)
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
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { if battery != 0 { IOObjectRelease(battery) } }
        let liveCapacity = SystemBatteryReading.rawCapacity(in: SystemBatteryReading.registrySnapshot(service: battery))
        print("8 raw capacity pair checks passed; live current/full=\(String(describing: liveCapacity))")
        let pack = SystemBatteryReading.packData(service: battery)
        print("3 pack temperature checks passed; live pack temperature=\(String(describing: SystemBatteryReading.packTemperature(in: pack)))")
        let registrations = NativeChargeRegistration.read()
        print("7 active registration checks passed; live registration=\(String(describing: registrations?.map(\.percentage))), EOC=\(String(describing: registrations?.map(\.isEndOfCharge)))")
    }
}
