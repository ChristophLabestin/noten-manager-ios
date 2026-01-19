import SwiftUI

struct HelpCenterLink: View {
    @EnvironmentObject private var store: GradesStore
    let title: String
    let subtitle: String?
    let section: HelpCenterSection
    var accent: Color = .indigo
    var scrollId: String? = nil
    @State private var showHelp: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            showHelp = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.22 : 0.14))
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(accent.opacity(colorScheme == .dark ? 0.30 : 0.20), lineWidth: 1)
                        )
                    Image(systemName: "questionmark.circle.fill")
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

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .opacity(0.5)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(GradeCardStyle.surface(colorScheme: colorScheme, theme: store.theme, accent: accent))
            .overlay(GradeCardStyle.border(colorScheme: colorScheme, accent: accent))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.40 : 0.06),
                radius: 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showHelp) {
            NavigationStack {
                HelpCenterView(initialSection: section, initialScrollId: scrollId)
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showHelp = false
                            } label: {
                                Image(systemName: "chevron.down")
                                    .imageScale(.medium)
                                    .foregroundStyle(store.darkMode ? .white : .black)
                            }
                            .accessibilityLabel("Schließen")
                        }
                    }
            }
        }
    }
}
