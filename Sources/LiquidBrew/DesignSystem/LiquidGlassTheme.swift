import SwiftUI
import AppKit

// MARK: - Native macOS 26+ Liquid Glass Design System

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

/// Applies true macOS 26+ `.glassEffect(..., in: RoundedRectangle(...))` with subtle specular refraction
public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var tint: Color?
    public var isInteractive: Bool

    public init(cornerRadius: CGFloat = 16, tint: Color? = nil, isInteractive: Bool = false) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.isInteractive = isInteractive
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let baseGlass: Glass = isInteractive ? .regular.interactive() : .regular
        let configuredGlass: Glass = tint != nil ? baseGlass.tint(tint?.opacity(0.28)) : baseGlass

        content
            .glassEffect(configuredGlass, in: shape)
    }
}

public extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 16, tint: Color? = nil, isInteractive: Bool = false) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, isInteractive: isInteractive))
    }
}

/// Compact native Liquid Glass pill badge
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
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .glassEffect(.regular.tint(color.opacity(0.22)), in: Capsule(style: .continuous))
    }
}

/// Native macOS 26+ `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` wrapper
public struct GlassPillButton: View {
    public let title: String
    public var icon: String?
    public var tint: Color
    public var isProminent: Bool
    public var isDisabled: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        tint: Color = .accentColor,
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
        Group {
            if isProminent {
                Button(action: action) {
                    buttonLabel
                }
                .buttonStyle(.glassProminent)
                .tint(tint)
            } else {
                Button(action: action) {
                    buttonLabel
                }
                .buttonStyle(.glass(.regular.tint(tint.opacity(0.25)).interactive()))
            }
        }
        .controlSize(.regular)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var buttonLabel: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
            }
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
            }
        }
        .padding(.horizontal, title.isEmpty ? 2 : 4)
    }
}

/// Subtle behind-window vibrancy canvas that lets macOS 26 Liquid Glass refract real desktop wallpaper & subtle ambient light
public struct LiquidMeshBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.accentColor.opacity(0.10), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: proxy.size.width * 0.45
                            )
                        )
                        .frame(width: proxy.size.width * 0.65, height: proxy.size.width * 0.65)
                        .offset(x: -proxy.size.width * 0.2, y: -proxy.size.height * 0.25)
                        .blur(radius: 70)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.cyan.opacity(0.08), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: proxy.size.width * 0.4
                            )
                        )
                        .frame(width: proxy.size.width * 0.55, height: proxy.size.width * 0.55)
                        .offset(x: proxy.size.width * 0.25, y: proxy.size.height * 0.2)
                        .blur(radius: 75)
                }
            }
            .ignoresSafeArea()
        }
    }
}
