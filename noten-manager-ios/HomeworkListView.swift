import SwiftUI

struct HomeworkListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var visibleInactiveCount: Int = 5
    @State private var editingHomework: Homework? = nil
    @State private var homeworkToDelete: Homework? = nil

    private var activeHomeworks: [Homework] {
        store.homeworks.filter { $0.isActive }.sorted {
            let a = $0.dueDate ?? $0.createdAt
            let b = $1.dueDate ?? $1.createdAt
            return a < b
        }
    }

    private var inactiveHomeworks: [Homework] {
        store.homeworks.filter { !$0.isActive }.sorted {
            let a = $0.dueDate ?? $0.createdAt
            let b = $1.dueDate ?? $1.createdAt
            return a > b
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Aktive Hausaufgaben") {
                    if activeHomeworks.isEmpty {
                        Text("Du hast aktuell keine aktiven Hausaufgaben.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeHomeworks) { hw in
                            homeworkRow(hw)
                        }
                    }
                }

                if !inactiveHomeworks.isEmpty {
                    Section("Erledigt / überfällig") {
                        ForEach(Array(inactiveHomeworks.prefix(visibleInactiveCount))) { hw in
                            homeworkRow(hw, isInactiveSection: true)
                        }

                        if inactiveHomeworks.count > visibleInactiveCount {
                            Button {
                                visibleInactiveCount += 5
                            } label: {
                                Text("Weitere 5 anzeigen")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hausaufgaben")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onAppear {
                visibleInactiveCount = 5
            }
            .sheet(item: $editingHomework) { hw in
                EditHomeworkView(homework: hw)
                    .environmentObject(store)
            }
            .alert(
                "Hausaufgabe löschen?",
                isPresented: Binding(
                    get: { homeworkToDelete != nil },
                    set: { newValue in
                        if !newValue {
                            homeworkToDelete = nil
                        }
                    }
                )
            ) {
                Button("Löschen", role: .destructive) {
                    if let hw = homeworkToDelete {
                        Task { await deleteHomework(hw) }
                    }
                }
                Button("Abbrechen", role: .cancel) {
                    homeworkToDelete = nil
                }
            } message: {
                Text("Diese Hausaufgabe wird dauerhaft gelöscht.")
            }
        }
    }

    @ViewBuilder
    private func homeworkRow(_ hw: Homework, isInactiveSection: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(hw.title)
                    .font(.body)
                    .lineLimit(2)
                if !hw.subjectName.isEmpty {
                    Text(hw.subjectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let due = hw.dueDate {
                    Text("Fällig am \(formattedDate(due))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kein Fälligkeitsdatum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                if !isInactiveSection && !hw.isCompleted {
                    Button {
                        Task { await markCompleted(hw) }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Als erledigt markieren")
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }

                Button {
                    editingHomework = hw
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .regular))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hausaufgabe bearbeiten")

                Button {
                    homeworkToDelete = hw
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hausaufgabe löschen")
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func markCompleted(_ hw: Homework) async {
        await store.setHomeworkCompleted(id: hw.id, completed: true)
    }

    private func deleteHomework(_ hw: Homework) async {
        await store.deleteHomeworkFromFirestore(id: hw.id)
        homeworkToDelete = nil
    }
}
