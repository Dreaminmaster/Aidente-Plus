import Defaults
import AidenteShared
import Foundation

extension EnergyMode: Defaults.Serializable {}
extension EnergySource: Defaults.Serializable {}
enum LEDBehavior: String, Defaults.Serializable, CaseIterable, Identifiable {
    case indicateLimit, alwaysOff, offDuringSleep
    var id: String { rawValue }
    var title: String {
        switch self {
        case .indicateLimit: AidenteL10n.t("指示充电上限", "Indicate Charge Limit")
        case .alwaysOff: AidenteL10n.t("始终关闭", "Always Off")
        case .offDuringSleep: AidenteL10n.t("睡眠时关闭", "Off During Sleep")
        }
    }
}
extension EnergyMode {
    var title: String {
        switch self {
        case .automatic: AidenteL10n.t("自动", "Automatic")
        case .low: AidenteL10n.t("低功耗", "Low Power")
        case .high: AidenteL10n.t("高功耗", "High Power")
        }
    }
}
extension AfterSystemCalibration: Defaults.Serializable {}
extension Defaults.Keys {
    static let lastDischargeSafetyStopReason = Key<String>("lastDischargeSafetyStopReason", default: "", suite: AidenteRuntime.preferenceStore)
    static let nativeGaugingEvidenceBoot = Key<Double>("nativeGaugingEvidenceBoot", default: 0, suite: AidenteRuntime.preferenceStore)
    static let lastObservedFullCharge = Key<Double>("lastObservedFullCharge", default: 0, suite: AidenteRuntime.preferenceStore)
    static let systemCalibrationRecovery = Key<Bool>("systemCalibrationRecovery", default: false, suite: AidenteRuntime.preferenceStore)
    static let systemCalibrationSession = Key<Data?>("systemCalibrationSession", default: nil, suite: AidenteRuntime.preferenceStore)
    static let afterSystemCalibration = Key<AfterSystemCalibration>("afterSystemCalibration", default: .dischargeToLimit, suite: AidenteRuntime.preferenceStore)
    static let restoreWindowLayout = Key<Bool>("restoreWindowLayout", default: true, suite: AidenteRuntime.preferenceStore)
    static let backgroundDashboardUpdates = Key<Bool>("backgroundDashboardUpdates", default: true, suite: AidenteRuntime.preferenceStore)
    static let scheduleCatchUpEnabled = Key<Bool>("scheduleCatchUpEnabled", default: true, suite: AidenteRuntime.preferenceStore)
    static let allowBelow80 = Key<Bool>("allowBelow80", default: false, suite: AidenteRuntime.preferenceStore)
    static let popoverShowPercentage = Key<Bool>("popoverShowPercentage", default: true, suite: AidenteRuntime.preferenceStore)
    static let popoverShowOnLaunch = Key<Bool>("popoverShowOnLaunch", default: false, suite: AidenteRuntime.preferenceStore)
    static let popoverMetricIDs = Key<[String]>("popoverMetricIDs", default: ["batteryHealth", "cycleCount", "temperature", "timeRemaining"], suite: AidenteRuntime.preferenceStore)
    static let sleepResumePercentage = Key<Int>("sleepResumePercentage", default: 20, suite: AidenteRuntime.preferenceStore)
    static let sleepStopOnUnplug = Key<Bool>("sleepStopOnUnplug", default: false, suite: AidenteRuntime.preferenceStore)
    static let ledBehavior = Key<LEDBehavior>("ledBehavior", default: .indicateLimit, suite: AidenteRuntime.preferenceStore)
    static let blinkLEDWhileDischarging = Key<Bool>("blinkLEDWhileDischarging", default: true, suite: AidenteRuntime.preferenceStore)
    static let preventDisplaySleep = Key<Bool>("preventDisplaySleep", default: false, suite: AidenteRuntime.preferenceStore)
    static let muteWhileDisplaySleeps = Key<Bool>("muteWhileDisplaySleeps", default: false, suite: AidenteRuntime.preferenceStore)
    static let lockWhenLidClosed = Key<Bool>("lockWhenLidClosed", default: false, suite: AidenteRuntime.preferenceStore)
    static let showAllRunningApps = Key<Bool>("showAllRunningApps", default: true, suite: AidenteRuntime.preferenceStore)
    static let energyUsageThreshold = Key<Int>("energyUsageThreshold", default: 5, suite: AidenteRuntime.preferenceStore)
    static let includeBackgroundEnergyProcesses = Key<Bool>("includeBackgroundEnergyProcesses", default: false, suite: AidenteRuntime.preferenceStore)
    static let compactEnergyWidget = Key<Bool>("compactEnergyWidget", default: false, suite: AidenteRuntime.preferenceStore)
    static let activeStatusItemsOnly = Key<Bool>("activeStatusItemsOnly", default: true, suite: AidenteRuntime.preferenceStore)
    static let lastCalibrationCompleted = Key<Double>("lastCalibrationCompleted", default: 0, suite: AidenteRuntime.preferenceStore)
    static let scheduleHistoryData = Key<Data>("scheduleHistoryData", default: Data(), suite: AidenteRuntime.preferenceStore)
}
