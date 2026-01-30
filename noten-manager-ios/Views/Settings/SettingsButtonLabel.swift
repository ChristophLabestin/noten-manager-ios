
import SwiftUI

struct SettingsButtonLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: GradesStore
    
    let title: String
    let subtitle: String?
    let icon: String
    let accent: Color
    var showChevron: Bool = true
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon Components
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(accent.opacity(colorScheme == .dark ? 0.30 : 0.20), lineWidth: 1)
                    )
                Image(systemName: icon)
                    .font(.body.weight(.bold))
                    .foregroundStyle(accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .opacity(0.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(GradeCardStyle.surface(colorScheme: colorScheme, theme: store.theme, accent: accent, cornerRadius: 16))
        .overlay(GradeCardStyle.border(colorScheme: colorScheme, accent: accent, cornerRadius: 16))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.06),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}
