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
    @Environment(\.colorScheme) var colorScheme

    public func body(content: Content) -> some View {
        content
            .environment(\.dominantColors, themeManager.colors)
            .onChange(of: artworkUrl) { newUrl in
                themeManager.updateColors(from: newUrl, isDark: colorScheme == .dark)
            }
            .onChange(of: colorScheme) { newScheme in
                themeManager.updateColors(from: artworkUrl, isDark: newScheme == .dark)
            }
            .onAppear {
                themeManager.updateColors(from: artworkUrl, isDark: colorScheme == .dark)
            }
    }
}

public extension View {
    func dynamicTheme(artworkUrl: String?) -> some View {
        modifier(DynamicThemeViewModifier(artworkUrl: artworkUrl))
    }
}
