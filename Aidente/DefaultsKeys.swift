import Defaults
import Foundation
import smc_power

enum AidenteRuntime {
    static let preferenceStore = isUIPreview
        ? UserDefaults(suiteName: "com.aidente.app.preview")! : .standard
    static let isUIPreview = CommandLine.arguments.contains("--ui-preview")
}

enum AidenteMigration {
    private static let legacyBundleIdentifier = "com.iadente.app"
    private static let migrationMarker = "didMigrateLegacyPreferencesV1"

    static func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationMarker) { migrateMenuReadoutsIfNeeded(); return }

        let currentBundleIdentifier =
            Bundle.main.bundleIdentifier ?? "com.aidente.app"
        let currentValues =
            defaults.persistentDomain(forName: currentBundleIdentifier) ?? [:]

        if let legacyValues = defaults.persistentDomain(
            forName: legacyBundleIdentifier
        ) {
            for (key, value) in legacyValues where currentValues[key] == nil {
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: migrationMarker)
        migrateMenuReadoutsIfNeeded()
    }
    private static func migrateMenuReadoutsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didMigrateMenuReadoutsV2") else { return }
        if let legacy = defaults.string(forKey: "menuBarReadoutStyle"), legacy != "batteryPercentage" {
            var metrics = defaults.stringArray(forKey: "menuBarMetrics") ?? []
            if !metrics.contains("systemLoad") { metrics.append("systemLoad") }
            defaults.set(metrics, forKey: "menuBarMetrics")
            defaults.set(legacy == "batteryAndPower" ? "insideIcon" : "hidden", forKey: "batteryPercentageDisplayLocation")
            defaults.set("batteryPercentage", forKey: "menuBarReadoutStyle")
        }
        defaults.set(true, forKey: "didMigrateMenuReadoutsV2")
    }

}

extension MagSafeLEDState: Defaults.Serializable {}

enum AppLanguage: String, Defaults.Serializable, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: AidenteL10n.t("跟随系统", "System")
        case .simplifiedChinese: "中文"
        case .english: "English"
        }
    }
}

enum InterfaceAppearance: String, Defaults.Serializable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: AidenteL10n.t("跟随系统", "System")
        case .light: AidenteL10n.t("浅色", "Light")
        case .dark: AidenteL10n.t("深色", "Dark")
        }
    }
}

enum PercentageDisplayLocation: String, Defaults.Serializable, CaseIterable, Identifiable {
    case hidden
    case nextToIcon
    case insideIcon

    var id: String { rawValue }
}

enum MenuBarReadoutStyle: String, Defaults.Serializable, CaseIterable, Identifiable {
    case batteryPercentage
    case systemPower
    case batteryAndPower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batteryPercentage: AidenteL10n.t("实时电量")
        case .systemPower: AidenteL10n.t("实时功率")
        case .batteryAndPower: AidenteL10n.t("电量与功率")
        }
    }

    var icon: String {
        switch self {
        case .batteryPercentage: "battery.75percent"
        case .systemPower: "waveform.path.ecg"
        case .batteryAndPower: "gauge.with.dots.needle.67percent"
        }
    }
}

enum InterfaceMaterialStyle: String, Defaults.Serializable, CaseIterable, Identifiable {
    case solid
    case glass
    case frosted
    case liquidGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: AidenteL10n.t("清晰实体")
        case .glass: AidenteL10n.t("毛玻璃")
        case .frosted: AidenteL10n.t("高斯柔化")
        case .liquidGlass: AidenteL10n.t("液态玻璃")
        }
    }

    var subtitle: String {
        switch self {
        case .solid: AidenteL10n.t("最高文字对比度")
        case .glass: AidenteL10n.t("平衡透明度与清晰度")
        case .frosted: AidenteL10n.t("更明显的背景虚化")
        case .liquidGlass:
            AidenteL10n.t("兼容的玻璃高光与半透明效果")
        }
    }

    var icon: String {
        switch self {
        case .solid: "rectangle.fill"
        case .glass: "square.on.square"
        case .frosted: "aqi.medium"
        case .liquidGlass: "drop.circle.fill"
        }
    }
}

extension Defaults.Keys {
    // General
    static let interfaceAppearance = Key<InterfaceAppearance>("interfaceAppearance", default: .system, suite: AidenteRuntime.preferenceStore)
    static let showDockIcon = Key<Bool>("showDockIcon", default: true, suite: AidenteRuntime.preferenceStore)
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system, suite: AidenteRuntime.preferenceStore)
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false, suite: AidenteRuntime.preferenceStore)
    static let interfaceMaterialStyle = Key<InterfaceMaterialStyle>(
        "interfaceMaterialStyle", default: .glass, suite: AidenteRuntime.preferenceStore)
    static let automaticallyCheckForUpdates = Key<Bool>(
        "automaticallyCheckForUpdates", default: false, suite: AidenteRuntime.preferenceStore)

    // Status Icon
    static let batteryPercentageDisplayLocation = Key<PercentageDisplayLocation>(
        "batteryPercentageDisplayLocation", default: .nextToIcon, suite: AidenteRuntime.preferenceStore)
    static let menuBarReadoutStyle = Key<MenuBarReadoutStyle>(
        "menuBarReadoutStyle", default: .batteryPercentage, suite: AidenteRuntime.preferenceStore)
    static let showBatteryStateInStatusIcon = Key<Bool>(
        "showBatteryStateInStatusIcon", default: true, suite: AidenteRuntime.preferenceStore)

    // Notifications
    static let disableNotifications = Key<Bool>("disableNotifications", default: false, suite: AidenteRuntime.preferenceStore)
    static let showChargingStatusChangedNotification = Key<Bool>(
        "showChargingStatusChangedNotification", default: true, suite: AidenteRuntime.preferenceStore)

    // Menu Dashboard
    static let showTimeTillDischarge = Key<Bool>("showTimeTillDischarge", default: true, suite: AidenteRuntime.preferenceStore)
    static let showBatteryCycleCount = Key<Bool>("showBatteryCycleCount", default: true, suite: AidenteRuntime.preferenceStore)
    static let showBatteryHealth = Key<Bool>("showBatteryHealth", default: true, suite: AidenteRuntime.preferenceStore)
    static let showBatteryTemperature = Key<Bool>("showBatteryTemperature", default: false, suite: AidenteRuntime.preferenceStore)
    static let showPowerSource = Key<Bool>("showPowerSource", default: false, suite: AidenteRuntime.preferenceStore)
    static let showUptime = Key<Bool>("showUptime", default: true, suite: AidenteRuntime.preferenceStore)
    static let showBatteryMode = Key<Bool>("showBatteryMode", default: true, suite: AidenteRuntime.preferenceStore)
    static let showInternalPower = Key<Bool>("showInternalPower", default: true, suite: AidenteRuntime.preferenceStore)
    static let showExternalPower = Key<Bool>("showExternalPower", default: true, suite: AidenteRuntime.preferenceStore)
    static let showPowerDistribution = Key<Bool>("showPowerDistribution", default: false, suite: AidenteRuntime.preferenceStore)

    // Charging
    static let manageCharging = Key<Bool>("manageCharging", default: false, suite: AidenteRuntime.preferenceStore)
    static let chargeLimit = Key<Int>("chargeLimit", default: 80, suite: AidenteRuntime.preferenceStore)
    static let sailingMode = Key<Bool>("sailingMode", default: true, suite: AidenteRuntime.preferenceStore)
    static let sailingModeLimit = Key<Int>("sailingModeLimit", default: 5, suite: AidenteRuntime.preferenceStore)
    static let automaticDischarge = Key<Bool>("automaticDischarge", default: false, suite: AidenteRuntime.preferenceStore)
    static let disableSleepUntilChargeLimit = Key<Bool>("disableSleepUntilChargeLimit", default: false, suite: AidenteRuntime.preferenceStore)

    // Charging - Heat Protection
    static let enableHeatProtectionMode = Key<Bool>(
        "enableHeatProtectionMode", default: true, suite: AidenteRuntime.preferenceStore)
    static let heatProtectionLimit = Key<Int>("heatProtectionLimit", default: 40, suite: AidenteRuntime.preferenceStore)

    // Charging - MagSafe LED Control
    static let manageMagSafeLED = Key<Bool>("manageMagSafeLED", default: true, suite: AidenteRuntime.preferenceStore)
    static let heatProtectionMagSafeLEDState = Key<MagSafeLEDState>(
        "heatProtectionMagSafeLEDState", default: MagSafeLEDState.blinkOrangeSlow, suite: AidenteRuntime.preferenceStore)

    // Charging - Advanced workflows
    static let stopChargingWhenAppClosed = Key<Bool>(
        "stopChargingWhenAppClosed", default: false, suite: AidenteRuntime.preferenceStore)
    static let stopChargingWhileSleeping = Key<Bool>(
        "stopChargingWhileSleeping", default: true, suite: AidenteRuntime.preferenceStore)
    static let topUpActive = Key<Bool>("topUpActive", default: false, suite: AidenteRuntime.preferenceStore)
    static let manualPauseActive = Key<Bool>("manualPauseActive", default: false, suite: AidenteRuntime.preferenceStore)
    static let forcedDischargeTarget = Key<Int>("forcedDischargeTarget", default: 80, suite: AidenteRuntime.preferenceStore)
    static let calibrationStage = Key<String>("calibrationStage", default: "idle", suite: AidenteRuntime.preferenceStore)
    static let calibrationOriginalLimit = Key<Int>(
        "calibrationOriginalLimit", default: 80, suite: AidenteRuntime.preferenceStore)
    static let calibrationLowLevel = Key<Int>("calibrationLowLevel", default: 10, suite: AidenteRuntime.preferenceStore)
    static let calibrationHoldMinutes = Key<Int>("calibrationHoldMinutes", default: 60, suite: AidenteRuntime.preferenceStore)
    static let calibrationHoldUntil = Key<Double>("calibrationHoldUntil", default: 0, suite: AidenteRuntime.preferenceStore)

    // Automation
    static let scheduleTasksData = Key<Data>("scheduleTasksData", default: Data(), suite: AidenteRuntime.preferenceStore)

    // Advanced
    static let useHardwarePercentage = Key<Bool>("useHardwarePercentage", default: false, suite: AidenteRuntime.preferenceStore)

    // Diagnostics
    static let diagnosticSessionStartedAt = Key<Double>(
        "diagnosticSessionStartedAt", default: 0, suite: AidenteRuntime.preferenceStore)
    static let diagnosticSessionID = Key<String>(
        "diagnosticSessionID", default: "", suite: AidenteRuntime.preferenceStore)
}
