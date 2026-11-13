import AppKit
import SwiftUI

enum AidenteL10n { static func t(_ zh: String, _ en: String) -> String { zh } }
struct SliderInteractionFixture: View {
    @State private var limit = 75.0
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            Text("只读交互演示 · 不控制硬件").font(.caption).foregroundStyle(.secondary)
            Text("上限：\(Int(limit))%  ·  当前：74%")
            PopoverChargeSlider(value:$limit,percentage:74,showPercentage:true,adapterConnected:true,chargingMode:.pluggedIn,sailing:true,minimum:20,sailingLower:70,enabled:true,onEditing:{ editing in print("EDIT \(editing) LIMIT \(limit)"); fflush(stdout) })
                .onChange(of:limit) { _, value in print("DRAG_VALUE \(value)"); fflush(stdout) }
            Text("正在充电 · 原生合成高光").font(.caption).foregroundStyle(.secondary)
            PopoverChargeSlider(value:.constant(80),percentage:50,showPercentage:true,adapterConnected:true,chargingMode:.charging,sailing:false,minimum:20,sailingLower:nil,enabled:true,onEditing:{_ in})
        }.padding(20).frame(width:402).background(Color(white:0.12)).foregroundStyle(.white).environment(\.colorScheme,.dark)
    }
}
@main struct SliderInteractionPreview {
    @MainActor static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.regular)
        let window=NSWindow(contentViewController:NSHostingController(rootView:SliderInteractionFixture()))
        window.title="Aidente Slider Preview"; window.styleMask=[.titled,.closable]
        window.appearance=NSAppearance(named:.darkAqua);window.center();window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps:true);app.run()
    }
}
