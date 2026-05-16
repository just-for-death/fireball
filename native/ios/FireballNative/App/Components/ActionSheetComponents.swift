import SwiftUI

enum ActionSheetMetrics {
    static let rowSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 16
    static let cornerRadius: CGFloat = 14
    static let rowBackground = Color.secondary.opacity(0.14)
}

/// Stacks pill rows with consistent gaps (avoids merged rounded corners).
struct ActionSheetRowGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: ActionSheetMetrics.rowSpacing) {
            content()
        }
    }
}

struct ActionSheetSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }
}

struct ActionSheetRowButton: View {
    let title: String
    var systemImage: String? = nil
    var imageUrl: String? = nil
    var subtitle: String? = nil
    var role: ButtonRole? = nil
    var disabled: Bool = false
    var inset: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 14) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, inset ? 4 : 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                inset ? Color.clear : ActionSheetMetrics.rowBackground,
                in: RoundedRectangle(cornerRadius: ActionSheetMetrics.cornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    @ViewBuilder
    private var leading: some View {
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
                .frame(width: 24)
        }
    }
}

struct ActionSheetSectionCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: ActionSheetMetrics.rowSpacing) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ActionSheetChipRow: View {
    let labels: [String]
    let selectedLabel: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(labels, id: \.self) { label in
                    Button {
                        onSelect(label)
                    } label: {
                        Text(label)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedLabel == label
                                    ? Color.accentColor.opacity(0.22)
                                    : Color.secondary.opacity(0.14),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct ActionSheetPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .font(.body)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ActionSheetToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var inset: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, inset ? 4 : 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            inset ? Color.clear : ActionSheetMetrics.rowBackground,
            in: RoundedRectangle(cornerRadius: ActionSheetMetrics.cornerRadius, style: .continuous)
        )
    }
}
