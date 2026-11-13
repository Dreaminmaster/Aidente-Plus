import Defaults
import Foundation

enum MenuBarIconStyle: String, Defaults.Serializable, CaseIterable, Identifiable {
    case compact, hidden, appIcon, status, macOS27, macOS26, macOS26Colored, iOSNative
    var id: String { rawValue }
    /// Matches each platform style; a hidden percentage stays hidden.
    func percentageLocation(_ preference: PercentageDisplayLocation) -> PercentageDisplayLocation {
        guard preference != .hidden else { return .hidden }
        switch self {
        case .macOS27, .iOSNative: return .insideIcon
        case .macOS26, .macOS26Colored, .status, .appIcon, .hidden: return .nextToIcon
        case .compact: return preference
        }
    }
    var defaultPercentageLocation: PercentageDisplayLocation {
        percentageLocation(.nextToIcon)
    }
    var title: String {
        switch self {
        case .compact: return AidenteL10n.t("紧凑电池", "Compact Battery")
        case .hidden: return AidenteL10n.t("不显示", "None")
        case .appIcon: return AidenteL10n.t("Aidente 图标", "Aidente Icon")
        case .status: return AidenteL10n.t("Aidente 状态", "Aidente Status")
        case .macOS27: return "macOS 27"
        case .macOS26: return "macOS 26"
        case .macOS26Colored: return AidenteL10n.t("macOS 26 彩色", "macOS 26 Colored")
        case .iOSNative: return AidenteL10n.t("iOS 原生", "iOS Native")
        }
    }
}

enum ChargingIndicatorStyle: String, Defaults.Serializable, CaseIterable, Identifiable {
    case automatic, lightning, plug
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: AidenteL10n.t("自动区分充电与保持", "Automatic by State")
        case .lightning: AidenteL10n.t("闪电", "Lightning")
        case .plug: AidenteL10n.t("插头", "Plug")
        }
    }
    func usesPlug(for mode: ChargingMode) -> Bool { self == .plug || (self == .automatic && mode == .pluggedIn) }
}

enum MenuBarRightClick: String, Defaults.Serializable, CaseIterable, Identifiable {
    case popover, none, toggleCharging, toggleLowPower, dashboard, settings, contextMenu
    var id: String { rawValue }
    var title: String {
        switch self {
        case .popover: return AidenteL10n.t("同左击", "Same as Left Click")
        case .none: return AidenteL10n.t("不执行操作", "Do Nothing")
        case .toggleCharging: return AidenteL10n.t("开始／停止充电", "Start/Stop Charging")
        case .toggleLowPower: return AidenteL10n.t("开启／关闭低功耗", "Toggle Low Power Mode")
        case .dashboard: return AidenteL10n.t("打开仪表板", "Open Dashboard")
        case .settings: return AidenteL10n.t("打开设置", "Open Settings")
        case .contextMenu: return AidenteL10n.t("快捷菜单", "Quick Menu")
        }
    }
}

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case batteryHealth, batteryCondition, cycleCount, hardwarePercentage, temperature, timeRemaining
    case batteryCurrent, batteryVoltage, batteryPower, systemLoad
    case adapterCurrent, adapterVoltage, adapterPower
    case calibration, heatProtection, sailing, topUp
    var id: String { rawValue }
    var group: String {
        switch self {
        case .batteryHealth, .batteryCondition, .cycleCount:
            return AidenteL10n.t("电池健康", "Battery Health")
        case .adapterCurrent, .adapterVoltage, .adapterPower:
            return AidenteL10n.t("电源适配器规格", "Power Adapter Specs")
        case .calibration, .heatProtection, .sailing, .topUp:
            return AidenteL10n.t("Aidente 状态", "Aidente Status")
        default: return AidenteL10n.t("电池规格", "Battery Specs")
        }
    }
    var title: String {
        switch self {
        case .batteryHealth: return AidenteL10n.t("最大容量", "Maximum Capacity")
        case .batteryCondition: return AidenteL10n.t("macOS 状态", "macOS Condition")
        case .cycleCount: return AidenteL10n.t("循环次数", "Cycle Count")
        case .hardwarePercentage: return AidenteL10n.t("硬件电池百分比", "Hardware Battery Percentage")
        case .temperature: return AidenteL10n.t("温度", "Temperature")
        case .timeRemaining: return AidenteL10n.t("充满／剩余时间", "Time to Full / Remaining")
        case .batteryCurrent, .adapterCurrent: return AidenteL10n.t("电流", "Current")
        case .batteryVoltage, .adapterVoltage: return AidenteL10n.t("电压", "Voltage")
        case .batteryPower, .adapterPower: return AidenteL10n.t("功率", "Power")
        case .systemLoad: return AidenteL10n.t("系统负载", "System Load")
        case .calibration: return AidenteL10n.t("校准模式", "Calibration Mode")
        case .heatProtection: return AidenteL10n.t("过热保护", "Heat Protection")
        case .sailing: return AidenteL10n.t("巡航模式", "Sailing Mode")
        case .topUp: return AidenteL10n.t("充满", "Top Up")
        }
    }
    var icon: String {
        switch self {
        case .batteryHealth: return "heart"
        case .batteryCondition: return "cross.case"
        case .cycleCount: return "clock.arrow.circlepath"
        case .hardwarePercentage: return "gauge"
        case .temperature: return "thermometer.medium"
        case .timeRemaining: return "clock"
        case .batteryCurrent, .batteryVoltage, .batteryPower: return "battery.100percent"
        case .systemLoad: return "laptopcomputer"
        case .adapterCurrent, .adapterVoltage, .adapterPower: return "powerplug"
        case .calibration: return "slider.vertical.3"
        case .heatProtection: return "flame"
        case .sailing: return "sailboat"
        case .topUp: return "plus.circle"
        }
    }
    static func visible(from values: [String], activeOnly: Bool, active: Set<String>) -> [Self] {
        selected(from: values).filter { !activeOnly || ![Self.calibration, .heatProtection, .sailing, .topUp].contains($0) || active.contains($0.id) }
    }
    static func selected(from values: [String]) -> [Self] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard seen.insert(value).inserted else { return nil }
            return Self(rawValue: value)
        }
    }
}

extension Defaults.Keys {
    static let menuBarMainIconPosition = Key<Int>("menuBarMainIconPosition", default: 0, suite: AidenteRuntime.preferenceStore)
    static let chargingIndicatorStyle = Key<ChargingIndicatorStyle>("chargingIndicatorStyle", default: .automatic, suite: AidenteRuntime.preferenceStore)
    static let menuBarIconStyle = Key<MenuBarIconStyle>("menuBarIconStyle", default: .compact, suite: AidenteRuntime.preferenceStore)
    static let menuBarHiddenMetricIcons = Key<[String]>("menuBarHiddenMetricIcons", default: [], suite: AidenteRuntime.preferenceStore)
    static let menuBarMetrics = Key<[String]>("menuBarMetrics", default: [], suite: AidenteRuntime.preferenceStore)
    static let menuBarItemSpacing = Key<Int>("menuBarItemSpacing", default: 5, suite: AidenteRuntime.preferenceStore)
    static let menuBarUpdateInterval = Key<Int>("menuBarUpdateInterval", default: 5, suite: AidenteRuntime.preferenceStore)
    static let menuBarRightClick = Key<MenuBarRightClick>("menuBarRightClick", default: .popover, suite: AidenteRuntime.preferenceStore)
    static let menuBarLowPowerColor = Key<Bool>("menuBarLowPowerColor", default: true, suite: AidenteRuntime.preferenceStore)
}
