import SwiftUI

private enum PlayerLayoutMetrics {
    /// Matches native Android `PlayerSplitBreakpoint` (840.dp).
    static let splitBreakpoint: CGFloat = 840
}

private struct PlayerContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public struct NowPlayingScreen: View {
    let track: Track
    let settings: FireballSettings
    let isPlaying: Bool
    let positionSeconds: Double
    let durationSeconds: Double
    let currentLyrics: String?
    let lyricsAutoScroll: Bool
    let lyricsReducedMotion: Bool
    let shuffled: Bool
    let repeatMode: RepeatMode
    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeek: (Double) -> Void
    let onToggleShuffle: () -> Void
    let onCycleRepeat: () -> Void

    var queue: [Track] = []
    var currentIndex: Int? = nil
    var onPlayQueueIndex: (Int) -> Void = { _ in }
    var onFollowArtist: (String, String?) -> Void = { _, _ in }
    var onOpenArtist: (String, String?) -> Void = { _, _ in }
    let onClose: () -> Void
    var onOpenTrackMenu: () -> Void = {}
    var onOverflowQueueTrack: (Track) -> Void = { _ in }
    var isFavorite: Bool = false
    var onPlayNext: () -> Void = {}
    var onAddToQueue: () -> Void = {}
    var onToggleFavorite: () -> Void = {}
    var onSeeArtist: () -> Void = {}
    var isArtistFollowed: Bool = false
    var onFollowArtistFromMenu: () -> Void = {}
    var onUnfollowArtistFromMenu: () -> Void = {}

    @Environment(\.dominantColors) var dominantColors
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var dragOffset: CGSize = .zero
    @State private var queueExpanded = false
    @State private var containerWidth: CGFloat = 0
    @State private var artistPickerNames: [String]?
    @State private var artistPickerArtwork: String?
    /// Two-column layout on iPad regular width when the column is actually wide enough (Stage Manager friendly).
    private var splitLayoutEnabled: Bool {
        let w = containerWidth > 1 ? containerWidth : (horizontalSizeClass == .regular ? 900 : 390)
        return horizontalSizeClass == .regular && w >= PlayerLayoutMetrics.splitBreakpoint
    }

    private var swipeDismissGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = CGSize(width: 0, height: value.translation.height)
                }
            }
            .onEnded { value in
                if value.translation.height > 110 {
                    onClose()
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    dragOffset = .zero
                }
            }
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { durationSeconds > 0 ? min(1, max(0, positionSeconds / durationSeconds)) : 0 },
            set: { onSeek($0) }
        )
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [dominantColors.primary, dominantColors.secondary]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Group {
                if splitLayoutEnabled {
                    tabletTwoColumnBody
                } else {
                    phoneScrollBody
                }
            }
            .offset(y: dragOffset.height > 0 ? dragOffset.height : 0)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PlayerContainerWidthKey.self, value: proxy.size.width)
                }
            )
        }
        .onPreferenceChange(PlayerContainerWidthKey.self) { containerWidth = $0 }
        .dynamicTheme(artworkUrl: track.artwork, settings: settings)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 8) }
        .confirmationDialog(
            "Choose artist",
            isPresented: Binding(
                get: { artistPickerNames != nil },
                set: { if !$0 { artistPickerNames = nil; artistPickerArtwork = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let names = artistPickerNames {
                ForEach(names, id: \.self) { name in
                    Button(name) {
                        onOpenArtist(name, artistPickerArtwork)
                        artistPickerNames = nil
                        artistPickerArtwork = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                artistPickerNames = nil
                artistPickerArtwork = nil
            }
        } message: {
            Text("This track lists multiple artists.")
        }
    }

    private func openArtistFromDisplayLine(_ raw: String, artwork: String?) {
        let names = ArtistNameParser.splitArtists(raw)
        switch names.count {
        case 0:
            return
        case 1:
            onOpenArtist(names[0], artwork)
        default:
            artistPickerNames = names
            artistPickerArtwork = artwork
        }
    }

    private var playerDragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(dominantColors.onBackground.opacity(0.28))
            .frame(width: 44, height: 5)
            .padding(.top, splitLayoutEnabled ? 6 : 10)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityLabel("Swipe down to close")
            .accessibilityAddTraits(.isButton)
            .gesture(swipeDismissGesture)
    }

    private var pinnedHeaderChrome: some View {
        VStack(spacing: 0) {
            playerDragHandle
            topBarRow
        }
    }

    private var topBarRow: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundStyle(dominantColors.onBackground)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
            Text("Now Playing")
                .font(splitLayoutEnabled ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(dominantColors.onBackground.opacity(0.82))
            Spacer()
            Menu {
                Button("Play next", action: onPlayNext)
                Button("Add to queue", action: onAddToQueue)
                Button(isFavorite ? "Remove from favorites" : "Add to favorites", action: onToggleFavorite)
                Button("View artist catalog", action: onSeeArtist)
                Button(isArtistFollowed ? "Unfollow artist" : "Follow artist") {
                    if isArtistFollowed {
                        onUnfollowArtistFromMenu()
                    } else {
                        onFollowArtistFromMenu()
                    }
                }
                Button("More options…", action: onOpenTrackMenu)
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
                    .foregroundStyle(dominantColors.onBackground)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, splitLayoutEnabled ? 24 : 20)
    }

    private var lyricsPanelCap: CGFloat {
        if lyricsReducedMotion { return 112 }
        return splitLayoutEnabled ? 420 : 160
    }

    private var pinnedLyricsPanel: Bool { settings.alwaysShowLyricsPanel }

    private var hasLyricsToShow: Bool {
        guard let s = currentLyrics else { return false }
        return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func artworkOrLyricsView(maxSquare: CGFloat) -> some View {
        let corner: CGFloat = splitLayoutEnabled ? 28 : 22
        let lyricsCap = splitLayoutEnabled ? 360 : maxSquare - 24
        return Group {
            if hasLyricsToShow, let lyrics = currentLyrics {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(dominantColors.secondary.opacity(0.55))
                    SyncedLyricsPanel(
                        lyrics: lyrics,
                        positionMs: Int64(positionSeconds * 1000),
                        autoScroll: lyricsAutoScroll,
                        reducedMotion: lyricsReducedMotion,
                        textColor: dominantColors.onBackground,
                        accentColor: dominantColors.accent,
                        panelMaxHeight: lyricsCap
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    TapOrLongPressHostingView(onTap: onPlayPause, onLongPress: onOpenTrackMenu)
                }
            } else {
                ZStack {
                    AsyncImage(url: URL(string: track.artwork ?? "")) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(dominantColors.secondary)
                        }
                    }
                    TapOrLongPressHostingView(onTap: onPlayPause, onLongPress: onOpenTrackMenu)
                }
            }
        }
        .frame(width: maxSquare, height: maxSquare)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: Color.black.opacity(0.33), radius: splitLayoutEnabled ? 28 : 18, x: 0, y: 14)
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var phoneArtSquare: CGFloat { 336 }


    private var titleStack: some View {
        VStack(spacing: 8) {
            Text(track.title)
                .font(.system(size: splitLayoutEnabled ? 30 : 28, weight: .bold))
                .foregroundStyle(dominantColors.onBackground)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .overlay {
                    TapOrLongPressHostingView(onTap: {}, onLongPress: onOpenTrackMenu)
                }

            Button {
                openArtistFromDisplayLine(track.artist, artwork: track.artwork)
            } label: {
                Text(track.artist)
                    .font(.title3)
                    .foregroundStyle(dominantColors.onBackground.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .buttonStyle(ArtistPressButtonStyle())
            .accessibilityLabel("Open artist \(track.artist)")
        }
        .padding(.horizontal, splitLayoutEnabled ? 12 : 32)
        .frame(maxWidth: splitLayoutEnabled ? 440 : nil)
    }

    private var seekBlock: some View {
        VStack(spacing: 8) {
            Slider(value: sliderBinding)
                .tint(dominantColors.accent)
            HStack {
                Text(formatTime(positionSeconds))
                Spacer()
                Text(formatTime(durationSeconds))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(dominantColors.onBackground.opacity(0.62))
        }
        .padding(.horizontal, splitLayoutEnabled ? 0 : 32)
        .frame(maxWidth: splitLayoutEnabled ? 400 : nil)
    }

    private var transportPlusModes: some View {
        HStack(spacing: splitLayoutEnabled ? 18 : 8) {
            Button(action: onToggleShuffle) {
                Image(systemName: "shuffle")
                    .font(.system(size: 22))
                    .foregroundStyle(shuffled ? dominantColors.accent : dominantColors.onBackground.opacity(0.48))
            }
            .accessibilityLabel(shuffled ? "Shuffle on" : "Shuffle off")
            .frame(minWidth: 44, minHeight: 44)

            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(dominantColors.onBackground)
            }
            .frame(minWidth: 48, minHeight: 44)

            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 74))
                    .foregroundStyle(dominantColors.accent)
                    .shadow(color: dominantColors.accent.opacity(0.32), radius: 14, x: 0, y: 5)
            }
            .buttonStyle(.plain)

            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(dominantColors.onBackground)
            }
            .frame(minWidth: 48, minHeight: 44)

            Button(action: onCycleRepeat) {
                Image(systemName: repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 22))
                    .foregroundStyle(repeatMode == .off ? dominantColors.onBackground.opacity(0.48) : dominantColors.accent)
            }
            .accessibilityLabel("Repeat: \(String(describing: repeatMode))")
            .frame(minWidth: 44, minHeight: 44)
        }
    }

    /// One outer `ScrollView` so queue does not nest another scroll surface.
    private var phoneScrollBody: some View {
        VStack(spacing: 0) {
            pinnedHeaderChrome
            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        Spacer(minLength: 0)
                        artworkOrLyricsView(maxSquare: phoneArtSquare)
                        Spacer(minLength: 0)
                    }

                    titleStack

                    seekBlock

                    if pinnedLyricsPanel, hasLyricsToShow, let lyrics = currentLyrics {
                        Text("Lyrics (expanded)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(dominantColors.onBackground.opacity(0.54))
                        SyncedLyricsPanel(
                            lyrics: lyrics,
                            positionMs: Int64(positionSeconds * 1000),
                            autoScroll: lyricsAutoScroll,
                            reducedMotion: lyricsReducedMotion,
                            textColor: dominantColors.onBackground,
                            accentColor: dominantColors.accent,
                            panelMaxHeight: lyricsPanelCap
                        )
                    }

                    transportPlusModes
                        .padding(.top, 4)

                    queueSection
                }
                .padding(.bottom, 40)
            }
        }
    }

    private var tabletTwoColumnBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            pinnedHeaderChrome
                .padding(.top, 4)

            HStack(alignment: .top, spacing: 28) {
                ScrollView {
                    VStack(spacing: 22) {
                        artworkOrLyricsView(maxSquare: 360)
                            .padding(.top, 4)

                        titleStack

                        seekBlock

                        transportPlusModes
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 6)
                    .padding(.bottom, 32)
                }
                .frame(minWidth: 300, idealWidth: 370, maxWidth: 460)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if pinnedLyricsPanel, let lyrics = currentLyrics, !lyrics.isEmpty {
                            Text("Lyrics")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(dominantColors.onBackground.opacity(0.54))
                                .padding(.top, 4)

                            SyncedLyricsPanel(
                                lyrics: lyrics,
                                positionMs: Int64(positionSeconds * 1000),
                                autoScroll: lyricsAutoScroll,
                                reducedMotion: lyricsReducedMotion,
                                textColor: dominantColors.onBackground,
                                accentColor: dominantColors.accent,
                                panelMaxHeight: lyricsPanelCap
                            )
                        }

                        queueSection

                        Color.clear.frame(height: 28)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var queueSection: some View {
        if queue.count > 1 {
            Button {
                queueExpanded.toggle()
            } label: {
                Text(queueExpanded ? "Hide queue (\(queue.count))" : "Show queue (\(queue.count))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(dominantColors.onBackground)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, splitLayoutEnabled ? 0 : 16)

            if queueExpanded {
                VStack(spacing: 8) {
                    ForEach(Array(queue.enumerated()), id: \.element.effectiveId) { index, item in
                        let selected = index == (currentIndex ?? -1)
                        ZStack {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .fontWeight(selected ? .semibold : .regular)
                                        .foregroundStyle(dominantColors.onBackground)

                                    Text(item.artist)
                                        .font(.caption)
                                        .foregroundStyle(dominantColors.onBackground.opacity(0.74))
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selected ? dominantColors.accent.opacity(0.26) : dominantColors.secondary.opacity(0.2))
                            )
                            TapOrLongPressHostingView(
                                onTap: { onPlayQueueIndex(index) },
                                onLongPress: { onOverflowQueueTrack(item) }
                            )
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                openArtistFromDisplayLine(item.artist, artwork: item.artwork)
                            } label: {
                                Image(systemName: "person.crop.circle")
                                    .font(.caption)
                                    .foregroundStyle(dominantColors.onBackground.opacity(0.55))
                                    .padding(10)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open artist")
                        }
                    }
                }
                .padding(.horizontal, splitLayoutEnabled ? 0 : 8)
                .padding(.bottom, splitLayoutEnabled ? 0 : 8)
            }
        }
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
    var panelMaxHeight: CGFloat = 140

    private var lines: [LrcLine] { LrcParser.parse(lyrics) }
    private var activeIndex: Int {
        guard !lines.isEmpty else { return -1 }
        return LrcParser.activeLineIndex(lines: lines, positionMs: positionMs)
    }

    private func lineOpacity(index: Int) -> Double {
        guard activeIndex >= 0 else { return 0.78 }
        let distance = abs(index - activeIndex)
        switch distance {
        case 0: return 1
        case 1: return 0.62
        case 2: return 0.45
        default: return 0.28
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if lines.isEmpty {
                    Text(lyrics)
                        .font(.body)
                        .foregroundStyle(textColor.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 8)
                        .id("plain")
                } else {
                    VStack(alignment: .center, spacing: 8) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text)
                                .font(index == activeIndex ? .title3.weight(.semibold) : .subheadline)
                                .foregroundStyle(index == activeIndex ? accentColor : textColor)
                                .opacity(lineOpacity(index: index))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 2)
                                .animation(reducedMotion ? nil : .easeOut(duration: 0.22), value: activeIndex)
                                .id(index)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(maxHeight: panelMaxHeight)
            .padding(.horizontal, reducedMotion ? 10 : 16)
            .onChange(of: activeIndex) { idx in
                guard autoScroll, !reducedMotion, idx >= 0 else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }
}
