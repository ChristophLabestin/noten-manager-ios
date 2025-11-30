import SwiftUI
import UIKit

private struct SoftFadeModifier: ViewModifier {
    let enabled: Bool
    let delay: Double
    let offset: CGFloat
    let duration: Double

    @State private var isVisible: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : offset)
            .onAppear {
                guard !isVisible else { return }
                guard enabled else {
                    isVisible = true
                    return
                }
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    /// Soft upward fade similar to the web app's "home-fade-up-soft".
    func softFadeIn(enabled: Bool, delay: Double = 0, offset: CGFloat = 12, duration: Double = 0.42) -> some View {
        modifier(SoftFadeModifier(enabled: enabled, delay: delay, offset: offset, duration: duration))
    }

    /// Soft downward fade (starting slightly above).
    func softFadeDown(enabled: Bool, delay: Double = 0, distance: CGFloat = 10, duration: Double = 0.45) -> some View {
        modifier(SoftFadeModifier(enabled: enabled, delay: delay, offset: -abs(distance), duration: duration))
    }
}

extension Color {
    static var formCardBackground: Color {
        Color(
            uiColor: UIColor { trait in
                if trait.userInterfaceStyle == .dark {
                    return UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
                } else {
                    return .systemBackground
                }
            }
        )
    }

    static var formInputBackground: Color {
        Color(
            uiColor: UIColor { trait in
                if trait.userInterfaceStyle == .dark {
                    return UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0)
                } else {
                    return .systemGray6
                }
            }
        )
    }

    static var formSectionBackground: Color {
        Color(
            uiColor: UIColor { trait in
                if trait.userInterfaceStyle == .dark {
                    return UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
                } else {
                    return .secondarySystemGroupedBackground
                }
            }
        )
    }
}

struct AccentFilledButtonStyle: ButtonStyle {
    var accent: Color
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let base = accent
        let fillTop = base.opacity(isEnabled ? 0.52 : 0.28)
        let fillBottom = base.opacity(isEnabled ? 0.86 : 0.48)
        let glassTint = base.opacity(isEnabled ? 0.24 : 0.12)
        let edgeLight = Color.white.opacity(isEnabled ? 0.38 : 0.18)
        let edgeDark = base.opacity(isEnabled ? 0.55 : 0.26)
        let textColor = Color.white.opacity(isEnabled ? 0.97 : 0.62)

        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [fillTop, fillBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .fill(glassTint)
                                .blendMode(.softLight)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [edgeLight, edgeDark],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.25
                                )
                        )

                    // Glassy top sheen
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isEnabled ? 0.35 : 0.18),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(.horizontal, 1)
                        .padding(.vertical, pressed ? 3 : 2.5)
                        .blendMode(.screen)
                        .opacity(isEnabled ? 1 : 0.6)
                }
            )
            .scaleEffect(pressed ? 0.985 : 1)
            .offset(y: pressed ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.7)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: pressed)
    }
}

struct SoftTintButtonStyle: ButtonStyle {
    var accent: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let bg = accent.opacity(isEnabled ? 0.16 : 0.08)
        let stroke = accent.opacity(isEnabled ? 0.24 : 0.12)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accent.opacity(isEnabled ? 1 : 0.6))
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.7)
            .animation(.spring(response: 0.28, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

struct SettingsCard<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    let accent: Color
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        subtitle: String?,
        systemImage: String? = nil,
        accent: Color = .accentColor,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.trailing = trailing()
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
                trailing
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
                            accent.opacity(0.10),
                            .formCardBackground
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

extension SettingsCard where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String?,
        systemImage: String? = nil,
        accent: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            accent: accent,
            trailing: { EmptyView() },
            content: content
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
                .fill(Color.formSectionBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.10), lineWidth: 1)
        )
    }
}

struct ToolbarIcon: View {
    let symbol: String
    let showDot: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(4)
            if showDot {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: 0)
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

struct StatChip: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ThemedBackground: View {
    let isDark: Bool
    let isFeminine: Bool
    let intensity: Double

    init(isDark: Bool, isFeminine: Bool, intensity: Double = 1.0) {
        self.isDark = isDark
        self.isFeminine = isFeminine
        self.intensity = max(0, min(1, intensity))
    }

    private var clampedIntensity: Double {
        max(0, min(1, intensity))
    }

    private var baseColor: Color {
        if isDark {
            return Color(red: 8 / 255, green: 9 / 255, blue: 11 / 255)
        } else {
            return Color.white
        }
    }

    private var tintLayer: some View {
        Group {
            if isDark {
                if isFeminine {
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "#3f1b2e"),
                            Color(hex: "#1a0b14")
                        ]),
                        center: .top,
                        startRadius: 0,
                        endRadius: 800
                    )
                } else {
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "#1f2937"),
                            Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255)
                        ]),
                        center: .top,
                        startRadius: 0,
                        endRadius: 800
                    )
                }
            } else if isFeminine {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#fdf2ff"),
                        Color(hex: "#fdf2f8"),
                        Color(hex: "#fef2f2")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 238 / 255, green: 242 / 255, blue: 255 / 255),
                        Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255),
                        Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    var body: some View {
        ZStack {
            baseColor
            tintLayer.opacity(clampedIntensity)
        }
        .ignoresSafeArea()
    }
}
