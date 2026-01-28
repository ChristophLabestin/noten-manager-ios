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
                                                    Label(item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
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
            
            items = combined.sorted { $0.createdAt > $1.createdAt }
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
    let ticket: SupportTicket
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
                    // Original Ticket
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
                    
                    if let replies = ticket.replies, !replies.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "arrow.turn.down.right")
                                    .foregroundColor(activeColor)
                                Text("Antworten")
                                    .font(.headline)
                            }
                            .padding(.horizontal, 4)
                            
                            ForEach(replies) { reply in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: "shield.check.fill")
                                            .foregroundColor(activeColor)
                                        Text("Support-Team")
                                            .font(.caption.bold())
                                            .foregroundColor(activeColor)
                                        Spacer()
                                        Text(reply.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    VStack(alignment: .leading) {
                                        Text(reply.message)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(activeColor.opacity(0.08))
                                    .cornerRadius(16, corners: [.topRight, .bottomLeft, .bottomRight])
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(activeColor.opacity(0.1), lineWidth: 1)
                                    )
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
                }
                .padding()
            }
        }
        .navigationTitle("Ticket Details")
        .navigationBarTitleDisplayMode(.inline)
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
