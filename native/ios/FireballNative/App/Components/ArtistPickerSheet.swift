import SwiftUI

struct ArtistPickerContext: Identifiable {
    let id = UUID()
    let names: [String]
    let fallbackArtwork: String?
}

struct ArtistPickerSheet: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    let context: ArtistPickerContext
    let onSelect: (String) -> Void

    @State private var thumbnails: [String: String] = [:]
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This track lists multiple artists.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if loading && thumbnails.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(Array(context.names.enumerated()), id: \.element) { index, name in
                            SuvFadeSlideIn(delayMs: index * 40) {
                                actionRow(
                                    title: name,
                                    imageUrl: thumbnails[name] ?? context.fallbackArtwork
                                ) {
                                    onSelect(name)
                                    dismiss()
                                }
                            }
                        }
                    }

                    SuvFadeSlideIn(delayMs: 80) {
                        actionRow(title: "Cancel", systemImage: "xmark.circle.fill", role: .cancel) {
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Choose artist")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            loading = true
            var map: [String: String] = [:]
            for name in context.names {
                let url = await viewModel.resolveArtistThumbnail(
                    artistName: name,
                    fallbackArtwork: context.fallbackArtwork
                )
                if let url { map[name] = url }
            }
            thumbnails = map
            loading = false
        }
    }

    @ViewBuilder
    private func actionRow(
        title: String,
        systemImage: String? = nil,
        imageUrl: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 14) {
                if let imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Circle().fill(Color.secondary.opacity(0.25))
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)
                }
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
