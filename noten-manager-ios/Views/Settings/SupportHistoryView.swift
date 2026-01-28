import SwiftUI
import FirebaseAuth

struct SupportHistoryView: View {
    @EnvironmentObject var store: GradesStore
    @State private var items: [SupportHistoryItem] = []
    @State private var isLoading = true
    @State private var navigationPath = NavigationPath()
    @Environment(\.dismiss) var dismiss
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var activeColor: Color {
        if isFeminine {
            return isDark ? Color(hex: "#f472b6") : Color(hex: "#ec4899")
        }
        return isDark ? Color(hex: "#60a5fa") : Color(hex: "#2563eb")
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                ).ignoresSafeArea()
                
                Group {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else if items.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "tray")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Keine Support-Anfragen gefunden.")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                ForEach(items) { item in
                                    Button {
                                        navigationPath.append(item)
                                    } label: {
                                        SettingsSectionBox {
                                            VStack(alignment: .leading, spacing: 12) {
                                                HStack {
                                                    Text(item.title)
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                    StatusBadge(status: item.status)
                                                }
                                                
                                                Text(item.message)
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.leading)
                                                
                                                HStack {
                                                    Label(item.activityAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    
                                                    if case .ticket(let ticket) = item, let replies = ticket.replies, !replies.isEmpty {
                                                        Spacer()
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                                            Text("\(replies.count) Antwort(en)")
                                                        }
                                                        .font(.caption2.bold())
                                                        .foregroundColor(activeColor)
                                                    }
                                                    
                                                    if case .ticket(let ticket) = item, let updates = ticket.userUpdates, !updates.isEmpty {
                                                        Spacer()
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "person.fill")
                                                            Text("\(updates.count) Update(s)")
                                                        }
                                                        .font(.caption2.bold())
                                                        .foregroundColor(.secondary)
                                                    }
                                                    
                                                    if case .accessRequest = item {
                                                        Spacer()
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "person.badge.key.fill")
                                                            Text("Datenzugriff")
                                                        }
                                                        .font(.caption2.bold())
                                                        .foregroundColor(.indigo)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Support Verlauf")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SupportHistoryItem.self) { item in
                switch item {
                case .ticket(let ticket):
                    SupportDetailView(ticket: ticket, activeColor: activeColor)
                        .environmentObject(store)
                case .accessRequest(let request):
                    SupportAccessRequestDetailView(request: request, activeColor: activeColor)
                        .environmentObject(store)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
            .task {
                await loadItems()
                handleDeepLink()
            }
        }
    }
    
    private func loadItems() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            async let ticketsTask = FirestoreService.shared.getUserSupportTickets(userId: uid)
            async let requestsTask = FirestoreService.shared.getUserSupportAccessRequests(userId: uid)
            
            let (tickets, requests) = try await (ticketsTask, requestsTask)
            
            var combined: [SupportHistoryItem] = []
            combined.append(contentsOf: tickets.map { .ticket($0) })
            combined.append(contentsOf: requests.map { .accessRequest($0) })
            
            items = combined.sorted { $0.activityAt > $1.activityAt }
        } catch {
            print("Error loading items: \(error)")
        }
        isLoading = false
    }
    
    private func handleDeepLink() {
        if let pendingId = store.pendingTicketId {
            if let item = items.first(where: { 
                if case .ticket(let ticket) = $0 { return ticket.id == pendingId }
                return false
            }) {
                navigationPath.append(item)
            }
            store.pendingTicketId = nil
        }
    }
}

struct SupportDetailView: View {
    @EnvironmentObject var store: GradesStore
    @State private var ticket: SupportTicket
    let activeColor: Color
    @State private var newMessage: String = ""
    @State private var isSending: Bool = false
    @State private var sendError: String?
    @State private var isRefreshing: Bool = false
    
    init(ticket: SupportTicket, activeColor: Color) {
        _ticket = State(initialValue: ticket)
        self.activeColor = activeColor
    }
    
    var body: some View {
        ZStack {
            ThemedBackground(
                isDark: store.darkMode,
                isFeminine: store.theme == "feminine",
                intensity: store.themeBackgroundIntensity
            ).ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.secondary)
                            Text("Deine Anfrage")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(ticket.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ticket.subject)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(ticket.message)
                                    .font(.body)
                                    .foregroundColor(.primary.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    if !conversationEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .foregroundColor(activeColor)
                                Text("Verlauf")
                                    .font(.headline)
                            }
                            .padding(.horizontal, 4)
                            
                            ForEach(conversationEntries) { entry in
                                HStack {
                                    if entry.isUser { Spacer(minLength: 30) }
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: entry.isUser ? "person.fill" : "shield.check.fill")
                                                .foregroundColor(entry.isUser ? .secondary : activeColor)
                                            Text(entry.label)
                                                .font(.caption.bold())
                                                .foregroundColor(entry.isUser ? .secondary : activeColor)
                                            Spacer()
                                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Text(entry.message)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(entry.isUser ? Color.formInputBackground : activeColor.opacity(0.08))
                                    .cornerRadius(16, corners: entry.isUser ? [.topLeft, .bottomLeft, .bottomRight] : [.topRight, .bottomLeft, .bottomRight])
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(entry.isUser ? Color.secondary.opacity(0.12) : activeColor.opacity(0.1), lineWidth: 1)
                                    )
                                    if !entry.isUser { Spacer(minLength: 30) }
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            Spacer(minLength: 40)
                            Image(systemName: "hourglass.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("Unsere Antwort steht noch aus. Wir melden uns in Kürze!")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    SettingsSectionBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Weitere Informationen hinzufügen")
                                .font(.headline)
                            TextEditor(text: $newMessage)
                                .frame(minHeight: 110)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            if let sendError, !sendError.isEmpty {
                                Text(sendError)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                            
                            Button {
                                Task { await sendUpdate() }
                            } label: {
                                if isSending {
                                    ProgressView()
                                } else {
                                    Text("Nachricht senden")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: activeColor))
                            .disabled(!canSend)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Ticket Details")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissToolbar()
        .task {
            await refreshTicket()
        }
    }

    private var canSend: Bool {
        !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
    
    private struct ConversationEntry: Identifiable {
        let id: String
        let isUser: Bool
        let message: String
        let createdAt: Date
        let label: String
    }
    
    private var conversationEntries: [ConversationEntry] {
        var entries: [ConversationEntry] = []
        if let replies = ticket.replies {
            entries.append(contentsOf: replies.map {
                ConversationEntry(
                    id: "support-\($0.id)",
                    isUser: false,
                    message: $0.message,
                    createdAt: $0.createdAt,
                    label: "Support-Team"
                )
            })
        }
        if let updates = ticket.userUpdates {
            entries.append(contentsOf: updates.map {
                ConversationEntry(
                    id: "user-\($0.id)",
                    isUser: true,
                    message: $0.message,
                    createdAt: $0.createdAt,
                    label: "Du"
                )
            })
        }
        return entries.sorted { $0.createdAt < $1.createdAt }
    }
    
    @MainActor
    private func sendUpdate() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            sendError = "Kein Nutzer angemeldet."
            return
        }
        let trimmed = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        sendError = nil
        do {
            try await FirestoreService.shared.addSupportTicketUpdate(ticketId: ticket.id, userId: uid, message: trimmed)
            let update = SupportUserUpdate(message: trimmed, createdAt: Date(), userId: uid)
            var updates = ticket.userUpdates ?? []
            updates.append(update)
            ticket.userUpdates = updates
            ticket.status = "open"
            newMessage = ""
        } catch {
            sendError = "Nachricht konnte nicht gesendet werden."
            ErrorLoggingService.logErrorIfEnabled(error)
        }
        isSending = false
    }
    
    @MainActor
    private func refreshTicket() async {
        guard !isRefreshing else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isRefreshing = true
        if let updated = try? await FirestoreService.shared.getSupportTicket(ticketId: ticket.id, userId: uid) {
            ticket = updated
        }
        isRefreshing = false
    }
}

struct SupportAccessRequestDetailView: View {
    @EnvironmentObject var store: GradesStore
    let request: SupportAccessRequest
    let activeColor: Color
    
    var body: some View {
        ZStack {
            ThemedBackground(
                isDark: store.darkMode,
                isFeminine: store.theme == "feminine",
                intensity: store.themeBackgroundIntensity
            ).ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                                .foregroundColor(.indigo)
                            Text("Datenzugriffsanfrage")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(request.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Deine Nachricht")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(request.message)
                                    .font(.body)
                                    .foregroundColor(.primary.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.secondary)
                            Text("Status & Info")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Status")
                                    Spacer()
                                    StatusBadge(status: request.status)
                                }
                                
                                if let resolvedAt = request.resolvedAt {
                                    HStack {
                                        Text("Gelöst am")
                                        Spacer()
                                        Text(resolvedAt.formatted(date: .abbreviated, time: .shortened))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Divider()
                                
                                Text("Bei einer Datenzugriffsanfrage gewähren Sie dem Support-Team für 24 Stunden Zugriff auf Ihre Daten, um ein technisches Problem zu analysieren.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Anfrage Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Helper for rounded corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        Text(statusText)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.1))
            .foregroundColor(statusColor)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(statusColor.opacity(0.2), lineWidth: 1)
            )
    }
    
    var statusText: String {
        switch status {
        case "open": return "OFFEN"
        case "resolved": return "BEANTWORTET"
        case "closed": return "GESCHLOSSEN"
        default: return status.uppercased()
        }
    }
    
    var statusColor: Color {
        switch status {
        case "open": return .orange
        case "resolved": return .green
        case "closed": return .secondary
        default: return .gray
        }
    }
}
