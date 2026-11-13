import Foundation

public struct DashboardReading: Codable, Identifiable, Equatable, Sendable {
    public let timestamp: Date
    public let percentage, temperature, power, cycles, health: Double
    public let chargeLimit: Double?
    public let adapterPower: Double?
    public let systemPower: Double?
    public var id: Date { timestamp }
    public init(timestamp: Date, percentage: Double, temperature: Double, power: Double, cycles: Double, health: Double, chargeLimit: Double? = nil, adapterPower: Double? = nil, systemPower: Double? = nil) {
        self.timestamp = timestamp; self.percentage = percentage; self.temperature = temperature
        self.power = power; self.cycles = cycles; self.health = health
        self.chargeLimit = chargeLimit; self.adapterPower = adapterPower; self.systemPower = systemPower
    }
    /// Time-weighted battery power over contiguous observations. Sleep gaps are not interpolated.
    public static func averagePower(_ values: [Self], maximumGap: TimeInterval = 60) -> Double? {
        guard maximumGap.isFinite, maximumGap > 0 else { return nil }
        let ordered = values.sorted { $0.timestamp < $1.timestamp }
        var energy = 0.0, duration = 0.0
        for (first, second) in zip(ordered, ordered.dropFirst()) {
            let interval = second.timestamp.timeIntervalSince(first.timestamp)
            guard interval > 0, interval <= maximumGap,
                  first.power.isFinite, second.power.isFinite,
                  (0...1000).contains(first.power), (0...1000).contains(second.power) else { continue }
            energy += (first.power + second.power) * 0.5 * interval
            duration += interval
        }
        return duration > 0 ? energy / duration : nil
    }
    public static func retained(_ values: [Self], now: Date) -> [Self] {
        var seen = Set<Date>()
        return Array(values.filter {
            $0.timestamp >= now.addingTimeInterval(-30 * 86400) && $0.timestamp <= now.addingTimeInterval(5)
                && [$0.percentage, $0.temperature, $0.power, $0.cycles, $0.health].allSatisfy(\.isFinite)
                && (0...100).contains($0.percentage) && (0...100).contains($0.temperature)
                && (0...1000).contains($0.power) && (0...50000).contains($0.cycles)
                && (0...200).contains($0.health)
                && [$0.adapterPower, $0.systemPower].compactMap { $0 }.allSatisfy({ $0.isFinite && (0...1000).contains($0) })
                && ($0.chargeLimit.map { $0.isFinite && (0...100).contains($0) } ?? true)
                && seen.insert($0.timestamp).inserted
        }.sorted { $0.timestamp < $1.timestamp }.suffix(5760))
    }
}

/// Snap to an actual observation. Missing/sleep intervals never acquire invented samples.
public enum TrendSelection {
    public static func nearest(in timestamps: [Date], to target: Date, tolerance: TimeInterval) -> Int? {
        guard target.timeIntervalSinceReferenceDate.isFinite, tolerance.isFinite, tolerance >= 0 else { return nil }
        guard let index = timestamps.indices.min(by: { abs(timestamps[$0].timeIntervalSince(target)) < abs(timestamps[$1].timeIntervalSince(target)) }),
              abs(timestamps[index].timeIntervalSince(target)) <= tolerance else { return nil }
        return index
    }
}
