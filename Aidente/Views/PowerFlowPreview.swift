import AidenteShared
import AppKit
import Defaults
import SwiftUI

/// Hardware-free snapshots of production flow views; uses the isolated preview preferences.
@MainActor enum PowerFlowPreview {
    static func render(to directory:String) throws {
        guard AidenteRuntime.isUIPreview else { throw CocoaError(.userCancelled) }
        let destination=URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let old=Defaults[.interfaceMaterialStyle]
        defer { Defaults[.interfaceMaterialStyle]=old }
        for style in InterfaceMaterialStyle.allCases {
            Defaults[.interfaceMaterialStyle]=style
            for dark in [false,true] {
                let content=VStack(spacing:18) {
                    Text("\(style.rawValue) · \(dark ? "dark":"light")").font(.headline)
                    specimen("Hold",adapter:18.6,battery:0,soc:6.19)
                    specimen("Charging",adapter:44.3,battery:25,soc:6.59)
                    specimen("Battery",adapter:0,battery:-18.6,soc:6.19)
                    specimen("Assistance",adapter:20,battery:-10,soc:8.1)
                }.padding(24).frame(width:430).background(dark ? Color(white:0.12):Color(white:0.94))
                    .environment(\.colorScheme,dark ? .dark:.light)
                    .transaction { $0.animation=nil;$0.disablesAnimations=true }
                let view=NSHostingView(rootView:content)
                let size=view.fittingSize;view.frame=CGRect(origin:.zero,size:size)
                let window=NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.contentView=view;window.appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
                view.layoutSubtreeIfNeeded();window.displayIfNeeded()
                RunLoop.current.run(until:Date().addingTimeInterval(0.15))
                guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw CocoaError(.fileWriteUnknown) }
                view.cacheDisplay(in:view.bounds,to:bitmap)
                guard let png=bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to:destination.appendingPathComponent("flow-\(style.rawValue)-\(dark ? "dark":"light").png"))
                window.contentView=nil;window.close()
            }
        }
    }
    private static func specimen(_ name:String,adapter:Double,battery:Double,soc:Double)->some View {
        VStack(alignment:.leading,spacing:0) {
            Text(name).font(.caption)
            PowerSankeyView(powerSource:adapter>0 ? .acAdapter:.battery,isCharging:battery>0,batteryPower:battery,adapterPower:adapter,systemPower:adapter-battery,components:ComponentPowerReading(soc:soc,display:nil,usb:nil),previewPhase:0.48)
        }
    }
}
