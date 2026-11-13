import AppKit
import ApplicationServices
import CoreAudio
import Defaults
import IOKit
import IOKit.pwr_mgt
import Observation
import AidenteShared

@MainActor @Observable final class SleepBehaviorService {
    static let shared = SleepBehaviorService()
    private var savedForUninstall: (SleepControlPolicy, Bool)?
    private var manual = SleepControlPolicy()
    private var automatic = false
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var percentage = 100
    private var adapterConnected = false
    private var displayAsleep = false
    private var lastLidClosed = false
    private var timer: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var mutedDevice: (AudioObjectID, UInt32)?
    private(set) var isActive = false
    private(set) var manualActive = false
    private(set) var remaining = ""
    private(set) var error: String?
    func startMonitoring() {
        guard timer == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayAsleep = true; self?.refresh() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayAsleep = false; self?.refresh() }
        })
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func update(automatic: Bool, percentage: Int, adapterConnected: Bool) {
        self.automatic = automatic; self.percentage = percentage; self.adapterConnected = adapterConnected
        refresh()
    }
    @discardableResult func prevent(minutes: Int?) -> Bool {
        guard !AidenteRuntime.isUIPreview, !CompleteUninstaller.shared.isRunning, ConsoleSessionPolicy.currentUserIsActive else { return false }
        guard !Defaults[.sleepStopOnUnplug] || adapterConnected else {
            error = AidenteL10n.t("已启用拔电恢复睡眠，请先接通电源。", "Connect power before starting Sleep Control while Resume on Unplug is enabled."); return false
        }
        guard percentage > Defaults[.sleepResumePercentage] else {
            error = AidenteL10n.t("当前电量已低于睡眠恢复阈值。", "Battery is at or below the sleep-resume threshold."); return false
        }
        error = nil; startMonitoring()
        manual.start(minutes: minutes, now: Date()); refresh()
        if !isActive { manual.stop(); refresh(); return false }
        return manualActive
    }
    func stopManual() { manual.stop(); refresh() }
    func suspendForUninstall() { savedForUninstall = (manual, automatic); stop() }
    func resumeAfterUninstallFailure() {
        if let savedForUninstall { manual = savedForUninstall.0; automatic = savedForUninstall.1 }
        savedForUninstall = nil; startMonitoring(); refresh()
    }
    func stop() {
        automatic = false; manual.stop(); refresh()
        timer?.cancel(); timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; observers = []
    }
    private func assertion(_ id: inout IOPMAssertionID, type: CFString, needed: Bool) {
        if needed && id == 0 {
            let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Aidente Sleep Control" as CFString, &id)
            if result != kIOReturnSuccess { id = 0; error = "Sleep assertion failed: \(result)" }
        } else if !needed && id != 0 { IOPMAssertionRelease(id); id = 0 }
    }
    private func refresh() {
        manualActive = manual.active(now: Date(), percentage: percentage, threshold: Defaults[.sleepResumePercentage],
            adapterConnected: adapterConnected, stopOnUnplug: Defaults[.sleepStopOnUnplug])
        if let end = manual.endAt, manualActive {
            remaining = "\(max(0, Int(end.timeIntervalSinceNow / 60))) min"
        } else { remaining = manualActive ? "∞" : "" }
        let active = (automatic || manualActive) && !AidenteRuntime.isUIPreview && !CompleteUninstaller.shared.isRunning && ConsoleSessionPolicy.currentUserIsActive
        assertion(&systemAssertion, type: kIOPMAssertPreventUserIdleSystemSleep as CFString, needed: active)
        assertion(&displayAssertion, type: kIOPMAssertPreventUserIdleDisplaySleep as CFString, needed: active && Defaults[.preventDisplaySleep])
        isActive = systemAssertion != 0
        updateMute(needed: isActive && displayAsleep && Defaults[.muteWhileDisplaySleeps])
        let closed = lidClosed()
        if closed && !lastLidClosed && isActive && adapterConnected && Defaults[.lockWhenLidClosed] && !hasExternalDisplay() && AXIsProcessTrusted() {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: false)
            down?.flags = [.maskCommand, .maskControl]; up?.flags = [.maskCommand, .maskControl]
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
        lastLidClosed = closed
    }
    private func lidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }; defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool ?? false
    }
    private func hasExternalDisplay() -> Bool {
        NSScreen.screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return true }
            return CGDisplayIsBuiltin(id) == 0
        }
    }
    private func updateMute(needed: Bool) {
        if let (device, previous) = mutedDevice, !needed {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var current: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr, current == 1 {
                var restored = previous
                if AudioObjectSetPropertyData(device, &address, 0, nil, size, &restored) != noErr { error = "Unable to restore output mute state"; return }
            }
            mutedDevice = nil
        }
        guard needed, mutedDevice == nil else { return }
        var device: AudioObjectID = 0; var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return }
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var previous: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &previous) == noErr else { return }
        var mute: UInt32 = 1
        if AudioObjectSetPropertyData(device, &address, 0, nil, size, &mute) == noErr { mutedDevice = (device, previous) }
    }
}
