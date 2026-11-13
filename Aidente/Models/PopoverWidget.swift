import Defaults
import Foundation

enum PopoverWidget: String, CaseIterable, Identifiable {
    case sleepControl, energyMode, specifications
    case powerFlow, batterySpecs, capacityHistory, energyApps, careActions, protection, settingsLinks
    case batteryLevelGraph, temperatureGraph, powerGraph, cycleGraph
    var id: String { rawValue }
    var isGraph: Bool { [.capacityHistory, .batteryLevelGraph, .temperatureGraph, .powerGraph, .cycleGraph].contains(self) }
    static var minimalist: [String] { [Self.protection, .powerFlow, .specifications].map(\.id) }
    static var healthFocused: [String] { [Self.protection, .powerFlow, .energyApps, .capacityHistory, .specifications].map(\.id) }
    static var powerUser: [String] { [Self.protection, .powerFlow, .energyApps, .energyMode, .batteryLevelGraph, .specifications, .powerGraph].map(\.id) }
    var title: String {
        switch self {
        case .sleepControl: return AidenteL10n.t("手动睡眠控制", "Sleep Control")
        case .energyMode: return AidenteL10n.t("功耗模式", "Energy Mode")
        case .specifications: return AidenteL10n.t("规格", "Specifications")
        case .powerFlow: return AidenteL10n.t("功率分配图", "Power Flow")
        case .batterySpecs: return AidenteL10n.t("电池规格", "Battery Specifications")
        case .capacityHistory: return AidenteL10n.t("容量趋势", "Capacity History")
        case .energyApps: return AidenteL10n.t("App 用量", "App Activity")
        case .careActions: return AidenteL10n.t("快捷养护", "Battery Care")
        case .protection: return AidenteL10n.t("当前状态", "Current Status")
        case .batteryLevelGraph: return AidenteL10n.t("电池电量曲线", "Battery Level")
        case .temperatureGraph: return AidenteL10n.t("电池温度曲线", "Battery Temperature")
        case .powerGraph: return AidenteL10n.t("功耗曲线", "Power Consumption")
        case .cycleGraph: return AidenteL10n.t("循环次数曲线", "Cycle Count")
        case .settingsLinks: return AidenteL10n.t("设置入口", "Settings Links")
        }
    }
    static var defaultLayoutIDs: [String] { minimalist }
    static func selected(from ids: [String]) -> [Self] {
        var seen = Set<String>()
        return ids.compactMap { seen.insert($0).inserted ? Self(rawValue: $0) : nil }
    }
}

extension Defaults.Keys {
    static let dashboardGraphPeriod = Key<Int>("dashboardGraphPeriod", default: 15, suite: AidenteRuntime.preferenceStore)
    static let dashboardPowerAverageMinutes = Key<Int>("dashboardPowerAverageMinutes", default: 15, suite: AidenteRuntime.preferenceStore)
    static let popoverPowerAverageMinutes = Key<Int>("popoverPowerAverageMinutes", default: 15, suite: AidenteRuntime.preferenceStore)
    static let dashboardPowerAverage = Key<Bool>("dashboardPowerAverage", default: false, suite: AidenteRuntime.preferenceStore)
    static let dashboardCapacityRange = Key<String>("dashboardCapacityRange", default: "all", suite: AidenteRuntime.preferenceStore)
    static let dashboardSkipInactivePeriods = Key<Bool>("dashboardSkipInactivePeriods", default: true, suite: AidenteRuntime.preferenceStore)
    static let popoverGraphTimelines = Key<[String: String]>("popoverGraphTimelines", default: [:], suite: AidenteRuntime.preferenceStore)
    static let popoverGraphAxes = Key<[String: Bool]>("popoverGraphAxes", default: [:], suite: AidenteRuntime.preferenceStore)
    static let popoverGraphPeriods = Key<[String: Int]>("popoverGraphPeriods", default: [:], suite: AidenteRuntime.preferenceStore)
    static let popoverPowerAverage = Key<Bool>("popoverPowerAverage", default: false, suite: AidenteRuntime.preferenceStore)
    static let popoverCapacityRange = Key<String>("popoverCapacityRange", default: "all", suite: AidenteRuntime.preferenceStore)
    static let popoverWidgets = Key<[String]>("popoverWidgets",
        default: PopoverWidget.defaultLayoutIDs, suite: AidenteRuntime.preferenceStore)
}
