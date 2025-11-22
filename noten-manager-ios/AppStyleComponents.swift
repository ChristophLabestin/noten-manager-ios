import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    let accent: Color
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String?,
        systemImage: String? = nil,
        accent: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if let systemImage {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: systemImage)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.12),
                            Color(.secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SettingsSectionBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.15), lineWidth: 1)
        )
    }
}

struct ToolbarIcon: View {
    let symbol: String
    let showDot: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                )
            if showDot {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: 5, y: -4)
            }
        }
    }
}

struct PillBadge: View {
    let text: String
    let systemImage: String
    let foreground: Color
    let background: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(foreground.opacity(0.35), lineWidth: 1)
        )
        .lineLimit(1)
    }
}

struct HeaderTile: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(accent)
                }
                Spacer()
            }
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
    }
}

struct SummaryCard<Content: View>: View {
    let title: String
    let accent: Color
    @ViewBuilder let content: Content

    init(title: String, accent: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        SettingsCard(
            title: title.isEmpty ? " " : title,
            subtitle: nil,
            systemImage: nil,
            accent: accent
        ) {
            SettingsSectionBox {
                content
            }
        }
    }
}
