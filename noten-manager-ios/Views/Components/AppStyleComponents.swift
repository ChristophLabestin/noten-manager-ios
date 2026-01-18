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

    /// Blurs the content if Privacy Mode is active.
    func privacyBlur() -> some View {
        self.modifier(PrivacyBlurModifier())
    }
}

struct PrivacyBlurModifier: ViewModifier {
    @EnvironmentObject var store: GradesStore

    func body(content: Content) -> some View {
        content
            .blur(radius: store.isPrivacyModeActive ? 16 : 0)
            .overlay {
                if store.isPrivacyModeActive {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.ultraThinMaterial)
                        .opacity(0.3)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.isPrivacyModeActive)
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



struct SoftTintButtonStyle: ButtonStyle {
    var accent: Color
    var font: Font = .subheadline.weight(.semibold)
    var verticalPadding: CGFloat = 12
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let bg = accent.opacity(isEnabled ? 0.16 : 0.08)
        let stroke = accent.opacity(isEnabled ? 0.24 : 0.12)
        configuration.label
            .font(font)
            .foregroundStyle(accent.opacity(isEnabled ? 1 : 0.6))
            .padding(.vertical, verticalPadding)
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
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: GradesStore

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
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(iconBackground)
                            .frame(width: 46, height: 46)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(accent.opacity(colorScheme == .dark ? 0.30 : 0.20), lineWidth: 1)
                            )
                        Image(systemName: systemImage)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(accent)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
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
        .background(cardSurface)
        .overlay(cardBorder)
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08),
            radius: 6,
            x: 0,
            y: 4
        )
    }

    private var baseTop: Color {
        if colorScheme == .dark {
            return store.theme == "feminine" ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
        }
        return store.theme == "feminine" ? Color(hex: "#fff1f7") : Color(hex: "#eef2ff")
    }

    private var baseBottom: Color {
        if colorScheme == .dark {
            return store.theme == "feminine" ? Color(hex: "#120a16") : Color(hex: "#111827")
        }
        return store.theme == "feminine" ? Color(hex: "#fff7fb") : Color(hex: "#f8fafc")
    }

    private var iconBackground: Color {
        accent.opacity(colorScheme == .dark ? 0.22 : 0.14)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [baseTop, baseBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(accent.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
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
    var dotOffset: CGSize = CGSize(width: 2, height: 0)

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
                    .offset(x: dotOffset.width, y: dotOffset.height)
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
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: GradesStore

    let title: String
    let value: String
    let accent: Color
    var isGreyedOut: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .monospacedDigit()
                .privacyBlur()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(chipSurface)
        .overlay(chipBorder)
        .opacity(isGreyedOut ? 0.5 : 1.0)
        .saturation(isGreyedOut ? 0.3 : 1.0)
    }


    private var chipTop: Color {
        if colorScheme == .dark {
            return store.theme == "feminine" ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
        }
        return store.theme == "feminine" ? Color(hex: "#fff5fb") : Color(hex: "#f1f5ff")
    }

    private var chipBottom: Color {
        if colorScheme == .dark {
            return store.theme == "feminine" ? Color(hex: "#120a16") : Color(hex: "#111827")
        }
        return store.theme == "feminine" ? Color(hex: "#fffafb") : Color(hex: "#f8fafc")
    }

    private var chipSurface: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [chipTop, chipBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var chipBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(accent.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
    }
}

struct SegmentedPickerOption<T: Hashable>: Identifiable {
    let title: String
    let value: T

    var id: T { value }
}

struct SegmentedPicker<T: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: GradesStore
    @Binding var selection: T

    let options: [SegmentedPickerOption<T>]
    var accent: Color? = nil

    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isActive = selection == option.value
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        selection = option.value
                    }
                } label: {
                    ZStack {
                        if isActive {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(activeBackground)
                                .matchedGeometryEffect(id: "active-pill", in: selectionNamespace)
                        }
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isActive ? activeText : inactiveText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(trackBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(trackBorder, lineWidth: 1)
        )
    }

    private var accentColor: Color {
        accent ?? (store.theme == "feminine" ? Color(hex: "#ec4899") : Color(hex: "#2563eb"))
    }

    private var trackBackground: Color {
        if colorScheme == .dark {
            return store.theme == "feminine" ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
        }
        return store.theme == "feminine" ? Color(hex: "#fff5fb") : Color(hex: "#f1f5ff")
    }

    private var trackBorder: Color {
        accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)
    }

    private var activeBackground: Color {
        accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14)
    }

    private var activeText: Color {
        accentColor
    }

    private var inactiveText: Color {
        colorScheme == .dark ? Color(hex: "#cbd5e1") : Color(hex: "#475569")
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

// MARK: - Shared Grade Card Styles

struct GradeCardStyle {
    static func surface(colorScheme: ColorScheme, theme: String, accent: Color) -> some View {
        let baseTop = (colorScheme == .dark)
            ? (theme == "feminine" ? Color(hex: "#1b1022") : Color(hex: "#0b1220"))
            : (theme == "feminine" ? Color(hex: "#fff1f7") : Color(hex: "#eef2ff"))
            
        let baseBottom = (colorScheme == .dark)
            ? (theme == "feminine" ? Color(hex: "#120a16") : Color(hex: "#111827"))
            : (theme == "feminine" ? Color(hex: "#fff7fb") : Color(hex: "#f8fafc"))
            
        return RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [baseTop, baseBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    static func border(colorScheme: ColorScheme, accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(accent.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
    }
}
