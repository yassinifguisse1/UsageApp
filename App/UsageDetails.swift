import SwiftUI
import UsageCore

struct UsageDetails: View {
    let reading: ProviderDisplay
    let isDemo: Bool
    var isHUD = false
    var isPinned = false

    private var tint: Color { isHUD ? reading.provider.hudTint : reading.provider.tint }
    private var secondary: Color { isHUD ? HUDPalette.secondary : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                ProviderMark(provider: reading.provider, onDarkSurface: isHUD)
                Text(reading.provider.name)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .accessibilityLabel("Pinned")
                }
                if isDemo || reading.provider == .perplexity && reading.observedAt != nil {
                    Text(isDemo ? "Demo" : "Manual")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.primary.opacity(0.09), in: Capsule())
                }
            }

            if reading.windows.isEmpty {
                Text(reading.state.rawValue)
                    .font(.subheadline.weight(.semibold))
            }

            if let message = reading.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(reading.windows) { window in
                UsageWindowRow(window: window, tint: tint, secondary: secondary, isHUD: isHUD)
            }

            if let date = reading.observedAt {
                Rectangle()
                    .fill(.primary.opacity(0.11))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .accessibilityHidden(true)
                    Text("Captured \(UsageFormat.date(date))")
                        .font(.system(size: 10))
                }
                .foregroundStyle(secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageWindowRow: View {
    let window: WindowDisplay
    let tint: Color
    let secondary: Color
    let isHUD: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(window.label)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            if let percent = window.percent {
                AllowanceTrack(
                    percent: percent,
                    tint: tint.opacity(window.state == .stale ? 0.6 : 1),
                    track: isHUD ? HUDPalette.track : .primary.opacity(0.13)
                )
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        readingLabel(percent)
                        Spacer(minLength: 0)
                        Text(resetLabel).font(.system(size: 10)).foregroundStyle(secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        readingLabel(percent)
                        Text(resetLabel).font(.system(size: 10)).foregroundStyle(secondary)
                    }
                }
            } else {
                Text("Awaiting reset update")
                    .font(.system(size: 11, weight: .semibold))
                if let date = window.resetsAt {
                    Text("Reset passed \(UsageFormat.date(date))")
                        .font(.system(size: 10))
                        .foregroundStyle(secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func readingLabel(_ percent: Double) -> some View {
        HStack(spacing: 5) {
            Text("\(UsageFormat.percent(percent)) used")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
            if window.state == .stale {
                Text("Stale")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondary)
            }
        }
    }

    private var resetLabel: String {
        window.resetsAt.map { "Resets \(UsageFormat.date($0))" } ?? "Reset not provided"
    }
}

private struct AllowanceTrack: View {
    let percent: Double
    let tint: Color
    let track: Color

    var body: some View {
        GeometryReader { bounds in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if percent > 0 {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [tint.opacity(0.64), tint],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(2, bounds.size.width * percent / 100))
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

struct UsageCallout: View {
    nonisolated static let tipWidth: CGFloat = 19

    let reading: ProviderDisplay
    let isDemo: Bool
    let isPinned: Bool
    let width: CGFloat
    let height: CGFloat
    let tipY: CGFloat
    let onHover: (Bool) -> Void

    var body: some View {
        let contour = CalloutContour(tipY: tipY)
        ScrollView {
            UsageDetails(reading: reading, isDemo: isDemo, isHUD: true, isPinned: isPinned)
                .padding(17)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: height)
        .padding(.trailing, Self.tipWidth)
        .foregroundStyle(HUDPalette.text)
        .environment(\.colorScheme, .dark)
        .background {
            HUDGlassSurface(contour: contour)
        }
        .clipShape(contour)
        .background {
            AlwaysHover(onChange: onHover)
        }
    }
}

private struct CalloutContour: Shape {
    let tipY: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = rect.minY
        let bottom = rect.maxY
        let left = rect.minX
        let right = rect.maxX - UsageCallout.tipWidth
        let radius: CGFloat = 20
        let tip = min(max(rect.minY + tipY, top + 32), bottom - 32)

        return Path { path in
            path.move(to: CGPoint(x: left + radius, y: top))
            path.addLine(to: CGPoint(x: right - radius, y: top))
            path.addQuadCurve(to: CGPoint(x: right, y: top + radius), control: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: tip - 14))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: tip),
                control1: CGPoint(x: right, y: tip - 6),
                control2: CGPoint(x: rect.maxX - 6, y: tip - 3)
            )
            path.addCurve(
                to: CGPoint(x: right, y: tip + 14),
                control1: CGPoint(x: rect.maxX - 6, y: tip + 3),
                control2: CGPoint(x: right, y: tip + 6)
            )
            path.addLine(to: CGPoint(x: right, y: bottom - radius))
            path.addQuadCurve(to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
            path.addLine(to: CGPoint(x: left + radius, y: bottom))
            path.addQuadCurve(to: CGPoint(x: left, y: bottom - radius), control: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left, y: top + radius))
            path.addQuadCurve(to: CGPoint(x: left + radius, y: top), control: CGPoint(x: left, y: top))
            path.closeSubpath()
        }
    }
}
