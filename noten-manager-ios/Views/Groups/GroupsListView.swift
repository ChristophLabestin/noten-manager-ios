import SwiftUI
import FirebaseAuth

struct GroupsListView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var notificationStore = NotificationInboxStore.shared
    var onOpenCreationMenu: () -> Void = {}
    
    // Toolbar Sheets State
    @State private var showNotifications = false
    @State private var showExamSheet = false
    @State private var showHomeworkSheet = false
    
    // Groups Sheets State
    @State private var showJoinSheet: Bool = false
    @State private var showCreateSheet: Bool = false
    @State private var copiedGroupId: String?
    @State private var groupPendingLeave: String?
    
    // Animations
    private var animationsOn: Bool { store.animationsEnabled }
    
    // Derived Metrics
    private var uniquePeersCount: Int {
        let allMembers = store.groupMemberIds.values.flatMap { $0 }
        let myUid = Auth.auth().currentUser?.uid ?? ""
        let others = allMembers.filter { $0 != myUid }
        return Set(others).count
    }
    
    // Red Dot Logic
    private var hasOverdueExams: Bool {
        let now = Date()
        return store.allExams.contains { exam in
            !exam.isCompleted && exam.date < now
        }
    }
    
    private var hasOverdueHomeworks: Bool {
        let now = Date()
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate { return due < now }
            if let reminder = hw.reminderAt { return reminder < now }
            return false
        }
    }
    
    private var hasHomeworkDueTomorrow: Bool {
        let cal = Calendar.current
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted, let due = hw.dueDate else { return false }
            return cal.isDateInTomorrow(due)
        }
    }

    var body: some View {
        ZStack {
            // Themed Background
            ThemedBackground(
                isDark: store.darkMode,
                isFeminine: store.theme == "feminine",
                intensity: store.themeBackgroundIntensity
            )
            
            ScrollView {
                VStack(spacing: 20) {
                    // Removed "Lerngruppen" header as requested
                    
                    heroCard
                        .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                        .padding(.top, 16) // Added padding to compensate for missing header
                    
                    if store.groupIds.isEmpty {
                        emptyState
                            .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                    } else {
                        groupsList
                    }
                    
                    actionsSection
                        .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showNotifications = true
                } label: {
                    ToolbarIcon(
                        symbol: "bell",
                        showDot: notificationStore.hasUnread || (LaunchOfferNotificationManager.isOfferActive() && !UserDefaults.standard.bool(forKey: "launchOfferPurchased"))
                    )
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    Button {
                        onOpenCreationMenu()
                    } label: {
                        ToolbarIcon(symbol: "plus", showDot: false)
                    }
                    
                    Button {
                        showExamSheet = true
                    } label: {
                        ToolbarIcon(symbol: "calendar.badge.clock", showDot: hasOverdueExams)
                    }
                    
                    Button {
                         showHomeworkSheet = true
                    } label: {
                        ToolbarIcon(symbol: "checklist", showDot: hasOverdueHomeworks || hasHomeworkDueTomorrow)
                    }
                }
            }
        }
        .sheet(isPresented: $showNotifications) {
           NotificationsInboxView(
               inbox: notificationStore,
               onSelectNotification: { _ in },
               onOpenImportant: { NotificationCenter.default.post(name: .openLaunchOffer, object: nil) }
           )
           .environmentObject(store)
        }
        .sheet(isPresented: $showExamSheet) {
            ExamListView().environmentObject(store)
        }
        .sheet(isPresented: $showHomeworkSheet) {
            HomeworkListView().environmentObject(store)
        }
        .sheet(isPresented: $showJoinSheet) {
            GroupJoinView().environmentObject(store)
        }
        .sheet(isPresented: $showCreateSheet) {
            GroupCreationView().environmentObject(store)
        }
        .alert("Gruppe verlassen?", isPresented: Binding(
            get: { groupPendingLeave != nil },
            set: { if !$0 { groupPendingLeave = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { groupPendingLeave = nil }
            Button("Verlassen", role: .destructive) {
                if let gid = groupPendingLeave {
                    Task { await store.leaveSharedGroup(code: gid) }
                }
                groupPendingLeave = nil
            }
        } message: {
            Text("Möchtest du diese Gruppe wirklich verlassen?")
        }
    }
    
    private var heroCard: some View {
        SettingsCard(
            title: "Übersicht",
            subtitle: "Deine Gruppen-Statistik",
            systemImage: "chart.bar.fill",
            accent: .indigo
        ) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.groupIds.count)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.indigo)
                    Text("Gruppen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(uniquePeersCount)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.purple)
                    Text("Geteilte Mitschüler")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var emptyState: some View {
        SettingsCard(
            title: "Keine Gruppen",
            subtitle: "Tritt einer Gruppe bei oder erstelle eine neue.",
            systemImage: "person.3.sequence.fill",
            accent: .indigo
        ) {
            Text("In Gruppen kannst du Fächer und Noten mit deinen Freunden teilen und vergleichen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var groupsList: some View {
        VStack(spacing: 12) {
            ForEach(Array(store.groupIds.enumerated()), id: \.element) { index, gid in
                GroupCardView(
                    groupId: gid,
                    isOwner: store.groupOwners[gid] == Auth.auth().currentUser?.uid,
                    memberCount: store.groupMemberIds[gid]?.count ?? 0,
                    copiedGroupId: $copiedGroupId,
                    onLeave: { groupPendingLeave = gid }
                )
                .softFadeIn(enabled: animationsOn, delay: 0.1 + (Double(index) * 0.05), offset: 12)
            }
        }
    }
    
    private var actionsSection: some View {
        SettingsCard(
            title: "Verwaltung",
            subtitle: "Neue Gruppen und Beitritte",
            systemImage: "slider.horizontal.3",
            accent: .indigo
        ) {
            VStack(spacing: 12) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Neue Gruppe erstellen", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                
                Button {
                    showJoinSheet = true
                } label: {
                    Label("Gruppe beitreten", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .indigo))
            }
        }
    }
}

private struct GroupCardView: View {
    @EnvironmentObject var store: GradesStore
    
    let groupId: String
    let isOwner: Bool
    let memberCount: Int
    @Binding var copiedGroupId: String?
    let onLeave: () -> Void
    
    var body: some View {
        SettingsCard(
            title: store.groupNames[groupId] ?? "Unbenannte Gruppe",
            subtitle: "Code: \(groupId)",
            systemImage: "person.3.fill",
            accent: .indigo,
            trailing: {
                VStack(alignment: .trailing, spacing: 4) {
                    if isOwner {
                        PillBadge(text: "Owner", systemImage: "crown.fill", foreground: .indigo, background: .indigo.opacity(0.1))
                    }
                    
                    // Member Count Badge
                    PillBadge(
                        text: "\(memberCount) Mitglieder",
                        systemImage: "person.2.fill",
                        foreground: .secondary,
                        background: .secondary.opacity(0.1)
                    )
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        copyCode()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copiedGroupId == groupId ? "checkmark" : "doc.on.doc")
                            Text(copiedGroupId == groupId ? "Code kopiert" : "Code kopieren")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copiedGroupId == groupId ? .green : .indigo)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    NavigationLink {
                        GroupSubjectManagementView(groupId: groupId)
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Verwalten")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onLeave()
            } label: {
                Label("Verlassen", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
    
    private func copyCode() {
        UIPasteboard.general.string = groupId
        withAnimation { copiedGroupId = groupId }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copiedGroupId == groupId {
                withAnimation { copiedGroupId = nil }
            }
        }
    }
}


