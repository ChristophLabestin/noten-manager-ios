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
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.22 : 0.14))
                        .frame(width: 46, height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(accent.opacity(colorScheme == .dark ? 0.30 : 0.20), lineWidth: 1)
                        )
                    Image(systemName: "questionmark.circle.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .opacity(0.5)
            }
            .padding(12)
            .background(GradeCardStyle.surface(colorScheme: colorScheme, theme: store.theme, accent: accent))
            .overlay(GradeCardStyle.border(colorScheme: colorScheme, accent: accent))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08),
                radius: 6,
                x: 0,
                y: 4
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
