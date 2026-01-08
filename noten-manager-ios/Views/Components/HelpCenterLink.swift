import SwiftUI

struct HelpCenterLink: View {
    @EnvironmentObject private var store: GradesStore
    let title: String
    let subtitle: String?
    let section: HelpCenterSection
    var accent: Color = .indigo
    var scrollId: String? = nil
    @State private var showHelp: Bool = false

    var body: some View {
        Button {
            showHelp = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
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
