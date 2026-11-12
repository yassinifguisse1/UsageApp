import AppKit
import SwiftUI
import UsageCore

/// Whether the rail is slid out from the display edge. PanelController animates changes.
@MainActor @Observable
final class RailPresentation {
    var isRevealed = true
    /// The arcs sweep in on the first reveal only. Pointing at the edge is frequent, so later reveals skip it.
    var sweepsArcs = true
}

struct UsageRail: View {
    static let width: CGFloat = 76
    private static let lead: CGFloat = 45
    private static let tail: CGFloat = 27
    private static let menuButtonSize: CGFloat = 44
    static let tileHeight: CGFloat = 78

    static func providerHeight(for providers: [Provider]) -> CGFloat {
        lead + CGFloat(providers.count) * tileHeight + tail
    }

    static func height(for providers: [Provider]) -> CGFloat {
        providerHeight(for: providers) + menuButtonSize
    }

    let model: UsageModel
    let presentation: RailPresentation
    let onHover: (Provider, Bool) -> Void
    let onClick: (Provider) -> Void
    let onOpenMenu: (NSView) -> Void
    @State private var hovered: Provider?
    @State private var menuHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func entranceDelay(at index: Int) -> Double { 0.04 + Double(index) * 0.03 }

    static func ringCenter(for provider: Provider, in providers: [Provider]) -> CGFloat {
        let index = providers.firstIndex(of: provider) ?? 0
        return lead + CGFloat(index) * tileHeight + 23
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.lead)

            ForEach(Array(model.visibleProviders.enumerated()), id: \.element) { index, provider in
                Button {
                    onClick(provider)
                } label: {
                    RingTile(
                        reading: model.display(for: provider),
                        hovered: hovered == provider,
                        pinned: model.pinnedProvider == provider,
                        showingDetails: model.detailsProvider == provider,
                        revealed: presentation.isRevealed || !presentation.sweepsArcs,
                        entranceDelay: Self.entranceDelay(at: index)
                    )
                }
                .modifier(Entrance(revealed: presentation.isRevealed, delay: Self.entranceDelay(at: index)))
                .buttonStyle(.plain)
                .frame(height: Self.tileHeight, alignment: .top)
                .background {
                    AlwaysHover { inside in
                        if inside { hovered = provider }
                        else if hovered == provider { hovered = nil }
                        onHover(provider, inside)
                    }
                }
            }

            RailMenuButton(onOpen: onOpenMenu)
                .modifier(Entrance(
                    revealed: presentation.isRevealed,
                    delay: Self.entranceDelay(at: model.visibleProviders.count)
                ))
                .frame(width: Self.menuButtonSize, height: Self.menuButtonSize)
                .background {
                    Circle()
                        .fill(HUDPalette.track.opacity(menuHovered ? 1 : 0))
                        .frame(width: 32, height: 32)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    AlwaysHover { menuHovered = $0 }
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(HUDPalette.track)
                        .frame(width: 28, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

            Color.clear.frame(height: Self.tail)
        }
        .frame(width: Self.width, height: Self.height(for: model.visibleProviders))
        .background {
            HUDGlassSurface(contour: EdgeRailContour())
        }
        .overlay(alignment: .top) {
            if model.isDemo {
                Text("DEMO")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(HUDPalette.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.09), in: Capsule())
                    .padding(.top, 27)
                    .offset(x: 4)
                    .accessibilityLabel("Demo mode")
            }
        }
        // The glass slides in from the edge. Reduce Motion keeps it in place and only fades.
        .offset(x: presentation.isRevealed || reduceMotion ? 0 : Self.width)
        .opacity(presentation.isRevealed ? 1 : 0)
    }
}

/// Each tile follows the glass in, slightly later than the one above it.
private struct Entrance: ViewModifier {
    let revealed: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: revealed || reduceMotion ? 0 : 22)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.82, anchor: .trailing)
            .opacity(revealed ? 1 : 0)
            .animation(
                revealed
                    ? .spring(response: 0.46, dampingFraction: 0.78).delay(reduceMotion ? 0 : delay)
                    : .easeIn(duration: 0.12),
                value: revealed
            )
    }
}

/// A slim tab at the display edge that marks where the hidden panel is.
struct EdgeTab: View {
    nonisolated static let size = CGSize(width: 12, height: 64)

    let model: UsageModel

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: 44)
            .shadow(color: tint.opacity(0.55), radius: 4)
            .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            .padding(.trailing, 2)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .trailing)
            .animation(.easeInOut(duration: 0.3), value: tint)
            .accessibilityHidden(true)
    }

    /// Neutral, or the busiest provider's color once it passes the notification threshold.
    private var tint: Color {
        let busiest = model.visibleProviders
            .compactMap { provider in model.display(for: provider).headline?.percent.map { (provider, $0) } }
            .max { $0.1 < $1.1 }
        guard let busiest, busiest.1 >= model.alertThreshold else { return .white.opacity(0.8) }
        return busiest.0.hudTint
    }
}

private struct RailMenuButton: NSViewRepresentable {
    let onOpen: (NSView) -> Void

    func makeNSView(context: Context) -> MenuControl {
        let button = MenuControl()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        button.contentTintColor = NSColor(HUDPalette.text)
        button.toolTip = "Show UsageApp Menu"
        button.setAccessibilityLabel("UsageApp Menu")
        button.target = button
        button.action = #selector(MenuControl.openMenu)
        return button
    }

    func updateNSView(_ button: MenuControl, context: Context) {
        button.onOpen = onOpen
    }

    final class MenuControl: NSButton {
        var onOpen: ((NSView) -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        @objc func openMenu() {
            onOpen?(self)
        }
    }
}

private struct EdgeRailContour: Shape {
    func path(in rect: CGRect) -> Path {
        let right = rect.maxX
        let left = rect.minX
        let top = rect.minY
        let bottom = rect.maxY
        let waist = rect.midX + 7
        let shoulder: CGFloat = 21

        return Path { path in
            path.move(to: CGPoint(x: right, y: top))
            path.addCurve(
                to: CGPoint(x: waist, y: top + shoulder),
                control1: CGPoint(x: right - 4, y: top + 23),
                control2: CGPoint(x: right - 17, y: top + shoulder)
            )
            path.addCurve(
                to: CGPoint(x: left, y: top + 53),
                control1: CGPoint(x: left + 21, y: top + shoulder),
                control2: CGPoint(x: left, y: top + 36)
            )
            path.addLine(to: CGPoint(x: left, y: bottom - 53))
            path.addCurve(
                to: CGPoint(x: waist, y: bottom - shoulder),
                control1: CGPoint(x: left, y: bottom - 36),
                control2: CGPoint(x: left + 21, y: bottom - shoulder)
            )
            path.addCurve(
                to: CGPoint(x: right, y: bottom),
                control1: CGPoint(x: right - 17, y: bottom - shoulder),
                control2: CGPoint(x: right - 4, y: bottom - 23)
            )
            path.closeSubpath()
        }
    }
}

private struct RingTile: View {
    let reading: ProviderDisplay
    let hovered: Bool
    let pinned: Bool
    let showingDetails: Bool
    let revealed: Bool
    let entranceDelay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            UsageGauge(reading: reading, isEmphasized: hovered || pinned, drawn: revealed, delay: entranceDelay)
                .padding(.top, 2)

            if let percent = reading.headline?.percent {
                Text(UsageFormat.percent(percent))
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .contentTransition(.numericText(value: percent))
                    .animation(reduceMotion ? nil : .smooth, value: percent)
                    .foregroundStyle(HUDPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 21)

                if reading.state == .stale {
                    Text("Stale")
                        .font(.system(size: 10))
                        .foregroundStyle(HUDPalette.secondary)
                }
            } else {
                Text(reading.state.shortLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HUDPalette.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 68, height: UsageRail.tileHeight, alignment: .top)
        .background(alignment: .trailing) {
            if pinned {
                Capsule()
                    .fill(reading.provider.hudTint)
                    .frame(width: 2, height: 18)
                    .padding(.trailing, 1)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: pinned)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.provider.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(showingDetails ? "Dismisses usage details" : "Shows usage details")
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let percent = reading.headline?.percent {
            parts.append("\(UsageFormat.percent(percent)) used")
        }
        if let label = reading.headline?.label { parts.append(label) }
        if reading.state != .current { parts.append(reading.state.rawValue) }
        if pinned { parts.append("Details pinned") }
        return parts.joined(separator: ". ")
    }
}

private struct UsageGauge: View {
    let reading: ProviderDisplay
    let isEmphasized: Bool
    /// The arc sweeps to its value as the rail slides in.
    let drawn: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var accent: Color { reading.provider.hudTint }
    private var arc: Double { (reading.headline?.percent ?? 0) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.36))
                .padding(6)
            Circle()
                .strokeBorder(HUDPalette.track.opacity(contrast == .increased ? 1 : 0.87), lineWidth: 4)
            if arc > 0 {
                Circle()
                    .inset(by: 2)
                    .trim(from: 0, to: drawn || reduceMotion ? arc : 0.001)
                    .stroke(
                        AngularGradient(
                            colors: [accent.opacity(0.68), accent, accent.opacity(0.90)],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(isEmphasized ? 0.58 : 0.33), radius: isEmphasized ? 5 : 2)
                    .opacity(drawn ? (reading.state == .stale ? 0.58 : 1) : 0)
                    .animation(
                        reduceMotion ? nil : drawn
                            ? .spring(response: 0.8, dampingFraction: 0.86).delay(delay + 0.1)
                            : .easeIn(duration: 0.1),
                        value: drawn
                    )
                    .animation(reduceMotion ? nil : .smooth, value: arc)
            }
            ProviderMark(provider: reading.provider, onDarkSurface: true, size: reading.provider == .perplexity ? 23 : 27)
        }
        .frame(width: 42, height: 42)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isEmphasized)
        .accessibilityHidden(true)
    }
}
