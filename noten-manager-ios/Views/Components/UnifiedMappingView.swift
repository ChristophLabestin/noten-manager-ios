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
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" }).map { $0.name }
    }

    private var groupTitle: String {
        store.groupNames[groupId] ?? "Gruppe"
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
            ScrollView {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Fächer abgleichen",
                        subtitle: groupTitle,
                        systemImage: "arrow.triangle.2.circlepath",
                        accent: .purple
                    ) {
                        if groupSubjects.isEmpty {
                            Text("Keine Gruppenfächer vorhanden.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(groupSubjects, id: \.id) { gs in
                                    HStack(alignment: .center, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(gs.name)
                                                .font(.body.weight(.semibold))
                                            if let alias = gs.alias, !alias.isEmpty {
                                                Text(alias)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Picker("", selection: Binding(
                                            get: { workingMap[gs.id] ?? "" },
                                            set: { workingMap[gs.id] = $0 }
                                        )) {
                                            Text("—").tag("")
                                            ForEach(availableLocalNames(for: gs.id), id: \.self) { name in
                                                Text(name).tag(name)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .tint(.primary)
                                        .padding(4)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.formSectionBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.purple.opacity(0.14), lineWidth: 1)
                                    )
                                }
                            }
                        }

                        Text("Fächer, die bereits mit einer anderen Gruppe verknüpft sind, sind nicht aufgelistet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView() }
                            Text(isSaving ? "Speichern..." : "Speichern")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .purple))
                    .disabled(isSaving)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                    }
                    .accessibilityLabel("Abbrechen")
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
        var used: Set<String> = []
        for (gid, map) in store.groupSubjectMappings where gid != groupId {
            for (_, local) in map { used.insert(local) }
        }
        await MainActor.run { usedElsewhere = used }
    }
}
