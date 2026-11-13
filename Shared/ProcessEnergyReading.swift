import Foundation

public struct ProcessEnergyReading: Sendable {
    public let processStart: UInt64
    public let nanojoules: UInt64
    public let uptime: Double
    public init(processStart: UInt64, nanojoules: UInt64, uptime: Double) {
        self.processStart = processStart; self.nanojoules = nanojoules; self.uptime = uptime
    }
    /// Kernel per-process energy estimate, not whole-system watts attributed to
    /// an app and not Activity Monitor's proprietary Energy Impact score.
    public func averageWatts(since previous: Self) -> Double? {
        let elapsed = uptime - previous.uptime
        guard processStart == previous.processStart, uptime.isFinite, previous.uptime.isFinite,
              (1...60).contains(elapsed), nanojoules >= previous.nanojoules else { return nil }
        let watts = Double(nanojoules - previous.nanojoules) / 1_000_000_000 / elapsed
        guard watts.isFinite, watts >= 0 else { return nil }
        return watts
    }
}
