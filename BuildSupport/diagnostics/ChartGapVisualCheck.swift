import AidenteShared
import AppKit
import SwiftUI

enum AidenteL10n { static func t(_ zh:String,_ en:String)->String{zh} }
@main struct ChartGapVisualCheck {
    @MainActor static func main() throws {
        let start=Date(timeIntervalSince1970:1000)
        func row(_ time:Double,_ value:Double)->DashboardReading {
            DashboardReading(timestamp:start.addingTimeInterval(time),percentage:value,temperature:30,power:value,cycles:20,health:95)
        }
        let rows=[row(0,20),row(10,30),row(100,60),row(110,55)]
        for key:KeyPath<DashboardReading,Double> in [\.percentage,\.power] {
            let content=SessionTrend(samples:rows,key:key,color:.green,interval:DateInterval(start:start,end:start.addingTimeInterval(120)))
                .frame(width:360,height:140).background(.white).environment(\.colorScheme,.light)
            let renderer=ImageRenderer(content:content);renderer.scale=2
            guard let image=renderer.cgImage else{throw CocoaError(.fileReadUnknown)}
            let bitmap=NSBitmapImageRep(cgImage:image)
            var colored=0
            for x in (bitmap.pixelsWide/2-3)...(bitmap.pixelsWide/2+3) {
                // Skip the power legend/inspection strip; the plot gap must stay empty.
                for y in 65..<(bitmap.pixelsHigh-24) {
                    if let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) {
                        let channels=[color.redComponent,color.greenComponent,color.blueComponent]
                        if (channels.max()!-channels.min()!) > 0.12 {colored += 1}
                    }
                }
            }
            precondition(colored==0,"Missing interval must contain no colored cross-gap line or fill")
        }
        print("PASS: production chart renderer leaves missing intervals empty for battery and power")
    }
}
