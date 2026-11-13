import Foundation

@objc public protocol AidenteReaderProtocol {
    func readComponentPower(reply: @escaping @Sendable (String) -> Void)
    func nativeChargeLimits(reply: @escaping @Sendable (String) -> Void)
    func readBatteryTemperature(reply: @escaping @Sendable (Double) -> Void)
    func readBatteryMetrics(
        reply: @escaping @Sendable (Double, Double, Double) -> Void
    )
    func readAdapterMetrics(
        reply: @escaping @Sendable (Double, Double, Double) -> Void
    )
    func getCapabilities(
        reply: @escaping @Sendable (Bool, Bool, Bool, Bool) -> Void
    )
}

@objc public protocol AidenteControlProtocol {
    func readLastFullCharge(reply: @escaping @Sendable (Double) -> Void)
    func configureLED(enabled: Bool, mode: Int, blink: Bool, reply: @escaping @Sendable (Bool, String?) -> Void)
    func setEnergyMode(mode: Int, source: String, reply: @escaping @Sendable (Bool, String?) -> Void)
    func applyPowerPolicy(charging: Bool, adapter: Bool, managed: Bool,
                          stopWhileSleeping: Bool, resetOnDisconnect: Bool, followNaturalDrift: Bool,
                          chargeCeiling: Int, rechargeBelow: Int,
                          reply: @escaping @Sendable (Bool, String?) -> Void)
    func ping(
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func manageBatteryCharging(
        enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func manageExternalPower(
        enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func manageMagsafeLED(
        target: UInt8,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func setResetOnDisconnect(_ enabled: Bool)
    func resetToDefaults()
    func restoreDefaults(reply: @escaping @Sendable (Bool, String?) -> Void)
}
