import SwiftUI
import UIKit

@MainActor
final class KeyboardAccessoryManager {
    static let shared = KeyboardAccessoryManager()

    private let toolbarHeight: CGFloat = 52
    private var window: KeyboardAccessoryWindow?
    private var isConfigured = false

    private init() {}

    func start() {
        // Disabled in favor of native SwiftUI .toolbar(placement: .keyboard)
        // This stops the manager from creating custom windows that overlap the keyboard incorrectly.
        isConfigured = true
    }

    private func updateWindow(frame: CGRect) {
        guard let scene = currentScene() else { return }
        let keyboardFrame = scene.coordinateSpace.convert(frame, from: UIScreen.main.coordinateSpace)

        if keyboardFrame.height <= 0 {
            hideWindow()
            return
        }

        let screenBounds = scene.screen.bounds
        let targetFrame = CGRect(
            x: 0,
            y: max(0, keyboardFrame.minY - toolbarHeight),
            width: screenBounds.width,
            height: toolbarHeight
        )

        let window = ensureWindow(for: scene)
        window.frame = targetFrame
        if window.isHidden {
            window.isHidden = false
        }
    }

    private func hideWindow() {
        window?.isHidden = true
    }

    private func ensureWindow(for scene: UIWindowScene) -> KeyboardAccessoryWindow {
        if let window, window.windowScene == scene {
            return window
        }

        let newWindow = KeyboardAccessoryWindow(windowScene: scene)
        // Keyboard window level is very high (~10_000_000), so we need a higher level
        newWindow.windowLevel = UIWindow.Level(rawValue: 10_000_002)
        newWindow.backgroundColor = .clear
        newWindow.rootViewController = UIHostingController(rootView: KeyboardAccessoryHostView())
        newWindow.rootViewController?.view.backgroundColor = .clear
        newWindow.isHidden = true
        self.window = newWindow
        return newWindow
    }

    private func currentScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

}

final class KeyboardAccessoryWindow: UIWindow {}

private struct KeyboardAccessoryHostView: View {
    var body: some View {
        KeyboardAccessoryBar(
            canGoPrev: false,
            canGoNext: false,
            onPrev: {},
            onNext: {},
            onDone: { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) },
            label: "Tastatur schließen"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 16)
    }
}
