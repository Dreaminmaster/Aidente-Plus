import AidenteShared
import Defaults
import Foundation
import Darwin
import Observation

@MainActor @Observable final class SystemCalibrationService {
    static let shared = SystemCalibrationService()
    private(set) var session: SystemCalibrationSession
    private(set) var lastCheck: Date?
    private(set) var checking = false
    var canDiscardStaleSession: Bool { session.pending && Date().timeIntervalSince(session.latestEvent ?? .distantPast) > 120 }
    private(set) var error: String?
    private var task: Task<Void, Never>?
    var onEvidenceChanged: (() -> Void)?
    init() {
        session = Defaults[.systemCalibrationSession].flatMap { try? JSONDecoder().decode(SystemCalibrationSession.self, from: $0) } ?? SystemCalibrationSession()
    }
    var isActive: Bool { session.pending }
    var status: String {
        if session.handoffPendingRelease { return AidenteL10n.t("已确认充满并进入后续流程；如果电量不下降，请重新连接电源。", "Full charge confirmed and follow-up started. Reconnect power if discharge does not begin.") }
        if session.waitingForRelease { return AidenteL10n.t("已充满，等待 macOS 释放校准限制；持续不释放时可拔插电源。", "Full charge confirmed; waiting for macOS to release its override. Reconnect power if it remains active.") }
        if session.released { return AidenteL10n.t("系统已释放校准限制，正在确认充满状态。", "macOS released its override; confirming full charge.") }
        if canDiscardStaleSession { return AidenteL10n.t("先前检测到系统校准；目前等待系统结束的明确信号。", "System calibration was previously detected; waiting for explicit completion evidence.") }
        if session.pending { return AidenteL10n.t("macOS 正在强制充满以校准电池，暂时无法停止。", "macOS is forcing a full charge for battery calibration; it cannot be interrupted.") }
        if let error { return error }
        return AidenteL10n.t("未检测到新近的系统校准事件", "No recent system calibration event detected")
    }
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
    func refresh() async {
        guard !checking else { return }; checking = true; defer { checking = false }
        let result = await Task.detached(priority: .utility) { Self.readEvents() }.value
        guard !Task.isCancelled, !CompleteUninstaller.shared.isRunning else { return }
        lastCheck = Date()
        var evidence = result ?? []
        let boot = SystemService.bootTimestamp()?.timeIntervalSince1970 ?? 0
        let native = Self.readNativeState()
        let trusted = boot > 0 && Defaults[.nativeGaugingEvidenceBoot] == boot
        if let active = NativeGaugingSignal.active(value: native, trustedInCurrentBoot: trusted) {
            if active && boot > 0 { Defaults[.nativeGaugingEvidenceBoot] = boot }
            else if !active { Defaults[.nativeGaugingEvidenceBoot] = 0 }
            if active || session.pending || session.handoffPendingRelease { evidence.append(GaugingEvent(date: Date(), active: active)) }
        }
        guard result != nil || native == 1 || trusted && native == 0 else {
            error = AidenteL10n.t("系统日志无法读取，校准检测状态未知。", "System logs are unavailable; calibration detection is unknown."); return
        }
        error = nil
        let before = session
        for event in evidence.sorted(by: { $0.date < $1.date }) { session.observe(event, now: Date()) }
        if before != session { save(); onEvidenceChanged?() }
    }
    func recordFullSample(full: Bool, date: Date?, percentage: Int, isCharging: Bool) {
        let before = session
        session.sample(full: full, sampleDate: date, now: Date())
        session.finishIfInterrupted(percentage: percentage, isCharging: isCharging)
        if session != before { save() }
    }
    func didContinue() { session.finish(); save() }
    func discardStaleSession() {
        guard canDiscardStaleSession else { return }
        session.finish(); save(); onEvidenceChanged?()
    }
    private func save() { Defaults[.systemCalibrationSession] = try? JSONEncoder().encode(session) }
    nonisolated private static func readNativeState() -> UInt64? {
        guard #available(macOS 26.4, *) else { return nil }
        guard let library = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(library) }
        guard let r = dlsym(library, "notify_register_check"), let g = dlsym(library, "notify_get_state"), let c = dlsym(library, "notify_cancel") else { return nil }
        typealias Register = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<Int32>) -> UInt32
        typealias Get = @convention(c) (Int32, UnsafeMutablePointer<UInt64>) -> UInt32
        typealias Cancel = @convention(c) (Int32) -> UInt32
        let register = unsafeBitCast(r, to: Register.self), get = unsafeBitCast(g, to: Get.self), cancel = unsafeBitCast(c, to: Cancel.self)
        var token: Int32 = 0, state: UInt64 = 0
        guard "com.apple.system.powersources.chargingtofulloverride".withCString({ register($0, &token) }) == 0 else { return nil }
        defer { _ = cancel(token) }
        return get(token, &state) == 0 ? state : nil
    }
    nonisolated private static func readEvents() -> [GaugingEvent]? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--last", "2m", "--style", "ndjson", "--info", "--predicate",
            #"(process == "PowerUIAgent" AND (eventMessage CONTAINS[c] "ChargingUpForGauging" OR eventMessage CONTAINS[c] "Battery mitigations are in place")) OR (process == "powerd" AND eventMessage CONTAINS[c] "SOC limit policy suspend due to mitigation active:")"#]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 5)
        timer.setEventHandler { if process.isRunning { process.terminate() } }; timer.resume()
        defer { timer.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 1_048_576 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let message = record["eventMessage"] as? String,
                  let processName = record["processImagePath"] as? String,
                  let timestamp = record["timestamp"] as? String,
                  let date = formatter.date(from: timestamp) ?? iso.date(from: timestamp),
                  let active = GaugingLogParser.active(message: message, process: processName) else { return nil }
            return GaugingEvent(date: date, active: active)
        }
    }
}
