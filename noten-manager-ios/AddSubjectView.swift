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
                                    .onSubmit { hideKeyboard() }
                                    .padding(12)
                                    .background(Color(.secondarySystemBackground))
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
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle("Wahlfach / nicht einbringbar", isOn: $isElective)
                                        .onChange(of: isElective) { newVal in
                                            if newVal { type = 0 }
                                        }
                                    Text("Wahlfächer fließen nicht in die Abschlussnote ein. Für Sport/Musik bitte als Wahlfach markieren.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let error {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            Button {
                                Task { await save() }
                            } label: {
                                if isSaving { ProgressView() } else { Text("Fach speichern") }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemGray6),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Fach anlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Fach anlegen")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
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
        }
        .keyboardDismissToolbar()
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
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
