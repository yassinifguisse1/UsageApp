import SwiftUI
import UsageCore

struct UsageRail: View {
    static let width: CGFloat = 76
    private static let lead: CGFloat = 45
    private static let tail: CGFloat = 27
    static let tileHeight: CGFloat = 78
    static let height = lead + CGFloat(Provider.allCases.count) * tileHeight + tail

    let model: UsageModel
    let onHover: (Provider, Bool) -> Void
    let onClick: (Provider) -> Void
    @State private var hovered: Provider?

    static func ringCenter(for provider: Provider) -> CGFloat {
        let index = Provider.allCases.firstIndex(of: provider) ?? 0
        return lead + CGFloat(index) * tileHeight + 23
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.lead)

            ForEach(Provider.allCases, id: \.self) { provider in
                Button {
                    onClick(provider)
                } label: {
                    RingTile(
                        reading: model.display(for: provider),
                        hovered: hovered == provider,
                        pinned: model.pinnedProvider == provider
                    )
                }
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

            Color.clear.frame(height: Self.tail)
        }
        .frame(width: Self.width, height: Self.height)
        .background {
            HUDGlassSurface(contour: EdgeRailContour())
        }
        .overlay(alignment: .top) {
            if model.isDemo {
                Text("DEMO")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            UsageGauge(reading: reading, isEmphasized: hovered || pinned)
                .padding(.top, 2)

            if let percent = reading.headline?.percent {
                Text(UsageFormat.percent(percent))
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
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
                Text(statusLabel)
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
        .accessibilityHint(pinned ? "Dismisses usage details" : "Pins usage details")
    }

    private var statusLabel: String {
        switch reading.state {
        case .setupRequired: "Set up"
        case .awaitingReset: "Reset due"
        case .current, .unavailable, .stale: "No data"
        }
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
                    .trim(from: 0, to: arc)
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
                    .opacity(reading.state == .stale ? 0.58 : 1)
            }
            ProviderMark(provider: reading.provider, onDarkSurface: true, size: reading.provider == .perplexity ? 23 : 27)
        }
        .frame(width: 42, height: 42)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isEmphasized)
        .accessibilityHidden(true)
    }
}
