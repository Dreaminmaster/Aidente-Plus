import AidenteShared
import Charts
import Defaults
import SwiftUI

enum CapacityHistoryRange: String, CaseIterable, Identifiable {
    case month
    case year
    case all

    var id: String { rawValue }

    var duration: TimeInterval? {
        switch self {
        case .month: 30 * 24 * 60 * 60
        case .year: 365 * 24 * 60 * 60
        case .all: nil
        }
    }

    var title: String {
        switch self {
        case .month: AidenteL10n.t("30 天", "30 Days")
        case .year: AidenteL10n.t("1 年", "1 Year")
        case .all: AidenteL10n.t("全部", "All")
        }
    }
}

struct BatteryCapacityChartView: View {
    let samples: [BatteryCapacitySample]
    let range: CapacityHistoryRange
    @State private var selectedDate: Date?
    private var visibleSamples: [BatteryCapacitySample] {
        let cutoff = range.duration.map { Date().addingTimeInterval(-$0) } ?? .distantPast
        return samples.filter { $0.timestamp >= cutoff && $0.timestamp <= Date() && $0.estimatedFullChargeCapacityMilliampHours > 0 }.sorted { $0.timestamp < $1.timestamp }
    }
    private var indexed: [(sample: BatteryCapacitySample, segment: Int)] {
        var segment = 0; var previous: Date?
        return visibleSamples.map { sample in
            if let previous, sample.timestamp.timeIntervalSince(previous) > 172800 { segment += 1 }
            previous = sample.timestamp
            return (sample, segment)
        }
    }
    private var selected: BatteryCapacitySample? {
        guard let selectedDate,
              let index = TrendSelection.nearest(in: visibleSamples.map(\.timestamp), to: selectedDate, tolerance: 86400) else { return nil }
        return visibleSamples[index]
    }
    private var capacityDomain: ClosedRange<Double> {
        let values = visibleSamples.map { Double($0.estimatedFullChargeCapacityMilliampHours) }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let margin = max(20, (high - low) * 0.2)
        return max(0, low - margin)...(high + margin)
    }
    private func inspect(_ point: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { selectedDate = nil; return }
        let frame = geometry[anchor]
        guard frame.contains(point) else { selectedDate = nil; return }
        GraphInteractionState.shared.isInspecting = true
        selectedDate = proxy.value(atX: point.x - frame.minX, as: Date.self)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let selected {
                    Text(selected.timestamp.formatted(.dateTime.year().month().day().hour().minute()))
                    Spacer(minLength: 0)
                    Text("\(selected.estimatedFullChargeCapacityMilliampHours) mAh")
                    Text(String(format: "%.1f%%", selected.batteryHealth))
                } else {
                    Text(selectedDate == nil ? AidenteL10n.t("移动指针查看最大容量记录", "Hover to inspect maximum capacity") : AidenteL10n.t("此时间附近没有采样", "No observation near this time"))
                }
            }.font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary).frame(height: 12)
            if visibleSamples.isEmpty {
                Text(AidenteL10n.t("正在收集容量记录…", "Collecting capacity history…")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(indexed, id: \.sample.id) { entry in
                        let sample = entry.sample
                        let series = entry.segment
                        LineMark(x: .value("Time", sample.timestamp), y: .value("Maximum Capacity", sample.estimatedFullChargeCapacityMilliampHours), series: .value("Series", "capacity-\(series)"))
                            .foregroundStyle(Color.green).lineStyle(StrokeStyle(lineWidth: 1.5))
                        PointMark(x: .value("Time", sample.timestamp), y: .value("Maximum Capacity", sample.estimatedFullChargeCapacityMilliampHours)).foregroundStyle(Color.green).symbolSize(10)
                    }
                    if let selected {
                        RuleMark(x: .value("Time", selected.timestamp)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        PointMark(x: .value("Time", selected.timestamp), y: .value("Maximum Capacity", selected.estimatedFullChargeCapacityMilliampHours)).foregroundStyle(Color.green).symbolSize(28)
                    }
                }.chartYScale(domain: capacityDomain).chartYAxis(.hidden)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month().day()).font(.system(size: 8)) } }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let point): inspect(point, proxy: proxy, geometry: geometry)
                                    case .ended: selectedDate = nil; GraphInteractionState.shared.isInspecting = false
                                    }
                                }
                                .gesture(DragGesture(minimumDistance: 0).onChanged { event in inspect(event.location, proxy: proxy, geometry: geometry) })
                        }
                    }
            }
        }.onDisappear { GraphInteractionState.shared.isInspecting = false }.onChange(of: range) { _, _ in selectedDate = nil }
        .accessibilityLabel(AidenteL10n.t("最大容量历史，移动指针查看采样时间、毫安时与健康度", "Maximum capacity history: hover to inspect time, capacity and health"))
    }
}
