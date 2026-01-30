import SwiftUI

struct SpeedometerView: View {
    let score: Double // 0 to 15
    @Binding var animate: Bool
    var isPrivacyMode: Bool = false
    
    // Config
    private let maxScore: Double = 15.0
    
    // Interpolated score for smooth text counting
    @State private var displayScore: Double = 0.0
    
    var body: some View {
        ZStack {
            // 1. Background Track (Clean, standard/translucent)
            Circle()
                .trim(from: 0, to: 0.75) // 270 degrees
                .stroke(
                    Color.primary.opacity(0.1),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
            
            // 2. Active Progress Track (Traffic Light Color)
            Circle()
                .trim(from: 0, to: (animate && !isPrivacyMode) ? CGFloat(min(score / maxScore, 1.0)) * 0.75 : 0.001)
                .stroke(
                    trafficLightColor,
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .animation(.spring(response: 1.2, dampingFraction: 0.8), value: animate)
                .animation(.spring(response: 1.2, dampingFraction: 0.8), value: score)
                .animation(.spring(response: 1.2, dampingFraction: 0.8), value: isPrivacyMode)
            
            // 3. Center Content
            VStack(spacing: 0) {
                if isPrivacyMode {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.primary.opacity(0.3))
                } else {
                    Text(String(format: "%.2f", displayScore))
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundStyle(trafficLightColor) // Also coloring the text
                        .contentTransition(.numericText(value: displayScore))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                
                Text(isPrivacyMode ? "VERBORGEN" : "PUNKTE")
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundStyle(.primary.opacity(0.5))
                    .tracking(2)
                    .padding(.top, 4)
            }
        }
        .frame(width: 300, height: 300)
        .onAppear {
            if !isPrivacyMode {
                updateScore(to: score)
            }
        }
        .onChange(of: score) { _, newScore in
            if !isPrivacyMode {
                updateScore(to: newScore)
            }
        }
        .onChange(of: isPrivacyMode) { _, isPrivate in
            if !isPrivate {
                // If turning privacy OFF, animate up to current score
                updateScore(to: score)
            } else {
                // If turning privacy ON, maybe reset (optional, but UI handles hide)
                // We rely on the view rebuild to hide the text, and the trim animation to reset the circle
            }
        }
    }
    
    private func updateScore(to value: Double) {
        // Animate counting up
        // Simple linear animation for the number
        withAnimation(.easeOut(duration: 1.0)) {
            displayScore = value
        }
    }
    
    // Existing rule from HomeView: >= 7 Green, >= 4 Orange, else Red
    private var trafficLightColor: Color {
        if score >= 7 { return .green }
        if score >= 4 { return .orange }
        return .red
    }
}
