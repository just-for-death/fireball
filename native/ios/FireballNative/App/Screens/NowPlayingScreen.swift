import SwiftUI

public struct NowPlayingScreen: View {
    let track: Track
    let settings: FireballSettings
    let isPlaying: Bool
    let positionSeconds: Double
    let durationSeconds: Double
    let currentLyrics: String?
    let lyricsAutoScroll: Bool
    let lyricsReducedMotion: Bool
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeek: (Double) -> Void
    var queue: [Track] = []
    var currentIndex: Int? = nil
    var onPlayQueueIndex: (Int) -> Void = { _ in }
    var onFollowArtist: (String, String?) -> Void = { _, _ in }
    let onClose: () -> Void

    @Environment(\.dominantColors) var dominantColors
    @State private var dragOffset: CGSize = .zero
    @State private var queueExpanded = false

    public var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [dominantColors.primary, dominantColors.secondary]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
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
                    Menu {
                        if #available(iOS 16.0, *) {
                            if let lyrics = currentLyrics, !lyrics.isEmpty {
                                ShareLink(item: lyrics) {
                                    Label("Share lyrics", systemImage: "square.and.arrow.up")
                                }
                            }
                            ShareLink(item: "\(track.title) — \(track.artist)") {
                                Label("Share track", systemImage: "music.note")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(dominantColors.onBackground)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal)

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
                    SyncedLyricsPanel(
                        lyrics: lyrics,
                        positionMs: Int64(positionSeconds * 1000),
                        autoScroll: lyricsAutoScroll,
                        reducedMotion: lyricsReducedMotion,
                        textColor: dominantColors.onBackground,
                        accentColor: dominantColors.accent
                    )
                }

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

                if queue.count > 1 {
                    Button(queueExpanded ? "Hide queue (\(queue.count))" : "Show queue (\(queue.count))") {
                        queueExpanded.toggle()
                    }
                    .foregroundColor(dominantColors.onBackground)
                    if queueExpanded {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(Array(queue.enumerated()), id: \.element.effectiveId) { index, item in
                                    let selected = index == (currentIndex ?? -1)
                                    Button {
                                        onPlayQueueIndex(index)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(item.title)
                                                    .fontWeight(selected ? .semibold : .regular)
                                                    .foregroundColor(dominantColors.onBackground)
                                                Button(item.artist) {
                                                    onFollowArtist(item.artist, item.artwork)
                                                }
                                                .font(.caption)
                                                .foregroundColor(dominantColors.onBackground.opacity(0.7))
                                            }
                                            Spacer()
                                        }
                                        .padding(10)
                                        .background(
                                            selected
                                                ? dominantColors.accent.opacity(0.25)
                                                : dominantColors.secondary.opacity(0.2),
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 48)
        }
        .dynamicTheme(artworkUrl: track.artwork, settings: settings)
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

private struct SyncedLyricsPanel: View {
    let lyrics: String
    let positionMs: Int64
    let autoScroll: Bool
    let reducedMotion: Bool
    let textColor: Color
    let accentColor: Color

    private var lines: [LrcLine] { LrcParser.parse(lyrics) }
    private var activeIndex: Int {
        guard !lines.isEmpty else { return -1 }
        return LrcParser.activeLineIndex(lines: lines, positionMs: positionMs)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if lines.isEmpty {
                    Text(lyrics)
                        .font(.footnote)
                        .foregroundColor(textColor.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("plain")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text)
                                .font(index == activeIndex ? .body.weight(.bold) : .footnote)
                                .foregroundColor(index == activeIndex ? accentColor : textColor.opacity(0.75))
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: reducedMotion ? 80 : 140)
            .padding(.horizontal, 24)
            .onChange(of: activeIndex) { idx in
                guard autoScroll, !reducedMotion, idx >= 0 else { return }
                withAnimation(reducedMotion ? nil : .easeInOut(duration: 0.25)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }
}
