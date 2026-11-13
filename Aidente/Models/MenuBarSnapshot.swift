import Foundation
import Observation

struct MenuBarSnapshot: Equatable {
    var percentage = 0
    var chargingMode: ChargingMode = .discharging
    var lowPower = false
    var adapterConnected = false
    var power = "— W"
    var activeMetrics: Set<String> = []
    var values: [String: String] = [:]

    @MainActor init(viewModel: MenuViewModel) {
        percentage = viewModel.displayPercentage
        chargingMode = viewModel.chargingMode
        lowPower = viewModel.isLowPowerModeEnabled
        adapterConnected = viewModel.adapterConnected
        let sampleAge = viewModel.lastPowerSampleDate.map { Date().timeIntervalSince($0) }
        let powerAvailable = sampleAge.map { (0...30).contains($0) } ?? false
        power = powerAvailable && viewModel.systemPower.isFinite
            ? String(format: "%.2fW", abs(viewModel.systemPower)) : "— W"
        func number(_ value: Double, _ unit: String) -> String {
            powerAvailable && value.isFinite ? String(format: "%.2f%@", value, unit) : "—"
        }
        if viewModel.calibrationActive { activeMetrics.insert("calibration") }
        if viewModel.heatProtectionActive { activeMetrics.insert("heatProtection") }
        if viewModel.sailingActive { activeMetrics.insert("sailing") }
        if viewModel.chargeLimitOverrideActive { activeMetrics.insert("topUp") }
        let enabled = AidenteL10n.t("开启", "On")
        let disabled = AidenteL10n.t("关闭", "Off")
        values = [
            MenuBarMetric.batteryHealth.id: viewModel.batteryHealthText,
            MenuBarMetric.batteryCondition.id: viewModel.batteryCondition,
            MenuBarMetric.cycleCount.id: viewModel.cycleCountText,
            MenuBarMetric.hardwarePercentage.id: viewModel.hasHardwarePercentage ? "\(viewModel.hardwarePercentage)%" : "—",
            MenuBarMetric.temperature.id: viewModel.batteryTemperatureText,
            MenuBarMetric.timeRemaining.id: viewModel.timeRemainingText,
            MenuBarMetric.batteryCurrent.id: number(viewModel.batteryCurrent, "A"),
            MenuBarMetric.batteryVoltage.id: number(viewModel.batteryVoltage, "V"),
            MenuBarMetric.batteryPower.id: number(viewModel.batteryPower, "W"),
            MenuBarMetric.systemLoad.id: power,
            MenuBarMetric.adapterCurrent.id: adapterConnected ? number(viewModel.adapterCurrent, "A") : "— A",
            MenuBarMetric.adapterVoltage.id: adapterConnected ? number(viewModel.adapterVoltage, "V") : "— V",
            MenuBarMetric.adapterPower.id: adapterConnected ? number(viewModel.adapterPower, "W") : "— W",
            MenuBarMetric.calibration.id: viewModel.calibrationActive ? viewModel.operationStatusText : disabled,
            MenuBarMetric.heatProtection.id: viewModel.heatProtectionActive ? enabled : disabled,
            MenuBarMetric.sailing.id: viewModel.sailingActive ? enabled : disabled,
            MenuBarMetric.topUp.id: viewModel.chargeLimitOverrideActive ? enabled : disabled,
        ]
    }
}

@MainActor @Observable final class MenuBarDisplayState {
    var snapshot: MenuBarSnapshot
    init(viewModel: MenuViewModel) { snapshot = MenuBarSnapshot(viewModel: viewModel) }
}
