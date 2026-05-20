import SwiftUI

// MARK: - App Colors

extension Color {
    static let appPrimary   = Color("AppPrimary",   bundle: nil)   // deep navy/dark
    static let appAccent    = Color("AppAccent",    bundle: nil)   // vibrant green
    static let appDanger    = Color("AppDanger",    bundle: nil)   // warm red
    static let appSurface   = Color("AppSurface",   bundle: nil)   // card background

    // Fallbacks using system colors so it works before assets are configured
    static let sfPrimary  = Color(.label)
    static let sfAccent   = Color(red: 0.298, green: 0.686, blue: 0.314)   // #4CAF50
    static let sfDanger   = Color(red: 0.898, green: 0.224, blue: 0.208)   // #E53935
    static let sfSurface  = Color(.secondarySystemBackground)
    static let sfMuted    = Color(.tertiaryLabel)
}

// MARK: - Spacing

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs:  CGFloat = 8
    static let sm:  CGFloat = 12
    static let md:  CGFloat = 16   // baseline grid unit
    static let lg:  CGFloat = 24
    static let xl:  CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radii

enum Radius {
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let pill: CGFloat = 999
}

// MARK: - Typography helpers

extension Font {
    // Headlines
    static let sfTitle    = Font.system(.title2, design: .default, weight: .semibold)
    static let sfHeadline = Font.system(.headline, design: .default, weight: .semibold)
    static let sfSubhead  = Font.system(.subheadline, design: .default, weight: .medium)
    // Body
    static let sfBody     = Font.system(.body, design: .default, weight: .regular)
    static let sfCallout  = Font.system(.callout, design: .default, weight: .regular)
    // Detail
    static let sfCaption  = Font.system(.caption, design: .default, weight: .regular)
    static let sfCaption2 = Font.system(.caption2, design: .default, weight: .regular)
    // Monospaced numbers (great for timers)
    static let sfTimer    = Font.system(.largeTitle, design: .monospaced, weight: .bold)
    static let sfCounter  = Font.system(.title, design: .monospaced, weight: .semibold)
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.md)
            .background(Color.sfSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sfHeadline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(isDestructive ? Color.sfDanger : Color.sfAccent)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sfHeadline)
            .foregroundStyle(Color.sfAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(Color.sfAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Convenience extensions

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

extension Double {
    var weightFormatted: String {
        if truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", self)
        }
        return String(format: "%.1f", self)
    }
}

extension Int {
    /// Format seconds as M:SS
    var timerFormatted: String {
        let m = self / 60
        let s = self % 60
        return String(format: "%d:%02d", m, s)
    }
}
