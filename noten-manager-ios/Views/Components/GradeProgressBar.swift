import SwiftUI

struct GradeProgressBar: View {
    let value: Double
    private var clamped: Double {
        max(0, min(6, value))
    }

    private var colors: [Color] {
        if clamped <= 3.4 {
            return [Color.green, Color.green.opacity(0.7)]
        }
        if clamped <= 4.4 {
            return [Color.orange, Color.orange.opacity(0.7)]
        }
        return [Color.red, Color.red.opacity(0.7)]
    }

    var body: some View {
        GeometryReader { geo in
            let progress = 1 - (clamped / 6) // 1.0 (best) -> 0.0 (worst)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Bewertungsbalken")
        .accessibilityValue(String(format: "%.1f", value))
    }
}
