import Foundation
import AidenteShared

final class Registers: NativeChargeRegisters {
    var preferences = NativeChargePreferences(limit: 96, featureState: 1)
    var effective = 96
    var writes: [NativeChargePreferences] = []
    var lostWrites = 0
    var queued: NativeChargePreferences?
    var delayed = false
    var broken = false
    var releaseCount = 0
    func releaseLimit() throws {
        if broken { throw CocoaError(.fileWriteUnknown) }
        releaseCount += 1; effective = 100
    }
    func readPreferences() throws -> NativeChargePreferences { preferences }
    func writePreferences(_ value: NativeChargePreferences) throws {
        writes.append(value)
        if broken { throw CocoaError(.fileWriteUnknown) }
        if lostWrites > 0 { lostWrites -= 1; return }
        preferences = value
        if delayed { queued = value }
        else if value.featureState == 1 { effective = value.limit ?? 100 }
    }
    func effectiveLimit() throws -> Int { effective }
    func waitForApplication() {
        if let queued {
            if queued.featureState == 1 { effective = queued.limit ?? 100 }
            self.queued = nil
        }
    }
}
@main struct NativeChargePolicyTests {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ name: String) { precondition(condition, name); count += 1 }
        var request = ChargingPowerPolicy()
        request.managed = true; request.adapter = true; request.charging = true
        for ceiling in 20...100 {
            request.chargeCeiling = ceiling
            for level in 1...100 {
                var policy = NativeChargePolicy()
                let target = policy.target(policy: request, percentage: level, externalConnected: true)!
                check(target >= level, "A normal limit must never deliberately discharge an above-limit battery")
                check(level < ceiling ? target == ceiling : target == level, "Charge to requested level or hold at current level")
            }
        }
        request.chargeCeiling = 95; request.charging = false
        var policy = NativeChargePolicy()
        check(policy.target(policy: request, percentage: 96, externalConnected: true) == 96, "Above-limit hold captures published percentage")
        check(policy.target(policy: request, percentage: 94, externalConnected: true) == 96, "No chasing falling readings")
        check(policy.target(policy: request, percentage: 99, externalConnected: true) == 99, "An outside override cannot become an unwanted discharge")
        _ = policy.target(policy: request, percentage: 94, externalConnected: false)
        check(policy.target(policy: request, percentage: 94, externalConnected: true) == 94, "Replug captures a new hold")
        request.charging = true; request.stopWhileSleeping = true; request.sleeping = true
        check(policy.target(policy: request, percentage: 92, externalConnected: true) == 92, "Sleep has its own hold")
        request.sleeping = false
        check(policy.target(policy: request, percentage: 92, externalConnected: true) == 95, "Awake charging does not inherit a sleep hold")
        request.followNaturalDrift = true; request.charging = false
        check(policy.target(policy: request, percentage: 94, externalConnected: true) == 94, "Sailing starts at the current level")
        check(policy.target(policy: request, percentage: 93, externalConnected: true) == 93, "Sailing follows natural drift instead of recharging to an old hold")
        request.charging = true
        check(policy.target(policy: request, percentage: 90, externalConnected: true) == 95, "Sailing resumes up to the upper target at the lower threshold")
        request.followNaturalDrift = false; request.charging = false
        request.adapter = false
        check(policy.target(policy: request, percentage: 99, externalConnected: true) == 95, "Only explicit discharge permits a lower target")
        request.managed = false
        check(policy.target(policy: request, percentage: 99, externalConnected: true) == nil, "Disabled management restores original state")

        check(NativeChargePolicy.dischargeCeiling(standard: 100, phase: .dischargingToLow, lowLevel: 10, originalLimit: 80) == 10, "Calibration low stage must not send a full-charge target")
        check(NativeChargePolicy.dischargeCeiling(standard: 100, phase: .restoringLimit, lowLevel: 10, originalLimit: 73) == 73, "Calibration recovery uses the saved limit")
        check(NativeChargePolicy.dischargeCeiling(standard: 64, phase: .idle, lowLevel: 10, originalLimit: 73) == 64, "Normal discharge retains its explicit target")
        let registers = Registers()
        let controller = NativeChargeTransaction(registers: registers)
        let original = try controller.snapshot()
        try controller.set(96)
        check(registers.writes.isEmpty, "An already-applied non-five-point hold is idempotent")
        registers.delayed = true
        try controller.set(79)
        check(registers.effective == 79 && registers.preferences == .managed(79), "Delayed sub80 application is verified")
        try controller.replace(original)
        check(registers.effective == 96 && registers.preferences == original.preferences, "Original non-five-point setting restored")
        let missing = NativeChargeSnapshot(preferences: .init(limit: nil, featureState: nil), effectiveLimit: 100)
        try controller.replace(missing)
        check(registers.preferences.limit == nil && registers.preferences.featureState == nil, "Absent original preferences are deleted, not replaced by defaults")
        check(registers.releaseCount == 1 && registers.effective == 100, "Restoring disabled state must unregister powerd policy, not only edit preferences")
        try controller.replace(missing)
        check(registers.releaseCount == 2, "Already-disabled UI state must still unregister a potentially stale kernel policy")
        try controller.replace(original)
        registers.lostWrites = 1
        do { try controller.set(80); preconditionFailure("Lost write reported success") }
        catch { count += 1 }
        check(registers.preferences == original.preferences && registers.effective == 96, "Failed application restores both preferences and effective state")
        registers.broken = true
        do { try controller.set(80); preconditionFailure("Broken rollback reported success") }
        catch NativeChargeError.rollbackFailed { count += 1 }
        catch { preconditionFailure("Rollback failure was hidden") }
        for value in [-1,0,101,256] {
            let before = registers.writes.count
            do { try controller.set(value); preconditionFailure("Invalid input accepted") }
            catch NativeChargeError.invalidLimit { count += 1 }
            check(registers.writes.count == before, "Invalid limit has no write side effect")
        }
        let energy = ProcessEnergyReading(processStart: 10, nanojoules: 1_000_000_000, uptime: 10)
        check(ProcessEnergyReading(processStart: 10, nanojoules: 3_000_000_000, uptime: 14).averageWatts(since: energy) == 0.5, "Nanoujoules and elapsed seconds produce watts")
        check(ProcessEnergyReading(processStart: 11, nanojoules: 3_000_000_000, uptime: 14).averageWatts(since: energy) == nil, "PID reuse cannot attribute another process's energy")
        check(ProcessEnergyReading(processStart: 10, nanojoules: 0, uptime: 14).averageWatts(since: energy) == nil, "Counter resets do not underflow")
        check(ProcessEnergyReading(processStart: 10, nanojoules: 3_000_000_000, uptime: 80).averageWatts(since: energy) == nil, "Stale averages are discarded")
        check(ProcessEnergyReading(processStart: 10, nanojoules: 3_000_000_000, uptime: .nan).averageWatts(since: energy) == nil, "Non-finite time is rejected")
        check(ProcessEnergyReading(processStart: 10, nanojoules: 1_000_000_000, uptime: 14).averageWatts(since: energy) == 0, "Idle intervals are valid zero watts")
        var safety = DischargeSafetyPolicy()
        let start = Date(timeIntervalSince1970: 1000)
        check(!safety.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 82, raw: 81, now: start), "A bounded discharge may begin")
        check(!safety.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 83, raw: 81.6, now: start.addingTimeInterval(60)), "Gauge settling may temporarily rise")
        check(!safety.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 83, raw: 79.5, now: start.addingTimeInterval(500)), "A limited raw change alone does not claim completion")
        check(safety.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 83, raw: 78.9, now: start.addingTimeInterval(600)), "Stop when raw budget is consumed while the display stays stale")
        let persisted = try JSONDecoder().decode(DischargeSafetyPolicy.self, from: JSONEncoder().encode(safety))
        var restarted = persisted
        check(restarted.isBlocked, "A blocked safety state survives persistence for crash recovery")
        check(restarted.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 83, raw: 79.2, now: start.addingTimeInterval(700)), "Repeated requests and daemon restarts cannot rearm a blocked target")
        check(!restarted.mustStop(managed: false, dischargeRequested: false, target: 95, displayed: 83, raw: 79.2, now: start.addingTimeInterval(701)), "Explicitly disabling management releases the blocked intent")
        check(!restarted.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 82, raw: 81, now: start.addingTimeInterval(702)), "A new acknowledged session has a fresh budget")
        check(restarted.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 82, raw: .nan, now: start.addingTimeInterval(703)), "Missing safety telemetry must stop an active discharge")
        safety.reset()
        check(!safety.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 82, raw: 82, now: start), "Ordinary progress begins")
        check(!safety.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 81, raw: 80, now: start.addingTimeInterval(180)), "A fresh lower display reading is real progress")
        check(!safety.mustStop(managed: true, dischargeRequested: true, target: 80, displayed: 80, raw: 79.5, now: start.addingTimeInterval(360)), "Reaching the requested display target completes without a stale-gauge error")
        print("PASS: \(count) native policy, sleep, discharge intent, delayed readback and rollback checks (no hardware writes)")
    }
}
