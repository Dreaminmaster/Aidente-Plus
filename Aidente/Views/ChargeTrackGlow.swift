import AppKit
import QuartzCore
import SwiftUI
import AidenteShared

/// A compositor-only highlight; no per-frame SwiftUI state updates.
struct ChargeTrackGlow: NSViewRepresentable {
    let motion: ChargeTrackMotion
    let reducedMotion: Bool
    func makeNSView(context: Context) -> GlowView { GlowView() }
    func updateNSView(_ view: GlowView, context: Context) { view.motion = reducedMotion ? .stopped : motion; view.refresh() }
    final class GlowView: NSView {
        var motion: ChargeTrackMotion = .stopped
        private var appliedMotion: ChargeTrackMotion = .stopped
        private let highlight = CAGradientLayer()
        private var extent: CGFloat = -1
        override init(frame: NSRect) {
            super.init(frame: frame); wantsLayer = true
            layer?.masksToBounds = true; layer?.cornerRadius = 10
            highlight.startPoint = CGPoint(x:0,y:0.5); highlight.endPoint = CGPoint(x:1,y:0.5)
            highlight.colors = [NSColor.clear.cgColor,NSColor.white.withAlphaComponent(0.14).cgColor,NSColor.clear.cgColor]
            layer?.addSublayer(highlight)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() { super.layout(); refresh() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refresh() }
        func refresh() {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            highlight.bounds = CGRect(x:0,y:0,width:42,height:bounds.height)
            highlight.position = CGPoint(x:-21,y:bounds.height/2)
            CATransaction.commit()
            guard motion != .stopped,window != nil,bounds.width > 1 else { highlight.removeAllAnimations(); highlight.isHidden = true; extent = -1; return }
            highlight.isHidden = false
            if appliedMotion != motion || extent != bounds.width || highlight.animation(forKey:"flow") == nil {
                appliedMotion = motion
                extent = bounds.width
                let animation = CABasicAnimation(keyPath:"position.x")
                animation.fromValue = motion == .discharging ? bounds.width+21 : -21
                animation.toValue = motion == .discharging ? -21 : bounds.width+21
                animation.duration = 2.8; animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name:.linear)
                highlight.add(animation,forKey:"flow")
            }
        }
    }
}
