import Foundation

public struct ProcessActivityReading: Sendable {
    public let processStart, userTime, systemTime: UInt64
    public let uptime, nanosecondsPerTick: Double
    public init(processStart: UInt64, userTime: UInt64, systemTime: UInt64, uptime: Double, nanosecondsPerTick: Double = 1) {
        self.processStart = processStart; self.userTime = userTime
        self.systemTime = systemTime; self.uptime = uptime; self.nanosecondsPerTick = nanosecondsPerTick
    }
    public func cpuPercentage(since previous: Self) -> Double? {
        let duration = uptime - previous.uptime
        guard processStart == previous.processStart, nanosecondsPerTick.isFinite, nanosecondsPerTick > 0, nanosecondsPerTick == previous.nanosecondsPerTick, duration.isFinite, duration >= 0.5, duration <= 30,
              userTime >= previous.userTime, systemTime >= previous.systemTime else { return nil }
        let nanos = Double(userTime - previous.userTime) + Double(systemTime - previous.systemTime)
        return nanos * nanosecondsPerTick / (duration * 1_000_000_000) * 100
    }
}
