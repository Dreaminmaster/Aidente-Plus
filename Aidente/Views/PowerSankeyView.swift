import AidenteShared
import SwiftUI
import Defaults

struct PowerSankeyView: View {
    let powerSource: PowerSource
    let isCharging: Bool
    let batteryPower: Double
    let adapterPower: Double
    let systemPower: Double
    var components: ComponentPowerReading? = nil
    var previewPhase: Double? = nil
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 8) {
            if let power = PowerFlowReading(adapterConnected: powerSource != .battery, adapterPower: adapterPower, batteryPower: batteryPower) {
                LivePowerDiagram(power: power, breakdown: components?.breakdown(total: power.computer), previewPhase: previewPhase)
                detailToggle(power: power)
            } else {
                Label(AidenteL10n.t("等待一致的功率读数…", "Waiting for consistent power readings…"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).frame(maxWidth: .infinity, minHeight: 128)
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(AidenteL10n.t("实时功率分配", "Live Power Flow"))
    }
    @ViewBuilder private func detailToggle(power: PowerFlowReading) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(AidenteL10n.t("功率详情", "Power Details"))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }.font(.caption).foregroundStyle(.secondary).contentShape(Rectangle())
            }.buttonStyle(.plain).help(AidenteL10n.t("展开芯片、显示屏和 USB 的功率读数与说明", "Expand component readings and explanations"))
            if expanded {
                let parts = components?.breakdown(total: power.computer)
                ForEach(0..<4) { index in
                    HStack {
                        Text(["SoC", AidenteL10n.t("显示屏", "Display"), "USB", AidenteL10n.t("其他", "Other")][index])
                        Spacer()
                        Text(parts?[index].map { String(format: "%.2f W", $0) } ?? AidenteL10n.t("暂无可靠读数", "Unavailable"))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }.font(.caption)
                }
                Text(AidenteL10n.t("SoC 包括芯片内的 CPU 和 GPU。其他为电脑总功率减去已测分项，包含未单独测量的用电。App 能耗排行独立显示，不表示给 App 单独供电。", "SoC includes CPU and GPU. Other is Mac power minus measured components and includes unmeasured loads. App energy usage is shown separately, not as a dedicated power supply."))
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Layered highlights and shadows give neutral controls a shallow, raised surface.
struct AidenteReliefSurface: View {
    @Default(.interfaceMaterialStyle) private var material
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 15
    var pressed = false
    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if material != .solid {
                AidenteVisualEffectView(material: material == .frosted ? .hudWindow : .popover, blendingMode: .withinWindow)
            }
            shape.fill(LinearGradient(colors: dark
                ? [Color(white: pressed ? 0.22 : 0.265), Color(white: 0.235), Color(white: 0.215)]
                : [Color(white: pressed ? 0.88 : 0.97), Color(white: 0.925), Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                .opacity(material == .solid ? 1 : material == .frosted ? 0.88 : material == .glass ? 0.66 : 0.44)
            if material == .liquidGlass { AidenteLiquidGlassHighlights() }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.23 : 0.9), .white.opacity(0.04), .black.opacity(dark ? 0.40 : 0.16)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
        .shadow(color: .black.opacity(dark ? 0.24 : 0.09), radius: pressed ? 1 : 3, x: 0, y: pressed ? 0.5 : 2)
            .allowsHitTesting(false)
    }
}


private struct LivePowerDiagram: View {
    let power: PowerFlowReading
    let breakdown: [Double?]?
    let previewPhase: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var entries: [(Int, Double)] { (breakdown ?? []).enumerated().compactMap { i, v in v.map { (i, $0) } } }
    private let names = ["SoC", AidenteL10n.t("显示屏", "Display"), "USB", AidenteL10n.t("其他", "Other")]
    private let icons = ["cpu", "display", "cable.connector", "ellipsis"]
    private func accent(_ index: Int) -> Color? {
        // Distinct low-saturation hues keep the branches legible in both appearances.
        switch index { case 0: return Color(red: 0.47, green: 0.53, blue: 0.72)
        case 1: return Color(red: 0.48, green: 0.65, blue: 0.51)
        case 2: return Color(red: 0.63, green: 0.51, blue: 0.70)
        default: return Color(red: 0.40, green: 0.62, blue: 0.65) }
    }
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let h = geo.size.height
            let node: CGFloat = 28
            let meter: CGFloat = min(70, max(52, width * 0.195))
            let sourceEnd = node + 4 + meter
            let macLeft = sourceEnd + (power.batteryInput > 0.01 || (power.batteryOutput > 0.01 && power.adapter > 0.01) ? max(34, width * 0.115) : 4)
            let branchStart = macLeft + node + 4
            let end = width - node - 4
            let charging = power.batteryInput > 0.01
            let assisting = power.batteryOutput > 0.01 && power.adapter > 0.01
            let chargeHeight: CGFloat = charging ? 36 : 0
            let macTop: CGFloat = charging ? chargeHeight + 8 : 0
            let macHeight = h - macTop
            let inputFraction = power.adapter > 0 ? power.batteryInput / power.adapter : 0
            let parts = entries
            let topOutset: CGFloat = charging ? 0 : 10
            let bottomOutset: CGFloat = 10
            let branchGap: CGFloat = parts.count > 2 ? 8 : 26
            let heights = destinationHeights(parts.map { $0.1 }, available: macHeight + topOutset + bottomOutset - CGFloat(max(0, parts.count-1))*branchGap)
            let phase = previewPhase
                ZStack(alignment: .topLeading) {
                    if assisting {
                        PowerRibbon(left: sourceEnd, right: parts.isEmpty ? end : macLeft,
                                    top: 0, bottom: (h-8)/2, endTop: 0, endBottom: h * power.batteryOutput / max(0.1,power.computer), tint: nil, phase: phase)
                        PowerRibbon(left: sourceEnd, right: parts.isEmpty ? end : macLeft,
                                    top: (h+8)/2, bottom: h, endTop: h * power.batteryOutput / max(0.1,power.computer), endBottom: h, tint: nil, phase: phase)
                    } else {
                        if charging {
                            PowerRibbon(left: sourceEnd, right: end, top: 0, bottom: h*inputFraction,
                                        endTop: 0, endBottom: chargeHeight, tint: Color(red: 0.40, green: 0.66, blue: 0.53), phase: phase)
                        }
                        if charging || parts.isEmpty {
                        PowerRibbon(left: sourceEnd, right: parts.isEmpty ? end : macLeft,
                                    top: charging ? h*inputFraction : 0, bottom: h, endTop: macTop, endBottom: h, tint: Color(red: 0.40, green: 0.57, blue: 0.67), phase: phase)
                        }
                    }
                    if !parts.isEmpty {
                        ForEach(Array(parts.enumerated()), id: \.element.0) { row, part in
                            let rowHeight = heights[row]
                            let before = parts.prefix(row).map { $0.1 }.reduce(0,+)
                            let fraction = power.computer > 0 ? part.1 / power.computer : 1/Double(parts.count)
                            let startTop = macTop + macHeight * (power.computer > 0 ? before/power.computer : Double(row)/Double(parts.count))
                            let rowTop = macTop - topOutset + heights.prefix(row).reduce(0,+) + CGFloat(row)*branchGap
                            PowerRibbon(left: branchStart, right: end, top: startTop, bottom: startTop+macHeight*fraction,
                                        endTop: rowTop, endBottom: rowTop+rowHeight, tint: accent(part.0), phase: phase)
                            destination(icon: icons[part.0], name: names[part.0], watts: part.1, height: rowHeight)
                                .frame(width: width-branchStart).position(x:(branchStart+width)/2,y:rowTop+rowHeight/2)
                        }
                        Image(systemName:"laptopcomputer").font(.system(size:12,weight:.medium)).frame(width:node,height:macHeight)
                            .background(AidenteReliefSurface(cornerRadius:4)).position(x:macLeft+node/2,y:macTop+macHeight/2)
                            .help(AidenteL10n.t("电脑内部用电分项", "Mac hardware power breakdown"))
                    } else {
                        destination(icon:"laptopcomputer",name:AidenteL10n.t("电脑使用", "Mac"),watts:power.computer,height:macHeight)
                            .frame(width:width-sourceEnd).position(x:(sourceEnd+width)/2,y:macTop+macHeight/2)
                    }
                    if charging {
                        destination(icon:"battery.100.bolt",name:AidenteL10n.t("充入电池", "To Battery"),watts:power.batteryInput,height:chargeHeight)
                            .frame(width:width-sourceEnd).position(x:(sourceEnd+width)/2,y:chargeHeight/2)
                    }
                    if assisting {
                        source(icon:"battery.100",name:AidenteL10n.t("电池供电", "Battery"),watts:power.batteryOutput,meter:meter,height:(h-8)/2)
                            .position(x:sourceEnd/2,y:(h-8)/4)
                        source(icon:"powerplug.portrait.fill",name:AidenteL10n.t("适配器", "Adapter"),watts:power.adapter,meter:meter,height:(h-8)/2)
                            .position(x:sourceEnd/2,y:(h+8)/2+(h-8)/4)
                    } else {
                        source(icon:power.adapter > 0.01 ? "powerplug.portrait.fill" : "battery.100",name:power.adapter > 0.01 ? AidenteL10n.t("适配器", "Adapter") : AidenteL10n.t("电池供电", "Battery"),watts:power.adapter > 0.01 ? power.adapter : power.batteryOutput,meter:meter,height:h)
                            .position(x:sourceEnd/2,y:h/2)
                    }
                }
        }.frame(height:128).padding(.vertical, 10)
    }
    private func destinationHeights(_ weights: [Double], available: CGFloat) -> [CGFloat] {
        guard !weights.isEmpty else { return [] }
        let minimum = min(24, max(0,available) / CGFloat(weights.count))
        var result = Array(repeating: CGFloat(0), count: weights.count)
        var remaining = max(0,available), open = Array(weights.indices)
        while !open.isEmpty {
            let total = open.reduce(0.0) { $0 + max(0,weights[$1]) }
            let undersized = open.filter { remaining * CGFloat(total > 0 ? max(0,weights[$0])/total : 1/Double(open.count)) < minimum }
            if undersized.isEmpty {
                for index in open { result[index] = remaining * CGFloat(total > 0 ? max(0,weights[index])/total : 1/Double(open.count)) }
                break
            }
            for index in undersized { result[index] = minimum; remaining -= minimum }
            open.removeAll { undersized.contains($0) }
        }
        return result
    }
    private func source(icon:String,name:String,watts:Double,meter:CGFloat,height:CGFloat) -> some View {
        HStack(spacing:4) {
            Image(systemName:icon).font(.system(size:12,weight:.medium)).frame(width:28,height:height).background(AidenteReliefSurface(cornerRadius:7))
            Text(String(format:"%.2f W",watts)).font(.system(size:10,weight:.semibold)).monospacedDigit().contentTransition(.identity).transaction { $0.animation = nil }.frame(width:meter,height:height).background(AidenteReliefSurface(cornerRadius:3))
        }.accessibilityElement(children:.ignore).accessibilityLabel(name+String(format:" %.2f W",watts)).help(name)
    }
    private func destination(icon:String,name:String,watts:Double,height:CGFloat) -> some View {
        HStack(spacing:4) {
            Text(String(format:"%.2f W",watts)).font(.system(size:10,weight:.semibold)).monospacedDigit().contentTransition(.identity).transaction { $0.animation = nil }.frame(maxWidth:.infinity)
            Image(systemName:icon).font(.system(size:12,weight:.medium)).frame(width:28,height:height).background(AidenteReliefSurface(cornerRadius:7))
        }.accessibilityElement(children:.ignore).accessibilityLabel(name+String(format:" %.2f W",watts)).help(name)
    }
}

/// Four edges interpolate together when the measured allocation changes.
private struct RibbonShape: Shape {
    var left, right, top, bottom, endTop, endBottom: CGFloat
    var animatableData: AnimatablePair<AnimatablePair<CGFloat,CGFloat>,AnimatablePair<CGFloat,CGFloat>> {
        get { .init(.init(top,bottom),.init(endTop,endBottom)) }
        set { top=newValue.first.first; bottom=newValue.first.second; endTop=newValue.second.first; endBottom=newValue.second.second }
    }
    func path(in rect:CGRect) -> Path {
        Path(RibbonGeometry(left:left,right:right,top:top,bottom:bottom,endTop:endTop,endBottom:endBottom).path)
    }
}
private struct PowerRibbon: View {
    let left,right,top,bottom,endTop,endBottom:CGFloat
    let tint:Color?
    let phase:Double?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if phase == nil {
            NativeRibbon(left:left,right:right,top:top,bottom:bottom,endTop:endTop,endBottom:endBottom,tint:tint,dark:scheme == .dark,reducedMotion:reduceMotion)
                .frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true).allowsHitTesting(false)
        } else {
            fixture
        }
    }
    @ViewBuilder private var fixture: some View {
        let shape=RibbonShape(left:left,right:right,top:top,bottom:bottom,endTop:endTop,endBottom:endBottom)
        let low=min(top,endTop),high=max(bottom,endBottom)
        ZStack(alignment:.topLeading) {
            // Rasterize the ribbon material separately from its moving reflection.
            ZStack {
                shape.fill(LinearGradient(stops:[.init(color:Color(white:scheme == .dark ? 0.31 : 0.95),location:0),.init(color:Color(white:scheme == .dark ? 0.25 : 0.90),location:0.45),.init(color:Color(white:scheme == .dark ? 0.20 : 0.83),location:1)],startPoint:UnitPoint(x:0.5,y:low/128),endPoint:UnitPoint(x:0.5,y:high/128)))
                    .shadow(color:.black.opacity(scheme == .dark ? 0.35 : 0.12),radius:1.5,y:1.5)
                if let tint { shape.fill(tint.opacity(scheme == .dark ? 0.27 : 0.24)) }
                shape.fill(LinearGradient(colors:[.white.opacity(0.17),.clear,.black.opacity(0.09)],startPoint:.top,endPoint:.bottom))
                shape.stroke(.white.opacity(scheme == .dark ? 0.16 : 0.28),lineWidth:0.65)
            }
            if !reduceMotion {
                FlowReflection(left:left,right:right,low:low,high:high,phase:phase,dark:scheme == .dark)
                    .clipShape(shape)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// The compositor moves a small highlight; no 30 Hz view-tree invalidation is needed.
private struct FlowReflection: View {
    let left,right,low,high:CGFloat
    let phase:Double?
    let dark:Bool
    @State private var moving = false
    var body: some View {
        let progress = phase ?? (moving ? 1 : 0)
        Rectangle().fill(LinearGradient(colors:[.clear,.white.opacity(dark ? 0.10 : 0.14),.clear],startPoint:.leading,endPoint:.trailing))
            .frame(width:48,height:max(1,high-low))
            .position(x:left-24+(right-left+48)*progress,y:(low+high)/2)
            .animation(phase == nil ? .linear(duration:2.8).repeatForever(autoreverses:false) : nil,value:moving)
            .onAppear { if phase == nil { moving = true } }
            .onDisappear { moving = false }
    }
}
