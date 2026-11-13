import AidenteShared
import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum AidenteL10n { static func t(_ zh:String,_ en:String) -> String { zh } }
@main struct HistoryChartPreview {
    @MainActor static func main() throws {
        let source=URL(fileURLWithPath:CommandLine.arguments[1])
        let all=try JSONDecoder().decode([DashboardReading].self,from:Data(contentsOf:source))
        let now=Date(), rows=DashboardReading.retained(all,now:Date())
        let range=DateInterval(start:now.addingTimeInterval(-86400),end:now)
        let view=VStack(alignment:.leading,spacing:18) {
            Text("真实历史 · 过去24小时 / 跳过空档").font(.headline)
            ForEach([TrendTimeline.actual, .recorded], id: \.rawValue) { mode in
                Text(mode == .actual ? "按实际时间" : "跳过无记录空档").font(.caption)
                SessionTrend(samples:rows,key:\.percentage,color:.green,interval:range,timeline:mode,showAxes:true).frame(height:100)
                SessionTrend(samples:rows,key:\.power,color:.purple,interval:range,timeline:mode,showAxes:true).frame(height:100)
            }
        }.padding(16).frame(width:402).background(Color(white:0.94)).environment(\.colorScheme,.light)
        let renderer=ImageRenderer(content:view);renderer.scale=2
        guard let image=renderer.cgImage,let output=CGImageDestinationCreateWithURL(URL(fileURLWithPath:CommandLine.arguments[2]) as CFURL,UTType.png.identifier as CFString,1,nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(output,image,nil);guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
    }
}
