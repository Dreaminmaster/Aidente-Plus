import Foundation
import IOKit
import IOKit.ps

/// The displayed battery percentage comes from the Mac's internal battery.
/// Other IOPS entries can represent a UPS or an external accessory.
public enum SystemBatteryReading {
    public struct RawCapacity: Equatable, Sendable {
        public let current: Int
        public let full: Int
    }

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

    public static func registrySnapshot(service: io_service_t) -> [String: Any]? {
        guard service != 0 else { return nil }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    public static func rawCapacity(in snapshot: [String: Any]?) -> RawCapacity? {
        guard let snapshot else { return nil }
        let nested = snapshot["BatteryData"] as? [String: Any] ?? [:]
        func pair(_ current: Any?, _ full: Any?) -> RawCapacity? {
            guard let current = current as? NSNumber, let full = full as? NSNumber,
                  CFGetTypeID(current) == CFNumberGetTypeID(), CFGetTypeID(full) == CFNumberGetTypeID(),
                  let remaining = Int(exactly: current.doubleValue), remaining >= 0,
                  let maximum = Int(exactly: full.doubleValue), maximum > 0 else { return nil }
            return RawCapacity(current: remaining, full: maximum)
        }
        let current = "AppleRawCurrentCapacity"
        let full = "AppleRawMaxCapacity"
        return pair(snapshot[current], snapshot[full])
            ?? pair(nested[current], nested[full])
            ?? pair(snapshot[current] ?? nested[current], snapshot[full] ?? nested[full])
            ?? pair(nested["RemainingCapacity"], nested["FullChargeCapacity"])
    }

    public static func packData(service: io_service_t) -> [String: Any]? {
        guard service != 0 else { return nil }
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(children) }
        while case let child = IOIteratorNext(children), child != 0 {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "AppleSmartBatteryPack") != 0 else { continue }
            if let data = IORegistryEntryCreateCFProperty(child, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                return data
            }
        }
        return nil
    }

    public static func packTemperature(in data: [String: Any]?) -> Double? {
        for key in ["Temperature", "VirtualTemperature"] {
            guard let raw = data?[key] as? NSNumber, CFGetTypeID(raw) == CFNumberGetTypeID(),
                  raw.doubleValue > 0, raw.doubleValue <= 8000 else { continue }
            return raw.doubleValue / 100
        }
        return nil
    }
}
