import SwiftUI
import CryptoKit

struct PraktikumDetailView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet: Bool = false
    @State private var editingEntry: PracticalGradeEntry?
    @State private var entryToDelete: PracticalGradeEntry?
    @State private var showDeleteAllAlert: Bool = false
    @State private var isWorking: Bool = false
    @State private var error: String?

    private var sortedPracticalGrades: [PracticalGradeEntry] {
        let entries = store.practicalPerformance?.grades ?? []
        return entries.sorted { lhs, rhs in
            if let lh = lhs.halfYear, let rh = rhs.halfYear, lh != rh {
                return lh < rh
            }
            if lhs.halfYear != nil, rhs.halfYear == nil { return true }
            if lhs.halfYear == nil, rhs.halfYear != nil { return false }
            return lhs.date < rhs.date
        }
    }

    private var average: Double? {
        guard !sortedPracticalGrades.isEmpty else { return nil }
        let total = sortedPracticalGrades.reduce(0.0) { $0 + $1.grade }
        return total / Double(sortedPracticalGrades.count)
    }

    private var canManage: Bool {
        store.schoolType == .fos && store.encryptionKey != nil
    }

    private var nextHalfYearSuggestion: Int {
        if !sortedPracticalGrades.contains(where: { $0.halfYear == 1 }) { return 1 }
        if !sortedPracticalGrades.contains(where: { $0.halfYear == 2 }) { return 2 }
        return 1
    }

    private var statusText: String {
        if store.schoolType != .fos {
            return "Praktikumsnoten sind nur für die FOS relevant."
        }
        if store.encryptionKey == nil {
            return "Daten werden entsperrt …"
        }
        if sortedPracticalGrades.count == 2 {
            return "Beide Praktikumsnoten sind erfasst. Der Schnitt fließt in die Abschlussnote ein."
        }
        if sortedPracticalGrades.count == 1 {
            return "Eine Praktikumsnote ist gespeichert. Trage die zweite ein, sobald sie vorliegt."
        }
        return "Trage die erste Praktikumsnote ein. Maximal zwei Noten (1. und 2. Halbjahr) sind möglich."
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                SettingsCard(
                    title: "Praktikum",
                    subtitle: "Fachpraktische Ausbildung",
                    systemImage: "briefcase.fill",
                    accent: .orange,
                    trailing: {
                        if let avg = average {
                            PillBadge(
                                text: String(format: "%.2f", avg),
                                systemImage: "chart.bar.doc.horizontal",
                                foreground: gradeColor(avg),
                                background: gradeColor(avg).opacity(0.16)
                            )
                        }
                    }
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let avg = average {
                            HStack(spacing: 10) {
                                Text("Durchschnitt")
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "%.2f", avg))
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(gradeColor(avg).opacity(0.16))
                                    .foregroundStyle(gradeColor(avg))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                SettingsCard(
                    title: "Praktikumsnoten",
                    subtitle: nil,
                    systemImage: "list.bullet.rectangle.portrait.fill",
                    accent: .orange,
                    trailing: {
                        if canManage {
                            Button {
                                showAddSheet = true
                            } label: {
                                Label("Neu", systemImage: "plus")
                            }
                            .buttonStyle(TinyTintButtonStyle(accent: .orange))
                        }
                    }
                ) {
                    if sortedPracticalGrades.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Keine Praktikumsnoten gespeichert.")
                                .font(.subheadline.weight(.semibold))
                            Text("Lege die erste Note an. Du kannst später die zweite ergänzen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if canManage {
                                Button {
                                    showAddSheet = true
                                } label: {
                                    Text("Praktikumsnote hinzufügen")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .orange))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(sortedPracticalGrades) { entry in
                                gradeRow(entry)
                            }
                        }
                    }
                }

                if !sortedPracticalGrades.isEmpty, canManage {
                    Button(role: .destructive) {
                        showDeleteAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Alle Praktikumsnoten löschen")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .red))
                }

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .sheetNavigationTitle("Praktikum")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }
                    .disabled(isWorking)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if canManage {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(isWorking)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                AddPraktikumGradeView(preselectedHalfYear: nextHalfYearSuggestion)
                    .environmentObject(store)
            }
        }
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                EditPraktikumGradeView(entry: entry)
                    .environmentObject(store)
            }
        }
        .alert("Praktikumsnote löschen?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { newValue in
                if !newValue { entryToDelete = nil }
            })
        ) {
            Button("Löschen", role: .destructive) {
                if let entry = entryToDelete {
                    Task { await delete(entry) }
                }
            }
            Button("Abbrechen", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            Text("Diese Praktikumsnote wird dauerhaft gelöscht.")
        }
        .alert("Alle Praktikumsnoten löschen?", isPresented: $showDeleteAllAlert) {
            Button("Löschen", role: .destructive) {
                Task { await deleteAllEntries() }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Beide gespeicherten Praktikumsnoten werden entfernt.")
        }
        .disabled(isWorking)
    }

    @ViewBuilder
    private func gradeRow(_ entry: PracticalGradeEntry) -> some View {
        let tint = gradeColor(entry.grade)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label(for: entry))
                        .font(.headline)
                    if let company = entry.company, !company.isEmpty {
                        Label(company, systemImage: "building.2")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Label(dateFormatter.string(from: entry.date), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(String(format: "%.1f", entry.grade))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(tint.opacity(0.16))
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                    if let hy = entry.halfYear {
                        Text("\(hy). Halbjahr")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if canManage {
                HStack {
                    actionButton(icon: "slider.horizontal.3", tint: .orange, label: "Bearbeiten") {
                        editingEntry = entry
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color.formInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            editingEntry = entry
        }
        .swipeActions {
            if canManage {
                Button(role: .destructive) {
                    entryToDelete = entry
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
        .disabled(isWorking)
    }

    private func label(for entry: PracticalGradeEntry) -> String {
        if let hy = entry.halfYear {
            return hy == 1 ? "1. Praktikum" : "2. Praktikum"
        }
        return "Praktikum"
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        df.locale = .autoupdatingCurrent
        df.calendar = .autoupdatingCurrent
        return df
    }

    private func gradeColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    private func delete(_ entry: PracticalGradeEntry) async {
        guard let key = store.encryptionKey else {
            error = "Schlüssel noch nicht geladen."
            return
        }
        await MainActor.run {
            isWorking = true
            error = nil
        }
        do {
            try await store.deletePracticalGrade(id: entry.id, using: key)
            await MainActor.run {
                entryToDelete = nil
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
        await MainActor.run {
            isWorking = false
        }
    }

    private func deleteAllEntries() async {
        await MainActor.run {
            isWorking = true
            error = nil
        }
        do {
            try await store.deletePracticalPerformance()
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
        await MainActor.run {
            isWorking = false
            showDeleteAllAlert = false
        }
    }

    private func actionButton(icon: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private struct TinyTintButtonStyle: ButtonStyle {
        var accent: Color

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.footnote.weight(.semibold))
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(accent.opacity(0.12))
                .foregroundStyle(accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
                .opacity(configuration.isPressed ? 0.9 : 1.0)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
