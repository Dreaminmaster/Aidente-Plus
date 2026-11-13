import Foundation
import AidenteShared

@main struct FeatureCompletionTests {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ title: String) { precondition(condition, title); count += 1 }
        let trendStart = Date(timeIntervalSince1970: 1000)
        func power(_ seconds: Double, _ watts: Double) -> DashboardReading {
            DashboardReading(timestamp: trendStart.addingTimeInterval(seconds), percentage: 80, temperature: 30, power: watts, cycles: 100, health: 95)
        }
        check(DashboardReading.averagePower([]) == nil, "Empty power history has no average")
        check(DashboardReading.averagePower([power(0, 10)]) == nil, "One observation cannot establish duration")
        check(DashboardReading.averagePower([power(40, 30), power(0, 10), power(10, 10)]) == 17.5, "Irregular intervals use time weighting, independent of input order")
        check(DashboardReading.averagePower([power(0, 10), power(15, 10), power(3600, 100), power(3615, 100)]) == 55, "Sleep gap adds neither energy nor duration")
        check(DashboardReading.averagePower([power(0, 10), power(3600, 100)]) == nil, "Long gap alone does not invent an average")
        check(DashboardReading.averagePower([power(0, 0), power(15, 0)]) == 0, "Zero power is a valid observation")
        check(DashboardReading.averagePower([power(0, .nan), power(15, 20), power(30, 20)]) == 20, "Invalid observation cannot poison later contiguous data")
        check(DashboardReading.averagePower([power(0, 10), power(0, 10), power(15, 10)]) == 10, "Duplicate timestamps add no duration")
        check(DashboardReading.averagePower([power(0, 10), power(15, 20)], maximumGap: -1) == nil, "Invalid gap rejected")
        let splitPower = PowerFlowReading(adapterConnected: true, adapterPower: 60, batteryPower: 40)!
        check(splitPower.adapter == 60 && splitPower.batteryInput == 40 && splitPower.computer == 20, "Charging splits adapter power between battery and computer")
        let holdPower = PowerFlowReading(adapterConnected: true, adapterPower: 15, batteryPower: 0)!
        check(holdPower.computer == 15 && holdPower.batteryInput == 0, "Hold sends adapter power to computer")
        let assistedPower = PowerFlowReading(adapterConnected: true, adapterPower: 20, batteryPower: -10)!
        check(assistedPower.computer == 30 && assistedPower.batteryOutput == 10, "Weak adapter merges battery assistance")
        let unpluggedPower = PowerFlowReading(adapterConnected: false, adapterPower: 20, batteryPower: -12)!
        check(unpluggedPower.adapter == 0 && unpluggedPower.computer == 12, "Unplugged state ignores stale adapter measurement")
        check(PowerFlowReading(adapterConnected: true, adapterPower: .nan, batteryPower: 5) == nil, "Unknown power stays unknown")
        check(PowerFlowReading(adapterConnected: true, adapterPower: 10, batteryPower: 30) == nil, "Inconsistent charging samples do not invent negative computer power")
        check(PowerFlowReading(adapterConnected: true, adapterPower: -1, batteryPower: 0) == nil, "Invalid source rejected")
        let componentDate = Date(timeIntervalSince1970: 2000)
        let components = ComponentPowerReading(timestamp: componentDate, soc: 4, display: nil, usb: nil)
        check(components.breakdown(total: 10, now: componentDate) == [4, nil, nil, 6], "Missing sensors are unknown, not invented zero; residual conserves measured total")
        check(components.breakdown(total: 3, now: componentDate) == nil, "Components exceeding total cannot be rescaled into a fake flow")
        check(components.breakdown(total: 10, now: componentDate.addingTimeInterval(6)) == nil, "Stale component readings are not shown as live")
        check(components.breakdown(total: 10, now: componentDate.addingTimeInterval(-2)) == nil, "Future sample rejected")
        check(components.breakdown(total: .nan, now: componentDate) == nil, "Unknown total cannot form a breakdown")
        check(ComponentPowerReading(timestamp: componentDate, soc: nil, display: nil, usb: nil).breakdown(total: 10, now: componentDate) == nil, "Unavailable hardware does not create a measured Other branch")
        check(ComponentPowerReading(timestamp: componentDate, soc: .nan, display: -1, usb: 1001).soc == nil, "Invalid sensor values rejected")
        check(ComponentPowerReading(timestamp: componentDate, soc: 0, display: 0, usb: 0).breakdown(total: 0, now: componentDate) == [0, 0, 0, 0], "Measured zeros remain distinct from unavailable")
        let hoverTimes = [0.0, 15, 30, 3600].map { trendStart.addingTimeInterval($0) }
        check(TrendSelection.nearest(in: hoverTimes, to: trendStart.addingTimeInterval(16), tolerance: 30) == 1, "Hover snaps to a real sample and preserves its actual timestamp")
        check(TrendSelection.nearest(in: hoverTimes, to: trendStart.addingTimeInterval(900), tolerance: 30) == nil, "Hover over a sleep gap never invents interpolated observations")
        check(TrendSelection.nearest(in: [], to: trendStart, tolerance: 30) == nil, "Empty history cannot show an invented hover value")
        check(TrendSelection.nearest(in: hoverTimes, to: trendStart, tolerance: -1) == nil, "Invalid selection tolerance rejected")
        let legacyData = Data("{\"timestamp\":1000,\"percentage\":80,\"temperature\":30,\"power\":0,\"cycles\":50,\"health\":95}".utf8)
        let legacyReading = try JSONDecoder().decode(DashboardReading.self, from: legacyData)
        check(legacyReading.chargeLimit == nil && legacyReading.systemPower == nil, "Old history remains readable without backfilling guessed limits or system power")
        let newReading = DashboardReading(timestamp: trendStart, percentage: 80, temperature: 30, power: 0, cycles: 50, health: 95, chargeLimit: 85, adapterPower: 20, systemPower: 20)
        check(try JSONDecoder().decode(DashboardReading.self, from: JSONEncoder().encode(newReading)) == newReading, "New history round-trips independent measured power sources and the limit")
        check(DashboardReading.retained([DashboardReading(timestamp: trendStart, percentage: 80, temperature: 30, power: 0, cycles: 50, health: 95, chargeLimit: 999)], now: trendStart).isEmpty, "Out-of-range historical limit rejected")
        var denseHistory: [DashboardReading] = []
        for i in 0..<5760 {
            let time = trendStart.addingTimeInterval(Double(i) * 15)
            let battery: Double = i == 1234 ? 100 : 1
            let adapter: Double = i == 3000 ? 120 : 10
            let system: Double = i == 4500 ? 130 : 10
            let limit: Double = i < 2500 ? 80 : 90
            denseHistory.append(DashboardReading(timestamp: time, percentage: 80, temperature: 30,
                power: battery, cycles: 50, health: 95, chargeLimit: limit, adapterPower: adapter, systemPower: system))
        }
        let renderPower = TrendChartSnapshot(samples: denseHistory, metric: .power)
        let drawnPower = renderPower.segments.flatMap { $0 }
        check(renderPower.observations.count == 5760, "Rendering budget never discards raw hover observations")
        check(drawnPower.count < 330, "Dense power history has a bounded rendering workload")
        let drawnTimes = Set(drawnPower.map(\.timestamp))
        check([1234,3000,4500].allSatisfy { drawnTimes.contains(denseHistory[$0].timestamp) }, "Battery, adapter and Mac peaks survive drawing reduction independently")
        check(renderPower.domain.upperBound > 130, "Scale derives from full measurements, not a subset")
        let renderedLimit = TrendChartSnapshot(samples: denseHistory, metric: .percentage).segments.flatMap { $0 }
        let renderedTimes = Set(renderedLimit.map(\.timestamp))
        check([2499,2500].allSatisfy { renderedTimes.contains(denseHistory[$0].timestamp) }, "Both sides of a limit transition survive reduction")
        check(drawnPower.allSatisfy { denseHistory.contains($0) }, "Drawing uses original observations, never synthetic points")
        let splitHistory = [power(0, 1), power(15, 2), power(600, 3), power(615, 4)]
        check(TrendChartSnapshot(samples: splitHistory, metric: .power).segments.count == 2, "Sleep gaps remain separate after preparing render data")
        let recorded = TrendChartSnapshot(samples: splitHistory, metric: .power, interval: DateInterval(start: trendStart.addingTimeInterval(-86400), end: trendStart.addingTimeInterval(615)), timeline: .recorded)
        check(recorded.recordedDuration == 30 && recorded.hasCollapsedIntervals, "Recorded duration excludes the 585-second empty interval")
        check(recorded.times.upperBound.timeIntervalSince(recorded.times.lowerBound) == 45, "Recorded view fits available samples with only a small break")
        check(recorded.segments.count == 2, "Compressed gaps never connect separate observation runs")
        check(recorded.nearestObservation(to: recorded.plotDate(for: splitHistory[2].timestamp)) == splitHistory[2], "Compressed hover returns the original observation and clock timestamp")
        check(recorded.actualTime(at: recorded.plotDate(for: splitHistory[2].timestamp)) == splitHistory[2].timestamp, "Compressed axis labels preserve real clock times")
        let clockInterval = DateInterval(start: trendStart.addingTimeInterval(590), end: trendStart.addingTimeInterval(615))
        let actualClock = TrendChartSnapshot(samples: splitHistory, metric: .power, interval: clockInterval)
        check(actualClock.observations.count == 2 && actualClock.times.lowerBound == clockInterval.start, "Actual-time mode scopes strictly to the requested elapsed period")
        let recordedWindow = TrendChartSnapshot(samples: splitHistory, metric: .power, interval: clockInterval, timeline: .recorded)
        check(recordedWindow.observations.count == 4, "Recorded-time mode can include older sessions to fill the requested usage duration")
        check(DashboardReading.retained([power(0, 1)], now: trendStart.addingTimeInterval(2 * 86400)).count == 1, "Available earlier sessions survive a two-day inactive period")
        let singleRecord = TrendChartSnapshot(samples: [power(0,1)], metric: .power, timeline: .recorded)
        check(singleRecord.nearestObservation(to: singleRecord.plotDate(for: trendStart)) != nil && singleRecord.times.upperBound.timeIntervalSince(singleRecord.times.lowerBound) > 0, "A single record has a valid fitted domain and hover")
        let appNames = ["chrome":"Google Chrome", "safari":"Safari", "chat":"ChatGPT", "finder":"Finder", "mail":"Mail", "music":"Music"]
        let stableApps = AppListOrder.orderedIDs(names: appNames)
        check(stableApps.count == 6, "Application list ordering does not silently cap the list to four")
        check(stableApps == AppListOrder.orderedIDs(names: Dictionary(uniqueKeysWithValues: appNames.reversed())), "Sampling order cannot reorder click targets")
        check(stableApps.first == "chat" && stableApps.contains("safari"), "Idle applications remain in the complete input list")
        check(AppListOrder.presentationIDs(current: stableApps, incoming: ["new"] + stableApps, interacting: true) == stableApps, "A newly running app cannot push rows under the pointer")
        check(AppListOrder.presentationIDs(current: stableApps, incoming: ["chrome"], interacting: true) == stableApps, "Removal is deferred while hovering or confirming Quit")
        check(AppListOrder.presentationIDs(current: stableApps, incoming: ["chrome"], interacting: false) == ["chrome"], "Leaving the list applies the updated membership")
        check(AppListOrder.presentationIDs(current: [], incoming: stableApps, interacting: true) == stableApps, "Hovering the initial placeholder cannot prevent the first list from loading")
        var appPolicy = EnergyActivityPolicy()
        func appSample(_ cpu: Double?, _ watts: Double? = nil) -> [EnergyAppObservation] { [EnergyAppObservation(id: "app", cpu: cpu, watts: watts)] }
        check(appPolicy.update(appSample(nil), threshold: 5, now: 0).isEmpty, "An unmeasured first observation never creates a high usage app")
        check(appPolicy.update(appSample(8), threshold: 5, now: 2).count == 1, "A valid high CPU interval appears promptly")
        check(appPolicy.update(appSample(4.8), threshold: 5, now: 4).count == 1, "A small threshold crossing cannot flicker the app off")
        check(appPolicy.update(appSample(0), threshold: 5, now: 6).count == 1, "One quiet interval does not remove an active app")
        var quiet: [EnergyAppActivity] = []
        for time in stride(from: 8.0, through: 30.0, by: 2) { quiet = appPolicy.update(appSample(0), threshold: 5, now: time) }
        check(quiet.isEmpty, "Sustained quiet use eventually removes the app")
        _ = appPolicy.update(appSample(20), threshold: 5, now: 32)
        check(appPolicy.update([], threshold: 5, now: 34).isEmpty, "An exited process disappears immediately, without retaining stale rows")
        _ = appPolicy.update(appSample(20), threshold: 5, now: 36)
        check(appPolicy.update(appSample(0), threshold: 5, now: 60).isEmpty, "Reopening after a long gap cannot reuse old activity")
        var meteredPolicy = EnergyActivityPolicy()
        let metered = meteredPolicy.update(appSample(20,0.2), threshold: 5, now: 0)
        let brieflyUnavailable = meteredPolicy.update(appSample(20), threshold: 5, now: 2)
        check(metered.count == 1 && brieflyUnavailable.first?.watts == 0.2, "One unavailable energy counter does not switch the display to CPU")
        check(meteredPolicy.update(appSample(20), threshold: 5, now: 8).first?.watts == nil, "Expired energy estimates are dropped rather than displayed as current")
        check(meteredPolicy.update(appSample(20,0), threshold: 5, now: 10).count == 1, "A CPU-active app remains visible when energy counters report zero")
        check(meteredPolicy.update(appSample(0), threshold: 20, now: 12).isEmpty, "Changing the filter level resets prior membership")
        var dedupPolicy = EnergyActivityPolicy()
        _ = dedupPolicy.update(appSample(10), threshold: 5, now: 0)
        check(dedupPolicy.update(appSample(0), threshold: 5, now: 0.2).first?.cpu == 10, "Overlapping refreshes cannot count as consecutive low intervals")
        let cpuBefore = ProcessActivityReading(processStart: 1, userTime: 100, systemTime: 100, uptime: 1)
        let cpuAfter = ProcessActivityReading(processStart: 1, userTime: 1_000_000_100, systemTime: 1_000_000_100, uptime: 3)
        check(cpuAfter.cpuPercentage(since: cpuBefore) == 100, "Recent CPU derives from interval, not process lifetime")
        check(ProcessActivityReading(processStart: 1, userTime: 4_000_000_100, systemTime: 100, uptime: 3).cpuPercentage(since: cpuBefore) == 200, "Multi-core CPU above 100 percent remains valid")
        check(ProcessActivityReading(processStart: 2, userTime: 100, systemTime: 100, uptime: 3).cpuPercentage(since: cpuBefore) == nil, "Reused PID cannot inherit previous CPU activity")
        check(ProcessActivityReading(processStart: 1, userTime: 0, systemTime: 100, uptime: 3).cpuPercentage(since: cpuBefore) == nil, "Counter rollback rejected")
        check(ProcessActivityReading(processStart: 1, userTime: 100, systemTime: 100, uptime: 40).cpuPercentage(since: cpuBefore) == nil, "Sleeping gap cannot create recent CPU usage")
        let machBefore = ProcessActivityReading(processStart: 1, userTime: 100, systemTime: 100, uptime: 1, nanosecondsPerTick: 10)
        let machAfter = ProcessActivityReading(processStart: 1, userTime: 100_000_100, systemTime: 100_000_100, uptime: 3, nanosecondsPerTick: 10)
        check(machAfter.cpuPercentage(since: machBefore) == 100, "Apple Silicon Mach ticks convert using host timebase")
        let text = "Battery Power:\n lowpowermode 1\nAC Power:\n lowpowermode 0\n powermode 2\nUPS Power:\n powermode 0\n"
        let modes = EnergyModePolicy.parse(text)
        check(modes[.battery]?.mode == .low, "Battery source parsed")
        check(modes[.adapter]?.mode == .high, "Power mode wins over low-power fallback")
        check(EnergyModePolicy.parse("Battery Power:\n lowpowermode 99").isEmpty, "Invalid modes rejected")
        check(try EnergyModePolicy.arguments(mode: .low, source: .battery, reading: modes[.battery]!) == ["-b", "lowpowermode", "1"], "Fixed command arguments")
        do { _ = try EnergyModePolicy.arguments(mode: .high, source: .battery, reading: modes[.battery]!); preconditionFailure("Unsupported high mode accepted") }
        catch { count += 1 }
        do { _ = try EnergyModePolicy.arguments(mode: .low, source: .adapter, reading: EnergyModeReading(key: "; rm", value: 0)); preconditionFailure("Invalid key accepted") }
        catch { count += 1 }

        let suite = "com.aidente.tests.energy." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var battery = 0, adapter = 1, operations: [[String]] = [], corruptReadback = false
        let controller = EnergyModeController(defaults: defaults, runner: { args in
            operations.append(args)
            if args == ["-g", "custom"] {
                if corruptReadback { corruptReadback = false; return "Battery Power:\n lowpowermode 0\nAC Power:\n lowpowermode \(adapter)" }
                return "Battery Power:\n lowpowermode \(battery)\nAC Power:\n lowpowermode \(adapter)"
            }
            guard args.count == 3, args[1] == "lowpowermode", let value = Int(args[2]) else { throw CocoaError(.fileReadCorruptFile) }
            if args[0] == "-b" { battery = value } else if args[0] == "-c" { adapter = value } else { throw CocoaError(.fileReadCorruptFile) }
            return ""
        })
        try controller.set(mode: .low, source: .battery)
        check(battery == 1, "Energy change applied via injected command runner")
        check(defaults.data(forKey: "energyModesBeforeAidente") != nil, "Original energy mode persisted before write")
        try controller.restore()
        check(battery == 0 && adapter == 1, "Restoration retains original per-source settings")
        check(defaults.data(forKey: "energyModesBeforeAidente") == nil, "Snapshot cleared only after readback")
        corruptReadback = true // First read sees baseline, so arm failure after the write with another runner.
        var failureBattery = 0, afterWrite = false
        let failing = EnergyModeController(defaults: defaults, runner: { args in
            if args == ["-g", "custom"] {
                return "Battery Power:\n lowpowermode \(afterWrite ? 0 : failureBattery)\nAC Power:\n lowpowermode 0"
            }
            failureBattery = Int(args[2])!; afterWrite = args[2] == "1"; return ""
        })
        do { try failing.set(mode: .low, source: .battery); preconditionFailure("Failed readback reported success") }
        catch { count += 1 }
        check(failureBattery == 0, "Failed energy change rolls back")
        check(defaults.data(forKey: "energyModesBeforeAidente") != nil, "Failure preserves original settings for repair")

        var sleep = SleepControlPolicy()
        let now = Date(timeIntervalSince1970: 0)
        sleep.start(minutes: 30, now: now)
        check(sleep.active(now: now, percentage: 80, threshold: 20, adapterConnected: false, stopOnUnplug: false), "Manual keep-awake works on battery when enabled")
        check(!sleep.active(now: now.addingTimeInterval(1800), percentage: 80, threshold: 20, adapterConnected: true, stopOnUnplug: false), "Duration expires at exact boundary")
        sleep.start(minutes: nil, now: now)
        check(!sleep.active(now: now, percentage: 20, threshold: 20, adapterConnected: true, stopOnUnplug: false), "Low battery always ends manual keep-awake")
        sleep.start(minutes: nil, now: now)
        check(!sleep.active(now: now, percentage: 80, threshold: 20, adapterConnected: false, stopOnUnplug: true), "Unplug condition ends manual control")
        check(MagSafePolicy.target(enabled: true, mode: 2, sleeping: true, discharging: false, blinkDuringDischarge: false, requested: 3) == 1, "Sleep LED policy turns off")
        check(MagSafePolicy.target(enabled: true, mode: 2, sleeping: false, discharging: false, blinkDuringDischarge: false, requested: 3) == 3, "Wake restores requested LED")
        check(MagSafePolicy.target(enabled: false, mode: 1, sleeping: true, discharging: true, blinkDuringDischarge: true, requested: 3) == 0, "Disabled LED management restores system control")
        check(MagSafePolicy.target(enabled: true, mode: 0, sleeping: false, discharging: true, blinkDuringDischarge: true, requested: 3) == 6, "Explicit discharge blinking")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let january = date(2026,1,31)
        let february = ScheduleRecurrence.next(after: january, previous: january, rule: "monthly", weekdays: [], anchorDay: 31, anchorMonth: 1, calendar: calendar)!
        check(february == date(2026,2,28), "Monthly 31st clamps to last day")
        check(ScheduleRecurrence.next(after: february, previous: february, rule: "monthly", weekdays: [], anchorDay: 31, anchorMonth: 1, calendar: calendar) == date(2026,3,31), "Monthly anchor does not drift after February")
        let leap = date(2024,2,29)
        check(ScheduleRecurrence.next(after: date(2025,1,1), previous: leap, rule: "yearly", weekdays: [], anchorDay: 29, anchorMonth: 2, calendar: calendar) == date(2025,2,28), "Yearly leap-day clamp")
        check(ScheduleRecurrence.next(after: date(2028,1,1), previous: leap, rule: "yearly", weekdays: [], anchorDay: 29, anchorMonth: 2, calendar: calendar) == date(2028,2,29), "Leap-day anchor restored in leap years")
        let monday = date(2026,11,2)
        check(ScheduleRecurrence.next(after: monday, previous: monday, rule: "weekly", weekdays: [2,4,6], anchorDay: nil, anchorMonth: nil, calendar: calendar) == date(2026,11,4), "Multiple weekdays honored")
        check(ScheduleRecurrence.next(after: date(2026,11,6), previous: monday, rule: "weekdays", weekdays: [], anchorDay: nil, anchorMonth: nil, calendar: calendar) == date(2026,11,9), "Weekdays skip weekend")
        check(ScheduleRecurrence.next(after: monday, previous: monday, rule: "biweekly", weekdays: [], anchorDay: nil, anchorMonth: nil, calendar: calendar) == date(2026,11,16), "Biweekly recurrence")
        check(ScheduleRecurrence.next(after: monday, previous: monday, rule: "never", weekdays: [], anchorDay: nil, anchorMonth: nil, calendar: calendar) == nil, "One-shot task deactivates")
        check(GaugingLogParser.active(message: "SOC limit policy suspend due to mitigation active:1", process: "powerd") == true, "Explicit powerd mitigation start")
        check(GaugingLogParser.active(message: "SOC limit policy suspend due to mitigation active:0", process: "powerd") == false, "Explicit powerd mitigation release")
        check(GaugingLogParser.active(message: "ChargingUpForGauging = false", process: "PowerUIAgent") == false, "Negative gauging value never becomes a start")
        check(GaugingLogParser.active(message: "ChargingUpForGauging: true", process: "/usr/libexec/PowerUIAgent") == true, "PowerUIAgent process path accepted")
        check(GaugingLogParser.active(message: "Battery mitigations are in place, MCL will be ignored", process: "PowerUIAgent") == true, "Vendor-documented mitigation evidence")
        check(GaugingLogParser.active(message: "GaugingMitigationActions", process: "powerd") == nil, "Routine hourly job is not calibration evidence")
        check(GaugingLogParser.active(message: "chargeControl charge to full requested:1", process: "powerd") == nil, "Generic full-charge request is not calibration evidence")
        check(GaugingLogParser.active(message: "ChargingUpForGauging: true", process: "other") == nil, "Unrelated process cannot start recovery")
        check(GaugingLogParser.active(message: "ChargingUpForGauging unavailable", process: "PowerUIAgent") == nil, "Ambiguous evidence stays unknown")
        var session = SystemCalibrationSession()
        session.observe(GaugingEvent(date: now.addingTimeInterval(-121), active: true), now: now)
        check(!session.pending, "Old log records do not lock controls or cause a discharge")
        session.observe(GaugingEvent(date: now.addingTimeInterval(10), active: true), now: now)
        check(!session.pending, "Future log records rejected")
        session.observe(GaugingEvent(date: now, active: true), now: now)
        check(session.pending && !session.canContinue, "Fresh start waits without discharge")
        session.sample(full: true, sampleDate: now.addingTimeInterval(1), now: now.addingTimeInterval(1))
        session.sample(full: true, sampleDate: now.addingTimeInterval(1), now: now.addingTimeInterval(1))
        check(session.fullSamples == 1, "Repeated samples cannot manufacture full confirmation")
        session.sample(full: true, sampleDate: now.addingTimeInterval(2), now: now.addingTimeInterval(50))
        check(session.fullSamples == 1, "Stale full readings rejected")
        session.sample(full: false, sampleDate: now.addingTimeInterval(3), now: now.addingTimeInterval(3))
        check(session.fullSamples == 0, "Interrupted full confirmation restarts")
        for second in 4...6 { session.sample(full: true, sampleDate: now.addingTimeInterval(Double(second)), now: now.addingTimeInterval(Double(second))) }
        check(session.waitingForRelease && session.canContinue, "Confirmed full charge permits handoff even before Apple clears its override flag")
        let persisted = try JSONEncoder().encode(session)
        session = try JSONDecoder().decode(SystemCalibrationSession.self, from: persisted)
        check(session.waitingForRelease, "Pending system calibration survives restart")
        session.observe(GaugingEvent(date: now.addingTimeInterval(7), active: false), now: now.addingTimeInterval(7))
        check(session.canContinue, "Release and confirmed full charge permit the selected follow-up")
        session.finish()
        check(!session.pending && !session.canContinue, "Follow-up consumed once")
        session.observe(GaugingEvent(date: now, active: true), now: now.addingTimeInterval(8))
        check(!session.pending, "Consumed start cannot replay on log polling")
        var interrupted = SystemCalibrationSession()
        interrupted.observe(GaugingEvent(date: now, active: true), now: now)
        interrupted.observe(GaugingEvent(date: now.addingTimeInterval(1), active: false), now: now.addingTimeInterval(1))
        interrupted.finishIfInterrupted(percentage: 80, isCharging: false)
        check(!interrupted.pending && !interrupted.canContinue, "Interrupted OS calibration unlocks controls without a discharge")
        session.observe(GaugingEvent(date: now.addingTimeInterval(9), active: true), now: now.addingTimeInterval(9))
        session.finishIfInterrupted(percentage: 80, isCharging: false)
        check(session.pending, "No release cannot be mistaken for an aborted OS calibration")
        check(SystemCalibrationFollowUp.stage(current: .idle, preference: .dischargeToLimit) == .restoringLimit, "Default OS follow-up never adds a deep calibration cycle")
        check(SystemCalibrationFollowUp.stage(current: .idle, preference: .continueCalibration) == .dischargingToLow, "Explicit full-calibration preference continues the remaining stages")
        check(SystemCalibrationFollowUp.stage(current: .chargingToFull, preference: .dischargeToLimit) == .dischargingToLow, "An already requested user calibration continues correctly")
        check(SystemCalibrationFollowUp.stage(current: .rechargingToFull, preference: .continueCalibration) == .restoringLimit, "Second full charge cannot restart a deep cycle")
        check(SystemCalibrationFollowUp.stage(current: .holdingAtFull, preference: .continueCalibration) == .restoringLimit, "Legacy final hold restores instead of repeating a cycle")
        let retainedNow = Date(timeIntervalSince1970: 100000)
        func reading(_ seconds: Double, power: Double = 5) -> DashboardReading {
            DashboardReading(timestamp: retainedNow.addingTimeInterval(seconds), percentage: 80, temperature: 30, power: power, cycles: 59, health: 99)
        }
        check(DashboardReading.retained([reading(-30 * 86400 - 1), reading(-10)], now: retainedNow).count == 1, "Trend archive drops records older than 30 days")
        check(DashboardReading.retained([reading(-10), reading(-10)], now: retainedNow).count == 1, "Trend replay does not duplicate timestamps")
        check(DashboardReading.retained([reading(60), reading(-10, power: .nan)], now: retainedNow).isEmpty, "Future and invalid trends cannot corrupt charts")
        let unordered = DashboardReading.retained([reading(-1), reading(-20)], now: retainedNow)
        check(unordered.first?.timestamp == retainedNow.addingTimeInterval(-20), "Restored chart history is chronological")
        let archive = try JSONEncoder().encode(unordered)
        check(try JSONDecoder().decode([DashboardReading].self, from: archive) == unordered, "Actual trend samples survive a persistence round trip")
        check(NativeGaugingSignal.active(value: 0, trustedInCurrentBoot: false) == nil, "Missing native publication cannot fabricate a release")
        check(NativeGaugingSignal.active(value: 1, trustedInCurrentBoot: false) == true, "Native positive evidence starts observation")
        check(NativeGaugingSignal.active(value: 0, trustedInCurrentBoot: true) == false, "Native release requires same-boot positive evidence")
        check(NativeGaugingSignal.active(value: 2, trustedInCurrentBoot: true) == nil, "Unknown native schema remains unknown")
        let metadataNow = Date(timeIntervalSince1970: 1793713687), fullDate = Date(timeIntervalSince1970: 1793200000)
        check(GaugingMetadata.lastFullCharge(in: ["lastFullCharge": fullDate.timeIntervalSince1970], now: metadataNow) == fullDate, "System full-charge Unix timestamp")
        check(GaugingMetadata.lastFullCharge(in: ["lastFullCharge": fullDate.timeIntervalSinceReferenceDate], now: metadataNow) == fullDate, "System full-charge CF timestamp")
        check(GaugingMetadata.lastFullCharge(in: ["lastFullChargeDate": fullDate], now: metadataNow) == fullDate, "System full-charge plist date")
        check(GaugingMetadata.lastFullCharge(in: ["lastFullCharge": 0], now: metadataNow) == nil, "Missing system full date stays unavailable")
        check(GaugingMetadata.lastFullCharge(in: ["lastFullCharge": metadataNow.timeIntervalSince1970 + 10000], now: metadataNow) == nil, "Future full charge date rejected")
        var retainedOverride = SystemCalibrationSession()
        retainedOverride.observe(GaugingEvent(date: now, active: true), now: now)
        for second in 1...3 { retainedOverride.sample(full: true, sampleDate: now.addingTimeInterval(Double(second)), now: now.addingTimeInterval(Double(second))) }
        retainedOverride.finish()
        retainedOverride.observe(GaugingEvent(date: now.addingTimeInterval(4), active: true), now: now.addingTimeInterval(4))
        check(!retainedOverride.pending && retainedOverride.handoffPendingRelease, "A retained Apple override cannot restart a second calibration cycle")
        retainedOverride.observe(GaugingEvent(date: now.addingTimeInterval(5), active: false), now: now.addingTimeInterval(5))
        check(!retainedOverride.handoffPendingRelease, "Explicit release re-arms the next distinct calibration")
        retainedOverride.observe(GaugingEvent(date: now.addingTimeInterval(6), active: true), now: now.addingTimeInterval(6))
        check(retainedOverride.pending, "A distinct later Apple calibration can be observed")
        var lowSailing = ChargeLimitPolicy()
        check(lowSailing.evaluate(percentage: 19, limit: 25, sailing: true, sailingRange: 20, automaticDischarge: false, initialize: true).charging, "Sailing never holds below 20 percent")
        check(lowSailing.evaluate(percentage: 24, limit: 25, sailing: true, sailingRange: 20, automaticDischarge: false, initialize: false).charging, "Low battery recovery continues to upper limit")
        check(!lowSailing.evaluate(percentage: 25, limit: 25, sailing: true, sailingRange: 20, automaticDischarge: false, initialize: false).charging, "Low recovery stops at limit")
        print("PASS: \(count) feature-policy and energy rollback checks (no hardware writes)")
    }
}
