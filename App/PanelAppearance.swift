import SwiftUI
import UsageCore

enum HUDPalette {
    static let upper = Color(red: 0.087, green: 0.096, blue: 0.114)
    static let lower = Color(red: 0.027, green: 0.032, blue: 0.041)
    static let text = Color(red: 0.97, green: 0.975, blue: 0.985)
    static let secondary = Color(red: 0.75, green: 0.78, blue: 0.82)
    static let track = Color.white.opacity(0.14)

    static let surface = LinearGradient(
        colors: [upper, lower],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Provider {
    var hudTint: Color {
        switch self {
        case .claude: Color(red: 1, green: 0.43, blue: 0.24)
        case .codex: Color(red: 0.28, green: 0.88, blue: 0.68)
        case .perplexity: Color(red: 0.35, green: 0.84, blue: 0.93)
        }
    }

    var tint: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return switch (self, dark) {
            case (.claude, true): NSColor(srgbRed: 1, green: 0.56, blue: 0.36, alpha: 1)
            case (.claude, false): NSColor(srgbRed: 0.68, green: 0.31, blue: 0.10, alpha: 1)
            case (.codex, true): NSColor(srgbRed: 0.34, green: 0.87, blue: 0.71, alpha: 1)
            case (.codex, false): NSColor(srgbRed: 0.10, green: 0.46, blue: 0.37, alpha: 1)
            case (.perplexity, true): NSColor(srgbRed: 0.35, green: 0.84, blue: 0.93, alpha: 1)
            case (.perplexity, false): NSColor(srgbRed: 0.07, green: 0.40, blue: 0.47, alpha: 1)
            }
        })
    }
}

struct ProviderMark: View {
    let provider: Provider
    var onDarkSurface = false
    var size: CGFloat = 24
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(assetName)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var assetName: String {
        provider.logoAsset(onDark: onDarkSurface || colorScheme == .dark)
    }
}

extension UsageState {
    /// A one- or two-word state for tight spaces such as the rail and menu badges.
    var shortLabel: String {
        switch self {
        case .setupRequired: "Set up"
        case .waiting: "Waiting"
        case .awaitingReset: "Reset due"
        case .current, .unavailable, .stale: "No data"
        }
    }
}

extension Provider {
    func logoAsset(onDark: Bool) -> String {
        switch self {
        case .claude: "ClaudeCode"
        case .codex: onDark ? "CodexDark" : "CodexLight"
        case .perplexity: onDark ? "PerplexityDark" : "PerplexityLight"
        }
    }

    /// The logo for menus and toolbars. It picks its light or dark artwork each time it draws.
    func logoImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            NSImage(named: logoAsset(onDark: dark))?.draw(in: rect.insetBy(dx: size * 0.04, dy: size * 0.04))
            return true
        }
        image.accessibilityDescription = name
        return image
    }
}

enum UsageFormat {
    static func percent(_ value: Double) -> String {
        if value > 0 && value < 0.1 {
            return "<" + 0.001.formatted(.percent.precision(.fractionLength(1)))
        }
        if value < 100 && value > 99.9 {
            return ">" + 0.999.formatted(.percent.precision(.fractionLength(1)))
        }
        return (value / 100).formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute().timeZone(.specificName(.short)))
    }
}
