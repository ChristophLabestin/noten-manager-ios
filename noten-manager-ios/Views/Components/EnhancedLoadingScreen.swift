import SwiftUI

struct EnhancedLoadingScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var store: GradesStore
    
    @State private var animate = false
    @State private var showText = false
    
    // Animation constants
    private let rotationDuration: Double = 2.0
    private let pulseDuration: Double = 1.6

    private var brandColor: Color {
        if store.theme == "feminine" {
            return store.darkMode ? Color(hex: "#f472b6") : Color(hex: "#ec4899")
        }
        return store.darkMode ? Color(hex: "#60a5fa") : Color(hex: "#2563eb")
    }

    var body: some View {
        ZStack {
            // MARK: - App Native Themed Background
            // Uses the same logic as HomeView/SettingsView for consistency
            ThemedBackground(
                isDark: colorScheme == .dark,
                isFeminine: store.theme == "feminine",
                intensity: 1.0 // Full intensity
            )
            .ignoresSafeArea()
            
            // MARK: - Center Content
            VStack(spacing: 40) {
                // Elegant Spinner
                ZStack {
                    // 1. Soft glowing backlight
                    Circle()
                        .fill(brandColor.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .blur(radius: 20)
                        .scaleEffect(animate ? 1.1 : 0.9)
                        .animation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true), value: animate)
                    
                    // 2. Static Ring
                    Circle()
                        .stroke(brandColor.opacity(0.15), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    // 3. Rotating Arc
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(
                            brandColor,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(animate ? 360 : 0))
                        .animation(.linear(duration: rotationDuration).repeatForever(autoreverses: false), value: animate)
                    
                    // 4. Center Icon appearing smoothly
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(brandColor)
                        .scaleEffect(animate ? 1.0 : 0.8)
                        .opacity(animate ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.8).delay(0.2), value: animate)
                }
                
                // Status Text
                VStack(spacing: 12) {
                    Text("NotenManager")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .tracking(0.5)
                        .opacity(showText ? 1.0 : 0.0)
                        .offset(y: showText ? 0 : 5)
                    
                    Text(store.loadingLabel.isEmpty ? "Lädt ..." : store.loadingLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .opacity(showText ? 1.0 : 0.0)
                        .offset(y: showText ? 0 : 5)
                        .id(store.loadingLabel) // Animate text changes
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            animate = true
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                showText = true
            }
        }
    }
}
