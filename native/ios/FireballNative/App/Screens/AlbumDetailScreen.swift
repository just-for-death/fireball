import SwiftUI

struct AlbumDetailRoute: Identifiable, Hashable {
    let collectionId: Int
    let title: String
    let artist: String
    let artworkUrl: String?

    var id: String { "\(collectionId)-\(title)" }
}

struct AlbumDetailScreen: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    let route: AlbumDetailRoute
    var onOpenTrackMenu: (Track) -> Void

    @State private var tracks: [Track] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                Text("No tracks found for this album.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                List {
                    Section {
                        HStack(spacing: 14) {
                            AsyncImage(url: URL(string: route.artworkUrl ?? "")) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.secondary.opacity(0.25))
                                }
                            }
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.title).font(.title3.bold())
                                Text(route.artist).font(.subheadline).foregroundStyle(.secondary)
                                Text("\(tracks.count) tracks").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))

                        HStack(spacing: 8) {
                            Button("Play") {
                                guard let first = tracks.first else { return }
                                viewModel.playFromPlaylist(track: first, source: tracks)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Play next") {
                                viewModel.appendTracksUpNext(tracks)
                            }
                            .buttonStyle(.bordered)
                            Button("Add to queue") {
                                viewModel.appendTracksToQueue(tracks)
                            }
                            .buttonStyle(.bordered)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                    }

                    Section {
                        ForEach(tracks, id: \.effectiveId) { track in
                            Button {
                                viewModel.playFromPlaylist(track: track, source: tracks)
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: URL(string: track.artwork ?? route.artworkUrl ?? "")) { phase in
                                        if let image = phase.image {
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } else {
                                            Color.secondary.opacity(0.2)
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(track.title).lineLimit(1)
                                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                                    onOpenTrackMenu(track)
                                }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.collectionId) {
            loading = true
            tracks = await viewModel.albumTracksCatalog(collectionId: route.collectionId)
            loading = false
        }
    }
}
