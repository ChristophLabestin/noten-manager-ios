import SwiftUI
import StoreKit

struct NotificationsInboxView: View {
    @ObservedObject var inbox: NotificationInboxStore
    let onSelectNotification: (NotificationInboxItem) -> Void
    let onOpenImportant: () -> Void

    @EnvironmentObject private var store: GradesStore
    @EnvironmentObject private var storeKit: StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("launchOfferPurchased") private var launchOfferPurchased = false

    private var displayItems: [NotificationInboxItem] {
        inbox.items
    }

    private var accentPrimary: Color {
        store.theme == "feminine" ? Color(hex: "#ec4899") : Color(hex: "#2563eb")
    }

    private var ctaAccent: Color {
        if store.theme == "feminine" {
            return colorScheme == .dark ? Color(hex: "#f9a8d4") : Color(hex: "#f472b6")
        }
        return colorScheme == .dark ? Color(hex: "#93c5fd") : Color(hex: "#3b82f6")
    }

    private var offerDisplayPrice: String {
        let price = storeKit.product?.displayPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        if let price, !price.isEmpty {
            return price
        }
        return "3,99€"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if LaunchOfferNotificationManager.isOfferActive(), !launchOfferPurchased {
                        sectionHeader("Wichtig")
                        importantNoticeCard
                    }

                    notificationsHeader
                    if displayItems.isEmpty {
                        emptyStateCard
                    } else {
                        ForEach(displayItems) { item in
                            notificationRow(item)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
            )
            .sheetNavigationTitle("Benachrichtigungen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.medium)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
            .onAppear {
                inbox.refreshFromDelivered()
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private var notificationsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Benachrichtigungen")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Alle löschen", role: .destructive) {
                inbox.clearAll()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .disabled(displayItems.isEmpty)
            .opacity(displayItems.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 4)
    }

    private var importantNoticeCard: some View {
        Button {
            onOpenImportant()
            dismiss()
        } label: {
            SettingsCard(
                title: "Wichtige Info",
                subtitle: "Preisphase ab 01.02.2026",
                systemImage: "megaphone.fill",
                accent: accentPrimary,
                trailing: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(offerDisplayPrice) einmalig statt 9,99€ / Jahr")
                        .font(.headline)
                        .foregroundStyle(ctaAccent)
                    Text("Angebot gültig bis 31.01.2026")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyStateCard: some View {
        SettingsCard(
            title: "Noch nichts hier",
            subtitle: "Deine Benachrichtigungen erscheinen hier",
            systemImage: "bell",
            accent: .secondary,
            trailing: { EmptyView() }
        ) {
            Text("Sobald Erinnerungen oder Hinweise ausgelöst werden, kannst du sie hier erneut öffnen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func notificationRow(_ item: NotificationInboxItem) -> some View {
        Button {
            inbox.markRead(item.id)
            onSelectNotification(item)
            dismiss()
        } label: {
            SettingsCard(
                title: item.title,
                subtitle: formattedDate(item.date),
                systemImage: iconName(for: item.kind),
                accent: accentColor(for: item.kind),
                trailing: {
                    HStack(spacing: 8) {
                        if !item.isRead {
                            Circle()
                                .fill(accentColor(for: item.kind))
                                .frame(width: 8, height: 8)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            ) {
                if item.body.isEmpty {
                    Text("Ohne zusätzliche Details")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.body)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func accentColor(for kind: NotificationInboxItem.Kind) -> Color {
        switch kind {
        case .exam:
            return .indigo
        case .homework:
            return .green
        case .daily:
            return .orange
        default:
            return .secondary
        }
    }

    private func iconName(for kind: NotificationInboxItem.Kind) -> String {
        switch kind {
        case .exam:
            return "calendar.badge.clock"
        case .homework:
            return "checklist"
        case .daily:
            return "clock.badge.exclamationmark"
        default:
            return "bell"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        return formatter
    }()
}
