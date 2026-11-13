import AidenteShared
import Foundation

@main struct TrendPerformanceProbe {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let real = try JSONDecoder().decode([DashboardReading].self, from: data)
        let start = Date(timeIntervalSince1970: 1000)
        var dense: [DashboardReading] = []
        for i in 0..<5760 {
            let date = start.addingTimeInterval(Double(i) * 15)
            let battery = Double(i % 70), adapter = Double(i % 90), system = Double(i % 80)
            dense.append(DashboardReading(timestamp: date, percentage: 80, temperature: 30, power: battery, cycles: 100, health: 95, chargeLimit: 80, adapterPower: adapter, systemPower: system))
        }
        var results: [[String: Any]] = []
        for (name, rows, mode) in [("actual-retained-history", real, TrendTimeline.actual), ("recorded-retained-history", real, .recorded), ("synthetic-24h-at-15s", dense, .recorded)] {
            let begin = DispatchTime.now().uptimeNanoseconds
            var points = 0
            for _ in 0..<10 { points = TrendChartSnapshot(samples: rows, metric: .power, timeline: mode).segments.reduce(0) { $0 + $1.count } }
            results.append(["case":name,"observations":rows.count,"drawnPoints":points,"preparationMeanMilliseconds":Double(DispatchTime.now().uptimeNanoseconds-begin)/10/1e6])
        }
        let output = try JSONSerialization.data(withJSONObject: results, options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:output,as:UTF8.self))
    }
}
