import SwiftUI

struct FachreferatDetailView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    let subject: Subject
    @State private var showEditSheet: Bool = false

    private var referat: Fachreferat? {
        store.fachreferat
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df
    }

    private func formatGrade(_ grade: Double?) -> String {
        guard let grade else { return "–" }
        return String(format: "%.2f", grade)
    }

    private func gradeColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsCard(
                    title: "Fachreferat",
                    subtitle: referat?.subjectName ?? "Noch nicht eingetragen",
                    systemImage: "doc.text.fill",
                    accent: .pink
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            Text(formatGrade(referat?.grade))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(gradeColor(referat?.grade).opacity(0.16))
                                .foregroundStyle(gradeColor(referat?.grade))
                                .clipShape(Capsule())

                            Spacer()
                        }

                        if let subjectName = referat?.subjectName, !subjectName.isEmpty {
                            Label(subjectName, systemImage: "text.book.closed")
                                .font(.subheadline.weight(.semibold))
                        }

                        if let date = referat?.date {
                            Label(dateFormatter.string(from: date), systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let note = referat?.note, !note.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notiz")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(note)
                                    .font(.body)
                            }
                        }

                        if referat == nil {
                            Text("Es ist noch keine Fachreferat-Note hinterlegt. Lege sie jetzt an.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Fachreferat eintragen") { showEditSheet = true }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.pink.opacity(0.14))
                                .foregroundStyle(Color.pink)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .sheetNavigationTitle("Fachreferat")
        .sheet(isPresented: $showEditSheet) {
            AddFachreferatView(preselectedSubjectName: referat?.subjectName)
                .environmentObject(store)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if referat != nil {
                    Button("Bearbeiten") {
                        showEditSheet = true
                    }
                }
            }
        }
    }
}
