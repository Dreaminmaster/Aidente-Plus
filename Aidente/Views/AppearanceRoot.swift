import AppKit
import Defaults
import SwiftUI

/// Apply app window appearance without recoloring the system menu bar item.
struct AidenteAppearanceRoot<Content: View>: View {
    @Default(.interfaceAppearance) private var mode
    @Default(.interfaceMaterialStyle) private var material
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        glassContainer.preferredColorScheme(mode == .system ? nil : mode == .dark ? .dark : .light)
            .background(WindowAppearanceBridge(mode: mode).frame(width: 0, height: 0))
    }
    @ViewBuilder private var glassContainer: some View {
        if #available(macOS 26.0, *), material == .liquidGlass {
            NativeGlassWindowContent(content: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity).ignoresSafeArea()
        } else { content }
    }
}

private struct WindowAppearanceBridge: NSViewRepresentable {
    let mode: InterfaceAppearance
    func makeNSView(context: Context) -> AppearanceAnchor { AppearanceAnchor() }
    func updateNSView(_ view: AppearanceAnchor, context: Context) { view.mode = mode; view.apply() }
    final class AppearanceAnchor: NSView {
        var mode: InterfaceAppearance = .system
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        func apply() {
            window?.appearance = mode == .system ? nil : NSAppearance(named: mode == .dark ? .darkAqua : .aqua)
        }
    }
}

/// AppKit owns the glass surface; the hosting view is its documented contentView.
@available(macOS 26.0, *)
private struct NativeGlassWindowContent<Content: View>: NSViewRepresentable {
    let content: Content
    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 14
        let hosting = NSHostingView(rootView: content)
        hosting.autoresizingMask = [.width, .height]
        glass.contentView = hosting
        return glass
    }
    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        (view.contentView as? NSHostingView<Content>)?.rootView = content
    }
}
