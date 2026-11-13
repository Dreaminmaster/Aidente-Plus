import AppKit
import SwiftUI

enum AidenteL10n { static func t(_ a: String, _ b: String) -> String { a } }
@main struct FlowPreview {
    @MainActor static func main() throws {
        let view = VStack(alignment: .leading, spacing: 20) {
            Text("测试数据：适配器60W → 电池40W + 电脑20W").font(.caption)
            PowerSankeyView(powerSource: .acAdapter, isCharging: true, batteryPower: 40, adapterPower: 60, systemPower: 20)
            Text("测试数据：适配器20W + 电池10W → 电脑30W").font(.caption)
            PowerSankeyView(powerSource: .both, isCharging: false, batteryPower: -10, adapterPower: 20, systemPower: 30)
        }.padding(20).frame(width:402).background(Color(white:0.94)).environment(\.colorScheme,.light)
        let renderer = ImageRenderer(content:view); renderer.scale = 2
        guard let cg = renderer.cgImage else { throw CocoaError(.fileReadCorruptFile) }
        let data = NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
    }
}
