import SwiftUI
import FirebaseAuth

struct ClassDetailView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme
    let classId: String
    
    @State private var isJoiningAll: Bool = false
    @State private var joinAllMessage: String?
    @State private var showCreateGroupSheet: Bool = false
    
    private var schoolClass: SchoolClass? {
        store.classDetails[classId]
    }
    
    // Sort groups: unjoined first
    private var displayGroups: [GroupDetails] {
        guard let groups = schoolClass?.fetchedGroups else { return [] }
        return groups.sorted { g1, g2 in
            let j1 = store.groupIds.contains(g1.id)
            let j2 = store.groupIds.contains(g2.id)
            if j1 != j2 { return !j1 } // unjoined first
            return g1.name < g2.name
        }
    }
    
    private var isOwner: Bool {
        store.classOwners[classId] == Auth.auth().currentUser?.uid
    }
    
    private var animationsOn: Bool { store.animationsEnabled }
    
    private var unjoinedGroups: [GroupDetails] {
        displayGroups.filter { !store.groupIds.contains($0.id) }
    }
    
    private var addableGroups: [String] {
        let allClassGroupIds = Set(store.classDetails.values.flatMap { $0.groupIds })
        return store.groupIds.filter { !allClassGroupIds.contains($0) }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with Stats
                headerSection
                    .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 10)
                
                // Stats Row
                statsRow
                    .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                
                // Join All Section
                if !unjoinedGroups.isEmpty {
                    joinAllCard
                        .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                }
                
                // Groups List
                groupsListSection
                    .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 12)
                
                // Add Existing Groups
                if !addableGroups.isEmpty && store.classIds.contains(classId) {
                    addableGroupsSection
                        .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 12)
                }
                
                // Warning hint
                if store.classIds.contains(classId) {
                    warningHint
                        .softFadeIn(enabled: animationsOn, delay: 0.3, offset: 10)
                }
            }
            .padding()
            .padding(.bottom, 60)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .task {
            await store.fetchClassDetails(classId: classId)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateGroupSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
            }
        }
        .sheet(isPresented: $showCreateGroupSheet) {
            ClassGroupCreationView(classId: classId)
                .environmentObject(store)
        }
    }
    
    // MARK: - Section Views
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.indigo.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "rectangle.stack.person.crop.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.indigo)
            }
            Text(store.classNames[classId] ?? "Klasse")
                .font(.title2.weight(.bold))
            if isOwner {
                PillBadge(text: "Owner", systemImage: "crown.fill", foreground: .indigo, background: .indigo.opacity(0.1))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
    
    private var statsRow: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            StatChip(title: "Mitglieder", value: "\(schoolClass?.memberCount ?? 0)", accent: .indigo)
            StatChip(title: "Gruppen", value: "\(schoolClass?.fetchedGroups?.count ?? 0)", accent: .cyan)
            StatChip(title: "Beigetreten", value: "\(displayGroups.filter { store.groupIds.contains($0.id) }.count)", accent: .green)
        }
    }
    
    private var joinAllCard: some View {
        SettingsCard(
            title: "Schnellzugriff",
            subtitle: "\(unjoinedGroups.count) neuen Gruppen beitreten",
            systemImage: "bolt.fill",
            accent: .orange
        ) {
            if let msg = joinAllMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            } else {
                Button {
                    Task { await joinAll(groups: unjoinedGroups) }
                } label: {
                    if isJoiningAll {
                        ProgressView()
                    } else {
                        Label("Allen beitreten", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(SoftTintButtonStyle(accent: .orange))
            }
        }
    }
    
    private var groupsListSection: some View {
        SettingsCard(
            title: "Gruppen",
            subtitle: "\(displayGroups.count) Gruppen in dieser Klasse",
            systemImage: "person.3.fill",
            accent: .cyan
        ) {
            if let groups = schoolClass?.fetchedGroups, !groups.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(displayGroups.enumerated()), id: \.element.id) { index, group in
                        ClassGroupRow(group: group, classId: classId, isJoined: store.groupIds.contains(group.id))
                            .environmentObject(store)
                        
                        if index < displayGroups.count - 1 {
                            Divider()
                                .opacity(0.5)
                                .padding(.leading, 54)
                        }
                    }
                }
                .background(Color.formInputBackground.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Noch keine Gruppen hinzugefügt.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tippe auf + um eine neue Gruppe zu erstellen.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.formInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    
    private var addableGroupsSection: some View {
        SettingsCard(
            title: "Verfügbare Gruppen",
            subtitle: "Füge deine eigenen Gruppen dieser Klasse hinzu",
            systemImage: "plus.circle.fill",
            accent: .blue
        ) {
            VStack(spacing: 1) {
                ForEach(Array(addableGroups.enumerated()), id: \.element) { index, gid in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 36, height: 36)
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.groupNames[gid] ?? "Unbenannte Gruppe")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(store.groupMemberIds[gid]?.count ?? 0) Mitglieder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task {
                                try? await store.addGroupToClass(classId: classId, groupId: gid)
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .padding(8)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.formInputBackground.opacity(0.5))
                    
                    if index < addableGroups.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    private var warningHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.indigo)
            Text("Füge nur Gruppen hinzu, deren Mitglieder alle in dieser Klasse sind. Für gemischte Kurse lasse die Gruppe unabhängig.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.indigo.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func joinAll(groups: [GroupDetails]) async {
        isJoiningAll = true
        let codes = groups.map { $0.id }
        _ = await store.joinSharedGroups(codes: codes)
        joinAllMessage = "Erfolgreich beigetreten!"
        isJoiningAll = false
    }
}

struct ClassGroupRow: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme
    let group: GroupDetails
    let classId: String
    let isJoined: Bool
    
    @State private var showRemoveConfirmation = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Group Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isJoined ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .frame(width: 42, height: 42)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isJoined ? .green : .orange)
            }
            
            NavigationLink {
                GroupSubjectManagementView(groupId: group.id)
                    .environmentObject(store)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 4) {
                            if isJoined {
                                Label("Beigetreten", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Nicht beigetreten", systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            Text("•")
                            Text("\(group.memberCount) Mitglieder")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            
            // Remove button
            Button {
                showRemoveConfirmation = true
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .alert("Gruppe entfernen?", isPresented: $showRemoveConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Entfernen", role: .destructive) {
                Task {
                    try? await store.removeGroupFromClass(classId: classId, groupId: group.id)
                }
            }
        } message: {
            Text("Möchtest du \"\(group.name)\" aus dieser Klasse entfernen?")
        }
    }
}
