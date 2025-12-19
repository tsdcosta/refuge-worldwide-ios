//
//  Theme.swift
//  Refuge Worldwide
//
//  Design system matching refugeworldwide.com
//

import SwiftUI

// MARK: - Design Tokens

struct Theme {
    // MARK: - Primary Colors
    static let background = Color.black
    static let foreground = Color.white
    static let lightGrey = Color(hex: "#ececec")

    // MARK: - Brand Colors (Section Accents)
    static let orange = Color(hex: "#ff9300")
    static let red = Color(hex: "#ff0000")

    // MARK: - Semantic Colors
    static let accent = orange                      // Primary accent (radio app)
    static let secondaryText = Color.gray
    static let cardBackground = Color(white: 0.08)  // Darker cards
    static let pillBackground = Color.clear
    static let pillBorder = Color.white

    // MARK: - Typography
    struct Typography {
        // Heading sizes (matching website rem values)
        static let headingLarge: CGFloat = 45      // 2.8125rem
        static let headingMedium: CGFloat = 38     // 2.4rem
        static let headingBase: CGFloat = 30       // 1.875rem
        static let headingSmall: CGFloat = 24      // 1.5rem

        // Body sizes
        static let bodyLarge: CGFloat = 20         // 1.25rem (small in website)
        static let bodyBase: CGFloat = 17          // iOS default body
        static let bodySmall: CGFloat = 14         // 0.875rem
        static let caption: CGFloat = 12           // 0.75rem (xxs)

        // Line height multipliers
        static let headingLineHeight: CGFloat = 1.15
        static let bodyLineHeight: CGFloat = 1.5
    }

    // MARK: - Spacing
    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let base: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius
    struct Radius {
        static let none: CGFloat = 0
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let full: CGFloat = 999  // Pill shape
    }

    // MARK: - Shadows (3D effect like website)
    struct Shadow {
        static let pillBlack = Color.black
        static let pillWhite = Color.white
        static let pillOrange = orange
        static let offset: CGFloat = 2
    }

    // MARK: - Animation
    struct Animation {
        static let fast: Double = 0.15
        static let normal: Double = 0.25
        static let slow: Double = 0.4
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Font Extensions

extension Font {
    /// Serif font for headings (Bely Display preferred, falls back to Georgia/Cambria/Times)
    static func serifHeading(size: CGFloat) -> Font {
        // Try the exact PostScript / font name first
        if UIFont(name: "BelyDisplay-Regular", size: size) != nil {
            return Font.custom("BelyDisplay-Regular", size: size)
        }
        // Try common serif fallbacks explicitly
        if UIFont(name: "Georgia", size: size) != nil {
            return Font.custom("Georgia", size: size)
        }
        if UIFont(name: "Cambria", size: size) != nil {
            return Font.custom("Cambria", size: size)
        }
        if UIFont(name: "TimesNewRomanPSMT", size: size) != nil {
            return Font.custom("TimesNewRomanPSMT", size: size)
        }
        // Last resort: system serif design
        return .system(size: size, design: .serif)
    }

    /// Light weight body text (Visuelt preferred)
    static func lightBody(size: CGFloat) -> Font {
        if UIFont(name: "Visuelt-Light", size: size) != nil {
            return Font.custom("Visuelt-Light", size: size)
        }
        if UIFont(name: "VisueltLight", size: size) != nil {
            return Font.custom("VisueltLight", size: size)
        }
        // Fall back to system UI font with light weight
        return .system(size: size, weight: .light)
    }

    /// Medium weight for emphasis (Visuelt preferred)
    static func mediumBody(size: CGFloat) -> Font {
        if UIFont(name: "Visuelt-Medium", size: size) != nil {
            return Font.custom("Visuelt-Medium", size: size)
        }
        if UIFont(name: "VisueltMedium", size: size) != nil {
            return Font.custom("VisueltMedium", size: size)
        }
        // Fall back to system UI font with medium weight
        return .system(size: size, weight: .medium)
    }
}

// MARK: - View Modifiers

struct PillButtonStyle: ViewModifier {
    var backgroundColor: Color = .clear
    var borderColor: Color = Theme.foreground
    var shadowColor: Color = Theme.Shadow.pillBlack
    var height: CGFloat = 40

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: height)
            .background(backgroundColor)
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 2)
            )
            .clipShape(Capsule())
            .shadow(color: shadowColor, radius: 0, x: 0, y: Theme.Shadow.offset)
    }
}

struct BadgeStyle: ViewModifier {
    var inverted: Bool = false
    var small: Bool = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: small ? Theme.Typography.caption : 14, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, small ? Theme.Spacing.sm : Theme.Spacing.md)
            .padding(.vertical, small ? Theme.Spacing.xs : Theme.Spacing.sm)
            .background(inverted ? Theme.foreground : .clear)
            .foregroundColor(inverted ? Theme.background : Theme.foreground)
            .overlay(
                Capsule()
                    .stroke(Theme.foreground, lineWidth: 1.5)
            )
            .clipShape(Capsule())
    }
}

extension View {
    func pillButton(
        backgroundColor: Color = .clear,
        borderColor: Color = Theme.foreground,
        shadowColor: Color = Theme.Shadow.pillBlack,
        height: CGFloat = 40
    ) -> some View {
        modifier(PillButtonStyle(
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            shadowColor: shadowColor,
            height: height
        ))
    }

    func badge(inverted: Bool = false, small: Bool = false) -> some View {
        modifier(BadgeStyle(inverted: inverted, small: small))
    }
}
