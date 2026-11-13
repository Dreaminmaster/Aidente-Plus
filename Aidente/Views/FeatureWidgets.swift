import AidenteShared
import Defaults
import SwiftUI
import Charts

struct EnergyModeWidget: View {
    private let service = EnergyModeService.shared
    @Default(.compactEnergyWidget) private var compact
    private var subtitle: String {
        switch service.lowPowerPreset {
        case 0: return AidenteL10n.t("始终关闭", "Always Off")
        case 1: return AidenteL10n.t("始终开启", "Always On")
        case 2: return AidenteL10n.t("仅使用电池时", "Only on Battery")
        case 3: return AidenteL10n.t("仅接入电源时", "Only on Adapter")
        default: return AidenteL10n.t("按电源分别设置", "Configured per Source")
        }
    }
    var body: some View {
        if !compact || service.isNonAutomaticActive {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "leaf").font(.system(size: 15))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(service.readings[service.activeSource]?.mode == .high
                            ? AidenteL10n.t("高功耗模式", "High Power Mode")
                            : service.readings[service.activeSource]?.mode == .low
                            ? AidenteL10n.t("低电量模式", "Low Power Mode")
                            : AidenteL10n.t("功耗模式", "Energy Mode")).font(.caption.weight(.semibold))
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                    ForEach(EnergySource.allCases, id: \.self) { source in
                        let reading = service.readings[source]
                        Menu {
                            ForEach(EnergyMode.allCases.filter { $0 != .high || reading?.supportsHigh == true }, id: \.self) { mode in
                                Button { service.choose(mode, source: source) } label: {
                                    if reading?.mode == mode { Label(mode.title, systemImage: "checkmark") } else { Text(mode.title) }
                                }
                            }
                        } label: {
                            Image(systemName: source == .battery ? "battery.100" : "powerplug.fill")
                                .font(.system(size: 12)).foregroundStyle(reading?.mode == .low ? Color.accentColor : Color.primary)
                                .frame(width: 28, height: 28).background(AidenteReliefSurface(cornerRadius: 20))
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .disabled(AidenteRuntime.isUIPreview || service.isBusy || reading == nil)
                            .accessibilityLabel((source == .battery ? AidenteL10n.t("电池", "Battery") : AidenteL10n.t("电源", "Adapter")) + " · " + (reading?.mode?.title ?? "—"))
                            .help(source == .battery ? AidenteL10n.t("设置使用电池时的功耗模式", "Set power mode on battery") : AidenteL10n.t("设置接入电源时的功耗模式", "Set power mode on adapter"))
                    }
                }
                if let error = service.error { Text(error).font(.caption2).foregroundStyle(.red) }
            }.onAppear { service.refresh() }
        }
    }
}
struct SpecificationsWidget: View {
    let viewModel: MenuViewModel
    @Default(.popoverMetricIDs) private var metricIDs
    var body: some View {
        let snapshot = MenuBarSnapshot(viewModel: viewModel)
        let metrics = MenuBarMetric.selected(from: metricIDs)
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 && metrics[index - 1].group != metric.group { Divider().opacity(0.45) }
                HStack(spacing: 10) {
                    Label(title(metric), systemImage: metric == .batteryHealth ? "stethoscope" : metric.icon).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    if metric == .batteryHealth {
                        Text(viewModel.estimatedFullCapacityText).monospacedDigit()
                        Text(viewModel.batteryHealthText).monospacedDigit()
                    } else {
                        Text(metric == .timeRemaining && viewModel.adapterConnected && !viewModel.isCharging ? "—" : (snapshot.values[metric.id] ?? "—")).monospacedDigit()
                    }
                }.font(.caption)
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(AidenteL10n.t("规格", "Specifications"))
    }
    private func title(_ metric: MenuBarMetric) -> String {
        if metric == .temperature { return AidenteL10n.t("电池温度", "Battery Temperature") }
        if metric == .timeRemaining { return viewModel.adapterConnected ? AidenteL10n.t("充满所需时间", "Time to Full") : AidenteL10n.t("剩余使用时间", "Time Remaining") }
        return [MenuBarMetric.batteryCurrent, .batteryVoltage, .batteryPower, .adapterCurrent, .adapterVoltage, .adapterPower].contains(metric) ? metric.group + " · " + metric.title : metric.title
    }
}
struct FullDashboardView: View {
    let viewModel: MenuViewModel
    @Default(.lastCalibrationCompleted) private var lastCalibration
    @Default(.dashboardGraphPeriod) private var range
    @Default(.dashboardPowerAverage) private var average
    @Default(.dashboardPowerAverageMinutes) private var averageMinutes
    @Default(.dashboardSkipInactivePeriods) private var skipInactive
    @Default(.dashboardCapacityRange) private var capacityRangeID
    private var capacityRange: CapacityHistoryRange { CapacityHistoryRange(rawValue: capacityRangeID) ?? .all }
    private var timeline: TrendTimeline { skipInactive ? .recorded : .actual }
    private var readings: [DashboardReading] { viewModel.dashboardReadings }
    private var averageReadings: [DashboardReading] {
        let now = Date(), window = [5,15,30].contains(averageMinutes) ? averageMinutes : 15
        return readings.filter { $0.timestamp >= now.addingTimeInterval(-Double(window * 60)) && $0.timestamp <= now }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    UtilitySurface {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(AidenteL10n.t("实时功率分配", "Live Power Flow"), systemImage: "arrow.triangle.branch").font(.headline)
                            PowerSankeyView(powerSource: viewModel.powerSource, isCharging: viewModel.isCharging, batteryPower: viewModel.batteryPower, adapterPower: viewModel.adapterPower, systemPower: viewModel.systemPower, components: viewModel.componentPower)
                                .frame(maxWidth: 600).frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .top)], alignment: .leading, spacing: 16) {
                    specification("电池规格", "bolt.fill") {
                        dashboardValue(AidenteL10n.t("电流", "Current"), String(format: "%.2f A", viewModel.batteryCurrent))
                        dashboardValue(AidenteL10n.t("电压", "Voltage"), String(format: "%.2f V", viewModel.batteryVoltage))
                        dashboardValue(AidenteL10n.t("功率", "Power"), String(format: "%.2f W", viewModel.batteryPower))
                        dashboardValue(AidenteL10n.t("系统负载", "System Load"), String(format: "%.2f W", viewModel.systemPower))
                        dashboardValue(AidenteL10n.t("电池电量", "Charge"), viewModel.currentCapacityText)
                        dashboardValue(viewModel.lastFullChargeTitle, viewModel.lastObservedFullChargeText)
                    }
                    specification("电池健康", "heart.fill") {
                        dashboardValue(AidenteL10n.t("设计容量", "Design Capacity"), viewModel.designCapacityText)
                        dashboardValue(AidenteL10n.t("最大容量", "Full Charge Capacity"), viewModel.estimatedFullCapacityText)
                        dashboardValue(AidenteL10n.t("macOS 状态", "macOS Condition"), viewModel.batteryCondition)
                        dashboardValue(AidenteL10n.t("循环次数", "Cycles"), viewModel.cycleCountText)
                    }
                    specification("电源适配器规格", "powerplug.fill") {
                        dashboardValue(AidenteL10n.t("电流", "Current"), String(format: "%.2f A", viewModel.adapterCurrent))
                        dashboardValue(AidenteL10n.t("电压", "Voltage"), String(format: "%.2f V", viewModel.adapterVoltage))
                        dashboardValue(AidenteL10n.t("功率", "Power"), String(format: "%.2f W", viewModel.adapterPower))
                        dashboardValue(AidenteL10n.t("名称", "Name"), viewModel.adapterName)
                        dashboardValue(AidenteL10n.t("制造商", "Manufacturer"), viewModel.adapterManufacturer)
                        dashboardValue(AidenteL10n.t("适配器固件", "Adapter Firmware"), viewModel.adapterFirmware)
                    }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], alignment: .leading, spacing: 22) {
                        trend("电池电量", value: viewModel.batteryPercentageText, icon: "battery.100percent", color: .green, key: \.percentage)
                        trend("电池循环次数", value: viewModel.cycleCountText, icon: "clock.arrow.circlepath", color: .orange, key: \.cycles)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(AidenteL10n.t("App 用量", "App Activity")).foregroundStyle(.secondary)
                            UtilitySurface { EnergyAppsWidget(viewModel: viewModel) }
                        }
                        trend("电池温度", value: viewModel.batteryTemperatureText, icon: "flame", color: .blue, key: \.temperature)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(AidenteL10n.t("电池功率", "Battery Power")).foregroundStyle(.secondary)
                                Spacer()
                                Menu("\(range) m") { Toggle(AidenteL10n.t("跳过无记录空档", "Skip Recording Gaps"), isOn: $skipInactive); Divider(); ForEach([15,60,180,1440], id: \.self) { period in Button("\(period) m") { range = period } } }.fixedSize()
                            }
                            HStack {
                                Menu {
                                    Button(AidenteL10n.t("当前功率", "Instant Power")) { average = false }
                                    ForEach([5,15,30], id: \.self) { window in
                                        Button(AidenteL10n.t("过去\(window)分钟平均", "Average: Last \(window) Minutes")) { averageMinutes = window; average = true }
                                    }
                                } label: { Text(average ? AidenteL10n.t("\(averageMinutes)分均值", "\(averageMinutes)m Avg") : AidenteL10n.t("当前", "Current")) }.menuStyle(.borderlessButton).fixedSize()
                                Text(average ? (DashboardReading.averagePower(averageReadings).map { String(format:"%.2f W",$0) } ?? "— W") : String(format:"%.2f W",abs(viewModel.batteryPower))).monospacedDigit()
                            }
                            UtilitySurface { SessionTrend(samples: readings,key: \.power,color: .purple, interval: DateInterval(start: Date().addingTimeInterval(Double(-range * 60)), end: Date()), timeline: timeline).frame(height:140) }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(AidenteL10n.t("最大容量", "Maximum Capacity")).foregroundStyle(.secondary)
                                Spacer()
                                Picker("", selection: $capacityRangeID) { ForEach(CapacityHistoryRange.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden().frame(width:90)
                            }
                            Text(viewModel.batteryHealthText).font(.system(size:16,weight:.semibold))
                            UtilitySurface { BatteryCapacityChartView(samples:viewModel.batteryCapacityHistory,range:capacityRange).frame(height:140) }
                            if AidenteRuntime.isUIPreview { Text(AidenteL10n.t("容量历史为演示数据", "Demo capacity history")).font(.caption2) }
                        }
                        UtilitySurface {
                            VStack(alignment:.leading,spacing:12) {
                                Label(AidenteL10n.t("电池校准", "Calibration"),systemImage:"slider.vertical.3")
                                Text(lastCalibration > 0 ? Date(timeIntervalSince1970:lastCalibration).formatted(date:.numeric,time:.omitted) : AidenteL10n.t("尚无 Aidente 校准记录", "No Aidente calibration recorded")).font(.caption)
                                Button { viewModel.toggleCalibration() } label: { Label(AidenteL10n.t(viewModel.calibrationActive ? "取消校准" : "开始校准"),systemImage:viewModel.calibrationActive ? "stop.circle" : "play.circle") }
                                    .disabled(!viewModel.manageChargingEnabled || AidenteRuntime.isUIPreview || viewModel.systemCalibrationActive)
                            }
                        }
                        UtilitySurface { SleepControlWidget() }
                        UtilitySurface { EnergyModeWidget() }
                    }
                }
                .frame(width: max(0, geometry.size.width - 40), alignment: .leading)
                .padding(20)
            }
        }.onAppear { viewModel.menuWillOpen() }.onDisappear { viewModel.menuDidClose() }
    }
    private func specification<Content: View>(_ title: String, _ icon: String, @ViewBuilder content: () -> Content) -> some View {
        UtilitySurface {
            VStack(alignment: .leading, spacing: 4) {
                Label(AidenteL10n.t(title), systemImage: icon).font(.system(size: 13, weight: .semibold)).padding(.bottom, 3)
                content()
                Spacer(minLength: 0)
            }.frame(minHeight: 140, alignment: .top)
        }.frame(maxWidth: .infinity)
    }
    private func trend(_ title: String, value: String, icon: String, color: Color, key: KeyPath<DashboardReading, Double>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AidenteL10n.t(title)).foregroundStyle(.secondary)
            HStack {
                Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                Spacer()
                Image(systemName: icon).font(.system(size: 17))
            }
            UtilitySurface { SessionTrend(samples: readings, key: key, color: color, interval: DateInterval(start: Date().addingTimeInterval(Double(-range * 60)), end: Date()), timeline: timeline).frame(height: 140) }
        }
    }
}

struct SessionTrend: View {
    let samples: [DashboardReading]
    let key: KeyPath<DashboardReading, Double>
    let color: Color
    var interval: DateInterval? = nil
    let timeline: TrendTimeline
    let showAxes: Bool
    @State private var selectedDate: Date?
    private let snapshot: TrendChartSnapshot
    init(samples: [DashboardReading], key: KeyPath<DashboardReading, Double>, color: Color, interval: DateInterval? = nil, timeline: TrendTimeline = .actual, showAxes: Bool = true) {
        self.samples = samples; self.key = key; self.color = color; self.interval = interval; self.timeline = timeline; self.showAxes = showAxes
        let metric: TrendMetric = key == \.percentage ? .percentage : key == \.temperature ? .temperature : key == \.power ? .power : key == \.cycles ? .cycles : .health
        snapshot = TrendChartSnapshot(samples: samples, metric: metric, interval: interval, timeline: timeline)
    }
    private var selected: DashboardReading? {
        guard let date = selectedDate else { return nil }
        return snapshot.nearestObservation(to: date)
    }
    private func inspect(_ point: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { selectedDate = nil; return }
        let frame = geometry[anchor]
        guard frame.contains(point) else { selectedDate = nil; return }
        GraphInteractionState.shared.isInspecting = true
        selectedDate = proxy.value(atX: point.x - frame.minX, as: Date.self)
    }
    private func formatted(_ value: Double) -> String {
        if key == \.percentage { return String(format: "%.0f%%", value) }
        if key == \.temperature { return String(format: "%.1f °C", value) }
        if key == \.power { return String(format: "%.2f W", value) }
        return String(format: "%.0f", value)
    }
    @ChartContentBuilder
    private func sampleMarks(_ sample: DashboardReading, segment: Int, baseline: Double, single: Bool) -> some ChartContent {
        let plotTime = snapshot.plotDate(for: sample.timestamp)
        AreaMark(x: .value("Time", plotTime), yStart: .value("Base", baseline), yEnd: .value("Value", sample[keyPath: key]), series: .value("Series", "battery-\(segment)"))
            .foregroundStyle(LinearGradient(colors: [color.opacity(0.2), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("Time", plotTime), y: .value("Value", sample[keyPath: key]), series: .value("Series", "battery-\(segment)"))
            .foregroundStyle(key == \.percentage ? Color.yellow.opacity(0.85) : color).lineStyle(StrokeStyle(lineWidth: 1.3))
        if key == \.power {
            if let adapter = sample.adapterPower, adapter.isFinite, (0...1000).contains(adapter) {
                LineMark(x: .value("Time", plotTime), y: .value("Adapter", adapter), series: .value("Series", "adapter-\(segment)"))
                    .foregroundStyle(Color.blue).lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            if let system = sample.systemPower, system.isFinite, (0...1000).contains(system) {
                LineMark(x: .value("Time", plotTime), y: .value("Mac", system), series: .value("Series", "mac-\(segment)"))
                    .foregroundStyle(Color.green).lineStyle(StrokeStyle(lineWidth: 1.2))
            }
        }
        if single {
            PointMark(x: .value("Time", plotTime), y: .value("Value", sample[keyPath: key])).foregroundStyle(color).symbolSize(9)
        }
        if key == \.percentage, let limit = sample.chargeLimit, (0...100).contains(limit) {
            LineMark(x: .value("Time", plotTime), y: .value("Limit", limit), series: .value("Series", "limit-\(segment)"))
                .foregroundStyle(Color.orange.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).interpolationMethod(.stepEnd)
        }
    }
    var body: some View {
        let focus = selected
        let bands = snapshot.segments
        let yRange = snapshot.domain
        let xRange = snapshot.times
        let span = (snapshot.observations.last?.timestamp.timeIntervalSince(snapshot.observations.first?.timestamp ?? Date())) ?? 0
        let axisFormat: Date.FormatStyle = span >= 16 * 3600 ? .dateTime.day().hour().minute() : .dateTime.hour().minute()
        VStack(alignment: .leading, spacing: 4) {
            // Reserve a stable inspection strip so hovering never changes card/window size.
            HStack(spacing: 8) {
                if let selected = focus {
                    Text(selected.timestamp.formatted(.dateTime.month().day().hour().minute().second()))
                    Spacer(minLength: 0)
                    Text((key == \.power ? AidenteL10n.t("电池 ", "Battery ") : "") + formatted(selected[keyPath: key])).fontWeight(.semibold)
                    if key == \.power, let system = selected.systemPower { Text(String(format: AidenteL10n.t("电脑 %.2f W", "Mac %.2f W"), system)) }
                    if key == \.percentage, let limit = selected.chargeLimit {
                        Text(AidenteL10n.t("上限 \(Int(limit))%", "Limit \(Int(limit))%"))
                    }
                } else {
                    Text(selectedDate == nil ? (timeline == .recorded ? AidenteL10n.t("跳过空档 · 悬停查看原始时间", "Gaps skipped · hover for original time") : AidenteL10n.t("按实际时间 · 悬停查看读数", "Clock time · hover to inspect")) : AidenteL10n.t("此时间附近没有采样", "No observation near this time"))
                }
            }.font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary).frame(height: 12)
            if key == \.power {
                HStack(spacing: 10) {
                    Text(AidenteL10n.t("电池", "Battery")).foregroundStyle(color)
                    Text(AidenteL10n.t("适配器", "Adapter")).foregroundStyle(.blue)
                    Text(AidenteL10n.t("电脑", "Mac")).foregroundStyle(.green)
                }.font(.system(size: 8))
            }
            if snapshot.observations.isEmpty {
                Text(AidenteL10n.t("正在收集趋势数据…", "Collecting trend data…")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(Array(bands.enumerated()), id: \.offset) { segment, values in
                        ForEach(values) { sample in
                            sampleMarks(sample, segment: segment, baseline: yRange.lowerBound, single: values.count == 1)
                        }
                    }
                    if let selected = focus {
                        RuleMark(x: .value("Time", snapshot.plotDate(for: selected.timestamp))).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        PointMark(x: .value("Time", snapshot.plotDate(for: selected.timestamp)), y: .value("Value", selected[keyPath: key])).foregroundStyle(color).symbolSize(26)
                    }
                }.chartXScale(domain: xRange).chartYScale(domain: yRange)
                    .chartYAxis {
                        if showAxes {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { axis in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                            AxisValueLabel {
                                if let value = axis.as(Double.self) {
                                    Text(key == \.power ? String(format: yRange.upperBound < 10 ? "%.1f W" : "%.0f W", value) : formatted(value))
                                        .font(.system(size: 8)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        }
                    }
                    .chartXAxis {
                        if showAxes {
                        AxisMarks(values: .automatic(desiredCount: 3)) { tick in
                            AxisValueLabel {
                                if let date = tick.as(Date.self) {
                                    let actual = snapshot.actualTime(at: date)
                                    Text(actual.formatted(axisFormat)).font(.system(size: 8))
                                }
                            }
                        }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location): inspect(location, proxy: proxy, geometry: geometry)
                                    case .ended: selectedDate = nil; GraphInteractionState.shared.isInspecting = false
                                    }
                                }
                                .gesture(DragGesture(minimumDistance: 0).onChanged { event in inspect(event.location, proxy: proxy, geometry: geometry) })
                        }
                    }
                    .accessibilityElement(children: timeline == .recorded ? .ignore : .contain)
                    .accessibilityLabel(AidenteL10n.t("历史曲线，移动指针查看真实采样时间和读数", "History: hover to inspect actual observation time and value"))
                    .accessibilityValue(snapshot.observations.first.map { first in
                        first.timestamp.formatted(date: .abbreviated, time: .shortened) + " – " + (snapshot.observations.last?.timestamp ?? first.timestamp).formatted(date: .abbreviated, time: .shortened)
                    } ?? AidenteL10n.t("尚无记录", "No observations"))
            }
        }.onDisappear { GraphInteractionState.shared.isInspecting = false }.onChange(of: interval.map { Int($0.duration.rounded()) }) { _, _ in selectedDate = nil }.onChange(of: timeline) { _, _ in selectedDate = nil }
    }
}
