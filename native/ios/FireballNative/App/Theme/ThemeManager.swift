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
    let useDynamicFromArtwork: Bool
    @Environment(\.colorScheme) var colorScheme

    public func body(content: Content) -> some View {
        content
            .environment(\.dominantColors, themeManager.colors)
            .onChange(of: artworkUrl) { newUrl in
                applyTheme(artworkUrl: newUrl)
            }
            .onChange(of: colorScheme) { _ in
                applyTheme(artworkUrl: artworkUrl)
            }
            .onChange(of: useDynamicFromArtwork) { _ in
                applyTheme(artworkUrl: artworkUrl)
            }
            .onAppear {
                applyTheme(artworkUrl: artworkUrl)
            }
    }

    private func applyTheme(artworkUrl: String?) {
        if useDynamicFromArtwork {
            themeManager.updateColors(from: artworkUrl, isDark: colorScheme == .dark)
        } else {
            themeManager.colors = .defaultColors
        }
    }
}

public extension View {
    func dynamicTheme(artworkUrl: String?, useDynamicFromArtwork: Bool = true) -> some View {
        modifier(DynamicThemeViewModifier(artworkUrl: artworkUrl, useDynamicFromArtwork: useDynamicFromArtwork))
    }
}
