import AppKit
import SwiftUI
import UsageCore

/// The panel as a bar that drops out of the notch. Collapsed, it matches `NotchTab`.
struct NotchBar: View {
    static let tileWidth: CGFloat = 72
    fileprivate static let ear: CGFloat = 38
    private static let sidePadding: CGFloat = 14
    private static let rowInset: CGFloat = 4

    static func collapsedSize(notch: CGSize) -> CGSize {
        CGSize(width: notch.width + 2 * (ear + NotchContour.flare), height: notch.height)
    }

    static func expandedSize(notch: CGSize, providers: [Provider]) -> CGSize {
        CGSize(
            width: max(
                collapsedSize(notch: notch).width,
                rowWidth(for: providers) + 2 * (sidePadding + NotchContour.flare)
            ),
            height: notch.height + rowInset + UsageRail.tileHeight
        )
    }

    private static func rowWidth(for providers: [Provider]) -> CGFloat {
        CGFloat(providers.count) * tileWidth + RailGear.size
    }

    /// A ring's center, measured from the left end of the expanded bar.
    static func ringCenter(for provider: Provider, in providers: [Provider], notch: CGSize) -> CGFloat {
        let index = CGFloat(providers.firstIndex(of: provider) ?? 0)
        let rowStart = (expandedSize(notch: notch, providers: providers).width - rowWidth(for: providers)) / 2
        return rowStart + (index + 0.5) * tileWidth
    }

    let model: UsageModel
    let presentation: RailPresentation
    let onHover: (Provider, Bool) -> Void
    let onClick: (Provider) -> Void
    let onOpenMenu: (NSView) -> Void
    @State private var hovered: Provider?

    var body: some View {
        let providers = model.visibleProviders
        let notch = presentation.notch
        let expanded = presentation.isRevealed
        let full = Self.expandedSize(notch: notch, providers: providers)
        let size = expanded ? full : Self.collapsedSize(notch: notch)

        ZStack(alignment: .top) {
            // The housing grows out of the notch, so it stays opaque black instead of fading in.
            NotchContour(bottomRadius: expanded ? 24 : NotchContour.restingRadius)
                .fill(.black)
                .frame(width: size.width, height: size.height)

            NotchEars(model: model, notch: notch)
                .opacity(expanded ? 0 : 1)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
                    Button {
                        onClick(provider)
                    } label: {
                        RingTile(
                            reading: model.display(for: provider),
                            hovered: hovered == provider,
                            pinned: model.pinnedProvider == provider,
                            showingDetails: model.detailsProvider == provider,
                            revealed: expanded || !presentation.sweepsArcs,
                            entranceDelay: UsageRail.entranceDelay(at: index),
                            pinEdge: .bottom
                        )
                    }
                    .modifier(Entrance(revealed: expanded, delay: UsageRail.entranceDelay(at: index), from: .top))
                    .buttonStyle(.plain)
                    .frame(width: Self.tileWidth, height: UsageRail.tileHeight, alignment: .top)
                    .background {
                        AlwaysHover { inside in
                            if inside { hovered = provider }
                            else if hovered == provider { hovered = nil }
                            onHover(provider, inside)
                        }
                    }
                }

                VStack(spacing: 0) {
                    RailGear(divider: .leading, onOpenMenu: onOpenMenu)
                    if model.isDemo {
                        Text("DEMO")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(HUDPalette.secondary)
                            .accessibilityLabel("Demo mode")
                    }
                }
                .modifier(Entrance(
                    revealed: expanded, delay: UsageRail.entranceDelay(at: providers.count), from: .top
                ))
            }
            .padding(.top, notch.height + Self.rowInset)
        }
        .frame(width: full.width, height: full.height, alignment: .top)
    }
}

/// The collapsed notch. It marks where the hidden bar is and shows the busiest reading at a glance.
struct NotchTab: View {
    let model: UsageModel
    let presentation: RailPresentation

    var body: some View {
        let size = NotchBar.collapsedSize(notch: presentation.notch)
        NotchContour(bottomRadius: NotchContour.restingRadius)
            .fill(.black)
            .overlay { NotchEars(model: model, notch: presentation.notch) }
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}

/// The busiest provider's ring on one side of the camera housing and its reading on the other.
private struct NotchEars: View {
    let model: UsageModel
    let notch: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let busiest = model.busiest
        HStack(spacing: 0) {
            Group {
                if let busiest {
                    ZStack {
                        Circle().stroke(HUDPalette.track, lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: max(0.001, busiest.percent / 100))
                            .stroke(busiest.provider.hudTint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(reduceMotion ? nil : .smooth, value: busiest.percent)
                    }
                    .frame(width: 13, height: 13)
                } else {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HUDPalette.secondary)
                }
            }
            .frame(width: NotchBar.ear)

            Color.clear.frame(width: notch.width)

            Text(busiest.map { UsageFormat.percent($0.percent) } ?? "")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(HUDPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: NotchBar.ear - 4)
                .padding(.trailing, 4)
        }
        .frame(height: notch.height)
        .accessibilityHidden(true)
    }
}

/// A notch outline: flush with the top of the display, flaring into it at the top corners.
struct NotchContour: Shape {
    static let flare: CGFloat = 6
    static let restingRadius: CGFloat = 10

    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let flare = Self.flare
        let left = rect.minX + flare
        let right = rect.maxX - flare
        let radius = min(bottomRadius, rect.height - flare, (right - left) / 2)

        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: left, y: rect.minY + flare), control: CGPoint(x: left, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: left, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: left + radius, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: right - radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: right, y: rect.maxY - radius), control: CGPoint(x: right, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: right, y: rect.minY + flare))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY)
            )
            path.closeSubpath()
        }
    }
}
