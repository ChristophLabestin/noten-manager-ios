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
    @State private var activeSheet: NotificationSheet?

    private enum NotificationSheet: Identifiable {
        case exam(Exam)
        case homework(Homework)
        case daily(DailySummaryData)
        case support
        case examList
        case homeworkList

        var id: String {
            switch self {
            case .exam(let exam): return "exam_\(exam.id)"
            case .homework(let homework): return "homework_\(homework.id)"
            case .daily(let data): return "daily_\(data.id)"
            case .support: return "support"
            case .examList: return "examList"
            case .homeworkList: return "homeworkList"
            }
        }
    }

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
            List {
                if !inbox.broadcasts.isEmpty {
                    Section(header: sectionHeader("Wichtige Meldungen")) {
                        ForEach(inbox.broadcasts) { broadcast in
                            broadcastRow(broadcast)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }

                if LaunchOfferNotificationManager.isOfferActive(), !launchOfferPurchased {
                    Section(header: sectionHeader("Spezialangebot")) {
                        importantNoticeCard
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }

                Section(header: notificationsHeader) {
                    if displayItems.isEmpty {
                        emptyStateCard
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(displayItems) { item in
                            notificationRow(item)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "chevron.down", showDot: false)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
            .onAppear {
                inbox.refreshFromDelivered()
            }
            .onChange(of: inbox.pendingOpenItem) { _, item in
                guard let item else { return }
                inbox.clearPendingOpen()
                openNotification(item)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .exam(let exam):
                    ExamDetailSheet(exam: exam, onEdit: { _ in })
                case .homework(let homework):
                    HomeworkDetailSheet(homework: homework, onEdit: { _ in })
                case .daily(let data):
                    DailySummarySheet(data: data)
                        .environmentObject(store)
                case .support:
                    SupportHistoryView()
                        .environmentObject(store)
                case .examList:
                    ExamListView()
                        .environmentObject(store)
                case .homeworkList:
                    HomeworkListView()
                        .environmentObject(store)
                }
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

    private func broadcastRow(_ broadcast: BroadcastNotification) -> some View {
        SettingsCard(
            title: broadcast.title,
            subtitle: "Ankündigung • \(formattedDate(broadcast.createdAt))",
            systemImage: broadcastIcon(for: broadcast.type),
            accent: broadcastAccent(for: broadcast.type),
            trailing: {
                Image(systemName: "megaphone.fill")
                    .font(.caption)
                    .foregroundStyle(broadcastAccent(for: broadcast.type).opacity(0.6))
            }
        ) {
            Text(broadcast.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func broadcastIcon(for type: String) -> String {
        switch type {
        case "maintenance": return "wrench.and.screwdriver.fill"
        case "update": return "arrow.up.circle.fill"
        case "important": return "exclamationmark.shield.fill"
        default: return "megaphone.fill"
        }
    }

    private func broadcastAccent(for type: String) -> Color {
        switch type {
        case "maintenance": return .orange
        case "update": return .blue
        case "important": return .red
        default: return accentPrimary
        }
    }

    private func notificationRow(_ item: NotificationInboxItem) -> some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            openNotification(item)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                inbox.remove(item)
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                        .font(.headline.weight(.bold))
                    Text("Löschen")
                        .font(.caption.weight(.semibold))
                }
            }
            .tint(.red)
        }
    }

    private func openNotification(_ item: NotificationInboxItem) {
        inbox.markRead(item.id)
        switch item.kind {
        case .exam:
            if let examId = item.examId,
               let exam = store.allExams.first(where: { $0.id == examId }) {
                activeSheet = .exam(exam)
            } else {
                activeSheet = .examList
            }
        case .homework:
            if let homeworkId = item.homeworkId {
                let homework = store.allHomeworks.first { hw in
                    guard hw.id == homeworkId else { return false }
                    if let gid = item.groupId {
                        return hw.groupId == gid
                    }
                    return true
                }
                if let homework {
                    activeSheet = .homework(homework)
                } else {
                    activeSheet = .homeworkList
                }
            } else {
                activeSheet = .homeworkList
            }
        case .daily:
            let examIds = item.examIds ?? (item.examId.map { [$0] } ?? [])
            let homeworkIds = item.homeworkIds ?? (item.homeworkId.map { [$0] } ?? [])
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let hasExplicitIds = !examIds.isEmpty || !homeworkIds.isEmpty
            let tomorrowExams = hasExplicitIds
                ? store.allExams.filter { examIds.contains($0.id) }
                : store.allExams.filter { exam in
                    !exam.isCompleted && Calendar.current.isDate(exam.date, inSameDayAs: tomorrow)
                }
            let tomorrowHomeworks = hasExplicitIds
                ? store.allHomeworks.filter { homeworkIds.contains($0.id) }
                : store.allHomeworks.filter { hw in
                    guard !hw.isCompleted, let due = hw.dueDate else { return false }
                    return Calendar.current.isDate(due, inSameDayAs: tomorrow)
                }
            activeSheet = .daily(DailySummaryData(exams: tomorrowExams, homeworks: tomorrowHomeworks, date: tomorrow))
        case .support:
            if let ticketId = item.ticketId {
                store.pendingTicketId = ticketId
            }
            activeSheet = .support
        case .unknown:
            if let examId = item.examId,
               let exam = store.allExams.first(where: { $0.id == examId }) {
                activeSheet = .exam(exam)
                return
            }
            if let homeworkId = item.homeworkId {
                let homework = store.allHomeworks.first { hw in
                    guard hw.id == homeworkId else { return false }
                    if let gid = item.groupId {
                        return hw.groupId == gid
                    }
                    return true
                }
                if let homework {
                    activeSheet = .homework(homework)
                    return
                }
            }
            if (item.examIds?.isEmpty == false) || (item.homeworkIds?.isEmpty == false) || item.body.lowercased().contains("morgen") {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                let tomorrowExams = store.allExams.filter { exam in
                    !exam.isCompleted && Calendar.current.isDate(exam.date, inSameDayAs: tomorrow)
                }
                let tomorrowHomeworks = store.allHomeworks.filter { hw in
                    guard !hw.isCompleted, let due = hw.dueDate else { return false }
                    return Calendar.current.isDate(due, inSameDayAs: tomorrow)
                }
                activeSheet = .daily(DailySummaryData(exams: tomorrowExams, homeworks: tomorrowHomeworks, date: tomorrow))
                return
            }
            onSelectNotification(item)
        }
    }

    private func accentColor(for kind: NotificationInboxItem.Kind) -> Color {
        switch kind {
        case .exam:
            return .indigo
        case .homework:
            return .green
        case .daily:
            return .orange
        case .support:
            return .blue
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
        case .support:
            return "message.badge.filled.fill"
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
