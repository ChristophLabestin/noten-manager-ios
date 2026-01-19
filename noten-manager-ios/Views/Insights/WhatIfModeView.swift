import SwiftUI

extension AssessmentType {
    var shortName: String {
        switch self {
        case .schulaufgabe: return "SA"
        case .kurzarbeit: return "KA"
        case .stegreifaufgabe: return "Ex"
        case .muendlich: return "Md"
        case .praktisch: return "Pr"
        case .projekt: return "Pj"
        }
    }
}

struct WhatIfModeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var activeSubjectForAdd: SubjectIdentifier? = nil
    @State private var expandedSubjects: Set<String> = []
    
    struct SubjectIdentifier: Identifiable {
        let id: String
        var name: String { id }
    }

    private var currentAverage: Double? {
        overallAverage(using: realGradesAsGradeDict())
    }

    private var simulatedAverage: Double? {
        overallAverage(using: combinedGrades())
    }

    private var deltaAverage: Double? {
        guard let curr = currentAverage, let sim = simulatedAverage else { return nil }
        return sim - curr
    }

    private var filteredSubjects: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    WhatIfHeaderCard(
                        currentAverage: currentAverage,
                        simulatedAverage: simulatedAverage ?? currentAverage,
                        deltaAverage: deltaAverage,
                        includeDroppedGrades: $store.includeDroppedGrades,
                        animationsEnabled: store.animationsEnabled
                    )

                    let realDict = realGradesAsGradeDict()
                    let simDict = combinedGrades()

                    VStack(spacing: 12) {
                        ForEach(Array(filteredSubjects.enumerated()), id: \.element.name) { index, subject in
                            makeSubjectRow(index: index, subject: subject, realDict: realDict, simDict: simDict)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        withAnimation {
                            store.clearGradeSimulations()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .imageScale(.medium)
                            .foregroundStyle(.pink)
                    }
                }
            }
            .sheet(item: $activeSubjectForAdd) { item in
                let name = item.name
                AddGhostGradeSheet(
                    subjectName: name,
                    gradingMode: store.subjects.first(where: { $0.name == name })?.gradingMode ?? .withSchulaufgaben,
                    onAdd: { grade, weight, isCustom, halfYear, type in
                        let entry = SimulatedGradeEntry(
                            subjectName: name,
                            grade: grade,
                            weight: weight,
                            assessmentType: type,
                            isCustomWeight: isCustom,
                            halfYear: halfYear
                        )
                        store.simulatedGrades.append(entry)
                    }
                )
                .environmentObject(store)
                .presentationBackground {
                    ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                }
                .presentationDetents([.large])
            }
        }
    }
    
    // MARK: - Data Conversion

    private func realGradesAsGradeDict() -> [String: [Grade]] {
        store.gradesBySubject.mapValues { list in
            list.map { g in
                Grade(
                    grade: g.grade,
                    weight: g.weight,
                    date: g.date,
                    note: g.note,
                    halfYear: g.halfYear,
                    linkedExamId: g.linkedExamId,
                    assessmentType: g.assessmentType
                )
            }
        }
    }

    private func combinedGrades() -> [String: [Grade]] {
        var result: [String: [Grade]] = [:]
        
        for subject in store.subjects {
            let real = store.gradesBySubject[subject.name] ?? []
            let filteredReal = real.filter { !store.excludedRealGradeIds.contains($0.id) }
            
            let ghostEntries = store.simulatedGrades.filter { $0.subjectName == subject.name }
            let ghostGrades = ghostEntries.map { entry in
                Grade(
                    grade: entry.grade,
                    weight: entry.weight,
                    date: entry.createdAt,
                    note: nil,
                    halfYear: entry.halfYear ?? 1,
                    linkedExamId: nil,
                    assessmentType: entry.assessmentType
                )
            }
            
            result[subject.name] = filteredReal.map { Grade(
                grade: $0.grade,
                weight: $0.weight,
                date: $0.date,
                note: $0.note,
                halfYear: $0.halfYear,
                linkedExamId: $0.linkedExamId,
                assessmentType: $0.assessmentType
            )} + ghostGrades
        }
        
        return result
    }

    // MARK: - Helpers

    private func subjectAverage(_ subject: Subject, using dict: [String: [Grade]]) -> Double? {
        let list = dict[subject.name] ?? []
        return GradeCalculationService.calculateSubjectAverage(
            subject: subject,
            grades: list,
            dropValue: store.includeDroppedGrades ? nil : subject.droppedHalfYear,
            effectiveGradeWeight: { [store] in store.effectiveGradeWeight(subjectType: $0, rawWeight: $1) }
        )
    }

    private func overallAverage(using dict: [String: [Grade]]) -> Double? {
        GradeCalculationService.calculateOverallAverage(
            subjects: store.subjects,
            halfYearValueProvider: { subject, halfYear in
                let grades = dict[subject.name] ?? []
                return GradeCalculationService.calculateHalfYearAverage(
                    grades: grades,
                    subject: subject,
                    halfYear: halfYear,
                    effectiveGradeWeight: { [store] in store.effectiveGradeWeight(subjectType: $0, rawWeight: $1) }
                )
            },
            droppedHalfYearProvider: { subject in
                store.includeDroppedGrades ? nil : subject.droppedHalfYear
            },
            halfYearFilter: nil,
            fachreferat: store.fachreferat,
            seminar: store.seminarPerformance,
            practical: store.practicalPerformance,
            examPoints: store.examPoints,
            schoolType: store.schoolType,
            gradeYear: store.gradeYear ?? 12
        )
    }

    private func makeSubjectRow(index: Int, subject: Subject, realDict: [String: [Grade]], simDict: [String: [Grade]]) -> some View {
        SubjectWhatIfRow(
            subject: subject,
            currentAvg: subjectAverage(subject, using: realDict),
            simulatedAvg: subjectAverage(subject, using: simDict),
            simulatedGrades: store.simulatedGrades.filter { $0.subjectName == subject.name },
            realGrades: store.gradesBySubject[subject.name] ?? [] ,
            excludedIds: store.excludedRealGradeIds,
            isExpanded: expandedSubjects.contains(subject.name),
            onToggleExpand: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if expandedSubjects.contains(subject.name) {
                        expandedSubjects.remove(subject.name)
                    } else {
                        expandedSubjects.insert(subject.name)
                    }
                }
            },
            onAddGhost: { activeSubjectForAdd = SubjectIdentifier(id: subject.name) },
            onRemoveGhost: { id in store.simulatedGrades.removeAll { $0.id == id } },
            onToggleReal: { id in
                if store.excludedRealGradeIds.contains(id) {
                    store.excludedRealGradeIds.remove(id)
                } else {
                    store.excludedRealGradeIds.insert(id)
                }
            }
        )
        .softFadeIn(enabled: store.animationsEnabled, delay: 0.1 + Double(index) * 0.03)
    }
}


// MARK: - Subviews

struct WhatIfHeaderCard: View {
    let currentAverage: Double?
    let simulatedAverage: Double?
    let deltaAverage: Double?
    @Binding var includeDroppedGrades: Bool
    let animationsEnabled: Bool

    var body: some View {
        SettingsCard(
            title: "Simulation",
            subtitle: "Fiktive Noten ausprobieren",
            systemImage: "wand.and.stars",
            accent: .pink
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    StatChip(title: "Aktuell", value: formatAverage(currentAverage), accent: .indigo)
                    StatChip(title: "Simulation", value: formatAverage(simulatedAverage), accent: .secondary)
                    StatChip(title: "Δ", value: formatDelta(deltaAverage), accent: .orange)
                }
                
                SettingsSectionBox {
                    Toggle(isOn: $includeDroppedGrades.animation(.spring(response: 0.35, dampingFraction: 0.8))) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gestrichene HJE einbeziehen")
                                    .font(.subheadline.weight(.semibold))
                                Text("FOBOSO Streichungen ignorieren")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .foregroundStyle(.pink)
                        }
                    }
                    .tint(.pink)
                    .padding(.vertical, 4)
                }
                
                Text("Tippe auf ein Fach, um Noten hinzuzufügen oder vorhandene auszuschließen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .softFadeIn(enabled: animationsEnabled, delay: 0.05)
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.2f", value)
    }

    private func formatDelta(_ value: Double?) -> String {
        guard let value else { return "0,00" }
        let prefix = value > 0 ? "+" : ""
        return prefix + String(format: "%.2f", value)
    }
}

private func avgColor(_ v: Double?, privacyActive: Bool = false) -> Color {
    if privacyActive { return .primary }
    guard let v else { return .secondary }
    if v >= 7 { return .green }
    if v >= 4 { return .orange }
    return .red
}

struct SubjectWhatIfRow: View {
    let subject: Subject
    let currentAvg: Double?
    let simulatedAvg: Double?
    let simulatedGrades: [SimulatedGradeEntry]
    let realGrades: [GradeWithId]
    let excludedIds: Set<String>
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onAddGhost: () -> Void
    let onRemoveGhost: (UUID) -> Void
    let onToggleReal: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: GradesStore

    var body: some View {
        VStack(spacing: 0) {
            // Main Row Area
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    

                    Text(store.gradingMode(for: subject) == .withSchulaufgaben ? "Schulaufgaben" : "Keine Schulaufgaben")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(formatAvg(currentAvg))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                        
                        Text(formatAvg(simulatedAvg))
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(avgColor(simulatedAvg, privacyActive: store.isPrivacyModeActive))
                    }
                    
                    let delta = (simulatedAvg ?? 0) - (currentAvg ?? 0)
                    if abs(delta) > 0.001 {
                        Text((delta > 0 ? "+" : "") + String(format: "%.2f", delta))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(delta > 0 ? .green : .pink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((delta > 0 ? Color.green : Color.pink).opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleExpand()
            }
            
            if isExpanded {
                VStack(spacing: 12) {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Ghost Grades Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Fiktive Noten", systemImage: "sparkles")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.pink)
                                Spacer()
                                Button(action: onAddGhost) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.caption.weight(.bold))
                                        Text("Hinzufügen")
                                            .font(.caption.weight(.bold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.pink.opacity(0.1))
                                    .foregroundStyle(.pink)
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 16)
                            
                            if simulatedGrades.isEmpty {
                                Text("Noch keine fiktiven Noten")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 4)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(simulatedGrades) { grade in
                                        SimulatedGradeRow(grade: grade, privacyActive: store.isPrivacyModeActive, onRemove: { onRemoveGhost(grade.id) })
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        
                        // Real Grades Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Reale Noten ausschließen")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                            
                            if realGrades.isEmpty {
                                Text("Keine realen Noten")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(realGrades) { grade in
                                        RealGradeRow(
                                            grade: grade,
                                            isExcluded: excludedIds.contains(grade.id),
                                            onToggle: { onToggleReal(grade.id) }
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.formSectionBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.03), radius: 5, x: 0, y: 2)
    }

    private func formatAvg(_ v: Double?) -> String {
        guard let v else { return "-" }
        return String(format: "%.2f", v)
    }
}

struct SimulatedGradeRow: View {
    let grade: SimulatedGradeEntry
    let privacyActive: Bool
    let onRemove: () -> Void
    
    private var accentColor: Color {
        avgColor(grade.grade, privacyActive: privacyActive)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%.0f", grade.grade))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .frame(width: 32, height: 32)
                .background(accentColor.opacity(0.15))
                .foregroundStyle(accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(grade.assessmentType?.prettyName ?? "Sonstige")
                    .font(.subheadline.weight(.bold))
                HStack(spacing: 8) {
                    Label(String(format: "%.1fx", grade.weight), systemImage: "scalemass")
                    Label("\(grade.halfYear ?? 1). Hj", systemImage: "calendar")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.8))
                    .padding(8)
                    .background(accentColor.opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding(10)
        .background(accentColor.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RealGradeRow: View {
    let grade: GradeWithId
    let isExcluded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%.0f", grade.grade))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .strikethrough(isExcluded)
                .frame(width: 32, height: 32)
                .background(isExcluded ? Color.secondary.opacity(0.12) : Color.indigo.opacity(0.15))
                .foregroundStyle(isExcluded ? Color.secondary : Color.indigo)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(grade.assessmentType?.prettyName ?? "Note")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isExcluded ? .secondary : .primary)
                HStack(spacing: 8) {
                    Text(grade.date.formatted(date: .abbreviated, time: .omitted))
                    if let note = grade.note, !note.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onToggle) {
                Image(systemName: isExcluded ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isExcluded ? Color.secondary : Color.indigo)
                    .padding(8)
                    .background((isExcluded ? Color.secondary : Color.indigo).opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding(10)
        .background((isExcluded ? Color.secondary : Color.indigo).opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isExcluded ? 0.7 : 1)
    }
}

// MARK: - Add Ghost Grade Sheet

struct AddGhostGradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let subjectName: String
    let gradingMode: GradingMode
    var onAdd: (Double, Double, Bool, Int?, AssessmentType?) -> Void
    
    @State private var grade: Int = 10
    @State private var assessmentType: AssessmentType = .muendlich
    @State private var selectedHalfYear: Int = 1
    
    private let points = Array(0...15).reversed()
    private let columns = [
        GridItem(.flexible()), GridItem(.flexible()),
        GridItem(.flexible()), GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Points Selection
                    SettingsCard(
                        title: "Punkte wählen",
                        subtitle: "Wie viele Punkte simulierst du?",
                        systemImage: "target",
                        accent: .pink
                    ) {
                        VStack(spacing: 12) {
                            // Current Selection Display
                            Text("\(grade)")
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundStyle(.pink)
                                .frame(width: 60, height: 60)
                                .background(.pink.opacity(0.1))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.pink.opacity(0.2), lineWidth: 1.5))
                            
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(0...15, id: \.self) { val in
                                    Button {
                                        grade = val
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    } label: {
                                        Text("\(val)")
                                            .font(.subheadline.weight(.semibold).monospacedDigit())
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 36)
                                            .background(grade == val ? Color.pink : Color.secondary.opacity(0.1))
                                            .foregroundStyle(grade == val ? .white : .primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Category Selection
                    SettingsCard(
                        title: "Kategorie & Halbjahr",
                        subtitle: "Details der Simulation",
                        systemImage: "list.bullet.indent",
                        accent: .pink
                    ) {
                        VStack(spacing: 16) {
                            // assessment type
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Leistungsart", systemImage: "tag.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                
                                Picker("Typ", selection: $assessmentType) {
                                    if gradingMode == .withSchulaufgaben {
                                        Text("Schulaufgabe").tag(AssessmentType.schulaufgabe)
                                    }
                                    Text("Kurzarbeit").tag(AssessmentType.kurzarbeit)
                                    Text("Mündlich / EX").tag(AssessmentType.muendlich)
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            Divider().opacity(0.5)
                            
                            // Half year
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Halbjahr", systemImage: "calendar")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                
                                Picker("Halbjahr", selection: $selectedHalfYear) {
                                    Text("1. Halbjahr").tag(1)
                                    Text("2. Halbjahr").tag(2)
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                    
                    Button {
                        let w = assessmentType == .schulaufgabe ? 2.0 : 1.0
                        onAdd(Double(grade), w, false, selectedHalfYear, assessmentType)
                        dismiss()
                    } label: {
                        HStack {
                            Text("Simulation hinzufügen")
                            Image(systemName: "plus.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .pink, font: .headline.weight(.bold), verticalPadding: 16))
                    
                    Text("Simulierte Noten sind nur lokal und beeinflussen nicht deine echten Daten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .navigationTitle("Neue Simulation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
        }
    }
}
