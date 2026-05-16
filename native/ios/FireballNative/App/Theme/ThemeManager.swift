import SwiftUI

public class ThemeManager: ObservableObject {
    @Published public var colors: DominantColors = .defaultColors

    public static let shared = ThemeManager()

    public func updateColors(from urlString: String?, isDark: Bool) {
        Task {
            let extracted = await DominantColorExtractor.shared.extract(from: urlString, isDark: isDark)
            await MainActor.run {
                withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) {
                    self.colors = extracted
                }
            }
        }
    }
}

public struct ThemeEnvironmentKey: EnvironmentKey {
    public static let defaultValue: DominantColors = .defaultColors
}

public extension EnvironmentValues {
    var dominantColors: DominantColors {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

public struct DynamicThemeViewModifier: ViewModifier {
    @StateObject private var themeManager = ThemeManager.shared
    let artworkUrl: String?
    let settings: FireballSettings
    @Environment(\.colorScheme) var colorScheme

    public func body(content: Content) -> some View {
        content
            .environment(\.dominantColors, themeManager.colors)
            .onChange(of: artworkUrl) { _ in applyTheme() }
            .onChange(of: colorScheme) { _ in applyTheme() }
            .onChange(of: settings.useDynamicColorWhenAvailable) { _ in applyTheme() }
            .onChange(of: settings.flexScheme) { _ in applyTheme() }
            .onChange(of: settings.themeMode) { _ in applyTheme() }
            .onChange(of: settings.appearanceColorSource) { _ in applyTheme() }
            .onChange(of: settings.accentSeedColor) { _ in applyTheme() }
            .onAppear { applyTheme() }
    }

    private func resolvedChromeMode(_ settings: FireballSettings) -> String {
        let raw = settings.appearanceColorSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "music", "scheme": return raw
        case "material_you": return "scheme"
        default:
            return settings.useDynamicColorWhenAvailable ? "music" : "scheme"
        }
    }

    private func applyTheme() {
        let isDark = FlexTheme.isDark(themeMode: settings.themeMode, systemDark: colorScheme == .dark)
        switch resolvedChromeMode(settings) {
        case "music":
            themeManager.updateColors(from: artworkUrl, isDark: isDark)
        default:
            var colors = FlexTheme.colors(for: settings.flexScheme, isDark: isDark)
            if let seed = settings.accentSeedColor {
                colors = FlexTheme.withAccentSeed(colors, seedArgb: seed)
            }
            themeManager.colors = colors
        }
    }
}

public extension View {
    func dynamicTheme(artworkUrl: String?, settings: FireballSettings) -> some View {
        modifier(DynamicThemeViewModifier(artworkUrl: artworkUrl, settings: settings))
    }
}
