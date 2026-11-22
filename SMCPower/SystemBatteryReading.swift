import Foundation
import IOKit.ps

/// The displayed battery percentage comes from the Mac's internal battery.
/// Other IOPS entries can represent a UPS or an external accessory.
public enum SystemBatteryReading {
    public static func powerSource() -> [String: Any]? {
        guard let copiedInfo = IOPSCopyPowerSourcesInfo() else { return nil }
        let snapshot = copiedInfo.takeRetainedValue()
        guard let copiedSources = IOPSCopyPowerSourcesList(snapshot) else { return nil }
        let sources = copiedSources.takeRetainedValue() as Array
        return sources.lazy.compactMap {
            IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any]
        }.first(where: isInternalBattery)
    }

    static func isInternalBattery(_ source: [String: Any]) -> Bool {
        if let type = source[kIOPSTypeKey] as? String { return type == kIOPSInternalBatteryType }
        return source[kIOPSTransportTypeKey] as? String == kIOPSInternalType
    }

    public static func percentage(in source: [String: Any]?) -> Int? {
        guard let current = source?[kIOPSCurrentCapacityKey] as? NSNumber,
              let maximum = source?[kIOPSMaxCapacityKey] as? NSNumber else { return nil }
        return percentage(current: current.doubleValue, maximum: maximum.doubleValue)
    }

    static func percentage(current: Double, maximum: Double) -> Int? {
        guard current.isFinite, maximum.isFinite, maximum > 0, current >= 0, current <= maximum else { return nil }
        return Int((current / maximum * 100).rounded())
    }
}
