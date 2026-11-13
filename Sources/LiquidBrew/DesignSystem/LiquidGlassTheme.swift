import SwiftUI

public extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 12, tint: Color? = nil, isInteractive: Bool = false) -> some View {
        glassEffect(
            .regular.tint(tint?.opacity(0.22)).interactive(isInteractive),
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
    }
}

extension View {
    func glassToolbar() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background { Color.clear.liquidGlassCard(cornerRadius: 18) }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

struct GlassWorkspaceBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay {
                RadialGradient(colors: [.teal.opacity(0.26), .clear], center: .topTrailing, startRadius: 0, endRadius: 620)
            }
            .overlay {
                RadialGradient(colors: [.indigo.opacity(0.21), .clear], center: .bottomLeading, startRadius: 0, endRadius: 640)
            }
            .ignoresSafeArea()
    }
}

public struct GlassBadge: View {
    public let text: String
    public var icon: String?
    public var color: Color
    public init(_ text: String, icon: String? = nil, color: Color = .secondary) {
        self.text = text; self.icon = icon; self.color = color
    }
    public var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

public struct GlassPillButton: View {
    public let title: String
    public var icon: String?
    public var tint: Color
    public var isProminent: Bool
    public var isDisabled: Bool
    public let action: () -> Void
    public init(_ title: String, icon: String? = nil, tint: Color = .accentColor,
                isProminent: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.tint = tint
        self.isProminent = isProminent; self.isDisabled = isDisabled; self.action = action
    }
    public var body: some View {
        Group {
            if isProminent {
                Button(action: action) { buttonLabel }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                Button(action: action) { buttonLabel }
                    .buttonStyle(.glass(.regular.tint(tint.opacity(0.18))))
            }
        }
        .disabled(isDisabled)
    }
    @ViewBuilder private var buttonLabel: some View {
        if let icon { Label(title, systemImage: icon) } else { Text(title) }
    }
}
