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
    @State private var detailExam: Exam?
    @State private var detailHomework: Homework?
    let data: DailySummaryData
    
    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 26) {
                        headerCard
                        summaryChips
                        
                        if !data.exams.isEmpty {
                            examsSection
                        }
                        
                        if !data.homeworks.isEmpty {
                            homeworksSection
                        }
                        
                        if data.exams.isEmpty && data.homeworks.isEmpty {
                            emptyState
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Tagesübersicht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "checkmark", showDot: false)
                    }
                    .accessibilityLabel("Fertig")
                }
            }
            .sheet(item: $detailExam) { exam in
                ExamDetailSheet(exam: exam, onEdit: { _ in })
            }
            .sheet(item: $detailHomework) { hw in
                HomeworkDetailSheet(homework: hw, onEdit: { _ in })
            }
        }
    }
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Text(formatDate(data.date))
                .font(.system(.title, design: .rounded).weight(.bold))
        }
        .padding(.top, 8)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "GUTEN MORGEN" }
        if hour < 18 { return "GUTEN TAG" }
        return "GUTEN ABEND"
    }

    private var summaryChips: some View {
        HStack(spacing: 14) {
            summaryChip(
                title: data.exams.count == 1 ? "Klausur" : "Klausuren",
                value: data.exams.count,
                accent: examAccent,
                icon: "graduationcap.fill"
            )
            summaryChip(
                title: data.homeworks.count == 1 ? "Hausaufgabe" : "Hausaufgaben",
                value: data.homeworks.count,
                accent: homeworkAccent,
                icon: "pencil.and.outline"
            )
        }
    }
    
    private var examsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Klausuren & Prüfungen",
                subtitle: "\(data.exams.count) Termin\(data.exams.count == 1 ? "" : "e")",
                accent: examAccent,
                icon: "graduationcap.fill"
            )
            VStack(spacing: 12) {
                ForEach(data.exams) { exam in
                    ExamRowView(
                        exam: exam,
                        showActions: false,
                        onTap: { detailExam = exam }
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }
    
    private var homeworksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Hausaufgaben",
                subtitle: "\(data.homeworks.count) Aufgabe\(data.homeworks.count == 1 ? "" : "n")",
                accent: homeworkAccent,
                icon: "book.closed.fill"
            )
            VStack(spacing: 12) {
                ForEach(data.homeworks) { hw in
                    HomeworkRowView(
                        homework: hw,
                        showStatusBadge: false,
                        showCompletionToggle: false,
                        showReminderButton: false,
                        onTap: { detailHomework = hw }
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 64, height: 64)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 6) {
                Text("Alles erledigt")
                    .font(.headline.weight(.bold))
                Text("Für morgen stehen keine Aufgaben oder Klausuren mehr an.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(store.darkMode ? 0.05 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(store.darkMode ? 0.1 : 0.05), lineWidth: 1)
        )
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

    private func sectionHeader(title: String, subtitle: String, accent: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func summaryChip(title: String, value: Int, accent: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(store.darkMode ? 0.08 : 0.04))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(store.darkMode ? 0.1 : 0.05), lineWidth: 1)
                )
        }
    }

    private var examAccent: Color {
        store.theme == "feminine" ? Color(hex: "#f43f5e") : Color(hex: "#0ea5e9")
    }

    private var homeworkAccent: Color {
        store.theme == "feminine" ? Color(hex: "#f97316") : Color(hex: "#f59e0b")
    }

    private var headerGradient: [Color] {
        if store.theme == "feminine" {
            return [Color(hex: "#f472b6"), Color(hex: "#fb7185"), Color(hex: "#f59e0b")]
        }
        return [Color(hex: "#0ea5e9"), Color(hex: "#38bdf8"), Color(hex: "#f59e0b")]
    }

    struct LiftButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
        }
    }

    private let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()
    
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd"
        return formatter
    }()
    
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()
}
