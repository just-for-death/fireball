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
                VStack(alignment: .leading, spacing: ActionSheetMetrics.sectionSpacing) {
                    Text("This track lists multiple artists.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if loading && thumbnails.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ActionSheetRowGroup {
                            ForEach(Array(context.names.enumerated()), id: \.element) { index, name in
                                SuvFadeSlideIn(delayMs: index * 40) {
                                    ActionSheetRowButton(
                                        title: name,
                                        imageUrl: thumbnails[name] ?? context.fallbackArtwork
                                    ) {
                                        onSelect(name)
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }

                    ActionSheetRowGroup {
                        SuvFadeSlideIn(delayMs: 80) {
                            ActionSheetRowButton(
                                title: "Cancel",
                                systemImage: "xmark.circle.fill",
                                role: .cancel
                            ) {
                                dismiss()
                            }
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
}
