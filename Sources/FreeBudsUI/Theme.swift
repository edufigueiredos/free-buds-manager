import SwiftUI
import AppKit

// MARK: - Themes

/// The looks the user can pick, named after the colors the earbuds come in plus a neon one.
public enum AppTheme: String, CaseIterable, Identifiable {
    case gold, black, white, neon, glass, classic

    public var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gold: return "Gold"
        case .black: return "Black"
        case .white: return "White"
        case .neon: return "Neon"
        case .glass: return "Liquid Glass"
        case .classic: return "Classic"
        }
    }
}

/// Everything a view needs to paint itself in the chosen theme.
struct ThemeStyle {
    var theme: AppTheme
    var accent: Color
    var accentTop: Color
    var accentBottom: Color
    /// Text and icons drawn on top of a solid accent fill.
    var onAccent: Color
    /// Opaque backdrop, or `nil` to keep the system look.
    var background: Color?
    var card: Color
    var tile: Color
    var cardStroke: Color
    /// Color of the glow around selected items; `nil` for a flat look.
    var glow: Color?
    var batteryGood: Color
    var scheme: ColorScheme?
    /// Explicit text color for themes that force light or dark; `nil` keeps the system's.
    var text: Color?

    var isNeon: Bool { theme == .neon }
    var isGlass: Bool { theme == .glass }
    var accentGradient: LinearGradient {
        LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom)
    }
    /// Foreground for something sitting on a selected (accent) background.
    var selectedForeground: Color { isNeon ? accent : onAccent }

    static func make(_ theme: AppTheme, neon: Color) -> ThemeStyle {
        switch theme {
        case .gold:
            let top = Color(red: 0.95, green: 0.80, blue: 0.48), bottom = Color(red: 0.74, green: 0.54, blue: 0.20)
            return ThemeStyle(theme: theme, accent: Color(red: 0.88, green: 0.70, blue: 0.34), accentTop: top, accentBottom: bottom,
                              onAccent: Color(red: 0.13, green: 0.09, blue: 0.02),
                              background: Color(red: 0.075, green: 0.064, blue: 0.048),
                              card: Color.white.opacity(0.06), tile: Color.white.opacity(0.07), cardStroke: .clear,
                              glow: Color(red: 0.88, green: 0.70, blue: 0.34).opacity(0.35),
                              batteryGood: Color(red: 0.88, green: 0.70, blue: 0.34), scheme: .dark, text: Color(white: 0.96))
        case .black:
            return ThemeStyle(theme: theme, accent: Color(white: 0.92), accentTop: Color(white: 0.97), accentBottom: Color(white: 0.74),
                              onAccent: Color(white: 0.06),
                              background: Color(red: 0.045, green: 0.045, blue: 0.05),
                              card: Color.white.opacity(0.065), tile: Color.white.opacity(0.07), cardStroke: .clear,
                              glow: Color.white.opacity(0.16), batteryGood: Color(white: 0.9), scheme: .dark, text: Color(white: 0.96))
        case .white:
            return ThemeStyle(theme: theme, accent: Color(white: 0.12), accentTop: Color(white: 0.22), accentBottom: Color(white: 0.07),
                              onAccent: .white,
                              background: Color(red: 0.965, green: 0.96, blue: 0.945),
                              card: Color.black.opacity(0.05), tile: Color.black.opacity(0.055), cardStroke: .clear,
                              glow: nil, batteryGood: Color(white: 0.16), scheme: .light, text: Color(white: 0.09))
        case .neon:
            return ThemeStyle(theme: theme, accent: neon, accentTop: neon, accentBottom: neon, onAccent: .black,
                              background: .black,
                              card: neon.opacity(0.05), tile: neon.opacity(0.07), cardStroke: neon.opacity(0.28),
                              glow: neon.opacity(0.75), batteryGood: neon, scheme: .dark, text: Color(white: 0.96))
        case .glass:
            // Follows the system: its accent color, light or dark, and the translucent material behind.
            return ThemeStyle(theme: theme, accent: .accentColor, accentTop: .accentColor, accentBottom: .accentColor,
                              onAccent: .white, background: nil,
                              card: Color.primary.opacity(0.07), tile: Color.primary.opacity(0.08),
                              cardStroke: Color.primary.opacity(0.10), glow: nil,
                              batteryGood: .accentColor, scheme: nil, text: nil)
        case .classic:
            let top = Color(red: 0.96, green: 0.34, blue: 0.30), bottom = Color(red: 0.80, green: 0.14, blue: 0.25)
            return ThemeStyle(theme: theme, accent: top, accentTop: top, accentBottom: bottom, onAccent: .white,
                              background: nil, card: Color.primary.opacity(0.06), tile: Color.primary.opacity(0.07),
                              cardStroke: .clear, glow: top.opacity(0.35), batteryGood: Color(red: 0.20, green: 0.78, blue: 0.40),
                              scheme: nil, text: nil)
        }
    }
}

private struct ThemeStyleKey: EnvironmentKey {
    static let defaultValue = ThemeStyle.make(.classic, neon: .cyan)
}

extension EnvironmentValues {
    var style: ThemeStyle {
        get { self[ThemeStyleKey.self] }
        set { self[ThemeStyleKey.self] = newValue }
    }
}

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = Color(red: 0, green: 0.94, blue: 1)
            return
        }
        self = Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.cyan
        return String(format: "#%02X%02X%02X", Int(round(color.redComponent * 255)),
                      Int(round(color.greenComponent * 255)), Int(round(color.blueComponent * 255)))
    }
}

/// Reads the saved theme and applies it (colors, backdrop, light/dark) to everything inside.
struct ThemedRoot<Content: View>: View {
    @AppStorage("appTheme") private var themeName = AppTheme.gold.rawValue
    @AppStorage("neonColorHex") private var neonHex = "#00F0FF"
    @ViewBuilder var content: Content

    var body: some View {
        let style = ThemeStyle.make(AppTheme(rawValue: themeName) ?? .gold, neon: Color(hex: neonHex))
        content
            .modifier(TextColorModifier(color: style.text))
            .modifier(ForcedSchemeModifier(scheme: style.scheme))
            .environment(\.style, style)
            .tint(style.accent)
            .background {
                if style.isGlass {
                    // The real glass is the window's own backdrop; the preview tool draws a flat stand-in.
                    if GlassPreview.approximate {
                        ZStack {
                            LinearGradient(colors: [.cyan.opacity(0.5), .indigo.opacity(0.5), .pink.opacity(0.4)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            Color.black.opacity(0.35)
                        }
                    }
                } else {
                    style.background ?? Color(nsColor: .windowBackgroundColor)
                }
            }
            .preferredColorScheme(style.scheme)
    }
}

/// `preferredColorScheme` alone does not reach text inside a menu-bar popover, so set the
/// environment and the foreground color explicitly as well.
private struct ForcedSchemeModifier: ViewModifier {
    let scheme: ColorScheme?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let scheme { content.environment(\.colorScheme, scheme) } else { content }
    }
}

private struct TextColorModifier: ViewModifier {
    let color: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}

/// The real glass cannot be drawn off screen, so the preview tool turns this on to get a flat stand-in.
public enum GlassPreview {
    nonisolated(unsafe) public static var approximate = false
}

enum Palette {
    /// Status green: connected dot, charging bolt.
    static let good = Color(red: 0.20, green: 0.78, blue: 0.40)
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    @Environment(\.style) private var style
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(style.cardStroke, lineWidth: 1))
    }
}

struct SectionLabel: View {
    @Environment(\.style) private var style
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(style.isNeon ? style.accent.opacity(0.85) : Color.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

/// Background of a selectable item: solid accent normally, a glowing outline in neon, tinted glass in Liquid Glass.
struct SelectableBackground: View {
    @Environment(\.style) private var style
    let selected: Bool
    var radius: CGFloat = 11
    var capsule = false

    var body: some View {
        Group {
            if capsule {
                // A rounded rectangle with a radius of half the height, rather than `Capsule`, whose stroked
                // outline left stray hairlines at both ends in the offscreen renderer.
                layers(RoundedRectangle(cornerRadius: 14, style: .circular))
            } else {
                layers(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        }
        .shadow(color: selected ? (style.glow ?? .clear) : .clear, radius: style.isNeon ? 9 : 6, y: style.isNeon ? 0 : 2)
    }

    // Concrete shapes (not AnyShape): AnyShape leaves stray hairlines at the ends of a stroked capsule.
    @ViewBuilder
    private func layers(_ shape: RoundedRectangle) -> some View {
        if style.isGlass {
            glassLayers(shape)
        } else {
            ZStack {
                if selected {
                    if style.isNeon {
                        shape.fill(style.accent.opacity(0.16))
                        shape.strokeBorder(style.accent, lineWidth: 1.5)
                    } else {
                        shape.fill(style.accentGradient)
                    }
                } else {
                    shape.fill(style.tile)
                    if style.isNeon { shape.strokeBorder(style.accent.opacity(0.22), lineWidth: 1) }
                }
            }
        }
    }

    @ViewBuilder
    private func glassLayers(_ shape: RoundedRectangle) -> some View {
        if !selected {
            shape.fill(style.tile)
        } else if #available(macOS 26.0, *), !GlassPreview.approximate {
            shape.fill(Color.clear)
                .glassEffect(.regular.tint(style.accent.opacity(0.85)).interactive(), in: shape)
        } else {
            ZStack {
                shape.fill(style.accent.opacity(0.85))
                shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
        }
    }
}

/// A large selectable tile with an icon, used for the noise-control mode.
struct ModeTile: View {
    @Environment(\.style) private var style
    let icon: String
    let title: LocalizedStringKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .frame(height: 22)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(selected ? style.selectedForeground : Color.primary)
            .background(SelectableBackground(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of equal-width pill buttons: a segmented control that matches the tiles.
struct ChipRow<Value: Hashable>: View {
    @Environment(\.style) private var style

    struct Option {
        var value: Value
        var title: LocalizedStringKey
    }

    let options: [Option]
    let selection: Value?
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button { onSelect(option.value) } label: {
                    Text(option.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? style.selectedForeground : Color.primary)
                        .background(SelectableBackground(selected: selected, capsule: true))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

struct IconBadge: View {
    @Environment(\.style) private var style
    let systemName: String
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(style.isNeon ? style.accent : style.onAccent)
            .frame(width: size, height: size)
            .background {
                let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                if style.isNeon {
                    shape.fill(style.accent.opacity(0.14))
                    shape.stroke(style.accent.opacity(0.7), lineWidth: 1)
                } else {
                    shape.fill(style.accentGradient)
                }
            }
    }
}

struct ToggleRow: View {
    let icon: String
    let title: LocalizedStringKey
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(systemName: icon, size: 24)
            Text(title).font(.callout)
            Spacer(minLength: 8)
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 5)
    }
}

/// A capsule button in the accent color (the system prominent style cannot use dark text on gold).
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.style) private var style

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(style.selectedForeground)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(SelectableBackground(selected: true, capsule: true))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
