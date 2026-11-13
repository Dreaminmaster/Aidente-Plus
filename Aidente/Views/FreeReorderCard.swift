import SwiftUI

/// In-window dragging renders the original card exactly once; no system snapshot is created.
struct CardDragState {
    var item: String?
    var origin = CGPoint.zero
    var translation = CGSize.zero
    var frames: [String: CGRect] = [:]
}

struct CardFramesPreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct FreeReorderCard<Content: View>: View {
    let id: String
    @Binding var drag: CardDragState
    let move: (String, String) -> Void
    @ViewBuilder var content: () -> Content
    @GestureState private var pointerIsDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active: Bool { drag.item == id }
    private var displacement: CGSize {
        guard active, let frame = drag.frames[id] else { return .zero }
        return CGSize(width: drag.origin.x + drag.translation.width - frame.minX,
                      height: drag.origin.y + drag.translation.height - frame.minY)
    }
    var body: some View {
        content()
            .offset(displacement)
            .background(GeometryReader { geo in
                Color.clear.preference(key: CardFramesPreference.self, value: [id: geo.frame(in: .global)])
            })
            .shadow(color: .black.opacity(active ? 0.16 : 0), radius: active ? 8 : 0, y: active ? 4 : 0)
            .zIndex(active ? 1 : 0)
            .transaction { if active { $0.animation = nil } }
            .onChange(of: pointerIsDragging) { _, isDragging in
                if !isDragging && active {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        drag.item = nil; drag.translation = .zero
                    }
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                .updating($pointerIsDragging) { _, active, _ in active = true }
                .onChanged { value in
                    if drag.item == nil, let frame = drag.frames[id] {
                        drag.item = id; drag.origin = frame.origin
                    }
                    guard active else { return }
                    drag.translation = value.translation
                    if let target = drag.frames.first(where: { $0.key != id && $0.value.contains(value.location) })?.key {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { move(id, target) }
                    }
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        drag.item = nil; drag.translation = .zero
                    }
                })
    }
}
