import SwiftUI
import UIKit

#if canImport(UIKit)
private enum KeyboardToolbarMetrics {
    static let barHeight: CGFloat = 44
    static let bottomGap: CGFloat = 8
    static let cornerRadius: CGFloat = 999
    static var hairlineWidth: CGFloat {
        let scale = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.scale }
            .first ?? 1
        return scale > 0 ? 1 / scale : 1
    }
    static var totalHeight: CGFloat { barHeight + bottomGap }
}

struct KeyboardAccessoryBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let canGoPrev: Bool
    let canGoNext: Bool
    let onPrev: () -> Void
    let onNext: () -> Void
    let onDone: () -> Void
    let label: String?

    private var foreground: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.82)
    }

    private var baseBackground: Color {
        colorScheme == .dark ? Color(white: 0.1).opacity(0.9) : Color(white: 0.97).opacity(0.94)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        HStack(spacing: 10) {
            navigationControl

            Spacer(minLength: 8)

            Button(action: onDone) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fertig")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: 420)
        .frame(height: KeyboardToolbarMetrics.barHeight)
        .background(
            RoundedRectangle(cornerRadius: KeyboardToolbarMetrics.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            baseBackground.opacity(1.0),
                            baseBackground.opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: KeyboardToolbarMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KeyboardToolbarMetrics.cornerRadius, style: .continuous)
                .stroke(strokeColor, lineWidth: KeyboardToolbarMetrics.hairlineWidth)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 12, y: 5)
        .padding(.bottom, KeyboardToolbarMetrics.bottomGap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label ?? "Tastaturleiste")
    }

    private var navigationControl: some View {
        HStack(spacing: 0) {
            navButton(symbol: "chevron.up", enabled: canGoPrev, action: onPrev)
                .overlay(alignment: .trailing) {
                    strokeColor.opacity(0.8)
                        .frame(width: KeyboardToolbarMetrics.hairlineWidth)
                        .padding(.vertical, 6)
                }

            navButton(symbol: "chevron.down", enabled: canGoNext, action: onNext)
        }
        .frame(height: 32)
    }

    private func navButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            if enabled { action() }
        }) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 32)
                .foregroundStyle(foreground.opacity(enabled ? 0.95 : 0.35))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct KeyboardNavigationAccessory<Focus: Hashable>: View {
    let focus: FocusState<Focus?>.Binding
    let fields: [Focus]
    let label: String?
    let onDone: () -> Void

    var body: some View {
        KeyboardAccessoryBar(
            canGoPrev: previousFocus != nil,
            canGoNext: nextFocus != nil,
            onPrev: { if let previousFocus { focus.wrappedValue = previousFocus } },
            onNext: { if let nextFocus { focus.wrappedValue = nextFocus } },
            onDone: onDone,
            label: label
        )
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private var orderedFields: [Focus] {
        fields
    }

    private var currentIndex: Int? {
        guard let current = focus.wrappedValue else { return nil }
        return orderedFields.firstIndex(of: current)
    }

    private var previousFocus: Focus? {
        guard let index = currentIndex, index > 0 else { return nil }
        return orderedFields[index - 1]
    }

    private var nextFocus: Focus? {
        if let index = currentIndex {
            guard orderedFields.indices.contains(index + 1) else { return nil }
            return orderedFields[index + 1]
        } else {
            return orderedFields.first
        }
    }
}

struct KeyboardToolbarInset: ViewModifier {
    let height: CGFloat
    @State private var isKeyboardVisible = false

    init(height: CGFloat = KeyboardToolbarMetrics.totalHeight) {
        self.height = height
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: isKeyboardVisible ? height : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.easeOut(duration: 0.18)) { isKeyboardVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.18)) { isKeyboardVisible = false }
            }
    }
}

enum KeyboardToolbarAppearance {
    static var isConfigured = false

    static func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        if let inputController = NSClassFromString("UIInputWindowController") as? UIAppearanceContainer.Type {
            let toolbar = UIToolbar.appearance(whenContainedInInstancesOf: [inputController])
            if #available(iOS 15.0, *) {
                let appearance = UIToolbarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundEffect = nil
                appearance.backgroundColor = .clear
                appearance.shadowColor = .clear
                toolbar.standardAppearance = appearance
                toolbar.scrollEdgeAppearance = appearance
                toolbar.compactAppearance = appearance
                toolbar.isTranslucent = true
            } else {
                toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
                toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)
                toolbar.backgroundColor = .clear
                toolbar.barTintColor = .clear
                toolbar.isTranslucent = true
            }
        }
    }
}

extension View {
    /// Dismisses the keyboard.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Adds a global tap gesture to hide the keyboard when tapping anywhere.
    func hideKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { hideKeyboard() },
            including: .subviews // block as little as possible so List/Navigation gestures still work
        )
    }

    /// Shows a native-style bar above the keyboard with navigation and a done action.
    func keyboardDismissToolbar(label: String? = nil) -> some View {
        self.modifier(
            KeyboardToolbarOverlay(
                height: KeyboardToolbarMetrics.totalHeight
            ) {
                KeyboardAccessoryBar(
                    canGoPrev: false,
                    canGoNext: false,
                    onPrev: {},
                    onNext: {},
                    onDone: { hideKeyboard() },
                    label: label
                )
            }
        )
    }

    /// Keyboard toolbar that enables previous/next focus navigation for multi-field forms.
    func keyboardNavigationToolbar<Focus: Hashable>(
        focus: FocusState<Focus?>.Binding,
        fields: [Focus],
        label: String? = nil,
        onDone: (() -> Void)? = nil
    ) -> some View {
        self.modifier(
            KeyboardToolbarOverlay(
                height: KeyboardToolbarMetrics.totalHeight
            ) {
                KeyboardNavigationAccessory(
                    focus: focus,
                    fields: fields,
                    label: label,
                    onDone: onDone ?? { hideKeyboard() }
                )
            }
        )
    }
}

private struct KeyboardToolbarOverlay<Bar: View>: ViewModifier {
    let height: CGFloat
    let bar: () -> Bar
    @State private var isKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: isKeyboardVisible ? height : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) {
                if isKeyboardVisible {
                    HStack {
                        Spacer(minLength: 20)
                        bar()
                        Spacer(minLength: 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isKeyboardVisible)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                isKeyboardVisible = true
                keyboardHeight = extractedKeyboardHeight(from: notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                let newHeight = extractedKeyboardHeight(from: notification)
                // Sobald die Tastaturhöhe schrumpft (z. B. durch Scrollen), direkt komplett schließen,
                // damit sie nicht "gehalten" werden kann.
                if newHeight + 8 < keyboardHeight {
                    dismissKeyboard()
                    isKeyboardVisible = false
                    keyboardHeight = 0
                } else {
                    keyboardHeight = newHeight
                    isKeyboardVisible = newHeight > 0
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
                keyboardHeight = 0
            }
    }

    private func extractedKeyboardHeight(from notification: Notification) -> CGFloat {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let window = keyWindow()
        else { return 0 }
        let converted = window.convert(frame, from: nil)
        let intersection = window.bounds.intersection(converted)
        return intersection.isNull ? 0 : intersection.height
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

extension View {
    /// Applies a large navigation title that behaves like the system sheet header.
    func sheetNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }
}
