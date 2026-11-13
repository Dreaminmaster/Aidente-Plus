import SwiftUI
import Defaults

/// Shared geometry keeps the menu-bar allocation aligned with the rendered icon.
enum BatteryIndicatorLayout {
    static let bodyWidth: CGFloat = 23
    static let bodyHeight: CGFloat = 13
    static let insideBodyWidth: CGFloat = 25
    static let insideBodyHeight: CGFloat = 13
    static let terminalWidth: CGFloat = 2
    static let terminalHeight: CGFloat = 5
    static let terminalSpacing: CGFloat = 0.5
    static let outsideTextSpacing: CGFloat = 2
    static let statusInset: CGFloat = 1

    static func width(insidePercentage: Bool) -> CGFloat {
        (insidePercentage ? insideBodyWidth : bodyWidth) + terminalSpacing + terminalWidth
    }
}

struct BatteryIndicatorView: View {
    @Default(.chargingIndicatorStyle) private var indicatorStyle
    let batteryLevel: Int
    let chargingMode: ChargingMode
    var isLowPowerModeEnabled: Bool = false
    var percentageDisplayLocation: PercentageDisplayLocation = .hidden
    var showState: Bool = false
    var style: MenuBarIconStyle = .compact
    var adapterConnected: Bool = false

    private var shouldShowInsidePercentage: Bool {
        style.percentageLocation(percentageDisplayLocation) == .insideIcon
    }

    private var shouldShowOutsidePercentage: Bool {
        style.percentageLocation(percentageDisplayLocation) == .nextToIcon
    }

    private var isCritical: Bool {
        showState && batteryLevel <= 20
    }

    private var fillColor: Color {
        if isLowPowerModeEnabled { return AidenteTheme.gold }
        if !showState && style != .macOS26 && style != .macOS27 { return Color(red: 0.62, green: 0.70, blue: 0.78) }
        if style == .macOS26 || style == .macOS27 { return .primary }
        if style == .iOSNative && !isLowPowerModeEnabled {
            if batteryLevel <= 20 { return Color(red: 1, green: 0.28, blue: 0.30) }
            return chargingMode == .charging ? .green : Color(white: 0.92)
        }
        if isCritical { return Color(red: 0.99, green: 0.62, blue: 0.66) }
        if isLowPowerModeEnabled { return AidenteTheme.gold }
        if chargingMode == .charging { return AidenteTheme.mint }
        if showState && chargingMode == .pluggedIn { return AidenteTheme.sky }
        if showState { return AidenteTheme.jade }
        return Color(red: 0.62, green: 0.70, blue: 0.78)
    }

    private enum Layout {
        static let cornerRadius: CGFloat = 2
        static let strokeWidth: CGFloat = 0.75
        static let outlineOpacity: CGFloat = 0.5
        static let trackColor = Color(red: 0.84, green: 0.88, blue: 0.92)
        static let contentColor = Color(red: 0.10, green: 0.14, blue: 0.20)
        static let levelAnimation: Animation = .easeInOut(duration: 0.25)
    }

    var body: some View {
        Group {
            if style == .hidden {
                if percentageDisplayLocation != .hidden {
                    Text("\(batteryLevel)%").font(.system(size: 11)).monospacedDigit()
                }
            } else if style == .appIcon {
                HStack(spacing: 3) {
                    Image(systemName: statusSymbol).font(.system(size: 17, weight: .medium))
                    if percentageDisplayLocation != .hidden {
                        Text("\(batteryLevel)%").font(.system(size: 11)).monospacedDigit().lineLimit(1).fixedSize()
                    }
                }
            } else if style == .status {
                HStack(spacing: 3) {
                    if shouldShowOutsidePercentage {
                        Text("\(batteryLevel)%").font(.system(size: 11)).monospacedDigit()
                    }
                    statusBattery
                }
            } else {
                batteryContent
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var statusBattery: some View {
        HStack(spacing: BatteryIndicatorLayout.terminalSpacing) {
            HStack(spacing: 2) {
                if chargingMode == .charging || chargingMode == .pluggedIn {
                    Image(systemName: indicatorStyle.usesPlug(for: chargingMode) ? "powerplug.portrait.fill" : "bolt.fill")
                        .resizable().scaledToFit().frame(width: 6, height: 10)
                } else { Image(systemName: adapterConnected ? "minus" : "chevron.down").font(.system(size: 8, weight: .bold)) }
                ForEach(0..<3) { bar in
                    RoundedRectangle(cornerRadius: 0.5).fill(.primary.opacity(batteryLevel > bar * 33 ? 1 : 0.2))
                        .frame(width: 2, height: 7)
                }
            }.padding(.horizontal, 2).frame(width: 26, height: 13)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.8), lineWidth: 0.8))
            BatteryTerminal(width: 2, height: 5, cornerRadius: 0.5)
        }.foregroundStyle(isLowPowerModeEnabled ? AidenteTheme.gold : .primary)
    }

    private var statusSymbol: String {
        if style == .appIcon { return "leaf.circle" }
        if chargingMode == .charging { return "bolt.circle.fill" }
        if chargingMode == .pluggedIn { return "powerplug.fill" }
        return adapterConnected ? "battery.50percent" : "battery.25percent"
    }

    private var batteryContent: some View {
        HStack(spacing: BatteryIndicatorLayout.outsideTextSpacing) {
            if shouldShowOutsidePercentage {
                Text("\(batteryLevel)%")
                    .font(.system(size: 11))
                    .monospacedDigit()
            }

            HStack(spacing: BatteryIndicatorLayout.terminalSpacing) {
                batteryBody
                BatteryTerminal(
                    width: BatteryIndicatorLayout.terminalWidth,
                    height: BatteryIndicatorLayout.terminalHeight,
                    cornerRadius: 0.5
                )
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = [
            AidenteL10n.t(
                "电池电量 \(batteryLevel)%",
                "Battery level \(batteryLevel)%"
            )
        ]
        switch chargingMode {
        case .charging: parts.append(AidenteL10n.t("正在充电"))
        case .pluggedIn: parts.append(AidenteL10n.t("已接通电源", "Plugged In"))
        case .discharging: parts.append(adapterConnected ? AidenteL10n.t("已接电，正在放电", "Plugged in and Discharging") : AidenteL10n.t("正在使用电池", "On Battery"))
        }
        if isLowPowerModeEnabled {
            parts.append(AidenteL10n.t("低电量模式", "Low Power Mode"))
        }
        return parts.joined(separator: "，")
    }

    private var batteryBody: some View {
        ZStack {
            Rectangle()
                .fill((style == .macOS26 || style == .macOS27) ? Color.primary.opacity(0.15) : Layout.trackColor)

            GeometryReader { geo in
                Rectangle()
                    .fill(fillColor)
                    .clipShape(RoundedRectangle(cornerRadius: roundedStyle ? 2.5 : 0))
                    .frame(width: fillWidth(usableWidth: geo.size.width))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(Layout.levelAnimation, value: batteryLevel)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: roundedStyle ? 3 : Layout.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: roundedStyle ? 3 : Layout.cornerRadius)
                .strokeBorder(.primary.opacity(Layout.outlineOpacity), lineWidth: Layout.strokeWidth)
        }
        .overlay {
            Group {
                if shouldShowInsidePercentage { insideContent }
                else { chargingGlyph }
            }
            .foregroundStyle((style == .macOS26 || style == .macOS27) ? Color.white : Layout.contentColor)
            .blendMode((style == .macOS26 || style == .macOS27) ? .difference : .normal)
        }
        .compositingGroup()
        .frame(
            width: (shouldShowInsidePercentage ? BatteryIndicatorLayout.insideBodyWidth : BatteryIndicatorLayout.bodyWidth) + (style == .iOSNative ? 3 : 0),
            height: shouldShowInsidePercentage ? BatteryIndicatorLayout.insideBodyHeight : BatteryIndicatorLayout.bodyHeight
        )
    }

    private var roundedStyle: Bool { style == .macOS27 || style == .iOSNative }

    private func fillWidth(usableWidth: CGFloat) -> CGFloat {
        usableWidth * CGFloat(min(100, max(0, batteryLevel))) / 100
    }

    private var insideContent: some View {
        HStack(spacing: style == .macOS27 ? 0 : 0.5) {
            Text(verbatim: "\(batteryLevel)")
                .font(.system(size: batteryLevel >= 100 ? (chargingMode == .pluggedIn ? 8 : 9) : 10.5, weight: .semibold))
                .monospacedDigit()
                .fixedSize()
            chargingGlyph
        }
        .lineLimit(1)
        .fixedSize()
    }

    @ViewBuilder
    private var chargingGlyph: some View {
        if chargingMode == .charging || chargingMode == .pluggedIn {
            Image(systemName: indicatorStyle.usesPlug(for: chargingMode) ? "powerplug.portrait.fill" : "bolt.fill")
                .resizable().scaledToFit().frame(width: indicatorStyle.usesPlug(for: chargingMode) ? 5.5 : 4, height: 8)
        }
    }
}

struct BatteryTerminal: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: cornerRadius
        )
        .fill(.primary)
        .frame(width: width, height: height)
        .opacity(0.55)
    }
}

/// Original vector geometry: two prongs, rounded plug body and cable.
struct BatteryPlugGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.3, y: h * 0.05)); path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.35))
        path.move(to: CGPoint(x: w * 0.7, y: h * 0.05)); path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.35))
        path.addRoundedRect(in: CGRect(x: w * 0.08, y: h * 0.35, width: w * 0.84, height: h * 0.38), cornerSize: CGSize(width: w * 0.2, height: h * 0.12))
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.73)); path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.98))
        return path
    }
}
