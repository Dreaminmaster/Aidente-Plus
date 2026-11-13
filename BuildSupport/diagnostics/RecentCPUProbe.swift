import Foundation
import Darwin
import AidenteShared
func reading() -> ProcessActivityReading {
    var raw = rusage_info_v6(); var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
    let status = withUnsafeMutablePointer(to: &raw) { proc_pid_rusage(getpid(), RUSAGE_INFO_V6, UnsafeMutableRawPointer($0).assumingMemoryBound(to: rusage_info_t?.self)) }
    precondition(status == 0)
    return ProcessActivityReading(processStart: raw.ri_proc_start_abstime, userTime: raw.ri_user_time, systemTime: raw.ri_system_time, uptime: ProcessInfo.processInfo.systemUptime, nanosecondsPerTick: Double(tb.numer)/Double(tb.denom))
}
let before = reading()
var token: UInt64 = 1
let stop = ProcessInfo.processInfo.systemUptime + 0.55
while ProcessInfo.processInfo.systemUptime < stop { token = token &* 1664525 &+ 1013904223 }
let after = reading()
let usage = after.cpuPercentage(since: before)!
print(String(format: "Recent CPU %.1f%%; timebase %.6f; token %llu", usage, after.nanosecondsPerTick, token))
precondition((60...120).contains(usage), "CPU unit conversion inconsistent with one busy thread")
