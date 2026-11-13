import AppKit
import Defaults
import SwiftUI

enum AidenteTheme {
    static let jade = Color(red: 0.18, green: 0.84, blue: 0.50)
    static let mint = Color(red: 0.40, green: 0.92, blue: 0.68)
    static let ocean = Color(red: 0.24, green: 0.56, blue: 0.98)
    static let sky = Color(red: 0.36, green: 0.74, blue: 0.98)
    static let violet = Color(red: 0.55, green: 0.42, blue: 0.98)
    static let pink = Color(red: 0.90, green: 0.38, blue: 0.86)
    static let amber = Color(red: 1.00, green: 0.59, blue: 0.18)
    static let gold = Color(red: 1.00, green: 0.76, blue: 0.27)
    static let coral = Color(red: 0.98, green: 0.34, blue: 0.30)
    static let graphite = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let panel = Color(red: 0.13, green: 0.13, blue: 0.14)

    static let generalColors = [ocean, sky]
    static let dashboardColors = [violet, pink]
    static let chargingColors = [jade, mint]
    static let automationColors = [amber, gold]
    static let advancedColors = [Color.indigo, violet]
    static let aboutColors = [coral, amber]
}

struct AidenteVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

struct AidenteMaterialLayer: View {
    @Default(.interfaceMaterialStyle) private var materialStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            switch materialStyle {
            case .solid:
                Color(
                    nsColor: colorScheme == .dark
                        ? NSColor(calibratedWhite: 0.105, alpha: 1)
                        : NSColor(calibratedWhite: 0.975, alpha: 1)
                )
            case .glass:
                Rectangle()
                    .fill(.regularMaterial)
                Color.black.opacity(colorScheme == .dark ? 0.04 : 0.01)
            case .frosted:
                AidenteVisualEffectView(
                    material: .hudWindow,
                    blendingMode: .behindWindow
                )
                Color(
                    red: 0.065,
                    green: 0.052,
                    blue: 0.043
                )
                .opacity(colorScheme == .dark ? 0.58 : 0.08)
            case .liquidGlass:
                AidenteVisualEffectView(
                    material: .popover,
                    blendingMode: .behindWindow
                )
                Color(
                    red: 0.08,
                    green: 0.10,
                    blue: 0.12
                )
                .opacity(colorScheme == .dark ? 0.26 : 0.045)
                AidenteLiquidGlassHighlights()
            }
        }
    }
}

struct AidenteWindowBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
            ? [Color(white: 0.16), Color(white: 0.115)]
            : [.white, Color(white: 0.94)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct AidenteLiquidGlassHighlights: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(
                                    colorScheme == .dark ? 0.13 : 0.42
                                ),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(geometry.size.width, 1) * 0.58
                        )
                    )
                    .frame(
                        width: geometry.size.width * 0.92,
                        height: max(geometry.size.height * 0.36, 44)
                    )
                    .offset(
                        x: -geometry.size.width * 0.22,
                        y: -geometry.size.height * 0.34
                    )
                    .blur(radius: 9)

                LinearGradient(
                    colors: [
                        Color.white.opacity(
                            colorScheme == .dark ? 0.12 : 0.38
                        ),
                        AidenteTheme.sky.opacity(0.055),
                        Color.clear,
                        AidenteTheme.violet.opacity(0.045),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
    }
}

struct AidenteChromeBar: View {
    @Default(.interfaceMaterialStyle) private var materialStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if materialStyle == .liquidGlass {
                AidenteVisualEffectView(
                    material: .sidebar,
                    blendingMode: .withinWindow
                )
                Color(
                    red: 0.075,
                    green: 0.085,
                    blue: 0.10
                )
                .opacity(colorScheme == .dark ? 0.76 : 0.34)
                AidenteLiquidGlassHighlights()
            } else {
                Color(
                    red: 0.095,
                    green: 0.09,
                    blue: 0.085
                )
                .opacity(0.98)
            }
        }
    }
}

struct AidenteSettingsBackground: View {
    var body: some View {
        AidenteWindowBackdrop()
    }
}

struct AidenteIconBadge: View {
    let icon: String
    let colors: [Color]
    var size: CGFloat = 36
    var cornerRadius: CGFloat? = nil

    private var tint: Color { colors.first ?? AidenteTheme.jade }
    private var iconTint: Color { colors.last ?? tint }

    var body: some View {
        let radius = cornerRadius ?? max(7, size * 0.27)

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint.opacity(0.16))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(tint.opacity(0.34), lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: size * 0.46, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconTint)
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.16), radius: 4, y: 2)
    }
}

/// Immediate click help, with a short hover delay for pointer users.
struct AidenteHelpButton: View {
    let title: String
    let explanation: String
    @State private var showing = false
    @State private var pinned = false
    @State private var hoverTask: Task<Void, Never>?
    var body: some View {
        Button {
            hoverTask?.cancel()
            if showing && pinned { showing = false; pinned = false }
            else { pinned = true; showing = true }
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AidenteL10n.t(title) + AidenteL10n.t("说明", " Help"))
        .accessibilityHint(AidenteL10n.t(explanation))
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AidenteL10n.t(title)).font(.headline)
                Text(AidenteL10n.t(explanation)).font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }.padding(16).frame(width: 320, alignment: .leading)
        }
        .onHover { inside in
            hoverTask?.cancel()
            if inside {
                hoverTask = Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    guard !Task.isCancelled else { return }
                    showing = true
                }
            } else if !pinned { showing = false }
        }
        .onChange(of: showing) { _, value in if !value { pinned = false } }
        .onDisappear { hoverTask?.cancel() }
    }
}

struct AidenteSectionHeader: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colors: [Color]
    init(_ title: String, subtitle: String? = nil, icon: String, colors: [Color]) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.colors = colors
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).frame(width: 18)
            Text(AidenteL10n.t(title)).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                AidenteHelpButton(title: title, explanation: subtitle)
            }
            Spacer(minLength: 0)
        }.frame(minHeight: 25)
    }
}

struct AidenteCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colors: [Color]
    let content: Content
    init(_ title: String, subtitle: String? = nil, icon: String, colors: [Color], @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.colors = colors; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AidenteSectionHeader(title, subtitle: subtitle, icon: icon, colors: colors)
            VStack(alignment: .leading, spacing: 14) { content }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AidenteSettingsPage<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) { content }
                    .frame(width: max(0, geometry.size.width - 32), alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 24)
            }
        }.tint(.accentColor)
    }
}

struct AidenteSettingToggle: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colors: [Color]
    @Binding var isOn: Bool
    init(_ title: String, subtitle: String? = nil, icon: String, colors: [Color], isOn: Binding<Bool>) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.colors = colors; _isOn = isOn
    }
    var body: some View {
        AidenteControlRow(title, subtitle: subtitle, icon: icon, colors: colors) {
            Toggle(AidenteL10n.t(title), isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.regular)
        }
    }
}

struct AidenteControlRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let colors: [Color]
    let trailing: Trailing
    init(_ title: String, subtitle: String? = nil, icon: String, colors: [Color], @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.icon = icon; self.colors = colors; self.trailing = trailing()
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).frame(width: 18)
            Text(AidenteL10n.t(title)).font(.system(size: 13, weight: .semibold))
            if let subtitle {
                AidenteHelpButton(title: title, explanation: subtitle)
            }
            Spacer(minLength: 8)
            trailing
        }.frame(minHeight: 32)
    }
}

struct AidenteRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.09))
            .frame(height: 1)
    }
}

struct AidenteNotice: View {
    @Default(.appLanguage) private var appLanguage

    let text: String
    var icon = "exclamationmark.triangle.fill"
    var colors = [AidenteTheme.amber, AidenteTheme.gold]

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            AidenteIconBadge(icon: icon, colors: colors, size: 26)
            Text(AidenteL10n.t(text))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill((colors.first ?? AidenteTheme.amber).opacity(0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder((colors.first ?? AidenteTheme.amber).opacity(0.20))
        )
    }
}

struct AidenteActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    let colors: [Color]
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary).padding(.horizontal, 14).padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.02 : 0.09), radius: 5, y: 2)
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}

struct AidenteInsetPanel<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
            }
    }
}

/// Shared neutral surface for dashboard tiles and inset settings controls.
struct UtilitySurface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color(white: 0.20) : .white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.06)))
            .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.065), radius: 9, y: 3)
    }
}
