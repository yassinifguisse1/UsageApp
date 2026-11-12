import AppKit
import SwiftUI
import UsageCore

/// Whether the rail is slid out from the display edge. PanelController animates changes.
@MainActor @Observable
final class RailPresentation {
    var isRevealed = true
    /// The camera housing the notch bar hangs from. The width is zero on a display without one.
    var notch = CGSize.zero
    /// The arcs sweep in on the first reveal only. Pointing at the edge is frequent, so later reveals skip it.
    var sweepsArcs = true
}

struct UsageRail: View {
    static let width: CGFloat = 76
    private static let lead: CGFloat = 45
    private static let tail: CGFloat = 27
    static let tileHeight: CGFloat = 78

    static func providerHeight(for providers: [Provider]) -> CGFloat {
        lead + CGFloat(providers.count) * tileHeight + tail
    }

    static func height(for providers: [Provider]) -> CGFloat {
        providerHeight(for: providers) + RailGear.size
    }

    let model: UsageModel
    let presentation: RailPresentation
    /// The display edge the rail sits against.
    let edge: Edge
    let onHover: (Provider, Bool) -> Void
    let onClick: (Provider) -> Void
    let onOpenMenu: (NSView) -> Void
    @State private var hovered: Provider?
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
                        entranceDelay: Self.entranceDelay(at: index),
                        pinEdge: edge
                    )
                }
                .modifier(Entrance(revealed: presentation.isRevealed, delay: Self.entranceDelay(at: index), from: edge))
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

            RailGear(divider: .top, onOpenMenu: onOpenMenu)

            Color.clear.frame(height: Self.tail)
        }
        .frame(width: Self.width, height: Self.height(for: model.visibleProviders))
        .background {
            HUDGlassSurface(contour: EdgeRailContour(edge: edge))
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
                    .offset(x: edge == .leading ? -4 : 4)
                    .accessibilityLabel("Demo mode")
            }
        }
        // The glass slides in from the edge. Reduce Motion keeps it in place and only fades.
        .offset(x: presentation.isRevealed || reduceMotion ? 0 : edge == .leading ? -Self.width : Self.width)
        .opacity(presentation.isRevealed ? 1 : 0)
    }
}

/// The gear that opens the UsageApp menu when the pointer rests on it.
struct RailGear: View {
    static let size: CGFloat = 44

    /// The side facing the rings, which gets a hairline.
    let divider: Edge
    let onOpenMenu: (NSView) -> Void
    @State private var hovered = false

    var body: some View {
        Image(systemName: "gearshape")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(HUDPalette.text)
            .frame(width: Self.size, height: Self.size)
            .background {
                Circle()
                    .fill(HUDPalette.track.opacity(hovered ? 1 : 0))
                    .frame(width: 32, height: 32)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background {
                RailMenuHover(onHover: { hovered = $0 }, onOpen: onOpenMenu)
            }
            .accessibilityHidden(true)
            .overlay(alignment: divider == .top ? .top : .leading) {
                Capsule()
                    .fill(HUDPalette.track)
                    .frame(width: divider == .top ? 28 : 1, height: divider == .top ? 1 : 28)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// Each tile follows the panel in from its edge, slightly later than the one before it.
struct Entrance: ViewModifier {
    let revealed: Bool
    let delay: Double
    let from: Edge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var travel: CGSize {
        switch from {
        case .leading: CGSize(width: -22, height: 0)
        case .top: CGSize(width: 0, height: -14)
        default: CGSize(width: 22, height: 0)
        }
    }

    private var anchor: UnitPoint {
        switch from {
        case .leading: .leading
        case .top: .top
        default: .trailing
        }
    }

    func body(content: Content) -> some View {
        content
            .offset(revealed || reduceMotion ? .zero : travel)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.82, anchor: anchor)
            .opacity(revealed ? 1 : 0)
            .animation(
                revealed
                    ? .spring(response: 0.46, dampingFraction: 0.78).delay(reduceMotion ? 0 : delay)
                    : .easeIn(duration: 0.12),
                value: revealed
            )
    }
}

extension UsageModel {
    /// The visible provider with the highest headline reading.
    var busiest: (provider: Provider, percent: Double)? {
        visibleProviders
            .compactMap { provider in display(for: provider).headline?.percent.map { (provider: provider, percent: $0) } }
            .max { $0.percent < $1.percent }
    }
}

/// A slim tab at the display edge that marks where the hidden panel is.
struct EdgeTab: View {
    nonisolated static let size = CGSize(width: 12, height: 64)

    let model: UsageModel
    let edge: Edge

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: 44)
            .shadow(color: tint.opacity(0.55), radius: 4)
            .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            .padding(Edge.Set(edge), 2)
            .frame(width: Self.size.width, height: Self.size.height, alignment: edge == .leading ? .leading : .trailing)
            .animation(.easeInOut(duration: 0.3), value: tint)
            .accessibilityHidden(true)
    }

    /// Neutral, or the busiest provider's color once it passes the notification threshold.
    private var tint: Color {
        guard let busiest = model.busiest, busiest.percent >= model.alertThreshold else { return .white.opacity(0.8) }
        return busiest.provider.hudTint
    }
}

private struct RailMenuHover: NSViewRepresentable {
    let onHover: (Bool) -> Void
    let onOpen: (NSView) -> Void

    func makeNSView(context: Context) -> RailMenuControl {
        RailMenuControl(onHover: onHover, onOpen: onOpen)
    }

    func updateNSView(_ view: RailMenuControl, context: Context) {
        view.onHover = onHover
        view.onOpen = onOpen
    }
}

private struct EdgeRailContour: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        // Drawn against the right edge, then mirrored for the left.
        let contour = rightEdgePath(in: rect)
        guard edge == .leading else { return contour }
        return contour.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }

    private func rightEdgePath(in rect: CGRect) -> Path {
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

struct RingTile: View {
    let reading: ProviderDisplay
    let hovered: Bool
    let pinned: Bool
    let showingDetails: Bool
    let revealed: Bool
    let entranceDelay: Double
    /// The side that carries the pinned marker, toward the display edge.
    let pinEdge: Edge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pinAlignment: Alignment {
        switch pinEdge {
        case .leading: .leading
        case .top, .bottom: .bottom
        case .trailing: .trailing
        }
    }

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
            } else {
                Text(reading.state.shortLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HUDPalette.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 68, height: UsageRail.tileHeight, alignment: .top)
        .background(alignment: pinAlignment) {
            if pinned {
                Capsule()
                    .fill(reading.provider.hudTint)
                    .frame(width: pinAlignment == .bottom ? 18 : 2, height: pinAlignment == .bottom ? 2 : 18)
                    .padding(pinAlignment == .bottom ? .bottom : Edge.Set(pinEdge), 1)
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
                        // Hover thickens the arc slightly. The ring never uses a glow.
                        style: StrokeStyle(lineWidth: isEmphasized ? 5 : 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
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
