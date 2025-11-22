import SwiftUI

#if canImport(UIKit)
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

    /// Shows an "X" button above the keyboard to dismiss it.
    func keyboardDismissToolbar() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    hideKeyboard()
                }
                .font(.body.weight(.semibold))
            }
        }
    }
}
#endif
