import Foundation
import AidenteShared
import smc_power
import Darwin

/// Uses PowerUIAgent's documented-by-research preference protocol. No charge
/// policy archives or unrelated Apple preferences are read or rewritten.
struct PowerUIChargeRegisters: NativeChargeRegisters {
    let client: NativeChargeLimit
    private let domain = "com.apple.smartcharging.topoffprotection" as CFString
    private let limitKey = "mclLimitValue" as CFString
    private let stateKey = "MCLFeatureState" as CFString
    private func synchronize() throws {
        guard getuid() == 0 else { throw CocoaError(.fileWriteNoPermission) }
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
    func readPreferences() throws -> NativeChargePreferences {
        try synchronize()
        func integer(_ key: CFString) throws -> Int? {
            guard let value = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
            guard CFGetTypeID(value) == CFNumberGetTypeID(), let number = value as? NSNumber,
                  number.doubleValue.isFinite, number.doubleValue == Double(number.intValue) else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            return number.intValue
        }
        return NativeChargePreferences(limit: try integer(limitKey), featureState: try integer(stateKey))
    }
    func writePreferences(_ value: NativeChargePreferences) throws {
        guard getuid() == 0 else { throw CocoaError(.fileWriteNoPermission) }
        guard value.limit.map({ (0...100).contains($0) }) ?? true else { throw NativeChargeError.invalidLimit }
        CFPreferencesSetValue(limitKey, value.limit.map(NSNumber.init(value:)), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(stateKey, value.featureState.map(NSNumber.init(value:)), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        try synchronize()
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.apple.smartcharging.defaultschanged" as CFString), nil, nil, true)
    }
    func releaseLimit() throws { try client.disable() }
    func effectiveLimit() throws -> Int { try client.read().limit }
    func waitForApplication() { Thread.sleep(forTimeInterval: 0.15) }
}
