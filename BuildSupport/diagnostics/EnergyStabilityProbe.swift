import Foundation

@main struct EnergyStabilityProbe {
    static func main() throws {
        for index in 0..<12 {
            let rows = AppEnergyUsageService.readTopApps(minimumCPU: 5)
            let report: [String: Any] = ["index":index,"time":ISO8601DateFormatter().string(from:Date()),"ready":rows != nil,"apps":(rows ?? []).map { ["name":$0.name,"reading":$0.measurementText] }]
            let data = try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys])
            print(String(decoding:data,as:UTF8.self))
            fflush(stdout)
            if index < 11 { Thread.sleep(forTimeInterval:2) }
        }
    }
}
