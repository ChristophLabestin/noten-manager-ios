import SwiftUI

struct UnifiedMappingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let groupId: String

    @State private var workingMap: [String: String] = [:]
    @State private var isSaving: Bool = false
    @State private var usedElsewhere: Set<String> = []

    private var groupSubjects: [GroupSubject] {
        store.groupSubjectsByGroup[groupId] ?? []
    }

    private var existingMap: [String: String] {
        store.groupSubjectMappings[groupId] ?? [:]
    }

    private var localSubjectNames: [String] {
        store.subjects.filter { $0.name != "Fachreferat" }.map { $0.name }.sorted()
    }

    private func availableLocalNames(for groupSubjectId: String) -> [String] {
        let currentSelection = workingMap[groupSubjectId]
        return localSubjectNames.filter { name in
            if let current = currentSelection, current == name { return true }
            return !usedElsewhere.contains(name)
        }
    }

    var body: some View {
        NavigationStack {
            List {
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
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { workingMap[gs.id] ?? "" },
                                set: { workingMap[gs.id] = $0 }
                            )) {
                                Text("—").tag("")
                                ForEach(availableLocalNames(for: gs.id), id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Hinweis: Fächer, die bereits mit einer anderen Gruppe verknüpft sind, können hier nicht erneut verknüpft werden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
            .navigationTitle("Fächer abgleichen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Speichern") }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                workingMap = existingMap
                Task { await refreshUsedElsewhere() }
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        await store.updateGroupSubjectMapping(groupId: groupId, map: workingMap)
        isSaving = false
        dismiss()
    }

    private func refreshUsedElsewhere() async {
        // sammeln aller Mappings anderer Gruppen
        var used: Set<String> = []
        for (gid, map) in store.groupSubjectMappings where gid != groupId {
            for (_, local) in map { used.insert(local) }
        }
        await MainActor.run { usedElsewhere = used }
    }
}
