import Foundation

/// Signed battery power is positive into the battery and negative out of it.
public struct PowerFlowReading: Equatable, Sendable {
    public let adapter, batteryInput, batteryOutput, computer: Double
    public init?(adapterConnected: Bool, adapterPower: Double, batteryPower: Double) {
        guard adapterPower.isFinite, batteryPower.isFinite,
              (0...1000).contains(adapterPower), abs(batteryPower) <= 1000 else { return nil }
        let adapter = adapterConnected ? adapterPower : 0
        let output = max(0, -batteryPower)
        let input = max(0, batteryPower)
        guard input <= adapter + 1 else { return nil } // inconsistent source samples
        self.adapter = adapter
        self.batteryOutput = output
        self.batteryInput = min(input, adapter)
        self.computer = max(0, adapter + output - self.batteryInput)
    }
}

/// Independent hardware readings, never an allocation of watts to applications.
public struct ComponentPowerReading: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let soc: Double?
    public let display: Double?
    public let usb: Double?
    public init(timestamp: Date = Date(), soc: Double?, display: Double?, usb: Double?) {
        self.timestamp = timestamp
        func valid(_ v: Double?) -> Double? { v.flatMap { $0.isFinite && (0...1000).contains($0) ? $0 : nil } }
        self.soc = valid(soc); self.display = valid(display); self.usb = valid(usb)
    }
    /// Do not rescale overlapping/inconsistent sensors into a plausible-looking split.
    public func breakdown(total: Double, now: Date = Date()) -> [Double?]? {
        guard total.isFinite, total >= 0, now.timeIntervalSince(timestamp) >= -1,
              now.timeIntervalSince(timestamp) <= 5 else { return nil }
        let values = [soc, display, usb]
        guard values.contains(where: { $0 != nil }) else { return nil }
        guard values.compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...1000).contains($0) }) else { return nil }
        let sum = values.compactMap { $0 }.reduce(0, +)
        guard sum.isFinite, sum <= total else { return nil }
        return values + [total - sum]
    }
}
