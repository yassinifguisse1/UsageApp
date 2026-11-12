import AppKit
import SwiftUI

struct HUDGlassSurface<Contour: Shape>: View {
    let contour: Contour
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if reduceTransparency {
                contour.fill(HUDPalette.surface)
            } else {
                glass
                    .overlay {
                        contour.fill(HUDPalette.surface.opacity(tintOpacity))
                    }
            }
        }
        .overlay {
            contour.stroke(.white.opacity(contrast == .increased ? 0.34 : 0.16), lineWidth: 1)
        }
        .clipShape(contour)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Liquid Glass brings its own legibility, so it needs only a light dark tint. The older frosted
    /// material needs more to read as a HUD.
    private var tintOpacity: Double {
        if contrast == .increased { return 0.86 }
        if #available(macOS 26, *) { return 0.42 }
        return 0.75
    }

    @ViewBuilder private var glass: some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular, in: contour)
        } else {
            frostedSurface
        }
        #else
        frostedSurface
        #endif
    }

    private var frostedSurface: some View {
        HUDBackdrop()
    }
}

private struct HUDBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
