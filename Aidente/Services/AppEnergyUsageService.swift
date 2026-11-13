import AppKit
import Foundation
import Darwin
import AidenteShared

struct AppEnergyUsageSnapshot: Identifiable, Sendable {
    let bundlePath: String
    let name: String
    let cpuUsage: Double
    var isBackground = false
    var estimatedWatts: Double? = nil
    var isSampling = false
    var measurementText: String {
        if isSampling { return AidenteL10n.t("采样中…", "Sampling…") }
        if let watts = estimatedWatts {
            let power = watts < 0.005 ? "<0.01 W" : String(format: "≈%.2f W", watts)
            return power + String(format: " · %.0f%% CPU", cpuUsage)
        }
        return String(format: "%.0f%% CPU", cpuUsage)
    }

    var id: String { bundlePath }
}

private final class ProcessEnergySampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: [pid_t: ProcessEnergyReading] = [:]
    private var activity: [pid_t: ProcessActivityReading] = [:]
    private let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(max(1, info.denom))
    }()
    private var latest: [pid_t: (watts: Double?, cpu: Double?)] = [:]
    func sample(pid: pid_t, now: Double) -> (watts: Double?, cpu: Double?) {
        var info = rusage_info_v6()
        let status = withUnsafeMutablePointer(to: &info) {
            proc_pid_rusage(pid, RUSAGE_INFO_V6, UnsafeMutableRawPointer($0).assumingMemoryBound(to: rusage_info_t?.self))
        }
        guard status == 0 else { return (nil, nil) }
        let current = ProcessEnergyReading(processStart: info.ri_proc_start_abstime, nanojoules: info.ri_energy_nj, uptime: now)
        let cpu = ProcessActivityReading(processStart: info.ri_proc_start_abstime, userTime: info.ri_user_time, systemTime: info.ri_system_time, uptime: now, nanosecondsPerTick: timebase)
        lock.lock(); defer { lock.unlock() }
        let before = previous[pid]
        if let before, current.processStart == before.processStart, now - before.uptime < 1 { return latest[pid] ?? (nil,nil) }
        let watts = before.flatMap { $0.nanojoules > 0 && current.nanojoules > 0 ? current.averageWatts(since: $0) : nil }
        let usage = activity[pid].flatMap { cpu.cpuPercentage(since: $0) }
        previous[pid] = current; activity[pid] = cpu
        latest[pid] = (watts, usage)
        return (watts, usage)
    }
    func prune(now: Double) {
        lock.lock(); defer { lock.unlock() }
        previous = previous.filter { now - $0.value.uptime <= 60 }
        activity = activity.filter { previous[$0.key] != nil }
        latest = latest.filter { previous[$0.key] != nil }
    }
}

enum AppEnergyUsageService {
    private static let sampler = ProcessEnergySampler()
    private static let scanLock = NSLock()
    private static var activityPolicy = EnergyActivityPolicy()
    static func readTopApps(limit: Int = Int.max, minimumCPU: Double = 0, includeBackground: Bool = false, stabilize: Bool = true, onlySignificant: Bool = true) -> [AppEnergyUsageSnapshot]? {
        scanLock.lock(); defer { scanLock.unlock() }
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-wwaxo", "pid=,uid=,%cpu=,comm="]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["LC_ALL": "C"]
        ) { _, newValue in newValue }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let text = String(decoding: data, as: UTF8.self)
        var totals: [String: (name: String, cpuUsage: Double, background: Bool, watts: Double?, complete: Bool, measured: Bool)] = [:]
        let now = ProcessInfo.processInfo.systemUptime
        sampler.prune(now: now)

        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(
                maxSplits: 3,
                whereSeparator: \.isWhitespace
            )
            guard fields.count == 4, let processIdentifier = pid_t(fields[0]),
                  let uid = UInt32(fields[1]), uid == getuid(),
                  let processCPU = Double(fields[2]), processCPU.isFinite, processCPU >= 0 else { continue }
            let command = String(fields[3])
            let measurement = sampler.sample(pid: processIdentifier, now: now)
            let watts = measurement.watts
            let cpuUsage = measurement.cpu ?? 0 // first observation is a baseline, never lifetime ps CPU
            if let app = appIdentity(processIdentifier: processIdentifier, command: command) {
                guard !onlySignificant || app.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
                let current = totals[app.bundlePath]?.cpuUsage ?? 0
                let old = totals[app.bundlePath]
                totals[app.bundlePath] = (app.name, current + cpuUsage, false,
                    (old?.watts ?? 0) + (watts ?? 0), (old?.complete ?? true) && watts != nil, (old?.measured ?? false) || measurement.cpu != nil || watts != nil)
            } else if includeBackground {
                let name = URL(fileURLWithPath: command).lastPathComponent
                let current = totals[command]?.cpuUsage ?? 0
                let old = totals[command]
                totals[command] = (name, current + cpuUsage, true,
                    (old?.watts ?? 0) + (watts ?? 0), (old?.complete ?? true) && watts != nil, (old?.measured ?? false) || measurement.cpu != nil || watts != nil)
            }
        }

        if !onlySignificant {
            var rows: [String: AppEnergyUsageSnapshot] = [:]
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
                guard let url = app.bundleURL.flatMap(outermostApplicationURL), let name = sanitizedDisplayName(app.localizedName) else { continue }
                let key = url.path, measured = totals[key]
                rows[key] = AppEnergyUsageSnapshot(bundlePath: key, name: name, cpuUsage: measured?.cpuUsage ?? 0, estimatedWatts: measured?.complete == true ? measured?.watts : nil, isSampling: measured?.measured != true)
            }
            if includeBackground {
                for (key, value) in totals where rows[key] == nil {
                    rows[key] = AppEnergyUsageSnapshot(bundlePath: key, name: value.name, cpuUsage: value.cpuUsage, isBackground: true, estimatedWatts: value.complete ? value.watts : nil, isSampling: !value.measured)
                }
            }
            return ordered(Array(rows.values), limit: limit)
        }
        guard totals.values.contains(where: { $0.measured }) else { return nil }
        if !stabilize {
            return totals.map { AppEnergyUsageSnapshot(bundlePath: $0.key, name: $0.value.name, cpuUsage: $0.value.cpuUsage, isBackground: $0.value.background, estimatedWatts: $0.value.complete ? $0.value.watts : nil) }
                .sorted { $0.cpuUsage > $1.cpuUsage }.prefix(max(0,limit)).map { $0 }
        }
        let observations = totals.map { EnergyAppObservation(id: $0.key, cpu: $0.value.measured ? $0.value.cpuUsage : nil, watts: $0.value.complete ? $0.value.watts : nil) }
        let eligible = activityPolicy.update(observations, threshold: max(1,minimumCPU), now: now, limit: Int.max).compactMap { app -> AppEnergyUsageSnapshot? in
            guard let identity = totals[app.id] else { return nil }
            return AppEnergyUsageSnapshot(bundlePath: app.id, name: identity.name, cpuUsage: app.cpu, isBackground: identity.background, estimatedWatts: app.watts)
        }
        return ordered(eligible, limit: limit)
    }
    private static func ordered(_ rows: [AppEnergyUsageSnapshot], limit: Int) -> [AppEnergyUsageSnapshot] {
        let values = Dictionary(rows.map { ($0.id,$0) }, uniquingKeysWith: { first,_ in first })
        return AppListOrder.orderedIDs(names: values.mapValues(\.name)).prefix(max(0,limit)).compactMap { values[$0] }
    }

    private static func appIdentity(
        processIdentifier: pid_t,
        command: String
    ) -> (
        bundlePath: String,
        name: String,
        bundleIdentifier: String?
    )? {
        let runningApplication = NSRunningApplication(
            processIdentifier: processIdentifier
        )
        let applicationURL =
            runningApplication?.bundleURL.flatMap(outermostApplicationURL)
            ?? applicationURL(fromCommand: command)
        guard let applicationURL else {
            return nil
        }

        let bundle = Bundle(url: applicationURL)
        let candidates = [
            bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
            bundle?.localizedInfoDictionary?["CFBundleName"] as? String,
            bundle?.infoDictionary?["CFBundleDisplayName"] as? String,
            bundle?.infoDictionary?["CFBundleName"] as? String,
            FileManager.default.displayName(atPath: applicationURL.path),
            applicationURL.deletingPathExtension().lastPathComponent,
        ]
        guard let name = candidates.compactMap(sanitizedDisplayName).first else {
            return nil
        }

        return (
            applicationURL.path,
            name,
            bundle?.bundleIdentifier ?? runningApplication?.bundleIdentifier
        )
    }

    private static func applicationURL(fromCommand command: String) -> URL? {
        guard !command.contains("\u{FFFD}") else { return nil }
        return outermostApplicationURL(
            containing: URL(fileURLWithPath: command)
        )
    }

    private static func outermostApplicationURL(containing url: URL) -> URL? {
        let components = url.standardizedFileURL.pathComponents
        var path = ""

        for component in components {
            if component == "/" {
                path = "/"
                continue
            }
            path = URL(fileURLWithPath: path)
                .appendingPathComponent(component)
                .path
            if component.lowercased().hasSuffix(".app") {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
        }

        return nil
    }

    private static func sanitizedDisplayName(_ candidate: String?) -> String? {
        guard let candidate else { return nil }

        let name = candidate
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .components(separatedBy: .controlCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        let visibleName = name.hasSuffix(".app")
            ? String(name.dropLast(4))
            : name

        guard !visibleName.isEmpty else { return nil }
        return visibleName
    }
}
