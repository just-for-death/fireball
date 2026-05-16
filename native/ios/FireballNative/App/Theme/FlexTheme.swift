import SwiftUI
import UIKit

private extension UIColor {
    convenience init(argb: UInt32) {
        let a = CGFloat((argb >> 24) & 0xFF) / 255
        let r = CGFloat((argb >> 16) & 0xFF) / 255
        let g = CGFloat((argb >> 8) & 0xFF) / 255
        let b = CGFloat(argb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

/// Static palettes aligned with Android [flexSchemeToAppTheme].
enum FlexTheme {
    static func colors(for flexScheme: String, isDark: Bool) -> DominantColors {
        let key = flexScheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch true {
        case key.contains("ocean"), key.contains("blue"):
            return isDark ? oceanDark : oceanLight
        case key.contains("sunset"), key.contains("orange"), key.contains("amber"):
            return isDark ? sunsetDark : sunsetLight
        case key.contains("nature"), key.contains("green"), key.contains("forest"):
            return isDark ? natureDark : natureLight
        case key.contains("love"), key.contains("pink"), key.contains("mandy"):
            return isDark ? loveDark : loveLight
        default:
            return isDark ? defaultDark : defaultLight
        }
    }

    static func withAccentSeed(_ base: DominantColors, seedArgb: Int32) -> DominantColors {
        let uiColor = UIColor(argb: UInt32(bitPattern: seedArgb))
        let accent = Color(uiColor)
        return DominantColors(
            primary: base.primary,
            secondary: base.secondary,
            tertiary: base.tertiary,
            accent: accent,
            onBackground: base.onBackground
        )
    }

    static func isDark(themeMode: String, systemDark: Bool) -> Bool {
        switch themeMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "light": return false
        case "dark": return true
        default: return systemDark
        }
    }

    private static let defaultLight = DominantColors(
        primary: Color(red: 0.96, green: 0.95, blue: 0.98),
        secondary: Color(red: 0.93, green: 0.91, blue: 0.96),
        tertiary: Color(red: 0.90, green: 0.87, blue: 0.94),
        accent: Color(red: 0.40, green: 0.23, blue: 0.72),
        onBackground: Color(red: 0.11, green: 0.11, blue: 0.12)
    )
    private static let defaultDark = DominantColors(
        primary: Color(red: 0.11, green: 0.11, blue: 0.12),
        secondary: Color(red: 0.16, green: 0.15, blue: 0.18),
        tertiary: Color(red: 0.20, green: 0.19, blue: 0.23),
        accent: Color(red: 0.80, green: 0.67, blue: 1.0),
        onBackground: Color(red: 0.90, green: 0.89, blue: 0.92)
    )
    private static let oceanLight = DominantColors(
        primary: Color(red: 0.95, green: 0.97, blue: 1.0),
        secondary: Color(red: 0.88, green: 0.94, blue: 0.99),
        tertiary: Color(red: 0.80, green: 0.90, blue: 0.98),
        accent: Color(red: 0.0, green: 0.45, blue: 0.75),
        onBackground: Color(red: 0.05, green: 0.15, blue: 0.25)
    )
    private static let oceanDark = DominantColors(
        primary: Color(red: 0.05, green: 0.10, blue: 0.16),
        secondary: Color(red: 0.08, green: 0.16, blue: 0.24),
        tertiary: Color(red: 0.10, green: 0.22, blue: 0.32),
        accent: Color(red: 0.45, green: 0.78, blue: 1.0),
        onBackground: Color(red: 0.88, green: 0.94, blue: 0.99)
    )
    private static let sunsetLight = DominantColors(
        primary: Color(red: 1.0, green: 0.97, blue: 0.94),
        secondary: Color(red: 1.0, green: 0.92, blue: 0.86),
        tertiary: Color(red: 0.99, green: 0.86, blue: 0.76),
        accent: Color(red: 0.85, green: 0.35, blue: 0.10),
        onBackground: Color(red: 0.25, green: 0.12, blue: 0.05)
    )
    private static let sunsetDark = DominantColors(
        primary: Color(red: 0.14, green: 0.08, blue: 0.06),
        secondary: Color(red: 0.22, green: 0.12, blue: 0.08),
        tertiary: Color(red: 0.30, green: 0.16, blue: 0.10),
        accent: Color(red: 1.0, green: 0.65, blue: 0.40),
        onBackground: Color(red: 1.0, green: 0.92, blue: 0.86)
    )
    private static let natureLight = DominantColors(
        primary: Color(red: 0.95, green: 0.98, blue: 0.95),
        secondary: Color(red: 0.88, green: 0.95, blue: 0.88),
        tertiary: Color(red: 0.78, green: 0.90, blue: 0.78),
        accent: Color(red: 0.15, green: 0.55, blue: 0.25),
        onBackground: Color(red: 0.05, green: 0.18, blue: 0.08)
    )
    private static let natureDark = DominantColors(
        primary: Color(red: 0.06, green: 0.10, blue: 0.07),
        secondary: Color(red: 0.10, green: 0.16, blue: 0.11),
        tertiary: Color(red: 0.14, green: 0.22, blue: 0.15),
        accent: Color(red: 0.55, green: 0.85, blue: 0.60),
        onBackground: Color(red: 0.88, green: 0.95, blue: 0.88)
    )
    private static let loveLight = DominantColors(
        primary: Color(red: 1.0, green: 0.96, blue: 0.97),
        secondary: Color(red: 0.99, green: 0.90, blue: 0.93),
        tertiary: Color(red: 0.98, green: 0.84, blue: 0.88),
        accent: Color(red: 0.75, green: 0.15, blue: 0.40),
        onBackground: Color(red: 0.22, green: 0.05, blue: 0.10)
    )
    private static let loveDark = DominantColors(
        primary: Color(red: 0.14, green: 0.06, blue: 0.09),
        secondary: Color(red: 0.22, green: 0.10, blue: 0.14),
        tertiary: Color(red: 0.30, green: 0.14, blue: 0.18),
        accent: Color(red: 1.0, green: 0.55, blue: 0.70),
        onBackground: Color(red: 0.99, green: 0.90, blue: 0.93)
    )
}
