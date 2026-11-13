import Foundation
import smc_power
import SMCKit
let v = try SMCBattery.getVoltage(), a = try SMCBattery.getCurrent()
let av = try SMCAdapter.getVoltage(), aa = try SMCAdapter.getCurrent()
let output: [String: Any] = ["timestamp":ISO8601DateFormatter().string(from: Date()),
    "displayPercent":try SMCBattery.macOSPercentage(),"rawPercent":try SMCBattery.firmwarePercentageExact(),
    "externalConnected":try SMCBattery.externalPowerConnected(),
    "temperatureC":(try? SMCBattery.temperatureCelsius()) ?? -1,"batteryW":v*a,"adapterW":av*aa,"batteryA":a,
    "forcedDischargeRegister":(try? SMCBattery.probe().getForceDischarging()) ?? false,"ledRegister":(try? SMCAdapter.probe().getMagSafeLEDState().rawValue) ?? 255,"nativeLimit":try NativeChargeLimit().read().limit]
print(String(data: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), encoding:.utf8)!)
