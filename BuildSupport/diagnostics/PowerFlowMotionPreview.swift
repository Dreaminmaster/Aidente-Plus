import AidenteShared
import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum AidenteL10n { static func t(_ a: String, _ b: String) -> String { a } }
@main struct MotionPreview {
    @MainActor static func render(phase: Double, dark: Bool) -> CGImage? {
        let content = VStack(alignment: .leading, spacing: 18) {
            Text("视觉预览 · 测试数据").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            PowerSankeyView(powerSource: .acAdapter, isCharging: true, batteryPower: 46.53, adapterPower: 56.54, systemPower: 10.01, components: ComponentPowerReading(soc: 2.05, display: nil, usb: nil), previewPhase: phase)
            PowerSankeyView(powerSource: .acAdapter, isCharging: false, batteryPower: 0, adapterPower: 14.3, systemPower: 14.3, components: ComponentPowerReading(soc: 3.17, display: nil, usb: nil), previewPhase: phase)
            PowerSankeyView(powerSource: .battery, isCharging: false, batteryPower: -12, adapterPower: 0, systemPower: 12, components: ComponentPowerReading(soc: 5, display: nil, usb: nil), previewPhase: phase)
            PowerSankeyView(powerSource: .both, isCharging: false, batteryPower: -10, adapterPower: 20, systemPower: 30, components: ComponentPowerReading(soc: 18, display: nil, usb: nil), previewPhase: phase)
        }.padding(20).frame(width: 402).background(Color(white: dark ? 0.12 : 0.95))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content); renderer.scale = 2
        return renderer.cgImage
    }
    @MainActor static func main() throws {
        let path = CommandLine.arguments[1]; let dark = CommandLine.arguments.count < 3 || CommandLine.arguments[2] == "dark"
        let frames = path.hasSuffix(".gif") ? 28 : 1
        let kind = path.hasSuffix(".gif") ? UTType.gif.identifier : UTType.png.identifier
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath:path) as CFURL, kind as CFString, frames, nil) else { throw CocoaError(.fileWriteUnknown) }
        if frames > 1 { CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary) }
        for frame in 0..<frames {
            guard let image = render(phase: frames > 1 ? Double(frame)/Double(frames) : 0.4, dark:dark) else { throw CocoaError(.fileReadCorruptFile) }
            CGImageDestinationAddImage(destination, image, frames > 1 ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary : nil)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
