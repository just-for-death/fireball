import SwiftUI

struct DashedProgressRing: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let angle = Angle(degrees: 360 * progress - 90)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: Angle(degrees: -90),
            endAngle: angle,
            clockwise: false
        )
        return path
    }
}

enum PillMiniPlayerChrome: Sendable {
    /// Tab bar inset on iPhone / compact width.
    case phone
    /// iPad sidebar inset: larger art ring, previous track, richer capsule.
    case ipadSidebarRail
}

public struct PillMiniPlayer: View {
    let track: Track
    let isPlaying: Bool
    let progress: Double
    let isLoading: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    /// Shown only when `chrome` is `.ipadSidebarRail`.
    let onPrevious: () -> Void
    let onTap: () -> Void
    let onLongPressMenu: () -> Void
    var chrome: PillMiniPlayerChrome = .phone

    @Environment(\.dominantColors) var dominantColors

    public init(
        track: Track,
        isPlaying: Bool,
        progress: Double,
        isLoading: Bool = false,
        onPlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void = {},
        onTap: @escaping () -> Void,
        onLongPressMenu: @escaping () -> Void = {},
        chrome: PillMiniPlayerChrome = .phone
    ) {
        self.track = track
        self.isPlaying = isPlaying
        self.progress = progress
        self.isLoading = isLoading
        self.onPlayPause = onPlayPause
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onTap = onTap
        self.onLongPressMenu = onLongPressMenu
        self.chrome = chrome
    }

    private var artworkPoints: CGFloat {
        switch chrome {
        case .phone: return 48
        case .ipadSidebarRail: return 58
        }
    }

    private var ringDiameter: CGFloat { artworkPoints + 8 }

    public var body: some View {
        HStack(spacing: chrome == .ipadSidebarRail ? 14 : 10) {
            ZStack {
                AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Circle().fill(dominantColors.secondary)
                    }
                }
                .frame(width: artworkPoints, height: artworkPoints)
                .clipShape(Circle())

                DashedProgressRing(progress: progress)
                    .stroke(
                        dominantColors.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5])
                    )
                    .frame(width: ringDiameter, height: ringDiameter)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(dominantColors.accent)
                }
            }
            .contentShape(Circle())
        .overlay {
            TapOrLongPressHostingView(onTap: onTap, onLongPress: onLongPressMenu)
        }

            VStack(alignment: .leading, spacing: chrome == .ipadSidebarRail ? 4 : 2) {
                Text(track.title)
                    .font(.system(size: chrome == .ipadSidebarRail ? 16 : 15, weight: .semibold))
                    .foregroundStyle(dominantColors.onBackground)
                    .lineLimit(chrome == .ipadSidebarRail ? 2 : 1)
                    .minimumScaleFactor(0.82)

                Text(track.artist)
                    .font(chrome == .ipadSidebarRail ? .subheadline : .caption)
                    .foregroundStyle(dominantColors.onBackground.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        .overlay {
            TapOrLongPressHostingView(onTap: onTap, onLongPress: onLongPressMenu)
        }

            HStack(spacing: chrome == .ipadSidebarRail ? 10 : 6) {
                if chrome == .ipadSidebarRail {
                    IconCircleButton(icon: "backward.fill", size: 34, iconPoints: 15, action: onPrevious)
                }
                IconCircleButton(icon: isPlaying ? "pause.fill" : "play.fill", size: chrome == .ipadSidebarRail ? 40 : 36, iconPoints: chrome == .ipadSidebarRail ? 17 : 16, action: onPlayPause)
                IconCircleButton(icon: "forward.fill", size: chrome == .ipadSidebarRail ? 36 : 32, iconPoints: chrome == .ipadSidebarRail ? 15 : 14, action: onNext)
            }
        }
        .padding(.horizontal, chrome == .ipadSidebarRail ? 14 : 12)
        .padding(.vertical, chrome == .ipadSidebarRail ? 12 : 8)
        .background {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [dominantColors.primary, dominantColors.secondary.opacity(0.92)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
        .shadow(color: Color.black.opacity(0.18), radius: chrome == .ipadSidebarRail ? 14 : 8, x: 0, y: 6)
    }
}

private struct IconCircleButton: View {
    let icon: String
    let size: CGFloat
    let iconPoints: CGFloat
    let action: () -> Void

    @Environment(\.dominantColors) private var dominantColors

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconPoints, weight: .semibold))
                .foregroundStyle(dominantColors.onBackground)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(dominantColors.onBackground.opacity(0.09))
                )
        }
        .buttonStyle(.plain)
    }
}
