import Foundation
import AidenteShared
import smc_power
struct Sample: Encodable {
    let component: ComponentPowerReading
    let adapter: Double?
    let battery: Double?
}
for _ in 0..<5 {
    let adapter = try? SMCAdapter.getVoltage() * SMCAdapter.getCurrent()
    let battery = try? SMCBattery.getVoltage() * SMCBattery.getCurrent()
    let data = try JSONEncoder().encode(Sample(component: ComponentPowerSensors.read(), adapter: adapter, battery: battery))
    print(String(decoding: data, as: UTF8.self))
    Thread.sleep(forTimeInterval: 1)
}
