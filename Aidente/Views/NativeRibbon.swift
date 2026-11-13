import AppKit
import QuartzCore
import SwiftUI

struct StreamPort: Equatable {
    var top, bottom: CGFloat
}

/// One closed outline forms both the shared trunk and every fork: no internal card edges.
struct PowerStreamGeometry: Equatable {
    var left, right, top, bottom: CGFloat
    var ports: [StreamPort]
    var reversed = false
    func center(of index:Int, at fraction:CGFloat)->CGFloat {
        guard ports.indices.contains(index) else { return (top+bottom)/2 }
        let length=right-left,fork=left+length*0.22
        let x=left+length*min(0.95,max(0.3,fraction))
        let total=ports.reduce(CGFloat(0)) { $0+max(0,$1.bottom-$1.top) }
        func cut(_ i:Int)->CGFloat { top+(bottom-top)*(total>0 ? ports.prefix(i+1).reduce(CGFloat(0)) { $0+max(0,$1.bottom-$1.top) }/total:0.5) }
        func y(_ points:[CGPoint])->CGFloat {
            func value(_ t:CGFloat)->CGPoint {
                let a=1-t
                return CGPoint(x:a*a*a*points[0].x+3*a*a*t*points[1].x+3*a*t*t*points[2].x+t*t*t*points[3].x,
                               y:a*a*a*points[0].y+3*a*a*t*points[1].y+3*a*t*t*points[2].y+t*t*t*points[3].y)
            }
            var low:CGFloat=0,high:CGFloat=1
            let increasing=points[3].x>points[0].x
            for _ in 0..<20 { let mid=(low+high)/2;if (value(mid).x<x)==increasing { low=mid } else { high=mid } }
            return value((low+high)/2).y
        }
        let port=ports[index],r=min(4,max(0,(port.bottom-port.top)/4))
        let upper=index == 0
            ? y([CGPoint(x:left+3,y:top),CGPoint(x:left+length*0.48,y:top),CGPoint(x:right-length*0.35,y:port.top),CGPoint(x:right-r,y:port.top)])
            : y([CGPoint(x:fork,y:cut(index-1)),CGPoint(x:fork+length*0.1,y:cut(index-1)-0.4),CGPoint(x:right-length*0.34,y:port.top),CGPoint(x:right-r,y:port.top)])
        let lower=index == ports.count-1
            ? y([CGPoint(x:right-r,y:port.bottom),CGPoint(x:right-length*0.35,y:port.bottom),CGPoint(x:left+length*0.48,y:bottom),CGPoint(x:left+3,y:bottom)])
            : y([CGPoint(x:right-r,y:port.bottom),CGPoint(x:right-length*0.34,y:port.bottom),CGPoint(x:fork+length*0.1,y:cut(index)+0.4),CGPoint(x:fork,y:cut(index))])
        return (upper+lower)/2
    }
    var path: CGPath {
        guard let first = ports.first, let last = ports.last, right > left else { return CGMutablePath() }
        let length = right-left
        let fork = left+length*0.22
        let total = ports.reduce(CGFloat(0)) { $0+max(0,$1.bottom-$1.top) }
        let p = CGMutablePath()
        let r: CGFloat = min(4, max(0,(first.bottom-first.top)/4))
        p.move(to: CGPoint(x:left+3,y:top))
        p.addCurve(to: CGPoint(x:right-r,y:first.top), control1:CGPoint(x:left+length*0.48,y:top), control2:CGPoint(x:right-length*0.35,y:first.top))
        var consumed: CGFloat = 0
        for (index, port) in ports.enumerated() {
            let radius = min(4,max(0,(port.bottom-port.top)/4))
            p.addQuadCurve(to:CGPoint(x:right,y:port.top+radius),control:CGPoint(x:right,y:port.top))
            p.addLine(to:CGPoint(x:right,y:port.bottom-radius))
            p.addQuadCurve(to:CGPoint(x:right-radius,y:port.bottom),control:CGPoint(x:right,y:port.bottom))
            consumed += max(0,port.bottom-port.top)
            if index+1 < ports.count {
                let cut = top+(bottom-top)*(total > 0 ? consumed/total : CGFloat(index+1)/CGFloat(ports.count))
                let next = ports[index+1]
                // A narrow cusp appears inside the continuous trunk, rather than at its edge.
                p.addCurve(to:CGPoint(x:fork,y:cut),control1:CGPoint(x:right-length*0.34,y:port.bottom),control2:CGPoint(x:fork+length*0.1,y:cut+0.4))
                p.addCurve(to:CGPoint(x:right-min(4,(next.bottom-next.top)/4),y:next.top),control1:CGPoint(x:fork+length*0.1,y:cut-0.4),control2:CGPoint(x:right-length*0.34,y:next.top))
            }
        }
        p.addCurve(to:CGPoint(x:left+3,y:bottom),control1:CGPoint(x:right-length*0.35,y:last.bottom),control2:CGPoint(x:left+length*0.48,y:bottom))
        p.addQuadCurve(to:CGPoint(x:left,y:bottom-3),control:CGPoint(x:left,y:bottom))
        p.addLine(to:CGPoint(x:left,y:top+3))
        p.addQuadCurve(to:CGPoint(x:left+3,y:top),control:CGPoint(x:left,y:top))
        p.closeSubpath()
        if reversed {
            var transform=CGAffineTransform(a:-1,b:0,c:0,d:1,tx:left+right,ty:0)
            return p.copy(using:&transform) ?? p
        }
        return p
    }
}

struct StreamVector: VectorArithmetic {
    var values: [CGFloat]
    static var zero: Self { .init(values:[]) }
    static func + (a:Self,b:Self)->Self { combine(a,b,+) }
    static func - (a:Self,b:Self)->Self { combine(a,b,-) }
    private static func combine(_ a:Self,_ b:Self,_ f:(CGFloat,CGFloat)->CGFloat)->Self {
        .init(values:(0..<max(a.values.count,b.values.count)).map { f($0<a.values.count ? a.values[$0]:0,$0<b.values.count ? b.values[$0]:0) })
    }
    mutating func scale(by rhs:Double) { values=values.map { $0*rhs } }
    var magnitudeSquared:Double { values.reduce(0) { $0+Double($1*$1) } }
}

struct PowerStreamShape: Shape {
    var geometry:PowerStreamGeometry
    var animatableData:StreamVector {
        get { .init(values:[geometry.left,geometry.right,geometry.top,geometry.bottom]+geometry.ports.flatMap { [$0.top,$0.bottom] }) }
        set {
            guard newValue.values.count == 4+geometry.ports.count*2 else { return }
            geometry.left=newValue.values[0];geometry.right=newValue.values[1];geometry.top=newValue.values[2];geometry.bottom=newValue.values[3]
            for i in geometry.ports.indices { geometry.ports[i]=StreamPort(top:newValue.values[4+i*2],bottom:newValue.values[5+i*2]) }
        }
    }
    func path(in rect:CGRect)->Path { Path(geometry.path) }
}

struct NativePowerStream:NSViewRepresentable {
    let geometry:PowerStreamGeometry
    let dark,reducedMotion,increasedContrast:Bool
    let finish:Int
    let role:Int // 0: neutral, 1: adapter split, 2: hardware branches
    var phase:Double? = nil
    func makeNSView(context:Context)->PowerStreamLayerView { PowerStreamLayerView() }
    func updateNSView(_ view:PowerStreamLayerView,context:Context) {
        view.configure(geometry:geometry,dark:dark,reducedMotion:reducedMotion,contrast:increasedContrast,finish:finish,role:role,phase:phase)
    }
}

final class PowerStreamLayerView:NSView {
    override var isFlipped:Bool { true }
    override func hitTest(_ point:NSPoint)->NSView? { nil }
    private let base=CAGradientLayer(), hue=CAGradientLayer(), rim=CAShapeLayer(), dropLayer=CAShapeLayer()
    private let flow=CALayer(), aurora=CAGradientLayer(), sheen=CAGradientLayer()
    private let masks=(0..<4).map { _ in CAShapeLayer() }
    private var geometry:PowerStreamGeometry?
    private var moving=false
    private var phase:Double?
    private var animationExtent:ClosedRange<CGFloat>?
    override init(frame:NSRect) {
        super.init(frame:frame);wantsLayer=true;layerContentsRedrawPolicy = .never
        base.mask=masks[0];hue.mask=masks[1];flow.mask=masks[2];sheen.mask=masks[3]
        base.startPoint=CGPoint(x:0.5,y:0);base.endPoint=CGPoint(x:0.5,y:1)
        hue.startPoint=CGPoint(x:0.5,y:0);hue.endPoint=CGPoint(x:0.5,y:1)
        sheen.startPoint=CGPoint(x:0,y:0);sheen.endPoint=CGPoint(x:1,y:1)
        sheen.colors=[NSColor.white.withAlphaComponent(0.07).cgColor,NSColor.clear.cgColor,NSColor.white.withAlphaComponent(0.035).cgColor]
        rim.fillColor=nil;rim.lineWidth=0.65
        aurora.startPoint=CGPoint(x:0,y:0.5);aurora.endPoint=CGPoint(x:1,y:0.5)
        flow.addSublayer(aurora)
        for l in [dropLayer,base,hue,sheen,flow,rim] { layer?.addSublayer(l) }
        setAccessibilityElement(false)
    }
    required init?(coder:NSCoder) { nil }
    func configure(geometry:PowerStreamGeometry,dark:Bool,reducedMotion:Bool,contrast:Bool,finish:Int,role:Int,phase:Double?) {
        self.geometry=geometry;self.phase=phase;moving = !reducedMotion && phase == nil
        CATransaction.begin();CATransaction.setDisableActions(true)
        let opacity:CGFloat = contrast || finish == 0 ? 1 : finish == 1 ? 0.96 : finish == 2 ? 0.86 : 0.65
        let shades = dark ? [0.29,0.235,0.21] : [0.96,0.91,0.865]
        base.colors=shades.map { NSColor(white:$0,alpha:opacity).cgColor };base.locations=[0,0.5,1]
        let clear=NSColor.clear.cgColor
        let purple=NSColor(calibratedRed:0.50,green:0.47,blue:0.77,alpha:dark ? 0.22:0.14).cgColor
        let teal=NSColor(calibratedRed:0.36,green:0.68,blue:0.64,alpha:dark ? 0.22:0.14).cgColor
        let gold=NSColor(calibratedRed:0.89,green:0.74,blue:0.32,alpha:dark ? 0.19:0.13).cgColor
        hue.colors=role == 2 ? [purple,clear,teal] : role == 1 ? [gold,clear,clear] : [clear,clear]
        hue.locations=role == 2 || role == 1 ? [0,0.45,1]:[0,1]
        aurora.colors=role == 1 ? [clear,gold,NSColor.white.withAlphaComponent(0.04).cgColor,clear] : [clear,purple,teal,clear]
        if role == 0 { aurora.colors=[clear,NSColor.white.withAlphaComponent(0.08).cgColor,NSColor.white.withAlphaComponent(0.035).cgColor,clear] }
        aurora.locations=[0,0.35,0.7,1]
        rim.strokeColor=NSColor.white.withAlphaComponent(contrast ? 0.65:dark ? 0.25:0.74).cgColor
        dropLayer.fillColor=NSColor.clear.cgColor;dropLayer.shadowColor=NSColor.black.cgColor
        dropLayer.shadowOpacity=dark ? 0.24:0.1;dropLayer.shadowRadius=3;dropLayer.shadowOffset=CGSize(width:0,height:2)
        layoutLayers();CATransaction.commit();updateAnimation()
    }
    override func layout() { super.layout();CATransaction.begin();CATransaction.setDisableActions(true);layoutLayers();CATransaction.commit() }
    private func layoutLayers() {
        guard let g=geometry else { return }
        let inset:CGFloat=40
        let expanded=bounds.insetBy(dx:0,dy:-inset)
        for l in [base,hue,flow,sheen] { l.frame=expanded }
        rim.frame=bounds;dropLayer.frame=bounds;rim.path=g.path;dropLayer.path=g.path;dropLayer.shadowPath=g.path
        var translation=CGAffineTransform(translationX:0,y:inset)
        for mask in masks { mask.frame=CGRect(origin:.zero,size:expanded.size);mask.path=g.path.copy(using:&translation) }
        let low=min(g.top,g.ports.map(\.top).min() ?? g.top),high=max(g.bottom,g.ports.map(\.bottom).max() ?? g.bottom)
        for gradient in [base,hue] { gradient.startPoint=CGPoint(x:0.5,y:(low+inset)/max(1,expanded.height));gradient.endPoint=CGPoint(x:0.5,y:(high+inset)/max(1,expanded.height)) }
        let width=max(48,(g.right-g.left)*0.85)
        aurora.bounds=CGRect(x:0,y:0,width:width,height:max(1,high-low))
        let progress=CGFloat(phase ?? 0)
        aurora.position=CGPoint(x:g.left-width/2+(g.right-g.left+width)*progress,y:inset+(low+high)/2)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow();updateAnimation() }
    private func updateAnimation() {
        guard let g=geometry else { return }
        guard moving,window != nil else { aurora.removeAllAnimations();aurora.isHidden = phase == nil;return }
        aurora.isHidden=false
        let extent=g.left...max(g.left,g.right)
        guard animationExtent != extent || aurora.animation(forKey:"aurora") == nil else { return }
        animationExtent=extent
        let drift=CABasicAnimation(keyPath:"position.x")
        drift.fromValue=g.left-aurora.bounds.width/2;drift.toValue=g.right+aurora.bounds.width/2
        drift.duration=5.8;drift.repeatCount = .infinity;drift.timingFunction=CAMediaTimingFunction(name:.linear)
        // Synchronize the input and hardware streams to the same clock, independent of creation time.
        let now=CACurrentMediaTime();drift.beginTime=(now/5.8).rounded(.down)*5.8
        aurora.add(drift,forKey:"aurora")
        let pulse=CAKeyframeAnimation(keyPath:"opacity");pulse.values=[0.35,0.75,0.5,0.35];pulse.keyTimes=[0,0.4,0.75,1]
        pulse.duration=5.8;pulse.repeatCount = .infinity;pulse.beginTime=drift.beginTime
        aurora.add(pulse,forKey:"pulse")
    }
}
