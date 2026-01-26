import SwiftUI

struct MinimalLoadingIndicator: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animate = false

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.primary)
                .scaleEffect(0.8)
            
            Text("Synchronisiere …")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            animate = true
        }
    }
}
