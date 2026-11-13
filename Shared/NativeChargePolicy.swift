import Foundation

/// Published macOS percentage is the coordinate used by PowerUI. Raw capacity
/// ratios must not be substituted: they can differ by several percentage points.
public struct NativeChargePolicy {
    private var awakeHold: Int?
    private var sleepHold: Int?
    public init() {}
    public mutating func reset() { awakeHold = nil; sleepHold = nil }
    public static func dischargeCeiling(standard: Int, phase: CalibrationProgress,
                                        lowLevel: Int, originalLimit: Int) -> Int {
        switch phase {
        case .dischargingToLow: return min(100, max(1, lowLevel))
        case .restoringLimit: return min(100, max(1, originalLimit))
        default: return min(100, max(1, standard))
        }
    }
    public mutating func target(policy: ChargingPowerPolicy, percentage: Int,
                                externalConnected: Bool) -> Int? {
        guard policy.managed else { reset(); return nil }
        if !externalConnected { reset() }
        if !policy.sleeping { sleepHold = nil }
        let current = min(100, max(1, percentage))
        let power = policy.effective
        // A lower target is intentional only for an explicit discharge request.
        if !power.adapter { reset(); return min(100, max(1, policy.chargeCeiling)) }
        if power.charging && current < policy.chargeCeiling {
            if policy.sleeping { sleepHold = nil } else { awakeHold = nil }
            return min(100, max(1, policy.chargeCeiling))
        }
        if policy.followNaturalDrift && !power.charging && !policy.sleeping && externalConnected {
            awakeHold = current
            return current
        }
        // Freeze a hold once. Never chase declining readings and repeatedly
        // lower the target while still plugged in. Replug captures a new hold.
        if policy.sleeping {
            sleepHold = max(sleepHold ?? current, current)
            return sleepHold
        }
        awakeHold = max(awakeHold ?? current, current)
        return awakeHold
    }
}

public struct NativeChargePreferences: Codable, Equatable, Sendable {
    public var limit: Int?
    public var featureState: Int?
    public init(limit: Int?, featureState: Int?) {
        self.limit = limit; self.featureState = featureState
    }
    public static func managed(_ limit: Int) -> Self { .init(limit: limit, featureState: 1) }
}

public struct NativeChargeSnapshot: Codable, Equatable {
    public let preferences: NativeChargePreferences
    public let effectiveLimit: Int
    public init(preferences: NativeChargePreferences, effectiveLimit: Int) {
        self.preferences = preferences; self.effectiveLimit = effectiveLimit
    }
}

/// Backends whitelist precisely two PowerUI preferences. Tests use in-memory
/// registers; the production backend alone has permission to write root prefs.
public protocol NativeChargeRegisters {
    func readPreferences() throws -> NativeChargePreferences
    func writePreferences(_ value: NativeChargePreferences) throws
    func effectiveLimit() throws -> Int
    func releaseLimit() throws
    func waitForApplication()
}
public enum NativeChargeError: LocalizedError {
    case invalidLimit, verificationFailed, rollbackFailed
    public var errorDescription: String? {
        switch self {
        case .invalidLimit: "Invalid native charge limit"
        case .verificationFailed: "系统充电策略未通过读回验证"
        case .rollbackFailed: "系统充电策略恢复失败；已保留恢复快照，请修复服务"
        }
    }
}

public struct NativeChargeTransaction<Registers: NativeChargeRegisters> {
    public let registers: Registers
    public init(registers: Registers) { self.registers = registers }
    public func snapshot() throws -> NativeChargeSnapshot {
        NativeChargeSnapshot(preferences: try registers.readPreferences(), effectiveLimit: try registers.effectiveLimit())
    }
    private func verify(_ state: NativeChargeSnapshot) throws {
        for attempt in 0..<20 {
            if try registers.readPreferences() == state.preferences,
               try registers.effectiveLimit() == state.effectiveLimit { return }
            if attempt < 19 { registers.waitForApplication() }
        }
        throw NativeChargeError.verificationFailed
    }
    private func apply(_ state: NativeChargeSnapshot) throws {
        if state.preferences.featureState != 1 { try registers.releaseLimit() }
        try registers.writePreferences(state.preferences)
        try verify(state)
    }
    public func replace(_ state: NativeChargeSnapshot) throws {
        guard (0...100).contains(state.effectiveLimit),
              state.preferences.limit.map({ (0...100).contains($0) }) ?? true else { throw NativeChargeError.invalidLimit }
        let before = try snapshot()
        if before == state && state.preferences.featureState == 1 { return }
        do { try apply(state) }
        catch {
            do { try apply(before) }
            catch { throw NativeChargeError.rollbackFailed }
            throw error
        }
    }
    public func set(_ limit: Int) throws {
        guard (1...100).contains(limit) else { throw NativeChargeError.invalidLimit }
        try replace(.init(preferences: .managed(limit), effectiveLimit: limit))
    }
}
