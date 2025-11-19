import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var newName: String = ""
    @State private var isSavingName: Bool = false
    @State private var nameSavedSuccess: Bool = false

    // BottomNav Navigation
    @State private var navigateToFinal: Bool = false
    @State private var navigateToSubjects: Bool = false

    private var maxExamSubjects: Int { 4 }
    private var currentExamSubjectsCount: Int {
        store.subjects.filter { ($0.examSubject ?? false) }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // BurgerMenu Header – analog zur Web-Settings-Seite
                    BurgerMenuView(
                        isSmall: true,
                        title: "Einstellungen",
                        subjectType: nil,
                        subtitle: "Name und App-Design anpassen"
                    )
                    .environmentObject(store)

                    // Karte: Allgemein + App-Design
                    SettingsCard(
                        title: "Allgemein",
                        subtitle: "Allgemeine App- und Account-Einstellungen"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Anzeigename
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Anzeigename")
                                    .font(.subheadline)
                                HStack {
                                    TextField("Dein Name", text: $newName)
                                        .textContentType(.name)
                                    Button {
                                        Task { await saveName() }
                                    } label: {
                                        if isSavingName { ProgressView() } else { Text("Name speichern") }
                                    }
                                    .disabled(isSavingName || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                                if nameSavedSuccess {
                                    Text("✅ Name erfolgreich gespeichert!")
                                        .font(.footnote)
                                        .foregroundStyle(.green)
                                }
                            }

                            Divider().padding(.vertical, 4)

                            // Farbschema
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Farbschema")
                                    .font(.subheadline)
                                Picker(
                                    "",
                                    selection: Binding(
                                        get: { store.theme },
                                        set: { val in Task { await store.updatePreferences(theme: val) } }
                                    )
                                ) {
                                    Text("Klassisch").tag("default")
                                    Text("Pink").tag("feminine")
                                }
                                .pickerStyle(.segmented)

                                Text("Wähle, ob die Oberfläche eher klassisch oder mit einem weicheren Farbschema angezeigt wird.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Dark Mode
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Dark Mode")
                                    .font(.subheadline)
                                Toggle(
                                    isOn: Binding(
                                        get: { store.darkMode },
                                        set: { val in Task { await store.updatePreferences(darkMode: val) } }
                                    )
                                ) {
                                    Text(store.darkMode ? "Dark Mode aktiviert" : "Dark Mode deaktiviert")
                                }
                            }

                            // Weitere Einstellungen
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Weitere Einstellungen")
                                    .font(.subheadline)

                                Toggle(
                                    isOn: Binding(
                                        get: { store.compactView },
                                        set: { val in Task { await store.updatePreferences(compactView: val) } }
                                    )
                                ) {
                                    Text(
                                        store.compactView
                                        ? "Kompakte Tabellen-Ansicht aktiviert"
                                        : "Kompakte Tabellen-Ansicht deaktiviert"
                                    )
                                }

                                Toggle(
                                    isOn: Binding(
                                        get: { store.animationsEnabled },
                                        set: { val in Task { await store.updatePreferences(animationsEnabled: val) } }
                                    )
                                ) {
                                    Text(
                                        store.animationsEnabled
                                        ? "Animationen aktiviert"
                                        : "Animationen deaktiviert"
                                    )
                                }
                            }
                        }
                    }

                    // Karte: Schuljahr & Prüfungsfächer
                    SettingsCard(
                        title: "Schuljahr",
                        subtitle: "Jahrgangsstufe und Prüfungsfächer festlegen"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Schuljahr
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Jahrgangsstufe")
                                    .font(.subheadline)
                                Text("Wähle deine Jahrgangsstufe. Daraus werden Einbringung und Streichungen abgeleitet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Picker(
                                    "",
                                    selection: Binding(
                                        get: { store.gradeYear ?? 0 },
                                        set: { val in
                                            let year = (val == 12 || val == 13) ? val : 0
                                            if year != 0 {
                                                Task { await store.updateGradeYear(year) }
                                            }
                                        }
                                    )
                                ) {
                                    Text("Bitte auswählen").tag(0)
                                    Text("12. Jahrgang").tag(12)
                                    Text("13. Jahrgang").tag(13)
                                }
                                .pickerStyle(.segmented)
                            }

                            Divider().padding(.vertical, 4)

                            // Prüfungsfächer
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Prüfungsfächer")
                                    .font(.subheadline)
                                Text("Maximal 4 Prüfungsfächer auswählen.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if store.subjects.isEmpty {
                                    Text("Lege zuerst Fächer an, um Prüfungsfächer zu wählen.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(store.subjects, id: \.name) { subject in
                                        ExamSubjectRow(
                                            subject: subject,
                                            isDisabled: !(subject.examSubject ?? false) && currentExamSubjectsCount >= maxExamSubjects,
                                            onToggle: { isOn in
                                                let nextExamType = subject.examType ?? .written
                                                Task {
                                                    await store.updateSubjectExamFlags(
                                                        subjectName: subject.name,
                                                        examSubject: isOn,
                                                        examType: nextExamType
                                                    )
                                                }
                                            }
                                        )
                                    }
                                    if currentExamSubjectsCount >= maxExamSubjects {
                                        Text("Du hast bereits 4 Prüfungsfächer ausgewählt. Entferne eines, um ein anderes Fach als Prüfungsfach zu markieren.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Info-Karte
                    SettingsCard(
                        title: "Info",
                        subtitle: nil
                    ) {
                        Text("App Version 1.4")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            // Native Toolbar ausblenden, da BurgerMenuView den Header übernimmt
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                newName = ""
                nameSavedSuccess = false
            }
            .background(
                Group {
                    NavigationLink(
                        destination: AbiturExamView().environmentObject(store),
                        isActive: $navigateToFinal
                    ) { EmptyView() }
                    NavigationLink(
                        destination: SubjectsManageView().environmentObject(store),
                        isActive: $navigateToSubjects
                    ) { EmptyView() }
                }
            )
        }
    }

    private func saveName() async {
        guard !isSavingName else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingName = true
        await store.updateUserDisplayName(name: trimmed)
        isSavingName = false
        nameSavedSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            nameSavedSuccess = false
        }
        newName = ""
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct ExamSubjectRow: View {
    let subject: Subject
    let isDisabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name).font(.body)
                Text(subject.type == 1 ? "Hauptfach" : "Nebenfach")
                    .font(.caption)
                    .foregroundStyle(subject.type == 1 ? .blue : .secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { subject.examSubject ?? false },
                set: { val in onToggle(val) }
            ))
            .labelsHidden()
            .disabled(isDisabled)
        }
    }
}
