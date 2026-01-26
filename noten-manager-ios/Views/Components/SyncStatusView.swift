import SwiftUI

struct SyncStatusView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animate = false
    
    // Customize the "premium" colors here
    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(hex: "#3b82f6").opacity(0.3),
                Color(hex: "#8b5cf6").opacity(0.3)
            ]
        } else {
            return [
                Color(hex: "#bfdbfe").opacity(0.6),
                Color(hex: "#ddd6fe").opacity(0.6)
            ]
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Enhanced Spinner
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0),
                                Color.blue.opacity(0.4),
                                Color.blue
                            ]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 18, height: 18)
                    .rotationEffect(.degrees(animate ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1.0).repeatForever(autoreverses: false),
                        value: animate
                    )
            }
            .padding(2)
            
            Text("Aktualisiere Daten …")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary.opacity(0.85))
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Glassmorphic background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient tint
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(0.4)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
        .onAppear {
            animate = true
        }
    }
}
