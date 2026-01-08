import SwiftUI

struct GroupSubjectManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let groupId: String

    @State private var attachSelection: Set<String> = []
    @State private var importSelection: Set<String> = []
    @State private var isAdding: Bool = false
    @State private var isImporting: Bool = false
    @State private var deletingIds: Set<String> = []
    @State private var isOwner: Bool = false
    @State private var infoMessage: String?
    @State private var errorMessage: String?
    @State private var showMapping: Bool = false

    private var groupSubjects: [GroupSubject] {
        store.groupSubjectsByGroup[groupId] ?? []
    }

    private var mapping: [String: String] {
        store.groupSubjectMappings[groupId] ?? [:]
    }

    private var attachableSubjects: [Subject] {
        store
            .availableSubjectsForGroupAttachment(groupId: groupId)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var missingSubjects: [GroupSubject] {
        let existing = Set(store.subjects.map { $0.name.lowercased() })
        return (store.groupSubjectsByGroup[groupId] ?? [])
            .filter { !existing.contains($0.name.lowercased()) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var missingIds: Set<String> {
        Set(missingSubjects.map { $0.id })
    }

    private var groupTitle: String {
        store.groupNames[groupId] ?? "Gruppe"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Gruppenfächer",
                        subtitle: groupTitle,
                        systemImage: "square.stack.3d.up.fill",
                        accent: .indigo
                    ) {
                        SettingsSectionBox {
                            if groupSubjects.isEmpty {
                                Text("Keine Gruppenfächer vorhanden.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(groupSubjects, id: \.id) { gs in
                                        HStack(alignment: .center, spacing: 10) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(gs.name)
                                                    .font(.body.weight(.semibold))
                                                if let alias = gs.alias, !alias.isEmpty {
                                                    Text(alias)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                if let mapped = mapping[gs.id], !mapped.isEmpty, mapped != gs.name {
                                                    Text("Lokal: \(mapped)")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                            if deletingIds.contains(gs.id) {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            } else if isOwner {
                                                Button(role: .destructive) {
                                                    Task { await deleteGroupSubject(gs) }
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(PillActionButtonStyle(accent: .red))
                                            } else if missingIds.contains(gs.id) {
                                                Text("Nicht übernommen")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.orange)
                                            } else if mapping[gs.id] == nil {
                                                Text("Ohne Mapping")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                    }
                                }
                            }
                        }
                        if isOwner {
                            Text("Als Ersteller kannst du Fächer direkt löschen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsCard(
                        title: "Zur Gruppe hinzufügen",
                        subtitle: "Eigene Fächer anhängen",
                        systemImage: "plus.square.on.square",
                        accent: .blue
                    ) {
                        SettingsSectionBox {
                            if attachableSubjects.isEmpty {
                                Text("Keine freien Fächer verfügbar. Fächer, die bereits in anderen Gruppen gemappt sind, werden hier ausgeblendet.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(attachableSubjects, id: \.name) { subj in
                                        Toggle(isOn: Binding(
                                            get: { attachSelection.contains(subj.name) },
                                            set: { val in
                                                if val { attachSelection.insert(subj.name) }
                                                else { attachSelection.remove(subj.name) }
                                            }
                                        )) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(subj.name)
                                                if let alias = subj.alias, !alias.isEmpty {
                                                    Text(alias)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    Button {
                                        Task { await addSelectedSubjects() }
                                    } label: {
                                        HStack {
                                            if isAdding { ProgressView() }
                                            Text("Zur Gruppe hinzufügen")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                                    .disabled(isAdding || attachSelection.isEmpty)
                                }
                            }
                        }
                    }

                    SettingsCard(
                        title: "Aus Gruppe übernehmen",
                        subtitle: "Fehlende Fächer kopieren",
                        systemImage: "tray.and.arrow.down.fill",
                        accent: .teal
                    ) {
                        SettingsSectionBox {
                            if missingSubjects.isEmpty {
                                Text("Alle Gruppenfächer sind bereits in deinem Plan.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(missingSubjects, id: \.id) { gs in
                                        Toggle(isOn: Binding(
                                            get: { importSelection.contains(gs.name) },
                                            set: { val in
                                                if val { importSelection.insert(gs.name) }
                                                else { importSelection.remove(gs.name) }
                                            }
                                        )) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(gs.name)
                                                if let alias = gs.alias, !alias.isEmpty {
                                                    Text(alias)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    Button {
                                        Task { await importSelectedSubjects() }
                                    } label: {
                                        HStack {
                                            if isImporting { ProgressView() }
                                            Text("In eigene Fächer kopieren")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(SoftTintButtonStyle(accent: .teal))
                                    .disabled(isImporting || importSelection.isEmpty)
                                }
                            }
                        }
                    }

                    SettingsCard(
                        title: "Mapping & Abgleich",
                        subtitle: "Namen synchronisieren",
                        systemImage: "arrow.triangle.2.circlepath",
                        accent: .purple
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Prüfe das Mapping, wenn neue Fächer hinzugekommen sind oder Namen abweichen.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button {
                                    showMapping = true
                                } label: {
                                    Label("Abgleichen", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .purple))
                            }
                        }
                    }

                    if let info = infoMessage {
                        StatusLabel(text: info, color: .green, icon: "checkmark.circle.fill")
                    }
                    if let err = errorMessage {
                        StatusLabel(text: err, color: .red, icon: "exclamationmark.triangle.fill")
                    }
                }
                .padding(16)
            }
            .background(
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
            )
            .scrollContentBackground(.hidden)
            .sheetNavigationTitle(groupTitle)

            .onAppear {
                syncSelections()
                Task { await refreshOwnership() }
            }
            .sheet(isPresented: $showMapping) {
                UnifiedMappingView(groupId: groupId)
                    .environmentObject(store)
            }
        }
    }

    @MainActor
    private func syncSelections() {
        importSelection = Set(missingSubjects.map { $0.name })
    }

    @MainActor
    private func addSelectedSubjects() async {
        guard !attachSelection.isEmpty else { return }
        isAdding = true
        errorMessage = nil
        infoMessage = nil
        defer { isAdding = false }
        do {
            let added = try await store.addSubjectsToGroup(groupId: groupId, subjectNames: Array(attachSelection))
            if added > 0 {
                infoMessage = added == 1 ? "1 Fach zur Gruppe hinzugefügt." : "\(added) Fächer zur Gruppe hinzugefügt."
            } else {
                infoMessage = "Keine neuen Fächer hinzugefügt."
            }
            attachSelection.removeAll()
            syncSelections()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importSelectedSubjects() async {
        guard !importSelection.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        infoMessage = nil
        defer { isImporting = false }
        let imported = await store.importSubjectsFromGroups(groupIds: [groupId], allowedNames: Set(importSelection))
        if imported > 0 {
            infoMessage = imported == 1 ? "1 Fach kopiert." : "\(imported) Fächer kopiert."
        } else {
            infoMessage = "Keine neuen Fächer kopiert."
        }
        syncSelections()
    }

    @MainActor
    private func refreshOwnership() async {
        let isOwner = await store.isCurrentUserOwner(of: groupId)
        self.isOwner = isOwner
    }

    @MainActor
    private func deleteGroupSubject(_ gs: GroupSubject) async {
        guard !deletingIds.contains(gs.id) else { return }
        deletingIds.insert(gs.id)
        errorMessage = nil
        infoMessage = nil
        defer { deletingIds.remove(gs.id) }
        do {
            try await store.deleteGroupSubject(groupId: groupId, subjectId: gs.id)
            infoMessage = "\"\(gs.name)\" entfernt."
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            errorMessage = error.localizedDescription
        }
    }
}

private struct StatusLabel: View {
    let text: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
            Text(text)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PillActionButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .foregroundStyle(accent)
            .background(accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
