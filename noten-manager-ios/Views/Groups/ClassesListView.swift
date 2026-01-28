import SwiftUI
import FirebaseAuth
import Foundation

struct ClassesListView: View {
    @EnvironmentObject var store: GradesStore
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var copiedClassId: String?
    @State private var classPendingLeave: String?
    @State private var classPendingDelete: String?
    @State private var showCreateGroupSheet = false
    @State private var groupPendingLeave: String?
    @State private var copiedGroupId: String?
    @State private var showGroupJoinSheet = false
    @State private var groupPendingMigration: String?
    @State private var showScannerSheet = false
    @State private var scanError: String?
    @State private var showScanErrorAlert = false
    @State private var showManualJoinSheet = false
    @State private var joinPreview: JoinPreview?
    @State private var showGroupMergeSheet = false
    @State private var showSocialCreateSheet = false
    @State private var showClassesOnboarding = false
    @State private var showExplainingSheet = false
    
    // For Class Join Context (Course Selection)
    @State private var showCourseSelection: Bool = false
    @State private var joinContext: UnifiedJoinView.ClassJoinContext?
    
    private var animationsOn: Bool { store.animationsEnabled }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Section
                headerSection
                    .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 10)
                
                // Stats Overview
                statsSection
                    .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                
                

                if store.classIds.isEmpty && (store.groupsHidden || (socialGroups.isEmpty && legacyGroups.isEmpty)) {
                    emptyState
                        .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                } else {
                    if !store.classIds.isEmpty {
                        classesSection
                    }
                    
                    if !store.groupsHidden && !socialGroups.isEmpty {
                        socialGroupsSection
                            .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 14)
                    }
                    
                    if !store.groupsHidden && !legacyGroups.isEmpty {
                        legacyGroupsSection
                            .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 16)
                    }
                }
                
                HelpCenterLink(
                    title: store.groupsHidden ? "Hilfe zu Klassen" : "Hilfe zu Klassen & Gruppen",
                    subtitle: store.groupsHidden ? "Beitritt, Kurse & Synchronisation" : "Unterschiede, Synchronisation & Features",
                    section: .classesGroups,
                    accent: .pink
                )
                .softFadeIn(enabled: animationsOn, delay: 0.28, offset: 14)
                
                actionsSection
                    .softFadeIn(enabled: animationsOn, delay: 0.3, offset: 14)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
            } onManualEntry: {
                showScannerSheet = false
                // Small delay to let scanner dismiss before showing next sheet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showManualJoinSheet = true
                }
            }
        }
        .sheet(isPresented: $showManualJoinSheet) {
            UnifiedJoinView()
                .environmentObject(store)
        }
        .sheet(item: $joinPreview) { preview in
            JoinConfirmationSheet(preview: preview) {
                Task { await performConfirmedJoin(preview: preview) }
            }
            .environmentObject(store)
        }
        .navigationDestination(isPresented: $showCourseSelection) {
            if let ctx = joinContext {
                CourseJoinView(
                    classId: ctx.id,
                    className: ctx.name,
                    config: ctx.config,
                    linkedClassIds: ctx.linkedClassIds,
                    onJoinSuccess: { }
                )
                .environmentObject(store)
            }
        }
        .sheet(isPresented: $showGroupMergeSheet) {
            GroupMergeView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSocialCreateSheet) {
            SocialGroupCreationView()
                .environmentObject(store)
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
        .alert("Klasse löschen?", isPresented: Binding(
            get: { classPendingDelete != nil },
            set: { if !$0 { classPendingDelete = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { classPendingDelete = nil }
            Button("Löschen", role: .destructive) {
                if let cid = classPendingDelete {
                     Task {
                        try? await store.deleteClass(code: cid)
                     }
                }
                classPendingDelete = nil
            }
        } message: {
            Text("Möchtest du diese Klasse wirklich unwiderruflich löschen? Alle zugehörigen Kurse werden ebenfalls gelöscht.")
        }
        .sheet(isPresented: Binding(
            get: { groupPendingMigration != nil },
            set: { if !$0 { groupPendingMigration = nil } }
        )) {
            if let gid = groupPendingMigration {
                LegacyGroupMigrationSheet(groupId: gid, ownedClassIds: ownedClassIds) {
                    groupPendingMigration = nil
                }
                .environmentObject(store)
            }
        }
        .sheet(isPresented: $showClassesOnboarding) {
            ClassesFeatureOnboardingSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showExplainingSheet) {
            ClassesExplainingSheet()
                .environmentObject(store)
        }
        .onAppear {
            if !store.hasSeenClassesOnboarding {
                showClassesOnboarding = true
            }
        }
    }

    
    // Independent groups: Groups not in any known class list and not migrated
    private var independentGroups: [String] {
        guard !store.groupsHidden else { return [] }
        let allClassGroups = Set(store.classDetails.values.flatMap { $0.groupIds })
        return store.groupIds.filter { 
            !allClassGroups.contains($0) && !store.migratedGroupIds.contains($0)
        }
    }
    
    private var socialGroups: [String] {
        independentGroups.filter { store.groupTypes[$0] == "social" }
    }
    
    private var legacyGroups: [String] {
        independentGroups.filter { store.groupTypes[$0] != "social" }
    }

    private var ownedClassIds: [String] {
        let uid = Auth.auth().currentUser?.uid
        return store.classIds.filter { store.classOwners[$0] == uid }.sorted()
    }
    
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.groupsHidden ? "Klassen" : "Klassen & Gruppen")
                    .font(.title2.weight(.bold))
                Text(store.groupsHidden ? "Verwalte deine Klassen und Kurse" : "Verwalte deine Klassen und Lerngruppen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showExplainingSheet = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .padding(8)
                    .background(Color.indigo.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var statsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing:10) {
            StatChip(title: "Klassen", value: "\(store.classIds.count)", accent: .indigo)
            if store.groupsHidden {
                StatChip(title: "Meine Kurse", value: "\(store.courses.count)", accent: .orange)
            } else {
                StatChip(title: "Soziale Gruppen", value: "\(socialGroups.count)", accent: .purple)
                StatChip(title: "Legacy-Gruppen", value: "\(legacyGroups.count)", accent: .cyan)
                StatChip(title: "Meine Kurse", value: "\(store.courses.count)", accent: .orange)
            }
        }
    }
    
    private var emptyState: some View {
        SettingsCard(
            title: store.groupsHidden ? "Keine Klassen" : "Keine Klassen oder Gruppen",
            subtitle: "Tritt einer Klasse bei oder erstelle eine neue.",
            systemImage: "rectangle.stack.person.crop.fill",
            accent: .indigo
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.groupsHidden ? "Klassen bündeln Fächer und Kurse für deinen Jahrgang." : "In Klassen werden mehrere Gruppen gebündelt. Ideal für den gesamten Klassenverband.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var classesSection: some View {
        let sortedClasses = store.classIds.sorted { id1, id2 in
            let c1Courses = store.courses.filter { $0.classId == id1 }.count
            let c2Courses = store.courses.filter { $0.classId == id2 }.count
            return c1Courses > c2Courses
        }
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Meine Klassen")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            ForEach(Array(sortedClasses.enumerated()), id: \.element) { index, cid in
                ClassCardView(
                    classId: cid,
                    isOwner: store.classOwners[cid] == Auth.auth().currentUser?.uid,
                    memberCount: store.classDetails[cid]?.memberCount ?? 0,
                    courseCount: store.courses.filter { $0.classId == cid }.count,
                    branchCount: store.classDetails[cid]?.config?.branches?.count ?? 0,
                    onLeave: { classPendingLeave = cid },
                    onDelete: { classPendingDelete = cid },
                    onFinishSetup: {
                        Task {
                            do {
                                let info = try await store.fetchClassInfo(with: cid)
                                if let config = info.config {
                                    await MainActor.run {
                                        self.joinContext = UnifiedJoinView.ClassJoinContext(
                                            id: info.id,
                                            name: info.name,
                                            config: config,
                                            linkedClassIds: info.linkedClassIds ?? []
                                        )
                                        self.showCourseSelection = true
                                    }
                                }
                            } catch {
                                print("Error fetching class info for setup: \(error)")
                            }
                        }
                    }
                )
                .softFadeIn(enabled: animationsOn, delay: 0.15 + (Double(index) * 0.05), offset: 12)
            }
        }
    }
    
    private var socialGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Soziale Gruppen")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            ForEach(socialGroups, id: \.self) { gid in
                SocialGroupCardView(
                    groupId: gid,
                    isOwner: store.groupOwners[gid] == Auth.auth().currentUser?.uid,
                    memberCount: store.groupMemberIds[gid]?.count ?? 0,
                    onLeave: { groupPendingLeave = gid }
                )
            }
        }
    }
    
    private var legacyGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legacy‑Gruppen (Migration)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            ForEach(legacyGroups, id: \.self) { gid in
                LegacyGroupMigrationCardView(
                    groupId: gid,
                    isOwner: store.groupOwners[gid] == Auth.auth().currentUser?.uid,
                    memberCount: store.groupMemberIds[gid]?.count ?? 0,
                    onMigrate: { groupPendingMigration = gid }
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
                    showSocialCreateSheet = true
                } label: {
                    Label("Neue soziale Gruppe", systemImage: "person.2.badge.plus.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .purple))
                
                Button {
                    showScannerSheet = true
                } label: {
                    Label("Beitreten", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .cyan))
            }
        }
    }
    
    private func handleScannedCode(_ scannedCode: String) {
        let code = extractPureCode(from: scannedCode)
        Task {
            do {
                let preview = try await store.fetchJoinPreview(code: code)
                await MainActor.run {
                    self.joinPreview = preview
                }
            } catch {
                await MainActor.run {
                    self.scanError = error.localizedDescription
                    self.showScanErrorAlert = true
                }
            }
        }
    }
    
    @MainActor
    private func performConfirmedJoin(preview: JoinPreview) async {
        do {
            if preview.type == .schoolClass {
                // 1. Join Class Immediately for Persistence
                try await store.joinClass(with: preview.id)
                
                // 2. Prepare Context for Optional Selection
                let info = try await store.fetchClassInfo(with: preview.id)
                if let config = info.config {
                    self.joinContext = UnifiedJoinView.ClassJoinContext(
                        id: info.id,
                        name: info.name,
                        config: config,
                        linkedClassIds: info.linkedClassIds ?? []
                    )
                    self.showCourseSelection = true
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } else {
                let (_, errors) = await store.joinSharedGroups(codes: [preview.id])
                if let error = errors.first {
                    throw NSError(domain: "Join", code: -1, userInfo: [NSLocalizedDescriptionKey: error.value])
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            self.scanError = error.localizedDescription
            self.showScanErrorAlert = true
        }
    }
    
    private func extractPureCode(from raw: String) -> String {
        if raw.contains("://") || raw.contains("http"), let url = URL(string: raw) {
            return url.lastPathComponent
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct AddLegacyGroupToClassSheet: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    let groupId: String
    let ownedClassIds: [String]
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            AddLegacyGroupToClassForm(
                groupId: groupId,
                ownedClassIds: ownedClassIds
            ) {
                onComplete()
                dismiss()
            }
        }
    }
}

private struct LegacyGroupMigrationSheet: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    let groupId: String
    let ownedClassIds: [String]
    let onComplete: () -> Void

    @State private var isMigrating = false
    @State private var errorMessage: String?

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.indigo)
                            .padding(.bottom, 4)
                        
                        Text("Gruppe migrieren")
                            .font(.title3.weight(.bold))
                        
                        Text("Wähle eine Option, um diese Gruppe in das neue Klassensystem zu übertragen.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)

                    // Group Details
                    SettingsCard(
                        title: "Ausgewählte Gruppe",
                        subtitle: "Diese Gruppe wird migriert",
                        systemImage: "person.3.fill",
                        accent: .orange
                    ) {
                        Text(store.groupNames[groupId] ?? groupId)
                            .font(.headline)
                            .padding(.vertical, 4)
                    }

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            Task { await migrateToNewClass() }
                        } label: {
                            if isMigrating {
                                ProgressView().tint(.indigo)
                            } else {
                                Label("Als neue Klasse erstellen", systemImage: "plus.rectangle.fill.on.rectangle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                        .disabled(isMigrating)

                        if !ownedClassIds.isEmpty {
                            NavigationLink(value: MigrationRoute.addToClass) {
                                Label("Zu bestehender Klasse hinzufügen", systemImage: "arrow.branch")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.cyan.opacity(0.1))
                                    .foregroundStyle(.cyan)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12).strokeBorder(.cyan.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        } else {
                            Text("Keine eigenen Klassen gefunden, um diese Gruppe als Zweig hinzuzufügen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(16)
            }
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        ToolbarIcon(symbol: "chevron.down", showDot: false)
                    }
                }
            }
            .navigationDestination(for: MigrationRoute.self) { _ in
                AddLegacyGroupToClassForm(
                    groupId: groupId,
                    ownedClassIds: ownedClassIds
                ) {
                    onComplete()
                    dismiss()
                }
            }
        }
    }

    private func migrateToNewClass() async {
        guard !isMigrating else { return }
        isMigrating = true
        errorMessage = nil
        do {
            _ = try await store.migrateGroupToClass(groupId: groupId)
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isMigrating = false
    }
}

private enum MigrationRoute: Hashable {
    case addToClass
}

private struct AddLegacyGroupToClassForm: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    let groupId: String
    let ownedClassIds: [String]
    let onComplete: () -> Void

    @State private var selectedClassId: String = ""
    @State private var branchName: String = ""
    @State private var isWahlpflicht: Bool = false
    @State private var isSaving = false
    @State private var isMigrating = false
    @State private var errorMessage: String?

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ... (Header remains same)
                VStack(spacing: 4) {
                    Image(systemName: "arrow.branch")
                        .font(.system(size: 40))
                        .foregroundStyle(.cyan)
                        .padding(.bottom, 4)
                    
                    Text("Als Zweig hinzufügen")
                        .font(.title3.weight(.bold))
                    
                    Text("Wähle eine bestehende Klasse aus, zu der diese Gruppe als neuer Zweig oder Wahlpflichtfach hinzugefügt werden soll.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 16)

                // Selection Card
                SettingsCard(
                    title: "Konfiguration",
                    subtitle: "Wähle Zielklasse und Typ",
                    systemImage: "gearshape.fill",
                    accent: .cyan
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Class Picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Zielklasse")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            if ownedClassIds.isEmpty {
                                Text("Keine Klassen vorhanden.")
                                    .foregroundStyle(.secondary)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                Picker("Klasse", selection: $selectedClassId) {
                                    ForEach(ownedClassIds, id: \.self) { cid in
                                        Text(store.classNames[cid] ?? cid).tag(cid)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(4)
                                .frame(maxWidth: .infinity)
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        
                        // Type Selection
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Typ")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                
                            Picker("Typ", selection: $isWahlpflicht) {
                                Text("Zweig").tag(false)
                                Text("Wahlpflichtfach").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }

                        // Name TextField
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isWahlpflicht ? "Name des Wahlpflichtfachs" : "Zweigname (z.B. Technik)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            TextField("Name eingeben...", text: $branchName)
                                .padding(12)
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.vertical, 8)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal, 16)
                }

                // Add Button
                Button {
                    Task { await addToClass() }
                } label: {
                    if isSaving {
                        ProgressView().tint(.cyan)
                    } else {
                        Label(isWahlpflicht ? "Als Wahlpflichtfach hinzufügen" : "Als Zweig hinzufügen", systemImage: isWahlpflicht ? "star.fill" : "arrow.branch")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(SoftTintButtonStyle(accent: .cyan))
                .disabled(isSaving || selectedClassId.isEmpty || branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.top, 8)
            }
            .padding(16)
        }
        .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    ToolbarIcon(symbol: "xmark", showDot: false)
                }
            }
        }
        .onAppear {
            if selectedClassId.isEmpty, let first = ownedClassIds.first {
                selectedClassId = first
            }
            if branchName.isEmpty {
                branchName = store.groupNames[groupId] ?? ""
            }
        }
    }

    private func addToClass() async {
        let trimmedName = branchName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !selectedClassId.isEmpty, !trimmedName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.addLegacyGroupToClass(
                classId: selectedClassId,
                groupCode: groupId,
                branchName: trimmedName,
                isWahlpflicht: isWahlpflicht
            )
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ClassCardView: View {
    @EnvironmentObject var store: GradesStore
    let classId: String
    let isOwner: Bool
    let memberCount: Int
    let courseCount: Int
    let branchCount: Int
    let onLeave: () -> Void
    let onDelete: () -> Void
    let onFinishSetup: () -> Void
    
    @State private var showShareSheet = false
    
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
                        Image(systemName: "book.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(courseCount) Kurse")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(branchCount) Zweige")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "number")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(classId)
                            .font(.caption.monospaced().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Action Buttons
                if courseCount > 0 {
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
                } else {
                    Button {
                        onFinishSetup()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Setup abschließen")
                        }
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo, verticalPadding: 10))
                }
            }
        }
        .contextMenu {
            if isOwner {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Klasse löschen", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    onLeave()
                } label: {
                    Label("Verlassen", systemImage: "rectangle.portrait.and.arrow.right")
                }
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
    let onMigrate: () -> Void
    
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
            
            if isOwner {
                Button {
                    onMigrate()
                } label: {
                    Label("In Klasse umwandeln", systemImage: "arrow.up.circle")
                }
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

private struct LegacyGroupMigrationCardView: View {
    @EnvironmentObject var store: GradesStore
    let groupId: String
    let isOwner: Bool
    let memberCount: Int
    let onMigrate: () -> Void

    var body: some View {
        SettingsCard(
            title: store.groupNames[groupId] ?? "Legacy‑Gruppe",
            subtitle: "Nur Migration möglich",
            systemImage: "arrow.up.circle.fill",
            accent: .orange,
            trailing: {
                if isOwner {
                    PillBadge(text: "Owner", systemImage: "crown.fill", foreground: .orange, background: .orange.opacity(0.1))
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
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

                if isOwner {
                    Button {
                        onMigrate()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.merge")
                            Text("Jetzt migrieren")
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .orange, verticalPadding: 10))
                } else {
                    Text("Nur der Owner kann die Migration starten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SocialGroupCardView: View {
    @EnvironmentObject var store: GradesStore
    let groupId: String
    let isOwner: Bool
    let memberCount: Int
    let onLeave: () -> Void
    
    @State private var showShareSheet = false
    
    var body: some View {
        SettingsCard(
            title: store.groupNames[groupId] ?? "Soziale Gruppe",
            subtitle: nil,
            systemImage: "person.2.fill",
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
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo, verticalPadding: 10))
                    
                    NavigationLink {
                        SocialGroupDetailView(groupId: groupId)
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
                code: groupId,
                name: store.groupNames[groupId] ?? "Gruppe",
                type: .socialGroup
            )
        }
    }
}
