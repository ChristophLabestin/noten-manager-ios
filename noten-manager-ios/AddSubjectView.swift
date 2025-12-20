import SwiftUI

struct AddSubjectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var name: String = ""
    @State private var type: Int = 1 // 1 = Hauptfach, 0 = Nebenfach
    // Datum hat keine Funktion in der App, daher weggelassen
    @State private var isElective: Bool = false
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var teacher: String = ""
    @State private var room: String = ""
    @State private var alias: String = ""
    @State private var email: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, teacher, room, alias, email
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Fach anlegen",
                        subtitle: "Name, Typ und Wahlfach definieren",
                        systemImage: "book.closed.fill",
                        accent: .cyan
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                Text("Name")
                                    .font(.headline)
                                TextField("z. B. Mathematik", text: $name)
                                    .submitLabel(.done)
                                    .focused($focusedField, equals: .name)
                                    .onSubmit { hideKeyboard() }
                                    .padding(12)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Typ")
                                        .font(.headline)
                                    Picker("", selection: $type) {
                                        Text("Hauptfach").tag(1)
                                        Text("Nebenfach").tag(0)
                                    }
                                    .pickerStyle(.segmented)
                                    .disabled(isElective)

                                    Text("Hauptfach: Schulaufgaben zählen doppelt, Kurzarbeiten und Mündlich / EX einfach.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Text("Nebenfach: Kurzarbeiten zählen doppelt, Mündlich / EX einfach.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle("Wahlfach / nicht einbringbar", isOn: $isElective)
                                        .onChange(of: isElective) { _, newVal in
                                            if newVal { type = 0 }
                                        }
                                    Text("Wahlfächer fließen nicht in die Abschlussnote ein. Für Sport/Musik bitte als Wahlfach markieren.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Details (optional)")
                                        .font(.headline)
                                    detailField("Lehrkraft", text: $teacher, field: .teacher)
                                    detailField("Raum", text: $room, field: .room)
                                    detailField("Kürzel", text: $alias, field: .alias)
                                    detailField("E-Mail", text: $email, field: .email, keyboard: .emailAddress, autocap: .never, autocorrect: false)
                                }
                            }

                            if let error {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .sheetNavigationTitle("Fach anlegen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Speichern") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .keyboardNavigationToolbar(
                focus: $focusedField,
                fields: [.name],
                label: nil,
                onDone: { hideKeyboard() }
            )
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if ["sport", "musik"].contains(lower) && !isElective {
                error = "Bitte markiere Sport oder Musik als nicht einbringbar (Wahlfach)."
                isSaving = false
                return
            }
            try await store.addSubjectToFirestore(
                name: trimmed,
                type: type,
                date: Date(),
                isElective: isElective
            )
            dismiss()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    @ViewBuilder
    private func detailField(_ label: String, text: Binding<String>, field: Field, keyboard: UIKeyboardType = .default, autocap: TextInputAutocapitalization = .sentences, autocorrect: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled(!autocorrect)
                .focused($focusedField, equals: field)
                .padding(12)
                .background(Color.formInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
