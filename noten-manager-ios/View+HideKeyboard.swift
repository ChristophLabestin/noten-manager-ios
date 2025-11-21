import SwiftUI

#if canImport(UIKit)
extension View {
    /// Dismisses the keyboard.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Adds a global tap gesture to hide the keyboard when tapping anywhere.
    func hideKeyboardOnTap() -> some View {
        self.gesture(
            TapGesture().onEnded { hideKeyboard() },
            including: .all
        )
    }
}
#endif
