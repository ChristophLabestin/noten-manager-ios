import SwiftUI
import FirebaseAuth

struct ClassesListView: View {
    @EnvironmentObject var store: GradesStore
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var copiedClassId: String?
    @State private var classPendingLeave: String?
    @State private var showCreateGroupSheet = false
    @State private var groupPendingLeave: String?
    @State private var copiedGroupId: String?
    @State private var showGroupJoinSheet = false
    @State private var showScannerSheet = false
    @State private var scanError: String?
    @State private var showScanErrorAlert = false
    
    private var animationsOn: Bool { store.animationsEnabled }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Section
                headerSection
                    .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 10)
                
                // Stats Overview
                statsSection
                    .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                
                

                if store.classIds.isEmpty && independentGroups.isEmpty {
                    emptyState
                        .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                } else {
                    if !store.classIds.isEmpty {
                        classesSection
                    }
                    
                    if !independentGroups.isEmpty {
                        independentGroupsSection
                            .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 16)
                    }
                }
                
                HelpCenterLink(
                    title: "Hilfe zu Klassen & Gruppen",
                    subtitle: "Unterschiede, Synchronisation & Features",
                    section: .classesGroups,
                    accent: .pink
                )
                .softFadeIn(enabled: animationsOn, delay: 0.28, offset: 14)
                
                actionsSection
                    .softFadeIn(enabled: animationsOn, delay: 0.3, offset: 14)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .padding(.bottom, 100)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .sheet(isPresented: $showCreateSheet) {
            ClassCreationView()
        }
        .sheet(isPresented: $showCreateGroupSheet) {
            GroupCreationView().environmentObject(store)
        }
        .sheet(isPresented: $showJoinSheet) {
            ClassJoinView()
        }
        .sheet(isPresented: $showGroupJoinSheet) {
            GroupJoinView().environmentObject(store)
        }
        .sheet(isPresented: $showScannerSheet) {
            QRScannerView { scannedCode in
                handleScannedCode(scannedCode)
            }
        }
        .alert("Fehler beim Beitreten", isPresented: $showScanErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(scanError ?? "Unbekannter Fehler")
        }
        .alert("Klasse verlassen?", isPresented: Binding(
            get: { classPendingLeave != nil },
            set: { if !$0 { classPendingLeave = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { classPendingLeave = nil }
            Button("Verlassen", role: .destructive) {
                if let cid = classPendingLeave {
                     Task { await store.leaveClass(code: cid) }
                }
                classPendingLeave = nil
            }
        } message: {
            Text("Möchtest du diese Klasse wirklich verlassen?")
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
    
    // Independent groups: Groups not in any known class list
    private var independentGroups: [String] {
        let allClassGroups = Set(store.classDetails.values.flatMap { $0.groupIds })
        return store.groupIds.filter { !allClassGroups.contains($0) }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Klassen & Gruppen")
                .font(.title2.weight(.bold))
            Text("Verwalte deine Klassen und Lerngruppen")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var statsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            StatChip(title: "Klassen", value: "\(store.classIds.count)", accent: .indigo)
            StatChip(title: "Gruppen", value: "\(store.groupIds.count)", accent: .cyan)
            StatChip(title: "Unabhängig", value: "\(independentGroups.count)", accent: .orange)
        }
    }
    
    private var emptyState: some View {
        SettingsCard(
            title: "Keine Klassen oder Gruppen",
            subtitle: "Tritt einer Klasse bei oder erstelle eine neue.",
            systemImage: "rectangle.stack.person.crop.fill",
            accent: .indigo
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("In Klassen werden mehrere Gruppen gebündelt. Ideal für den gesamten Klassenverband.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var classesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meine Klassen")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            ForEach(Array(store.classIds.enumerated()), id: \.element) { index, cid in
                ClassCardView(
                    classId: cid,
                    isOwner: store.classOwners[cid] == Auth.auth().currentUser?.uid,
                    memberCount: store.classDetails[cid]?.memberCount ?? 0,
                    onLeave: { classPendingLeave = cid }
                )
                .softFadeIn(enabled: animationsOn, delay: 0.15 + (Double(index) * 0.05), offset: 12)
            }
        }
    }
    
    private var independentGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Andere Gruppen")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            ForEach(independentGroups, id: \.self) { gid in
                IndependentGroupCardView(
                    groupId: gid,
                    isOwner: store.groupOwners[gid] == Auth.auth().currentUser?.uid,
                    memberCount: store.groupMemberIds[gid]?.count ?? 0,
                    onLeave: { groupPendingLeave = gid }
                )
            }
        }
    }
    
    private var actionsSection: some View {
        SettingsCard(
            title: "Verwaltung",
            subtitle: "Neue Klassen und Beitritte",
            systemImage: "slider.horizontal.3",
            accent: .indigo
        ) {
            VStack(spacing: 12) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Neue Klasse erstellen", systemImage: "plus.rectangle.fill.on.rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                
                Button {
                    showJoinSheet = true
                } label: {
                    Label("Klasse beitreten", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                
                Divider()
                    .padding(.vertical, 4)
                
                Button {
                    showCreateGroupSheet = true
                } label: {
                    Label("Neue Gruppe erstellen", systemImage: "person.3.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .orange))
                
                Button {
                    showGroupJoinSheet = true
                } label: {
                    Label("Gruppe beitreten", systemImage: "person.badge.plus.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .orange))
                
                Divider()
                    .padding(.vertical, 4)
                
                Button {
                    showScannerSheet = true
                } label: {
                    Label("QR Code scannen", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .cyan))
            }
        }
    }
    
    private func handleScannedCode(_ scannedCode: String) {
        // Deep link format: notenmanager://join/group/CODE or notenmanager://join/class/CODE
        Task {
            do {
                if scannedCode.contains("join/class/") {
                    let code = scannedCode.components(separatedBy: "/").last ?? scannedCode
                    try await store.joinClass(with: code)
                } else if scannedCode.contains("join/group/") || !scannedCode.contains("://") {
                    // If it's a group link or just a raw code, treat as group
                    let code = scannedCode.components(separatedBy: "/").last ?? scannedCode
                    let (_, errors) = await store.joinSharedGroups(codes: [code])
                    if let firstError = errors.first {
                        throw NSError(domain: "App", code: -1, userInfo: [NSLocalizedDescriptionKey: firstError.value])
                    }
                }
            } catch {
                await MainActor.run {
                    self.scanError = error.localizedDescription
                    self.showScanErrorAlert = true
                }
            }
        }
    }
}

private struct ClassCardView: View {
    @EnvironmentObject var store: GradesStore
    let classId: String
    let isOwner: Bool
    let memberCount: Int
    let onLeave: () -> Void
    
    @State private var showShareSheet = false
    
    private var groupCount: Int {
        store.classDetails[classId]?.groupIds.count ?? 0
    }
    
    var body: some View {
        SettingsCard(
            title: store.classNames[classId] ?? "Unbenannte Klasse",
            subtitle: nil,
            systemImage: "rectangle.stack.fill",
            accent: .indigo,
            trailing: {
                if isOwner {
                    PillBadge(text: "Owner", systemImage: "crown.fill", foreground: .indigo, background: .indigo.opacity(0.1))
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Stats Row
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(memberCount) Mitglieder")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "person.3.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(groupCount) Gruppen")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button {
                        showShareSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode")
                            Text("Teilen")
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo, verticalPadding: 10))
                    
                    NavigationLink {
                        ClassDetailView(classId: classId)
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Öffnen")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .cyan, verticalPadding: 10))
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
        .sheet(isPresented: $showShareSheet) {
            ShareCodeSheet(
                code: classId,
                name: store.classNames[classId] ?? "Klasse",
                type: .schoolClass
            )
        }
    }
}

private struct IndependentGroupCardView: View {
    @EnvironmentObject var store: GradesStore
    let groupId: String
    let isOwner: Bool
    let memberCount: Int
    let onLeave: () -> Void
    
    @State private var showShareSheet = false
    
    var body: some View {
        SettingsCard(
            title: store.groupNames[groupId] ?? "Unbenannte Gruppe",
            subtitle: nil,
            systemImage: "person.3.fill",
            accent: .orange,
            trailing: {
                if isOwner {
                    PillBadge(text: "Owner", systemImage: "crown.fill", foreground: .orange, background: .orange.opacity(0.1))
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Stats Row
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(memberCount) Mitglieder")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(groupId)
                            .font(.caption.monospaced().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button {
                        showShareSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode")
                            Text("Teilen")
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .orange, verticalPadding: 10))
                    
                    NavigationLink {
                        GroupSubjectManagementView(groupId: groupId)
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Verwalten")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .cyan, verticalPadding: 10))
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
        .sheet(isPresented: $showShareSheet) {
            ShareCodeSheet(
                code: groupId,
                name: store.groupNames[groupId] ?? "Gruppe",
                type: .group
            )
        }
    }
}
