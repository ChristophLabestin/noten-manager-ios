import SwiftUI

struct DailySummaryData: Identifiable {
    let id = UUID()
    let exams: [Exam]
    let homeworks: [Homework]
    let date: Date
}

struct DailySummarySheet: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    let data: DailySummaryData
    
    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        
                        if !data.exams.isEmpty {
                            examsSection
                        }
                        
                        if !data.homeworks.isEmpty {
                            homeworksSection
                        }
                        
                        if data.exams.isEmpty && data.homeworks.isEmpty {
                            ContentUnavailableView(
                                "Alles erledigt",
                                systemImage: "checkmark.circle",
                                description: Text("Für morgen stehen keine Aufgaben oder Klausuren mehr an.")
                            )
                            .padding(.top, 40)
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Tagesübersicht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(formatDate(data.date))
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Das steht morgen an")
                .font(.title2.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
    
    private var examsSection: some View {
        SettingsCard(
            title: "Klausuren & Prüfungen",
            subtitle: "\(data.exams.count) Termin\(data.exams.count == 1 ? "" : "e")",
            systemImage: "graduationcap.fill",
            accent: .indigo
        ) {
            VStack(spacing: 12) {
                ForEach(data.exams) { exam in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exam.title)
                                .font(.subheadline.weight(.bold))
                            if !exam.subjectName.isEmpty {
                                Text(exam.subjectName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if exam.hasTime {
                            Text(formatTime(exam.date))
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.indigo.opacity(0.1))
                                .foregroundStyle(.indigo)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    private var homeworksSection: some View {
        SettingsCard(
            title: "Hausaufgaben",
            subtitle: "\(data.homeworks.count) Aufgabe\(data.homeworks.count == 1 ? "" : "n")",
            systemImage: "book.closed.fill",
            accent: .orange
        ) {
            VStack(spacing: 12) {
                ForEach(data.homeworks) { hw in
                    HStack(spacing: 12) {
                        Image(systemName: hw.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(hw.isCompleted ? .green : .secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hw.title)
                                .font(.subheadline.weight(.semibold))
                                .strikethrough(hw.isCompleted)
                                .foregroundStyle(hw.isCompleted ? .secondary : .primary)
                            
                            if !hw.subjectName.isEmpty {
                                Text(hw.subjectName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
