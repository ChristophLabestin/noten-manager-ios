import SwiftUI
import UIKit

#if canImport(UIKit)
struct KeyboardAccessoryBar: View {
    let canGoPrev: Bool
    let canGoNext: Bool
    let onPrev: () -> Void
    let onNext: () -> Void
    let onDone: () -> Void
    let label: String?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                navButton(symbol: "chevron.up", enabled: canGoPrev, action: onPrev)
                navButton(symbol: "chevron.down", enabled: canGoNext, action: onNext)
            }

            Spacer(minLength: 0)

            Button(action: onDone) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(.tertiarySystemFill).opacity(0.9))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fertig")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemFill).opacity(0.9))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label ?? "Tastaturleiste")
    }

    private func navButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            if enabled { action() }
        }) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color(.tertiarySystemFill).opacity(0.9))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .opacity(enabled ? 1 : 0.35)
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
        VStack(spacing: 6) {
            KeyboardAccessoryBar(
                canGoPrev: previousFocus != nil,
                canGoNext: nextFocus != nil,
                onPrev: { if let previousFocus { focus.wrappedValue = previousFocus } },
                onNext: { if let nextFocus { focus.wrappedValue = nextFocus } },
                onDone: onDone,
                label: label
            )

            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
            let appearance = UIToolbar.appearance(whenContainedInInstancesOf: [inputController])
            appearance.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
            appearance.setShadowImage(UIImage(), forToolbarPosition: .any)
            appearance.backgroundColor = .clear
            appearance.barTintColor = .clear
            appearance.isTranslucent = true
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

    /// Shows a pill-style bar above the keyboard with navigation and a done action.
    func keyboardDismissToolbar(label: String? = nil) -> some View {
        KeyboardToolbarAppearance.configure()
        return self
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    KeyboardAccessoryBar(
                        canGoPrev: false,
                        canGoNext: false,
                        onPrev: {},
                        onNext: {},
                        onDone: { hideKeyboard() },
                        label: label
                    )
                }
            }
            .modifier(KeyboardToolbarInset(height: 64))
    }

    /// Keyboard toolbar that enables previous/next focus navigation for multi-field forms.
    func keyboardNavigationToolbar<Focus: Hashable>(
        focus: FocusState<Focus?>.Binding,
        fields: [Focus],
        label: String? = nil,
        onDone: (() -> Void)? = nil
    ) -> some View {
        KeyboardToolbarAppearance.configure()
        return self
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    KeyboardNavigationAccessory(
                        focus: focus,
                        fields: fields,
                        label: label,
                        onDone: onDone ?? { hideKeyboard() }
                    )
                }
            }
            .modifier(KeyboardToolbarInset(height: 64))
    }
}
#endif
