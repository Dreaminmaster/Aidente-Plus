import Foundation
import smc_power
let client = try NativeChargeLimit()
guard CommandLine.arguments.count == 2 else { fatalError("Specify disable or restore95") }
switch CommandLine.arguments[1] {
case "disable": try client.disable()
case "restore95": try client.set(95)
default: fatalError("Unknown operation")
}
print(try client.read())
