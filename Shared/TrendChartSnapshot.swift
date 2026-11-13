import Foundation

public enum TrendMetric: Sendable {
    case percentage, temperature, power, cycles, health
    public func value(_ sample: DashboardReading) -> Double {
        switch self {
        case .percentage: sample.percentage
        case .temperature: sample.temperature
        case .power: sample.power
        case .cycles: sample.cycles
        case .health: sample.health
        }
    }
}

public enum TrendTimeline: String, Codable, Sendable { case actual, recorded }

/// Derived once for a chart input. Rendering closures never sort or scan the history.
public struct TrendChartSnapshot: Sendable {
    public let observations: [DashboardReading]
    public let segments: [[DashboardReading]]
    public let domain: ClosedRange<Double>
    public let times: ClosedRange<Date>
    public let timeline: TrendTimeline
    public let recordedDuration: TimeInterval
    public let hasCollapsedIntervals: Bool
    private let positions: [Date: Date]
    private let plottedTimes: [Date]
    public init(samples: [DashboardReading], metric: TrendMetric, interval: DateInterval? = nil, budget: Int = 320, timeline: TrendTimeline = .actual) {
        self.timeline = timeline
        var valid = samples.filter {
            $0.timestamp.timeIntervalSinceReferenceDate.isFinite && metric.value($0).isFinite
                && (metric != .temperature || $0.temperature > 0)
        }.sorted { $0.timestamp < $1.timestamp }
        if let interval {
            valid = valid.filter { $0.timestamp <= interval.end && (timeline == .recorded || $0.timestamp >= interval.start) }
            if timeline == .recorded, valid.count > 1 {
                var duration: TimeInterval = 0
                var first = valid.count - 1
                for index in stride(from: valid.count - 1, through: 1, by: -1) {
                    let gap = valid[index].timestamp.timeIntervalSince(valid[index - 1].timestamp)
                    if gap > 0 && gap <= 60 { duration += gap }
                    first = index - 1
                    if duration >= interval.duration { break }
                }
                valid = Array(valid[first...])
            }
        }
        observations = valid
        var duration: TimeInterval = 0, cursor: TimeInterval = 0, collapsed = false
        var mapping: [Date: Date] = [:], plotted: [Date] = []
        var previous: Date?
        for sample in valid {
            if let previous {
                let delta = sample.timestamp.timeIntervalSince(previous)
                if delta > 0 && delta <= 60 { duration += delta; cursor += delta }
                else if delta > 60 { cursor += 15; collapsed = true }
            }
            let position = timeline == .recorded ? Date(timeIntervalSince1970: cursor) : sample.timestamp
            mapping[sample.timestamp] = position; plotted.append(position)
            previous = sample.timestamp
        }
        positions = mapping; plottedTimes = plotted
        recordedDuration = duration; hasCollapsedIntervals = collapsed
        if timeline == .recorded {
            times = valid.count > 1 ? Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: max(1,cursor)) : Date(timeIntervalSince1970: -0.5)...Date(timeIntervalSince1970: 0.5)
        } else {
            let end = valid.last?.timestamp ?? interval?.end ?? Date()
            let start = valid.first?.timestamp ?? end.addingTimeInterval(-900)
            times = interval.map { $0.start...max($0.end,$0.start.addingTimeInterval(1)) } ?? start...max(end,start.addingTimeInterval(1))
        }
        if metric == .percentage { domain = 0...100 }
        else {
            var low = Double.infinity, high = -Double.infinity
            for sample in valid {
                var values = [metric.value(sample)]
                if metric == .power { values += [sample.adapterPower, sample.systemPower].compactMap { $0 }.filter { $0.isFinite && (0...1000).contains($0) } }
                for value in values { low = min(low, value); high = max(high, value) }
            }
            if !low.isFinite { low = 0; high = 1 }
            let margin = max((high - low) * 0.2, 1)
            domain = max(0, low - margin)...max(1, high + margin)
        }
        var groups: [[DashboardReading]] = []
        for sample in valid {
            if let previous = groups.last?.last, sample.timestamp.timeIntervalSince(previous.timestamp) <= 60 {
                groups[groups.count - 1].append(sample)
            } else { groups.append([sample]) }
        }
        segments = groups.map { group in
            let allowance = max(8, max(8, budget) * group.count / max(1, valid.count))
            guard group.count > allowance else { return group }
            let bucketSize = max(1, Int(ceil(Double(group.count) / Double(max(1, allowance / 6)))))
            var indices: Set<Int> = [0, group.count - 1]
            for base in stride(from: 0, to: group.count, by: bucketSize) {
                let range = base..<min(group.count, base + bucketSize)
                for field in 0..<(metric == .power ? 3 : 1) {
                    let readings: [(Int, Double)] = range.compactMap { i in
                        let value = field == 0 ? metric.value(group[i]) : field == 1 ? group[i].adapterPower : group[i].systemPower
                        guard let value, value.isFinite else { return nil }
                        return (i, value)
                    }
                    if let i = readings.min(by: { $0.1 < $1.1 })?.0 { indices.insert(i) }
                    if let i = readings.max(by: { $0.1 < $1.1 })?.0 { indices.insert(i) }
                }
            }
            // Preserve both sides of limit changes; old unknown limits stay unknown.
            if metric == .percentage {
                for i in group.indices.dropFirst() where group[i].chargeLimit != group[i - 1].chargeLimit {
                    indices.insert(i - 1); indices.insert(i)
                }
            }
            return indices.sorted().map { group[$0] }
        }
    }
    public func plotDate(for actual: Date) -> Date { positions[actual] ?? actual }
    public func nearestObservation(to plotted: Date, tolerance: TimeInterval = 30) -> DashboardReading? {
        guard let index = TrendSelection.nearest(in: plottedTimes, to: plotted, tolerance: tolerance) else { return nil }
        return observations[index]
    }
    /// Axis labels retain real clock times even when empty intervals are collapsed.
    public func actualTime(at plotted: Date) -> Date {
        guard timeline == .recorded, !plottedTimes.isEmpty else { return plotted }
        var low = 0, high = plottedTimes.count
        while low < high {
            let middle = (low + high) / 2
            if plottedTimes[middle] < plotted { low = middle + 1 } else { high = middle }
        }
        if low == 0 { return observations[0].timestamp }
        if low >= plottedTimes.count { return observations[observations.count - 1].timestamp }
        let before = observations[low - 1].timestamp, after = observations[low].timestamp
        let span = plottedTimes[low].timeIntervalSince(plottedTimes[low - 1])
        let fraction = min(1,max(0,plotted.timeIntervalSince(plottedTimes[low - 1]) / max(0.001,span)))
        if after.timeIntervalSince(before) > 60 { return fraction < 0.5 ? before : after }
        return before.addingTimeInterval(after.timeIntervalSince(before) * fraction)
    }

}
