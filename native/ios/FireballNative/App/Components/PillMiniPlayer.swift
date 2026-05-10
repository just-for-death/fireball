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

public struct PillMiniPlayer: View {
    let track: Track
    let isPlaying: Bool
    let progress: Double
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onTap: () -> Void

    @Environment(\.dominantColors) var dominantColors
    @State private var isPressed = false

    public init(
        track: Track,
        isPlaying: Bool,
        progress: Double,
        onPlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onTap: @escaping () -> Void
    ) {
        self.track = track
        self.isPlaying = isPlaying
        self.progress = progress
        self.onPlayPause = onPlayPause
        self.onNext = onNext
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Album Art with Progress Ring
            ZStack {
                AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                             .aspectRatio(contentMode: .fill)
                             .clipShape(Circle())
                    default:
                        Circle()
                            .fill(dominantColors.secondary)
                    }
                }
                .frame(width: 44, height: 44)

                DashedProgressRing(progress: progress)
                    .stroke(
                        dominantColors.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4])
                    )
                    .frame(width: 48, height: 48)
            }

            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(dominantColors.onBackground)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.caption)
                    .foregroundColor(dominantColors.onBackground.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Controls
            HStack(spacing: 8) {
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundColor(dominantColors.onBackground)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundColor(dominantColors.onBackground)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(dominantColors.primary)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onTapGesture {
            onTap()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}
