import SwiftUI
import AppKit

// MARK: - Liquid Glass Material & Shimmer System

public struct VisualEffectBlur: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var tint: Color?
    public var isInteractive: Bool
    @State private var isHovered: Bool = false

    public init(cornerRadius: CGFloat = 18, tint: Color? = nil, isInteractive: Bool = false) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.isInteractive = isInteractive
    }

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(isHovered && isInteractive ? 0.16 : 0.08))
                    } else if isHovered && isInteractive {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    }

                    // Specular liquid rim highlight
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered && isInteractive ? 0.55 : 0.35),
                                    Color.white.opacity(0.10),
                                    Color.cyan.opacity(isHovered && isInteractive ? 0.30 : 0.12),
                                    Color.white.opacity(0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isHovered && isInteractive ? 1.4 : 1.0
                        )
                }
                .shadow(color: Color.black.opacity(isHovered && isInteractive ? 0.24 : 0.14), radius: isHovered && isInteractive ? 16 : 10, x: 0, y: 6)
            }
            .scaleEffect(isHovered && isInteractive ? 1.008 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovered)
            .onHover { hovering in
                if isInteractive {
                    isHovered = hovering
                }
            }
    }
}

public extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 18, tint: Color? = nil, isInteractive: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, isInteractive: isInteractive))
    }
}

public struct GlassBadge: View {
    public let text: String
    public var icon: String?
    public var color: Color

    public init(_ text: String, icon: String? = nil, color: Color = .cyan) {
        self.text = text
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .foregroundStyle(color)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(color.opacity(0.38), lineWidth: 0.8)
                )
        )
    }
}

public struct GlassPillButton: View {
    public let title: String
    public var icon: String?
    public var tint: Color
    public var isProminent: Bool
    public var isDisabled: Bool
    public let action: () -> Void

    @State private var isHovered = false

    public init(
        _ title: String,
        icon: String? = nil,
        tint: Color = .cyan,
        isProminent: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.isProminent = isProminent
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                }
            }
            .padding(.horizontal, title.isEmpty ? 9 : 13)
            .padding(.vertical, 7)
            .foregroundStyle(isProminent ? Color.white : (isHovered ? tint : Color.primary))
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(
                            isProminent
                                ? LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [tint.opacity(isHovered ? 0.25 : 0.12), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.65 : 0.35),
                                    tint.opacity(isHovered ? 0.55 : 0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .shadow(color: tint.opacity(isHovered ? 0.28 : 0.08), radius: isHovered ? 10 : 4, x: 0, y: 3)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .onHover { isHovered = $0 }
    }
}

public struct LiquidMeshBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // Ambient refraction orbs
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.cyan.opacity(0.22), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: proxy.size.width * 0.45
                            )
                        )
                        .frame(width: proxy.size.width * 0.7, height: proxy.size.width * 0.7)
                        .offset(x: -proxy.size.width * 0.22, y: -proxy.size.height * 0.28)
                        .blur(radius: 50)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.indigo.opacity(0.20), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: proxy.size.width * 0.45
                            )
                        )
                        .frame(width: proxy.size.width * 0.65, height: proxy.size.width * 0.65)
                        .offset(x: proxy.size.width * 0.28, y: proxy.size.height * 0.22)
                        .blur(radius: 60)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.mint.opacity(0.14), Color.clear],
                                center: .center,
                                startRadius: 5,
                                endRadius: proxy.size.width * 0.35
                            )
                        )
                        .frame(width: proxy.size.width * 0.5, height: proxy.size.width * 0.5)
                        .offset(x: proxy.size.width * 0.1, y: -proxy.size.height * 0.15)
                        .blur(radius: 45)
                }
            }
            .ignoresSafeArea()
        }
    }
}
