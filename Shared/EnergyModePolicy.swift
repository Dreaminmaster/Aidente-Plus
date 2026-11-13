import Foundation

public enum EnergyMode: Int, Codable, CaseIterable, Sendable {
    case automatic = 0, low = 1, high = 2
}
public enum EnergySource: String, Codable, CaseIterable, Sendable {
    case battery, adapter
    public var argument: String { self == .battery ? "-b" : "-c" }
}
public struct EnergyModeReading: Codable, Equatable, Sendable {
    public let key: String
    public let value: Int
    public init(key: String, value: Int) { self.key = key; self.value = value }
    public var mode: EnergyMode? { EnergyMode(rawValue: value) }
    public var supportsHigh: Bool { key == "powermode" }
}
public enum EnergyModePolicy {
    public static func parse(_ text: String) -> [EnergySource: EnergyModeReading] {
        var result: [EnergySource: EnergyModeReading] = [:]
        var source: EnergySource?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "Battery Power:" { source = .battery; continue }
            if trimmed == "AC Power:" { source = .adapter; continue }
            if trimmed.hasSuffix(":") { source = nil; continue }
            let fields = trimmed.split(whereSeparator: \.isWhitespace)
            guard let source, fields.count == 2, let value = Int(fields[1]) else { continue }
            if fields[0] == "powermode", (0...2).contains(value) {
                result[source] = EnergyModeReading(key: "powermode", value: value)
            } else if fields[0] == "lowpowermode", (0...1).contains(value), result[source]?.key != "powermode" {
                result[source] = EnergyModeReading(key: "lowpowermode", value: value)
            }
        }
        return result
    }
    public static func arguments(mode: EnergyMode, source: EnergySource, reading: EnergyModeReading) throws -> [String] {
        guard ["lowpowermode", "powermode"].contains(reading.key), mode != .high || reading.supportsHigh else {
            throw NSError(domain: "AidenteEnergy", code: 1, userInfo: [NSLocalizedDescriptionKey: "This power source does not support the requested energy mode."])
        }
        return [source.argument, reading.key, String(mode.rawValue)]
    }
}
