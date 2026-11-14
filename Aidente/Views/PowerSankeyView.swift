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
                if parts?.prefix(3).allSatisfy({ $0 == nil }) ?? true {
                    Text(AidenteL10n.t("此机型暂无已验证的硬件分项，仅显示实测整机流向。", "Verified component sensors are unavailable on this Mac; only measured whole-system flows are shown."))
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
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
        Group {
            if material == .liquidGlass {
                if #available(macOS 26.0, *) {
                    shape.fill(.clear).glassEffect(.regular.interactive(), in: shape)
                } else { compatibleSurface(shape, dark: dark) }
            } else { compatibleSurface(shape, dark: dark) }
        }.allowsHitTesting(false)
    }
    private func compatibleSurface(_ shape: RoundedRectangle, dark: Bool) -> some View {
        ZStack {
            if material != .solid {
                AidenteVisualEffectView(material: material == .frosted ? .hudWindow : .popover, blendingMode: .withinWindow)
            }
            shape.fill(LinearGradient(colors: dark
                ? [Color(white: pressed ? 0.22 : 0.265), Color(white: 0.235), Color(white: 0.215)]
                : [Color(white: pressed ? 0.88 : 0.97), Color(white: 0.925), Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                .opacity(material == .solid ? 1 : material == .frosted ? 0.88 : material == .glass ? 0.66 : 0.44)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.23 : 0.9), .white.opacity(0.04), .black.opacity(dark ? 0.40 : 0.16)], startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
        .shadow(color: .black.opacity(dark ? 0.24 : 0.09), radius: pressed ? 1 : 3, x: 0, y: pressed ? 0.5 : 2)
            .allowsHitTesting(false)
    }
}


private struct LivePowerDiagram: View {
    let power:PowerFlowReading
    let breakdown:[Double?]?
    let previewPhase:Double?
    @State private var showHardware = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let names=["SoC",AidenteL10n.t("显示屏","Display"),"USB",AidenteL10n.t("其他","Other")]
    private let icons=["cpu","display","cable.connector","ellipsis"]
    private var entries:[(Int,Double)] {
        guard #available(macOS 26.0,*) else { return [] }
        return (breakdown ?? []).enumerated().compactMap { i,v in v.flatMap { $0 >= 1 ? (i,$0):nil } }
    }
    var body:some View {
        GeometryReader { proxy in
            let w=proxy.size.width,h=proxy.size.height,gap:CGFloat=5
            let node=min(44,max(28,w*0.116))
            let split=showHardware && !entries.isEmpty
            let middle=split ? (w-3*node-4*gap)/2 : w-2*node-2*gap
            let streamLeft=node+gap, junction=streamLeft+middle+gap
            let end=split ? w-node-gap:junction-gap
            let charging=power.batteryInput > 0.1
            let assisting=power.batteryOutput > 0.1 && power.adapter > 0.1
            let sourceHeight=h
            let primaryWeights=charging ? [power.batteryInput,power.computer] : [power.computer]
            let primary=ports(weights:primaryWeights,top:charging ? -16:0,bottom:charging ? h+16:h,gap:32)
            let macPort=primary.last ?? StreamPort(top:0,bottom:h)
            let hardware=ports(weights:entries.map { $0.1 },top:macPort.top-16,bottom:macPort.bottom+16,gap:entries.count>2 ? 14:32)
            ZStack(alignment:.topLeading) {
                if assisting {
                    let input=ports(weights:[power.batteryOutput,power.adapter],top:0,bottom:h,gap:14)
                    PowerStreamSurface(geometry:PowerStreamGeometry(left:streamLeft,right:junction-gap,top:0,bottom:h,ports:input,reversed:true),role:0,phase:previewPhase)
                    ForEach(Array(input.enumerated()),id:\.offset) { i,port in
                        sourceNode(icon:i == 0 ? "battery.100":"powerplug.portrait.fill",watts:i == 0 ? power.batteryOutput:power.adapter,height:port.bottom-port.top,width:node,showWatts:true)
                            .position(x:node/2,y:(port.top+port.bottom)/2)
                    }
                } else {
                    PowerStreamSurface(geometry:PowerStreamGeometry(left:streamLeft,right:junction-gap,top:0,bottom:sourceHeight,ports:primary),role:charging ? 1:0,phase:previewPhase)
                    sourceNode(icon:power.adapter > 0.1 ? "powerplug.portrait.fill":"battery.100",watts:power.adapter > 0.1 ? power.adapter:power.batteryOutput,height:sourceHeight,width:node,showWatts:charging)
                        .position(x:node/2,y:h/2)
                    ForEach(Array(primary.enumerated()),id:\.offset) { i,port in
                        watts(primaryWeights[i]).position(x:streamLeft+middle*0.55,y:PowerStreamGeometry(left:streamLeft,right:junction-gap,top:0,bottom:sourceHeight,ports:primary).center(of:i,at:0.55))
                    }
                }
                if charging,let battery=primary.first {
                    terminal(icon:"battery.100",name:AidenteL10n.t("充入电池","To Battery"),height:battery.bottom-battery.top,width:node)
                        .position(x:junction+node/2,y:(battery.top+battery.bottom)/2)
                }
                if split {
                    PowerStreamSurface(geometry:PowerStreamGeometry(left:junction+node+gap,right:end,top:macPort.top,bottom:macPort.bottom,ports:hardware),role:2,phase:previewPhase)
                        .id(entries.map { $0.0 })
                    ForEach(Array(entries.enumerated()),id:\.element.0) { index,entry in
                        let port=hardware[index]
                        watts(entry.1).position(x:(junction+node+gap+end)/2,y:PowerStreamGeometry(left:junction+node+gap,right:end,top:macPort.top,bottom:macPort.bottom,ports:hardware).center(of:index,at:0.5))
                        terminal(icon:icons[entry.0],name:names[entry.0],height:port.bottom-port.top,width:node)
                            .position(x:w-node/2,y:(port.top+port.bottom)/2)
                    }
                }
                Button {
                    withAnimation(reduceMotion ? nil:.easeInOut(duration:0.3)) { showHardware.toggle() }
                } label: {
                    VStack(spacing:5) {
                        Image(systemName:"laptopcomputer").font(.system(size:15,weight:.medium))
                        if assisting { Text(String(format:"%.1f W",power.computer)).font(.system(size:9,weight:.semibold)).monospacedDigit() }
                    }.frame(width:node,height:macPort.bottom-macPort.top)
                        .background(FlowNodeSurface(side:.junction))
                        .overlay(alignment:.topTrailing) {
                            if !showHardware && !entries.isEmpty {
                                Text("\(entries.count)").font(.system(size:9,weight:.bold)).foregroundStyle(.white)
                                    .padding(3).background(.blue,in:Circle()).offset(x:3,y:-4)
                            }
                        }
                }.buttonStyle(.plain).disabled(entries.isEmpty)
                    .accessibilityLabel(AidenteL10n.t(showHardware ? "收起电脑功耗分项":"展开电脑功耗分项",showHardware ? "Hide Mac power breakdown":"Show Mac power breakdown"))
                    .help(AidenteL10n.t("点击电脑展开或收起硬件流向；低于1 W的分项保留在功率详情中。","Click to expand or collapse hardware streams. Readings below 1 W remain in Power Details."))
                    .position(x:junction+node/2,y:(macPort.top+macPort.bottom)/2)
            }
            .animation(reduceMotion ? nil:.easeInOut(duration:0.65),value:[power.adapter,power.batteryInput,power.batteryOutput]+entries.map { $0.1 })
        }.frame(height:148).padding(.top,18).padding(.bottom,power.batteryInput > 0.1 ? 36:18)
    }
    private func ports(weights:[Double],top:CGFloat,bottom:CGFloat,gap:CGFloat)->[StreamPort] {
        guard !weights.isEmpty else { return [] }
        let available=max(0,bottom-top-gap*CGFloat(weights.count-1))
        let minimum=min(20,available/CGFloat(weights.count))
        var heights=Array(repeating:CGFloat(0),count:weights.count),open=Array(weights.indices),remaining=available
        while !open.isEmpty {
            let total=open.reduce(0.0) { $0+max(0,weights[$1]) }
            let small=open.filter { remaining*CGFloat(total>0 ? max(0,weights[$0])/total:1/Double(open.count))<minimum }
            if small.isEmpty {
                for i in open { heights[i]=remaining*CGFloat(total>0 ? max(0,weights[i])/total:1/Double(open.count)) }
                break
            }
            for i in small { heights[i]=minimum;remaining-=minimum }
            open.removeAll { small.contains($0) }
        }
        var cursor=top
        return heights.map { height in defer { cursor += height+gap };return StreamPort(top:cursor,bottom:cursor+height) }
    }
    private func watts(_ value:Double)->some View {
        Text(String(format:value >= 10 ? "%.1f W":"%.2f W",value)).font(.system(size:12,weight:.semibold)).monospacedDigit()
            .fixedSize().contentTransition(.identity).transaction { $0.animation=nil }
    }
    private func sourceNode(icon:String,watts value:Double,height:CGFloat,width:CGFloat,showWatts:Bool)->some View {
        VStack(spacing:5) {
            Image(systemName:icon).font(.system(size:16,weight:.medium))
            if showWatts { Text(String(format:"%.0f W",value)).font(.system(size:9,weight:.semibold)).monospacedDigit() }
        }.frame(width:width,height:height).background(FlowNodeSurface(side:.source))
            .accessibilityLabel(String(format:"%.1f W",value))
    }
    private func terminal(icon:String,name:String,height:CGFloat,width:CGFloat)->some View {
        Image(systemName:icon).font(.system(size:15,weight:.medium)).frame(width:width,height:height)
            .background(FlowNodeSurface(side:.destination)).help(name).accessibilityLabel(name)
    }
}

private struct PowerStreamSurface:View,Animatable {
    var geometry:PowerStreamGeometry
    let role:Int
    let phase:Double?
    @Default(.interfaceMaterialStyle) private var material
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animatableData:StreamVector {
        get { PowerStreamShape(geometry:geometry).animatableData }
        set { var shape=PowerStreamShape(geometry:geometry);shape.animatableData=newValue;geometry=shape.geometry }
    }
    private var finish:Int {
        switch material { case .solid:return 0;case .frosted:return 1;case .glass:return 2;case .liquidGlass:return 3 }
    }
    var body:some View {
        // The root window supplies native glass. A second refractive layer on a forked
        // shape produces inconsistent edges; the continuous stream uses one adaptive surface.
        ZStack {
            NativePowerStream(geometry:geometry,dark:scheme == .dark,reducedMotion:reduceMotion,increasedContrast:contrast == .increased,finish:finish,role:role,phase:phase)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true).allowsHitTesting(false)
    }
}

private struct FlowNodeSurface:View {
    enum Side { case source,junction,destination }
    let side:Side
    @Default(.interfaceMaterialStyle) private var material
    @Environment(\.colorScheme) private var scheme
    var body:some View {
        let dark=scheme == .dark
        let outer:CGFloat=20,inner:CGFloat=4
        let shape=UnevenRoundedRectangle(topLeadingRadius:side == .source ? outer:inner,
            bottomLeadingRadius:side == .source ? outer:inner,
            bottomTrailingRadius:side == .destination ? outer:inner,
            topTrailingRadius:side == .destination ? outer:inner)
        Group {
            if material == .liquidGlass {
                if #available(macOS 26.0,*) { shape.fill(.clear).glassEffect(.regular.interactive(),in:shape) }
                else { surface(shape,dark:dark) }
            } else { surface(shape,dark:dark) }
        }.allowsHitTesting(false)
    }
    private func surface(_ shape:UnevenRoundedRectangle,dark:Bool)->some View {
        ZStack {
            if material != .solid { AidenteVisualEffectView(material:.popover,blendingMode:.withinWindow) }
            shape.fill(LinearGradient(colors:dark ? [Color(white:0.285),Color(white:0.225)]:[Color(white:0.975),Color(white:0.885)],startPoint:.topLeading,endPoint:.bottomTrailing))
                .opacity(material == .solid ? 1:material == .frosted ? 0.92:0.75)
        }.clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors:[.white.opacity(dark ? 0.28:0.85),.black.opacity(dark ? 0.18:0.16)],startPoint:.top,endPoint:.bottom),lineWidth:0.65))
            .shadow(color:.black.opacity(dark ? 0.20:0.10),radius:3,y:2)
    }
}
