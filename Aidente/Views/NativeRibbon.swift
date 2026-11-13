import AppKit
import QuartzCore
import SwiftUI

/// Only the decorative ribbon crosses into AppKit. Watts and interactions remain SwiftUI values.
struct NativeRibbon: NSViewRepresentable {
    let left,right,top,bottom,endTop,endBottom:CGFloat
    let tint:Color?
    let dark,reducedMotion:Bool
    var animateGeometry = true
    func makeNSView(context:Context) -> RibbonLayerView { RibbonLayerView() }
    func updateNSView(_ view:RibbonLayerView,context:Context) {
        let shape=RibbonGeometry(left:left,right:right,top:top,bottom:bottom,endTop:endTop,endBottom:endBottom)
        view.configure(shape:shape,tint:tint.map { NSColor($0).cgColor },dark:dark,reducedMotion:reducedMotion,animateGeometry:animateGeometry)
    }
}

struct RibbonGeometry: Equatable {
    let left,right,top,bottom,endTop,endBottom:CGFloat
    var path:CGPath {
        let bend=max(0,right-left)*0.48
        let r=max(0,min(5.5,(bottom-top)/3,(endBottom-endTop)/3))
        let p=CGMutablePath();p.move(to:CGPoint(x:left,y:top))
        p.addCurve(to:CGPoint(x:right-r,y:endTop),control1:CGPoint(x:left+bend,y:top),control2:CGPoint(x:right-bend,y:endTop))
        p.addQuadCurve(to:CGPoint(x:right,y:endTop+r),control:CGPoint(x:right,y:endTop))
        p.addLine(to:CGPoint(x:right,y:endBottom-r))
        p.addQuadCurve(to:CGPoint(x:right-r,y:endBottom),control:CGPoint(x:right,y:endBottom))
        p.addCurve(to:CGPoint(x:left,y:bottom),control1:CGPoint(x:right-bend,y:endBottom),control2:CGPoint(x:left+bend,y:bottom))
        p.addLine(to:CGPoint(x:left,y:top))
        p.closeSubpath();return p
    }
}

final class RibbonLayerView:NSView {
    override var isFlipped:Bool { true }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    private let material=CAGradientLayer()
    private let drop=CAShapeLayer()
    private let color=CALayer()
    private let bevel=CAGradientLayer()
    private let edge=CAShapeLayer()
    private let glowContainer=CALayer()
    private let glow=CAGradientLayer()
    private let masks=[CAShapeLayer(),CAShapeLayer(),CAShapeLayer(),CAShapeLayer()]
    private var geometry:RibbonGeometry?
    private var reduced=true
    private var cycleBounds:ClosedRange<CGFloat>?
    override init(frame:NSRect) {
        super.init(frame:frame)
        wantsLayer=true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds=false
        material.mask=masks[0];color.mask=masks[1];bevel.mask=masks[2];glowContainer.mask=masks[3]
        material.startPoint=CGPoint(x:0.5,y:0);material.endPoint=CGPoint(x:0.5,y:1)
        bevel.startPoint=CGPoint(x:0.5,y:0);bevel.endPoint=CGPoint(x:0.5,y:1)
        bevel.colors=[NSColor.white.withAlphaComponent(0.15).cgColor,NSColor.clear.cgColor,NSColor.black.withAlphaComponent(0.09).cgColor]
        bevel.locations=[0,0.5,1]
        edge.fillColor=nil;edge.lineWidth=0.65
        glow.startPoint=CGPoint(x:0,y:0.5);glow.endPoint=CGPoint(x:1,y:0.5)
        glowContainer.addSublayer(glow)
        for item in [drop,material,color,bevel,edge,glowContainer] { layer?.addSublayer(item) }
        setAccessibilityElement(false)
    }
    required init?(coder:NSCoder) { nil }
    func configure(shape:RibbonGeometry,tint:CGColor?,dark:Bool,reducedMotion:Bool,animateGeometry:Bool = true) {
        let old=geometry
        let changed=old != nil && old != shape
        geometry=shape;reduced=reducedMotion
        CATransaction.begin();CATransaction.setDisableActions(true)
        material.colors=(dark ? [0.31,0.25,0.20] : [0.95,0.90,0.83]).map { NSColor(white:$0,alpha:1).cgColor }
        material.locations=[0,0.45,1]
        drop.fillColor=NSColor(white:dark ? 0.22 : 0.88,alpha:1).cgColor
        drop.shadowColor=NSColor.black.cgColor;drop.shadowOpacity=dark ? 0.22 : 0.08
        drop.shadowRadius=2;drop.shadowOffset=CGSize(width:0,height:1)
        let previousDrop=drop.presentation()?.path ?? drop.path
        drop.path=shape.path;drop.shadowPath=shape.path
        if changed && !reducedMotion && animateGeometry,let previousDrop {
            let animation=CABasicAnimation(keyPath:"path");animation.fromValue=previousDrop;animation.toValue=shape.path
            animation.duration=0.65;animation.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
            drop.add(animation,forKey:"shape")
        } else { drop.removeAnimation(forKey:"shape") }
        material.shadowColor=NSColor.black.cgColor;material.shadowOpacity=dark ? 0.35 : 0.12
        material.shadowRadius=1.5;material.shadowOffset=CGSize(width:0,height:1.5)
        material.shadowPath=shape.path
        color.backgroundColor=tint;color.opacity=dark ? 0.27 : 0.24
        edge.strokeColor=NSColor.white.withAlphaComponent(dark ? 0.16 : 0.28).cgColor
        glow.colors=[NSColor.clear.cgColor,
                     NSColor(calibratedRed:0.61,green:0.71,blue:0.98,alpha:dark ? 0.12 : 0.10).cgColor,
                     NSColor(calibratedRed:0.48,green:0.87,blue:0.78,alpha:dark ? 0.14 : 0.12).cgColor,
                     NSColor.clear.cgColor]
        glow.locations=[0,0.35,0.65,1]
        var maskTransform=CGAffineTransform(translationX:0,y:12)
        let maskPath=shape.path.copy(using:&maskTransform) ?? shape.path
        for mask in masks {
            let previous=mask.presentation()?.path ?? mask.path
            mask.path=maskPath
            if changed && !reducedMotion && animateGeometry,let previous {
                let animation=CABasicAnimation(keyPath:"path");animation.fromValue=previous;animation.toValue=maskPath
                animation.duration=0.65;animation.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
                mask.add(animation,forKey:"shape")
            } else { mask.removeAnimation(forKey:"shape") }
        }
        let previous=edge.presentation()?.path ?? edge.path;edge.path=shape.path
        if changed && !reducedMotion && animateGeometry,let previous {
            let animation=CABasicAnimation(keyPath:"path");animation.fromValue=previous;animation.toValue=shape.path
            animation.duration=0.65;animation.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut);edge.add(animation,forKey:"shape")
        } else { edge.removeAnimation(forKey:"shape") }
        layoutLayers()
        CATransaction.commit()
        updateReflection()
    }
    override func layout() { super.layout();CATransaction.begin();CATransaction.setDisableActions(true);layoutLayers();CATransaction.commit() }
    private func layoutLayers() {
        guard let geometry else { return }
        for item in [drop,edge] { item.frame=bounds }
        let expanded=bounds.insetBy(dx:0,dy:-12)
        for item in [material,color,bevel,glowContainer] { item.frame=expanded }
        for mask in masks { mask.frame=CGRect(origin:.zero,size:expanded.size) }
        let low=min(geometry.top,geometry.endTop),high=max(geometry.bottom,geometry.endBottom)
        let height=max(1,bounds.height+24)
        material.startPoint=CGPoint(x:0.5,y:(low+12)/height);material.endPoint=CGPoint(x:0.5,y:(high+12)/height)
        bevel.startPoint=material.startPoint;bevel.endPoint=material.endPoint
        let glowWidth=max(72,(geometry.right-geometry.left)*0.7)
        glow.bounds=CGRect(x:0,y:0,width:glowWidth,height:max(1,high-low))
        glow.position=CGPoint(x:geometry.left-24,y:12+(low+high)/2)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow();updateReflection() }
    private func updateReflection() {
        guard let geometry else { return }
        guard !reduced,window != nil else { glow.removeAllAnimations();glow.isHidden=true;cycleBounds=nil;return }
        glow.isHidden=false
        let extent=geometry.left...max(geometry.left,geometry.right)
        if cycleBounds != extent || glow.animation(forKey:"flow") == nil {
            cycleBounds=extent
            let animation=CABasicAnimation(keyPath:"position.x")
            animation.fromValue=geometry.left-glow.bounds.width/2;animation.toValue=geometry.right+glow.bounds.width/2
            animation.duration=6.4;animation.repeatCount = .infinity
            animation.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
            animation.beginTime=0
            glow.add(animation,forKey:"flow")
            let pulse=CAKeyframeAnimation(keyPath:"opacity")
            pulse.values=[0.35,0.9,0.5,0.35];pulse.keyTimes=[0,0.4,0.75,1]
            pulse.duration=6.4;pulse.repeatCount = .infinity
            glow.add(pulse,forKey:"pulse")
        }
    }
}
