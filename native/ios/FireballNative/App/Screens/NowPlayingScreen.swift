import SwiftUI

public struct NowPlayingScreen: View {
    let track: Track
    let isPlaying: Bool
    let positionSeconds: Double
    let durationSeconds: Double
    let currentLyrics: String?
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeek: (Double) -> Void
    let onClose: () -> Void
    
    @Environment(\.dominantColors) var dominantColors
    @State private var dragOffset: CGSize = .zero
    
    public var body: some View {
        ZStack {
            // Animated dynamic background
            LinearGradient(
                gradient: Gradient(colors: [dominantColors.primary, dominantColors.secondary]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Header
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .foregroundColor(dominantColors.onBackground)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text("Now Playing")
                        .font(.headline)
                        .foregroundColor(dominantColors.onBackground.opacity(0.8))
                    Spacer()
                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(dominantColors.onBackground)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal)
                
                // Artwork
                GeometryReader { geometry in
                    let size = min(geometry.size.width - 64, geometry.size.height)
                    ZStack {
                        AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle().fill(dominantColors.tertiary)
                            }
                        }
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .shadow(color: Color.black.opacity(0.3), radius: 24, x: 0, y: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Track Info
                VStack(spacing: 8) {
                    Text(track.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(dominantColors.onBackground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Text(track.artist)
                        .font(.title3)
                        .foregroundColor(dominantColors.onBackground.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.horizontal, 32)
                
                // Seek bar (scrub 0…1 of track duration)
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { durationSeconds > 0 ? min(1, max(0, positionSeconds / durationSeconds)) : 0 },
                            set: { onSeek($0) }
                        ),
                        in: 0...1
                    )
                    .tint(dominantColors.accent)

                    HStack {
                        Text(formatTime(positionSeconds))
                        Spacer()
                        Text(formatTime(durationSeconds))
                    }
                    .font(.caption)
                    .foregroundColor(dominantColors.onBackground.opacity(0.6))
                }
                .padding(.horizontal, 32)

                if let lyrics = currentLyrics, !lyrics.isEmpty {
                    ScrollView {
                        Text(lyrics)
                            .font(.footnote)
                            .foregroundColor(dominantColors.onBackground.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(.horizontal, 24)
                }

                // Playback Controls
                HStack(spacing: 40) {
                    Button(action: onPrevious) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 32))
                            .foregroundColor(dominantColors.onBackground)
                    }
                    
                    Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundColor(dominantColors.accent)
                            .shadow(color: dominantColors.accent.opacity(0.3), radius: 12, x: 0, y: 4)
                    }
                    
                    Button(action: onNext) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 32))
                            .foregroundColor(dominantColors.onBackground)
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .dynamicTheme(artworkUrl: track.artwork)
        .offset(y: dragOffset.height > 0 ? dragOffset.height : 0)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        onClose()
                    }
                    withAnimation(.spring()) {
                        dragOffset = .zero
                    }
                }
        )
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
