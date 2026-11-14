import AidenteShared
import Defaults
import SwiftUI

struct PopoverTrendWidget: View {
    let kind: PopoverWidget
    let viewModel: MenuViewModel
    @Default(.popoverGraphPeriods) private var periods
    @Default(.popoverPowerAverage) private var average
    @Default(.popoverPowerAverageMinutes) private var averageMinutes
    @Default(.popoverGraphTimelines) private var timelines
    @Default(.popoverGraphAxes) private var axes
    private var timeline: TrendTimeline { TrendTimeline(rawValue: timelines[kind.id] ?? "recorded") ?? .recorded }
    private var minutes: Int { let value = periods[kind.id] ?? 60; return [15, 60, 360, 1440].contains(value) ? value : 60 }
    private var periodTitle: String { minutes < 60 ? "15 min" : "\(minutes / 60) h" }
    private var samples: [DashboardReading] { viewModel.dashboardReadings }
    private var selectedSamples: [DashboardReading] {
        let now = Date(), window = [5,15,30].contains(averageMinutes) ? averageMinutes : 15
        return samples.filter { $0.timestamp >= now.addingTimeInterval(-Double(window * 60)) && $0.timestamp <= now }
    }
    private var key: KeyPath<DashboardReading, Double> {
        switch kind {
        case .temperatureGraph: return \.temperature
        case .powerGraph: return \.power
        case .cycleGraph: return \.cycles
        default: return \.percentage
        }
    }
    private var color: Color {
        switch kind { case .temperatureGraph: .blue; case .powerGraph: .purple; case .cycleGraph: .orange; default: .green }
    }
    private var value: String {
        switch kind {
        case .temperatureGraph: return viewModel.batteryTemperatureText
        case .powerGraph:
            if average { return DashboardReading.averagePower(selectedSamples).map { String(format: "%.2f W", $0) } ?? "— W" }
            return String(format: "%.2f W", abs(viewModel.batteryPower))
        case .cycleGraph: return viewModel.cycleCountText
        default: return viewModel.batteryPercentageText
        }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(kind == .batteryLevelGraph ? AidenteL10n.t("电池电量", "Battery Level") : kind.title).font(.caption.weight(.semibold))
                Spacer()
                if kind == .powerGraph {
                    Menu {
                        Button(AidenteL10n.t("当前功率", "Instant Power")) { average = false }
                        ForEach([5,15,30], id: \.self) { window in
                            Button(AidenteL10n.t("过去\(window)分钟平均", "Average: Last \(window) Minutes")) { averageMinutes = window; average = true }
                        }
                    } label: { Text(average ? AidenteL10n.t("\(averageMinutes)分均值", "\(averageMinutes)m Avg") : AidenteL10n.t("当前", "Current")).font(.caption2) }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel(AidenteL10n.t("功率平均时段", "Power Averaging Window"))
                        .help(AidenteL10n.t("当前值或过去5、15、30分钟的时间加权平均电池功率；无记录的长空档不计入平均。", "Instant battery power or a time-weighted average over the past 5, 15 or 30 minutes. Long recording gaps are excluded."))
                }
                Text((kind == .powerGraph ? AidenteL10n.t("电池 ", "Battery ") : "") + value).font(.caption).monospacedDigit()
                Menu {
                    Picker(AidenteL10n.t("时间轴", "Timeline"), selection: Binding(get: { timeline.rawValue }, set: { timelines[kind.id] = $0 })) {
                        Text(AidenteL10n.t("跳过无记录空档", "Skip Recording Gaps")).tag("recorded")
                        Text(AidenteL10n.t("按实际过去时间", "Actual Elapsed Time")).tag("actual")
                    }
                    Toggle(AidenteL10n.t("显示刻度", "Show Axes"), isOn: Binding(get: { axes[kind.id] ?? false }, set: { axes[kind.id] = $0 }))
                    Divider()
                    ForEach([15, 60, 360, 1440], id: \.self) { period in
                        Button(period < 60 ? "15 min" : "\(period / 60) h") { periods[kind.id] = period }
                    }
                } label: { Label(periodTitle, systemImage: "clock").font(.caption2) }.menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel(kind.title + AidenteL10n.t("时间范围", " Time Range"))
                    .help(AidenteL10n.t("跳过空档：按有记录的使用时长回看，记录不足时铺满已有数据；按实际时间：保留所选时段内的真实空档。悬停始终显示原始采样时间。", "Skip gaps: look back over recorded usage time and fit available data. Actual time: keep gaps within the selected elapsed period. Hover always shows the original observation time."))
            }
            SessionTrend(samples: samples, key: key, color: color, interval: DateInterval(start: Date().addingTimeInterval(-Double(minutes * 60)), end: Date()), timeline: timeline, showAxes: axes[kind.id] ?? false).frame(height: 100)
        }
    }
}

struct PopoverStatusExplanation: View {
    let viewModel: MenuViewModel
    @Default(.chargeLimit) private var limit
    @Default(.sailingModeLimit) private var sailingRange
    @Default(.automaticDischarge) private var automaticDischarge
    private var explanation: String {
        if let error = viewModel.controlErrorText { return error }
        if !viewModel.manageChargingEnabled {
            return AidenteL10n.t("当前仅监测电池，不改变充电行为。可在充电控制中启用管理。", "Battery monitoring only. Enable management in Charge Control to manage charging.")
        }
        if !viewModel.adapterConnected {
            return AidenteL10n.t("当前使用电池供电。接入电源后将按设定的充电上限管理。", "Running on battery. The charge limit will apply after connecting power.")
        }
        if viewModel.systemCalibrationActive {
            return AidenteL10n.t("macOS 正在执行系统校准；完成后会按所选方式恢复。", "macOS is calibrating the battery. Your selected recovery behavior will apply afterwards.")
        }
        if viewModel.calibrationActive { return viewModel.operationStatusText }
        if viewModel.chargeLimitOverrideActive {
            return AidenteL10n.t("正在临时充至100%，拔掉电源或停止后恢复原充电上限。", "Temporarily charging to 100%. Unplug or stop Top Up to restore your limit.")
        }
        if viewModel.dischargeRequested {
            return viewModel.operationStatusText
        }
        if viewModel.heatProtectionActive {
            return AidenteL10n.t("充电因温度保护暂停；降温并满足保护等待时间后恢复。", "Charging paused for heat protection. It resumes after cooling and the protection interval.")
        }
        if viewModel.sailingActive {
            return AidenteL10n.t("充电已暂停，允许电量自然浮动；降至\(max(20, limit - sailingRange))%时恢复充电，充至\(limit)%再暂停。", "Charging paused. It resumes at \(max(20, limit - sailingRange))% and stops again at \(limit)%.")
        }
        if viewModel.powerFlowPending {
            if viewModel.chargeResumeRequested {
                return AidenteL10n.t("已请求充至\(limit)%，但尚未确认电池实际充电。请检查 macOS 电池设置中是否另有上限或暂停状态。",
                    "Charging to \(limit)% was requested, but battery charging is not confirmed. Check for another charge limit or hold in macOS Battery settings.")
            }
            if viewModel.isCharging {
                return AidenteL10n.t("已请求暂停，但电池目前仍在充电；目标为\(limit)%，等待系统执行并确认保持。",
                    "Hold requested, but the battery is still charging. Target \(limit)%; waiting for macOS to apply and confirm the hold.")
            }
            return viewModel.operationStatusText
        }
        if viewModel.isCharging {
            return AidenteL10n.t("电源正在为电脑供电并给电池充电，达到\(limit)%后将请求保持。", "The adapter powers your Mac and charges the battery. A hold is requested at \(limit)%.")
        }
        if viewModel.displayPercentage > limit && !automaticDischarge {
            return AidenteL10n.t("当前\(viewModel.displayPercentage)%高于上限\(limit)%，充电已暂停。电脑使用适配器供电；若需主动降到\(limit)%，请点击“放电”或开启自动放电。",
                "Battery \(viewModel.displayPercentage)% is above the \(limit)% limit; charging is paused. The adapter powers your Mac. Use Discharge or enable Automatic Discharge to lower it actively.")
        }
        return AidenteL10n.t("充电已暂停，当前上限为\(limit)%。电脑优先使用适配器供电，瞬时负载较大时电池仍可能辅助供电。", "Charging paused at a \(limit)% limit. The adapter supplies power; the battery may assist during brief high loads.")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AidenteL10n.t("当前是什么状态？", "What's going on?")).font(.caption.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Array(viewModel.observedStatusSymbols.enumerated()), id: \.offset) { _, symbol in
                        Image(systemName: symbol)
                    }
                }.accessibilityLabel(viewModel.operationStatusText)
            }
            Text(explanation).font(.caption).fixedSize(horizontal: false, vertical: true)
            if let progress = viewModel.dischargeProgressText {
                Text(progress).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PopoverCapacityWidget: View {
    let viewModel: MenuViewModel
    @Default(.popoverCapacityRange) private var rangeID
    private var range: CapacityHistoryRange { CapacityHistoryRange(rawValue: rangeID) ?? .all }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AidenteL10n.t("最大容量", "Maximum Capacity")).font(.caption.weight(.semibold))
                Spacer()
                Text(viewModel.batteryHealthText).font(.caption).monospacedDigit()
                Menu {
                    ForEach(CapacityHistoryRange.allCases) { item in
                        Button(item.title) { rangeID = item.rawValue }
                    }
                } label: { Text(range.title).font(.caption2) }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel(AidenteL10n.t("容量历史范围", "Capacity History Range"))
            }
            HStack {
                Text(viewModel.estimatedFullCapacityText)
                Spacer()
                if AidenteRuntime.isUIPreview { Text(AidenteL10n.t("演示历史", "Demo History")) }
            }.font(.caption2).foregroundStyle(.secondary)
            BatteryCapacityChartView(samples: viewModel.batteryCapacityHistory, range: range).frame(height: 100)
        }
    }
}
