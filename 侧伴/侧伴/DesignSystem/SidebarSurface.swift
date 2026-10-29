import SwiftUI
import AppKit

/// Shared blue–teal atmosphere. Only the decorative backdrop is blurred.
struct SidebarSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    SidebarWindowMaterial()
                }
                LinearGradient(colors: colorScheme == .dark
                    ? [Color(red: 0.045, green: 0.10, blue: 0.20).opacity(0.80),
                       Color(red: 0.07, green: 0.19, blue: 0.24).opacity(0.64)]
                    : [Color(red: 0.83, green: 0.90, blue: 0.98).opacity(0.74),
                       Color(red: 0.86, green: 0.96, blue: 0.94).opacity(0.66)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                if !reduceTransparency {
                    Ellipse()
                        .fill(Color.cyan.opacity(colorScheme == .dark ? 0.16 : 0.18))
                        .frame(width: geometry.size.width * 0.95, height: geometry.size.height * 0.42)
                        .blur(radius: 65)
                        .offset(x: geometry.size.width * 0.35, y: -geometry.size.height * 0.20)
                    Ellipse()
                        .fill(Color.blue.opacity(colorScheme == .dark ? 0.14 : 0.12))
                        .frame(width: geometry.size.width, height: geometry.size.height * 0.40)
                        .blur(radius: 75)
                        .offset(x: -geometry.size.width * 0.35, y: geometry.size.height * 0.28)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SidebarWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct SidebarCardSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = 18
    var tint: Color? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(Color(nsColor: .controlBackgroundColor))
            } else {
                shape.fill(.thinMaterial)
                shape.fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.25 : 0.46))
            }
            if let tint {
                shape.fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.10))
            }
            shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.15 : 0.70),
                         .white.opacity(colorScheme == .dark ? 0.04 : 0.20)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .shadow(color: Color(red: 0.02, green: 0.12, blue: 0.22).opacity(colorScheme == .dark ? 0.12 : 0.055), radius: 12, y: 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
