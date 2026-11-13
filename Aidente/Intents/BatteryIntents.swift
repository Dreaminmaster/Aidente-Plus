import AppIntents
import Foundation

struct TopUpIntent: AppIntent {
    static var title: LocalizedStringResource = "充满电"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("top-up")
        return .result()
    }
}

struct PauseChargingIntent: AppIntent {
    static var title: LocalizedStringResource = "暂停充电"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("pause")
        return .result()
    }
}

struct ResumeChargingIntent: AppIntent {
    static var title: LocalizedStringResource = "恢复充电管理"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("resume")
        return .result()
    }
}

struct StartDischargeIntent: AppIntent {
    static var title: LocalizedStringResource = "开始放电"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("discharge")
        return .result()
    }
}

struct StartCalibrationIntent: AppIntent {
    static var title: LocalizedStringResource = "开始电池校准"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("calibrate")
        return .result()
    }
}

struct StopCalibrationIntent: AppIntent {
    static var title: LocalizedStringResource = "停止电池校准"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("stop-calibration")
        return .result()
    }
}

struct EnableLowPowerIntent: AppIntent {
    static var title: LocalizedStringResource = "启用低功耗模式"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("low-on")
        return .result()
    }
}

struct DisableLowPowerIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭低功耗模式"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("low-off")
        return .result()
    }
}

struct EnableHighPowerIntent: AppIntent {
    static var title: LocalizedStringResource = "启用高功耗模式"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("high-on")
        return .result()
    }
}

struct DisableHighPowerIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭高功耗模式"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("high-off")
        return .result()
    }
}

struct StopSleepControlIntent: AppIntent {
    static var title: LocalizedStringResource = "恢复系统睡眠"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("sleep-stop")
        return .result()
    }
}

struct SetChargeLimitIntent: AppIntent {
    static var title: LocalizedStringResource = "设置充电上限"
    static var openAppWhenRun = true
    @Parameter(title: "百分比", default: 80) var percentage: Int
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("set-limit", value: percentage)
        return .result()
    }
}
struct PreventSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "暂时阻止睡眠"
    static var openAppWhenRun = true
    @Parameter(title: "分钟", default: 60) var minutes: Int
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("sleep-prevent", value: minutes)
        return .result()
    }
}
enum MagSafeIntentColor: String, AppEnum {
    case green, orange, blink, off
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "MagSafe 灯光")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .green: "绿色", .orange: "橙色", .blink: "橙色闪烁", .off: "关闭"
    ]
    var value: Int { switch self { case .green: 3; case .orange: 4; case .blink: 6; case .off: 1 } }
}
struct SetMagSafeLEDIntent: AppIntent {
    static var title: LocalizedStringResource = "设置 MagSafe 指示灯"
    static var openAppWhenRun = true
    @Parameter(title: "灯光", default: .green) var color: MagSafeIntentColor
    func perform() async throws -> some IntentResult {
        try await ApplicationActions.shared.execute("led", value: color.value)
        return .result()
    }
}
struct GetBatteryPercentageIntent: AppIntent {
    static var title: LocalizedStringResource = "获取电池电量"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let value = try await ApplicationActions.shared.read("percentage")
        return .result(value: Int(value) ?? 0)
    }
}
struct GetChargeLimitIntent: AppIntent {
    static var title: LocalizedStringResource = "获取充电上限"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let value = try await ApplicationActions.shared.read("limit")
        return .result(value: Int(value) ?? 0)
    }
}
struct GetTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "获取电池温度"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let value = try await ApplicationActions.shared.read("temperature")
        return .result(value: Double(value) ?? -1)
    }
}
struct GetStateIntent: AppIntent {
    static var title: LocalizedStringResource = "获取充电状态"
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let value = try await ApplicationActions.shared.read("state")
        return .result(value: value)
    }
}
struct AidenteAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TopUpIntent(), phrases: ["用 \(.applicationName) 充满电"], shortTitle: "充满电", systemImageName: "battery.100percent.bolt")
        AppShortcut(intent: PauseChargingIntent(), phrases: ["用 \(.applicationName) 暂停充电"], shortTitle: "暂停充电", systemImageName: "pause.circle")
        AppShortcut(intent: GetBatteryPercentageIntent(), phrases: ["在 \(.applicationName) 查看电池电量"], shortTitle: "电池电量", systemImageName: "battery.75percent")
    }
}
