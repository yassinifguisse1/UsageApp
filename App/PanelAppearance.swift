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
    /// Inside a usage ring the letter stands alone so the ring stays readable.
    var isFilled = true

    private var tint: Color { onDarkSurface ? provider.hudTint : provider.tint }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(isFilled ? tint : .clear)
            .overlay {
                Text(provider.monogram)
                    .font(.system(size: size * 0.56, weight: .bold, design: .rounded))
                    .foregroundStyle(isFilled ? (onDarkSurface ? HUDPalette.lower : .white) : tint)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Provider {
    /// A neutral mark. The project does not ship provider logos.
    var monogram: String {
        switch self {
        case .claude: "C"
        case .codex: "X"
        case .perplexity: "P"
        }
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
