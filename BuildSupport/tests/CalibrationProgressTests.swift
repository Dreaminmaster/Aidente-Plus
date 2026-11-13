import Foundation
import AidenteShared

@main struct CalibrationProgressTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            precondition(condition, name); checks += 1
        }
        func full(_ percentage: Int = 100, _ hardware: Bool = true,
                  _ charging: Bool = false, _ power: Double = 0, _ age: Double? = 0) -> Bool {
            FullChargeConfirmation.evaluate(percentage: percentage, hardwareFull: hardware,
                isCharging: charging, batteryPower: power, sampleAge: age)
        }
        check(full(), "Fresh full-charge sample confirms completion")
        check(!full(99), "99 percent is not full")
        check(!full(100, false), "UI 100 alone cannot advance")
        check(!full(100, true, true), "Trickle charging must finish")
        for power in [1.0, -1, .nan, .infinity] {
            check(!full(100, true, false, power), "Charging, discharging and invalid power cannot confirm")
        }
        for age in [nil, -1, 11] as [Double?] {
            check(!full(100, true, false, 0, age), "Missing, future and stale samples cannot confirm")
        }
        var stage = CalibrationProgress.chargingToFull
        func advance(_ level: Int, _ confirmed: Bool = false) {
            stage = stage.next(percentage: level, fullChargeConfirmed: confirmed, lowLevel: 10, originalLimit: 80)
        }
        advance(100); check(stage == .chargingToFull, "Displayed 100 cannot start discharge")
        advance(100, true); check(stage == .dischargingToLow, "Confirmed full starts discharge")
        advance(11); check(stage == .dischargingToLow, "Discharge continues above target")
        advance(10); check(stage == .rechargingToFull, "Low target starts recharge")
        advance(100); check(stage == .rechargingToFull, "Recharge also waits for confirmed full")
        advance(100, true); check(stage == .restoringLimit, "Full recharge restores limit without timed hold")
        advance(81); check(stage == .restoringLimit, "Restore continues above original limit")
        advance(80); check(stage == .idle, "Original limit completes calibration")
        check(CalibrationProgress.holdingAtFull.next(percentage: 100, fullChargeConfirmed: true,
            lowLevel: 10, originalLimit: 80) == .restoringLimit, "Migrate old hold")
        check(CalibrationProgress.holdingAtFull.next(percentage: 98, fullChargeConfirmed: false,
            lowLevel: 10, originalLimit: 80) == .rechargingToFull, "Incomplete legacy hold resumes charge")
        print("Passed \(checks) calibration checks (hardware-free)")
    }
}
