import Foundation

/// Active limits reported by powerd, separate from PowerUI's configured limit.
public struct NativeChargeRegistration: Equatable, Sendable {
    public let percentage: Int
    public let reason: String?
    public let allowsDrain: Bool?
    public let isEndOfCharge: Bool?

    public static func read() -> [Self]? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "battlimit"]
        process.environment = ["LC_ALL": "C"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 3)
        timer.setEventHandler { if process.isRunning { process.terminate() } }
        timer.resume()
        defer { timer.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count < 65_536 else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ report: String) -> [Self]? {
        let text = report.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "No battery level limits set" { return [] }
        let header = "Battery level limits:"
        guard text.hasPrefix(header),
              let entries = try? PropertyListSerialization.propertyList(
                from: Data(text.dropFirst(header.count).utf8), options: [], format: nil
              ) as? [[String: String]] else { return nil }
        var active: [Self] = []
        for entry in entries {
            if entry["Terminated"] == "1" { continue }
            guard entry["Terminated"] == "0",
                  let percentage = entry["chargeSocLimitSoc"].flatMap(Int.init),
                  (1...100).contains(percentage) else { return nil }
            let registration = Self(
                percentage: percentage,
                reason: entry["chargeSocLimitReason"],
                allowsDrain: parseFlag(entry["chargeSocLimitDrain"]),
                isEndOfCharge: parseFlag(entry["chargeSocLimitIsEOC"])
            )
            if !active.contains(registration) { active.append(registration) }
        }
        return active
    }

    private static func parseFlag(_ value: String?) -> Bool? {
        switch value {
        case "1": true
        case "0": false
        default: nil
        }
    }
}
