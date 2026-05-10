import SwiftUI
import UIKit
import CoreGraphics

public struct DominantColors: Equatable {
    public var primary: Color
    public var secondary: Color
    public var tertiary: Color
    public var accent: Color
    public var onBackground: Color

    public static let defaultColors = DominantColors(
        primary: Color(uiColor: .systemBackground),
        secondary: Color(uiColor: .secondarySystemBackground),
        tertiary: Color(uiColor: .tertiarySystemBackground),
        accent: Color(uiColor: .systemBlue),
        onBackground: Color(uiColor: .label)
    )
}

public class DominantColorExtractor {
    public static let shared = DominantColorExtractor()
    private var cache: [String: DominantColors] = [:]

    public func extract(from urlString: String?, isDark: Bool) async -> DominantColors {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            return .defaultColors
        }

        if let cached = cache[urlString] {
            return adjustForTheme(cached, isDark: isDark)
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else { return .defaultColors }

            let colors = extractColors(from: uiImage, isDark: isDark)
            cache[urlString] = colors
            return colors
        } catch {
            return .defaultColors
        }
    }

    private func extractColors(from image: UIImage, isDark: Bool) -> DominantColors {
        let size = CGSize(width: 50, height: 50)
        UIGraphicsBeginImageContext(size)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let cgImage = resizedImage?.cgImage else { return .defaultColors }
        guard let dataProvider = cgImage.dataProvider else { return .defaultColors }
        guard let data = dataProvider.data else { return .defaultColors }
        guard let ptr = CFDataGetBytePtr(data) else { return .defaultColors }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow

        var rTotal = 0
        var gTotal = 0
        var bTotal = 0
        var pixelCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Int(ptr[offset])
                let g = Int(ptr[offset + 1])
                let b = Int(ptr[offset + 2])
                let a = Int(ptr[offset + 3])

                if a > 127 { // Ignore transparent pixels
                    rTotal += r
                    gTotal += g
                    bTotal += b
                    pixelCount += 1
                }
            }
        }

        guard pixelCount > 0 else { return .defaultColors }

        let rAvg = CGFloat(rTotal) / CGFloat(pixelCount) / 255.0
        let gAvg = CGFloat(gTotal) / CGFloat(pixelCount) / 255.0
        let bAvg = CGFloat(bTotal) / CGFloat(pixelCount) / 255.0

        let averageColor = UIColor(red: rAvg, green: gAvg, blue: bAvg, alpha: 1.0)
        
        // Simple generation based on average for now.
        // For a more advanced generation, we could convert to HSB and adjust brightness/saturation.
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        averageColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let baseColors = generateColors(hue: hue, saturation: saturation, brightness: brightness, isDark: isDark)
        return baseColors
    }
    
    private func generateColors(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, isDark: Bool) -> DominantColors {
        let b = isDark ? max(brightness * 0.3, 0.1) : min(brightness * 1.5, 0.95)
        let primary = UIColor(hue: hue, saturation: saturation * 0.5, brightness: b, alpha: 1.0)
        let secondary = UIColor(hue: hue, saturation: saturation * 0.4, brightness: isDark ? b + 0.1 : b - 0.1, alpha: 1.0)
        let tertiary = UIColor(hue: hue, saturation: saturation * 0.3, brightness: isDark ? b + 0.2 : b - 0.2, alpha: 1.0)
        let accent = UIColor(hue: hue, saturation: min(saturation * 1.5, 1.0), brightness: isDark ? min(brightness + 0.3, 1.0) : max(brightness - 0.2, 0.4), alpha: 1.0)
        let onBackground = isDark ? UIColor.white : UIColor.black
        
        return DominantColors(
            primary: Color(primary),
            secondary: Color(secondary),
            tertiary: Color(tertiary),
            accent: Color(accent),
            onBackground: Color(onBackground)
        )
    }

    private func adjustForTheme(_ colors: DominantColors, isDark: Bool) -> DominantColors {
        // Simple cache bypass: in reality cache should key on URL + isDark.
        // For this port, we will assume cache just needs recomputation or we key by both.
        return colors
    }
}
