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
            List {
                Section("Übersicht") {
                    if groupSubjects.isEmpty {
                        Text("Keine Gruppenfächer vorhanden.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(groupSubjects, id: \.id) { gs in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(gs.name)
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
                                Spacer()
                                if deletingIds.contains(gs.id) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else if isOwner {
                                    Button {
                                        Task { await deleteGroupSubject(gs) }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .tint(.red)
                                } else if missingIds.contains(gs.id) {
                                    Text("Nicht übernommen")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                } else if mapping[gs.id] == nil {
                                    Text("Ohne Mapping")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if isOwner {
                                    Button(role: .destructive) {
                                        Task { await deleteGroupSubject(gs) }
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                    .disabled(deletingIds.contains(gs.id))
                        }
                        if isOwner {
                            Text("Als Ersteller kannst du Fächer löschen: nach links wischen oder den Mülleimer nutzen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                    }
                }

                Section("Neue Fächer zur Gruppe hinzufügen") {
                    if attachableSubjects.isEmpty {
                        Text("Keine freien Fächer verfügbar. Fächer, die bereits in anderen Gruppen gemappt sind, werden hier ausgeblendet.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
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
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .disabled(isAdding || attachSelection.isEmpty)
                    }
                }

                Section("Fächer aus der Gruppe kopieren") {
                    if missingSubjects.isEmpty {
                        Text("Alle Gruppenfächer sind bereits in deinem Plan.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else {
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
                        .buttonStyle(.bordered)
                        .disabled(isImporting || importSelection.isEmpty)
                    }
                }

                Section {
                    Button {
                        showMapping = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            Text("Fach-Mapping öffnen")
                        }
                    }
                } footer: {
                    Text("Prüfe das Mapping, wenn neue Fächer hinzugekommen sind oder Namen abweichen.")
                        .font(.footnote)
                }

                if let info = infoMessage {
                    Section {
                        Text(info)
                            .foregroundStyle(.green)
                    }
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(groupTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .disabled(isAdding || isImporting)
                }
            }
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
            errorMessage = error.localizedDescription
        }
    }
}
