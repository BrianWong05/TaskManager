// UI/Theme.swift
// Win11-inspired visual language (spec §3.1): layered surfaces, 8pt radii,
// light borders, Windows 11 blue accent. Resolves per light/dark appearance;
// the user-selectable System/Light/Dark preference (spec §3.7) maps onto
// SwiftUI's preferredColorScheme.

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

/// Fluent-ish palette values for one color scheme.
struct FluentPalette {
    let page: Color      // window background (#F3F3F3 light)
    let card: Color      // raised surface (#FFFFFF light)
    let subdued: Color   // slightly recessed surface (rail, headers)
    let border: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let accentSoft: Color

    static let light = FluentPalette(
        page: Color(hex: 0xF3F3F3),
        card: Color(hex: 0xFFFFFF),
        subdued: Color(hex: 0xFAFAFA),
        border: Color(hex: 0xE5E5E5),
        textPrimary: Color(hex: 0x1B1B1B),
        textSecondary: Color(hex: 0x616161),
        accent: Color(hex: 0x0067C0),
        accentSoft: Color(hex: 0x0067C0).opacity(0.12)
    )

    static let dark = FluentPalette(
        page: Color(hex: 0x202020),
        card: Color(hex: 0x2B2B2B),
        subdued: Color(hex: 0x272727),
        border: Color(hex: 0x3D3D3D),
        textPrimary: Color(hex: 0xFFFFFF),
        textSecondary: Color(hex: 0xA6A6A6),
        accent: Color(hex: 0x60CDFF),
        accentSoft: Color(hex: 0x60CDFF).opacity(0.14)
    )
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = FluentPalette.light
}

extension EnvironmentValues {
    /// The palette for the currently effective color scheme.
    var palette: FluentPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Injects the scheme-appropriate palette and honors the user theme choice.
struct ThemedContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.environment(\.palette, colorScheme == .dark ? .dark : .light)
    }
}

/// Standard card modifier: raised surface, light border, 8pt radius (spec §3.1).
struct WinCard: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .background(palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
    }
}

extension View {
    func winCard() -> some View { modifier(WinCard()) }
}

/// User-selectable theme (spec §3.7), default System.
enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
