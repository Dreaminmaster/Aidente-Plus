import Foundation

public struct GaugingEvent: Equatable, Sendable {
    public let date: Date
    public let active: Bool
    public init(date: Date, active: Bool) { self.date = date; self.active = active }
}

/// Only accepts gauging-specific records. Charging above a limit, routine hourly
/// gauging checks, charge-to-full requests and missing logs are not evidence.
public enum GaugingLogParser {
    public static func active(message: String, process: String) -> Bool? {
        let process = URL(fileURLWithPath: process).lastPathComponent
        guard process == "PowerUIAgent" || process == "powerd" else { return nil }
        let message = message.lowercased()
        let patterns = process == "PowerUIAgent"
            ? [#"chargingupforgauging\s*[:=]\s*(true|false|yes|no|1|0)\b"#]
            : [#"soc limit policy suspend due to mitigation active:\s*(1|0)\b"#]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
                  let range = Range(match.range(at: 1), in: message) else { continue }
            return ["true", "yes", "1"].contains(String(message[range]))
        }
        if process == "PowerUIAgent" && message.contains("battery mitigations are in place, mcl will be ignored") { return true }
        return nil
    }
}

public enum AfterSystemCalibration: String, Codable, CaseIterable, Sendable {
    case dischargeToLimit, continueCalibration
}

/// Fresh explicit evidence identifies Apple's full-charge phase. Three distinct
/// full-charge samples permit handoff; Apple may retain its override until the
/// adapter is internally disconnected. Suppress replay until an explicit release.
public struct SystemCalibrationSession: Codable, Equatable, Sendable {
    public private(set) var startedAt: Date?
    public private(set) var latestEvent: Date?
    public private(set) var released = false
    public private(set) var handoffPendingRelease = false
    public private(set) var fullSamples = 0
    public private(set) var latestSample: Date?
    public init() {}
    public var pending: Bool { startedAt != nil }
    public var waitingForRelease: Bool { pending && fullSamples >= 3 && !released }
    public mutating func observe(_ event: GaugingEvent, now: Date) {
        guard event.date <= now.addingTimeInterval(5), now.timeIntervalSince(event.date) <= 120,
              latestEvent.map({ event.date > $0 }) ?? true else { return }
        latestEvent = event.date
        if event.active {
            guard !handoffPendingRelease else { return }
            if startedAt == nil { startedAt = event.date; fullSamples = 0; latestSample = nil }
            released = false
        } else {
            handoffPendingRelease = false
            if pending { released = true }
        }
    }
    public mutating func sample(full: Bool, sampleDate: Date?, now: Date) {
        guard pending, fullSamples < 3, let sampleDate, sampleDate > (latestSample ?? .distantPast),
              sampleDate >= (startedAt ?? now), now.timeIntervalSince(sampleDate) >= 0,
              now.timeIntervalSince(sampleDate) <= 10 else { return }
        latestSample = sampleDate
        if full { fullSamples = min(3, fullSamples + 1) }
        else if fullSamples < 3 { fullSamples = 0 }
    }
    public mutating func finishIfInterrupted(percentage: Int, isCharging: Bool) {
        if pending && released && fullSamples < 3 && percentage < 99 && !isCharging { finish() }
    }
    public var canContinue: Bool { pending && fullSamples >= 3 }
    public mutating func finish() {
        // Do not restart the same calibration if the OS keeps publishing 1
        // while the chosen follow-up disconnects the adapter to release it.
        handoffPendingRelease = pending && !released
        startedAt = nil; released = false; fullSamples = 0; latestSample = nil
    }
}

public enum SystemCalibrationFollowUp {
    public static func stage(current: CalibrationProgress, preference: AfterSystemCalibration) -> CalibrationProgress {
        switch current {
        case .rechargingToFull, .holdingAtFull, .restoringLimit: return .restoringLimit
        case .chargingToFull, .dischargingToLow: return .dischargingToLow
        case .idle: return preference == .continueCalibration ? .dischargingToLow : .restoringLimit
        }
    }
}

/// State zero is accepted only after this boot has supplied positive native
/// evidence. An unregistered/unsupported notification can otherwise also read 0.
public enum NativeGaugingSignal {
    public static func active(value: UInt64?, trustedInCurrentBoot: Bool) -> Bool? {
        if value == 1 { return true }
        if value == 0 && trustedInCurrentBoot { return false }
        return nil
    }
}
