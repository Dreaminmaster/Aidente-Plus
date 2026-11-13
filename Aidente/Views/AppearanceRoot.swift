import AppKit
import Defaults
import SwiftUI

/// Apply app window appearance without recoloring the system menu bar item.
struct AidenteAppearanceRoot<Content: View>: View {
    @Default(.interfaceAppearance) private var mode
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.preferredColorScheme(mode == .system ? nil : mode == .dark ? .dark : .light)
            .background(WindowAppearanceBridge(mode: mode).frame(width: 0, height: 0))
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
