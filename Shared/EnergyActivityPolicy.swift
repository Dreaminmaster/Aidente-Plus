import Foundation

public struct EnergyAppObservation: Sendable {
    public let id: String
    public let cpu, watts: Double?
    public init(id: String, cpu: Double?, watts: Double?) { self.id = id; self.cpu = cpu; self.watts = watts }
}

public struct EnergyAppActivity: Sendable {
    public let id: String
    public let cpu: Double
    public let watts: Double?
}

/// Presentation stability only. Does not manufacture per-app energy or change power control.
public struct EnergyActivityPolicy: Sendable {
    private struct State: Sendable {
        var cpu: Double
        var watts: Double?
        var wattTime: TimeInterval
        var updated: TimeInterval
        var belowSince: TimeInterval?
        var visible: Bool
    }
    private var states: [String: State] = [:]
    private var configuration: Double?
    public init() {}
    public mutating func update(_ samples: [EnergyAppObservation], threshold: Double, now: TimeInterval, limit: Int = 4) -> [EnergyAppActivity] {
        guard now.isFinite, threshold.isFinite, threshold > 0 else { return [] }
        if configuration != threshold { states.removeAll(); configuration = threshold }
        let present = Set(samples.map(\.id))
        states = states.filter { present.contains($0.key) && now >= $0.value.updated && now - $0.value.updated <= 8 }
        for sample in samples {
            let cpu = sample.cpu.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let watts = sample.watts.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            guard cpu != nil || watts != nil else { continue }
            if var state = states[sample.id] {
                let elapsed = now - state.updated
                guard elapsed >= 1 else { continue } // overlapping refreshes are not new evidence
                let alpha = 1 - exp(-elapsed / 4)
                if let cpu { state.cpu += alpha * (cpu - state.cpu) }
                if let watts {
                    state.watts = state.watts.map { $0 + alpha * (watts - $0) } ?? watts
                    state.wattTime = now
                } else if now - state.wattTime > 6 { state.watts = nil }
                let score = max(state.cpu / threshold, (state.watts ?? 0) / (threshold / 100))
                if !state.visible, score >= 1 { state.visible = true }
                if state.visible, score < 0.6 {
                    state.belowSince = state.belowSince ?? now
                    if now - state.belowSince! >= 8 { state.visible = false }
                } else { state.belowSince = nil }
                state.updated = now; states[sample.id] = state
            } else {
                let score = max((cpu ?? 0) / threshold, (watts ?? 0) / (threshold / 100))
                states[sample.id] = State(cpu: cpu ?? 0, watts: watts, wattTime: now, updated: now, belowSince: nil, visible: score >= 1)
            }
        }
        return states.filter { $0.value.visible }.sorted {
            let a = max($0.value.cpu / threshold, ($0.value.watts ?? 0) / (threshold / 100))
            let b = max($1.value.cpu / threshold, ($1.value.watts ?? 0) / (threshold / 100))
            return a == b ? $0.key < $1.key : a > b
        }.prefix(max(0,limit)).map { EnergyAppActivity(id: $0.key, cpu: $0.value.cpu, watts: $0.value.watts) }
    }
}
