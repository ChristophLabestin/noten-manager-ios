import SwiftUI

struct SimulatedGradeEntry: Identifiable, Equatable {
    let id = UUID()
    let subjectName: String
    let grade: Double
    let weight: Double
    let isCustomWeight: Bool
    let halfYear: Int?
    let createdAt: Date
}

struct WhatIfModeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var simulatedGrades: [SimulatedGradeEntry] = []
    @State private var subjectName: String = ""
    @State private var gradeText: String = ""
    @State private var weightChoice: WeightChoice = .preset(0)
    @State private var customWeightText: String = ""
    @State private var halfYearSelection: Int = 0
    @State private var error: String?
    @State private var excludedRealGradeIds: Set<String> = []
    @FocusState private var focusedField: Field?

    private enum WeightChoice: Hashable {
        case preset(Double)
        case custom
    }

    private enum Field: Hashable {
        case grade
        case customWeight
    }

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
    }

    private var gradingMode: GradingMode {
        let subj = subjects.first(where: { $0.name == subjectName })
        return subj?.gradingMode ?? ((subj?.type == 1) ? .withSchulaufgaben : .withoutSchulaufgaben)
    }

    private var currentAverage: Double? {
        overallAverage(using: realGradesBySubject)
    }

    private var simulatedAverage: Double? {
        overallAverage(using: whatIfGradesBySubject)
    }

    private var deltaAverage: Double? {
        guard let simulatedAverage else { return nil }
        guard let currentAverage else { return simulatedAverage }
        return simulatedAverage - currentAverage
    }

    private var realGradesBySubject: [String: [Grade]] {
        var dict: [String: [Grade]] = [:]
        for (key, list) in store.gradesBySubject {
            dict[key] = list.map {
                Grade(
                    grade: $0.grade,
                    weight: $0.weight,
                    date: $0.date,
                    note: $0.note,
                    halfYear: $0.halfYear,
                    linkedExamId: $0.linkedExamId
                )
            }
        }
        return dict
    }

    private var whatIfGradesBySubject: [String: [Grade]] {
        var dict: [String: [Grade]] = [:]
        
        // 1. Add real grades, but filter out excluded ones
        for (subjectName, list) in store.gradesBySubject {
            let filtered = list.compactMap { gw -> Grade? in
                if excludedRealGradeIds.contains(gw.id) { return nil }
                return Grade(
                    grade: gw.grade,
                    weight: gw.weight,
                    date: gw.date,
                    note: gw.note,
                    halfYear: gw.halfYear,
                    linkedExamId: gw.linkedExamId
                )
            }
            dict[subjectName] = filtered
        }
        
        // 2. Add simulated grades
        for entry in simulatedGrades {
            let grade = Grade(
                grade: entry.grade,
                weight: entry.weight,
                date: entry.createdAt,
                note: nil,
                halfYear: entry.halfYear,
                linkedExamId: nil
            )
            dict[entry.subjectName, default: []].append(grade)
        }
        return dict
    }

    private var subjectsWithSimulation: [Subject] {
        let names = Set(simulatedGrades.map { $0.subjectName })
        let excludedNames = Set(excludedGradesWithSubject.map { $0.subjectName })
        let allNames = names.union(excludedNames)
        return subjects.filter { allNames.contains($0.name) }
    }

    private var excludedGradesWithSubject: [(subjectName: String, grade: GradeWithId)] {
        var result: [(subjectName: String, grade: GradeWithId)] = []
        for (subjectName, grades) in store.gradesBySubject {
            for g in grades {
                if excludedRealGradeIds.contains(g.id) {
                    result.append((subjectName, g))
                }
            }
        }
        return result.sorted(by: { $0.grade.date > $1.grade.date })
    }

    private var canAdd: Bool {
        !subjects.isEmpty && parsedGrade() != nil && resolvedWeight() != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Was-wäre-wenn-Modus",
                        subtitle: "Fiktive Noten ausprobieren, ohne sie zu speichern",
                        systemImage: "wand.and.stars",
                        accent: .pink
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                StatChip(title: "Aktueller Ø", value: formatAverage(currentAverage), accent: .indigo)
                                StatChip(title: "Was-wäre-wenn", value: formatAverage(simulatedAverage ?? currentAverage), accent: .pink)
                                StatChip(title: "Δ", value: formatDelta(deltaAverage), accent: .orange)
                            }
                            Text("Die hier eingetragenen Noten werden nicht hochgeladen, beeinflussen deine echten Noten nicht und verschwinden, wenn du den Modus schließt.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsCard(
                        title: "Fiktive Note erfassen",
                        subtitle: "Wirkt nur in dieser Ansicht",
                        systemImage: "plus.circle.fill",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Fach")
                                        .font(.headline)
                                    Picker("Fach", selection: $subjectName) {
                                        ForEach(subjects, id: \.name) { subject in
                                            Text(subject.name).tag(subject.name)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.primary)
                                    .padding(10)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    if subjects.isEmpty {
                                        Text("Lege zuerst ein Fach an, um Noten zu simulieren.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Note & Gewichtung")
                                        .font(.headline)

                                    TextField("Note (0–15)", text: $gradeText)
                                        .keyboardType(.decimalPad)
                                        .padding(12)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .focused($focusedField, equals: .grade)

                                    Menu {
                                                ForEach(weightOptions(for: gradingMode), id: \.title) { option in
                                                    let isSelected: Bool = {
                                                        if case .preset(let value) = weightChoice {
                                                            return value == option.value
                                                        }
                                                        return false
                                            }()
                                            Button {
                                                weightChoice = .preset(option.value)
                                            } label: {
                                                HStack {
                                                    Text(option.title)
                                                    if isSelected {
                                                        Spacer()
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }

                                        Divider()

                                        let isCustomSelected = {
                                            if case .custom = weightChoice { return true }
                                            return false
                                        }()
                                        Button {
                                            weightChoice = .custom
                                        } label: {
                                            HStack {
                                                Text("Sonstige Leistung")
                                                if isCustomSelected {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    } label: {
                                        HStack {
                                                Text(selectedWeightLabel(for: gradingMode))
                                                    .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .tint(.primary)

                                    if case .custom = weightChoice {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Gewichtung")
                                                .font(.subheadline)
                                            TextField("Gewichtung z. B. 1 oder 2.5", text: $customWeightText)
                                                .keyboardType(.decimalPad)
                                                .padding(12)
                                                .background(Color.formInputBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                .focused($focusedField, equals: .customWeight)
                                            Text("Die eingetragene Gewichtung wird genau so in den simulierten Durchschnitt übernommen.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        let weightInfo: String = {
                                            if gradingMode == .withSchulaufgaben {
                                                return "Schulaufgaben zählen doppelt, Kurzarbeiten und Mündlich / EX einfach."
                                            }
                                            return "Kurzarbeiten zählen doppelt, Mündlich / EX einfach."
                                        }()
                                        Text(weightInfo)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Halbjahr")
                                            .font(.subheadline)
                                        Picker("", selection: $halfYearSelection) {
                                            Text("Keins").tag(0)
                                            Text("1. Hj").tag(1)
                                            Text("2. Hj").tag(2)
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                }
                            }

                            if let error {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            Button {
                                addSimulatedGrade()
                            } label: {
                                Label("Zur Simulation hinzufügen", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                            .disabled(!canAdd)
                        }
                    }

                    let realGradesForSubject = store.gradesBySubject[subjectName] ?? []
                    if !realGradesForSubject.isEmpty {
                        SettingsCard(
                            title: "Vorhandene Noten anpassen",
                            subtitle: "Tippe, um Noten testweise auszuschließen",
                            systemImage: "checklist",
                            accent: .blue
                        ) {
                            SettingsSectionBox {
                                VStack(spacing: 1) {
                                    let sortedReal = realGradesForSubject.sorted(by: { $0.date > $1.date })
                                    let gm = gradingMode
                                    ForEach(sortedReal) { gw in
                                        let isExcluded = excludedRealGradeIds.contains(gw.id)
                                        Button {
                                            if isExcluded {
                                                excludedRealGradeIds.remove(gw.id)
                                            } else {
                                                excludedRealGradeIds.insert(gw.id)
                                            }
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("Note \(formatGrade(gw.grade))")
                                                            .font(.subheadline.weight(.semibold))
                                                            .strikethrough(isExcluded)
                                                        Text(weightLabel(for: gw.weight, isCustom: false, gradingMode: gm))
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Image(systemName: isExcluded ? "eye.slash" : "eye")
                                                    .font(.caption)
                                                    .foregroundStyle(isExcluded ? .red : .blue)
                                            }
                                            .padding(.vertical, 8)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .opacity(isExcluded ? 0.5 : 1.0)
                                        
                                        if gw.id != sortedReal.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard(
                        title: "Anpassungen & Simulationen",
                        subtitle: "Zusammenfassung aller Änderungen",
                        systemImage: "tray.full.fill",
                        accent: .orange
                    ) {
                        if simulatedGrades.isEmpty && excludedRealGradeIds.isEmpty {
                            Text("Noch keine Anpassungen vorgenommen. Ergänze oben eine Note oder schließe eine vorhandene aus.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            SettingsSectionBox {
                                VStack(spacing: 8) {
                                    // 1. Show Excluded Grades
                                    ForEach(excludedGradesWithSubject, id: \.grade.id) { item in
                                        HStack(alignment: .top, spacing: 10) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 6) {
                                                    Text(item.subjectName)
                                                        .font(.subheadline.weight(.semibold))
                                                    Text("Entfernt")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.red.opacity(0.15))
                                                        .foregroundStyle(.red)
                                                        .clipShape(Capsule())
                                                }
                                                Text("Note \(formatGrade(item.grade.grade)) · \(weightLabel(for: item.grade.weight, isCustom: false, gradingMode: gradingModeForName(item.subjectName)))\(halfYearLabel(for: item.grade.halfYear))")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .strikethrough()
                                            }
                                            Spacer()
                                            Button {
                                                excludedRealGradeIds.remove(item.grade.id)
                                            } label: {
                                                Image(systemName: "arrow.uturn.backward")
                                                    .font(.caption2)
                                                    .foregroundStyle(.blue)
                                                    .padding(8)
                                                    .background(Color.blue.opacity(0.1))
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                    }

                                    // 2. Show Simulated Grades
                                    ForEach(simulatedGrades) { entry in
                                        HStack(alignment: .top, spacing: 10) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 6) {
                                                    Text(entry.subjectName)
                                                        .font(.subheadline.weight(.semibold))
                                                    Text("Hinzugefügt")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.green.opacity(0.15))
                                                        .foregroundStyle(.green)
                                                        .clipShape(Capsule())
                                                }
                                                Text("Note \(formatGrade(entry.grade)) · \(weightLabel(for: entry.weight, isCustom: entry.isCustomWeight, gradingMode: gradingModeForName(entry.subjectName)))\(halfYearLabel(for: entry.halfYear))")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button {
                                                remove(entry)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption2)
                                                    .foregroundStyle(.red)
                                                    .padding(8)
                                                    .background(Color.red.opacity(0.1))
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if !subjectsWithSimulation.isEmpty {
                        SettingsCard(
                            title: "Auswirkung nach Fach",
                            subtitle: "Aktueller vs. simuliert",
                            systemImage: "chart.line.uptrend.xyaxis",
                            accent: .cyan
                        ) {
                            SettingsSectionBox {
                                VStack(spacing: 10) {
                                    ForEach(subjectsWithSimulation, id: \.name) { subject in
                                        let current = subjectAverage(subject, using: realGradesBySubject)
                                        let simulated = subjectAverage(subject, using: whatIfGradesBySubject)
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(subject.name)
                                                    .font(.subheadline.weight(.semibold))
                                                Text("Aktuell \(formatAverage(current)) · Was-wäre-wenn \(formatAverage(simulated))")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(formatDelta(simulated.flatMap { sim in
                                                if let current { return sim - current }
                                                return sim
                                            }))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.cyan)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.cyan.opacity(0.15))
                                            .clipShape(Capsule())
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .sheetNavigationTitle("Was-wäre-wenn")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
            .keyboardNavigationToolbar(
                focus: $focusedField,
                fields: [.grade, .customWeight],
                label: nil,
                onDone: { hideKeyboard() }
            )
            .onAppear {
                if subjectName.isEmpty {
                    subjectName = subjects.first?.name ?? ""
                }
                if halfYearSelection == 0 {
                    halfYearSelection = WhatIfModeView.defaultHalfYear()
                }
            }
        }
    }

    private func addSimulatedGrade() {
        error = nil
        guard let grade = parsedGrade(), grade >= 0, grade <= 15 else {
            error = "Bitte eine gültige Note zwischen 0 und 15 eingeben."
            return
        }
        guard let weight = resolvedWeight() else {
            error = "Bitte eine gültige Gewichtung auswählen."
            return
        }
        guard !subjectName.isEmpty else {
            error = "Bitte ein Fach auswählen."
            return
        }
        let entry = SimulatedGradeEntry(
            subjectName: subjectName,
            grade: grade,
            weight: weight,
            isCustomWeight: {
                if case .custom = weightChoice { return true }
                return false
            }(),
            halfYear: selectedHalfYear(),
            createdAt: Date()
        )
        simulatedGrades.append(entry)
        gradeText = ""
        if case .custom = weightChoice {
            customWeightText = ""
        }
    }

    private func remove(_ entry: SimulatedGradeEntry) {
        simulatedGrades.removeAll { $0.id == entry.id }
    }

    private func subjectAverage(_ subject: Subject, using dict: [String: [Grade]]) -> Double? {
        let list = dict[subject.name] ?? []
        return GradeCalculationService.calculateSubjectAverage(
            subject: subject,
            grades: list,
            dropValue: subject.droppedHalfYear,
            effectiveGradeWeight: store.effectiveGradeWeight
        )
    }

    private func overallAverage(using dict: [String: [Grade]]) -> Double? {
        let subjectsData = store.subjects.map { s in
            let gradesForSubject = dict[s.name] ?? []
            let wrappedGrades = gradesForSubject.map { g in
                GradeWithId(
                    id: UUID().uuidString,
                    grade: g.grade,
                    weight: g.weight,
                    date: g.date,
                    note: g.note,
                    halfYear: g.halfYear,
                    linkedExamId: g.linkedExamId
                )
            }
            return GradeCalculationService.SubjectData.from(subject: s, grades: wrappedGrades)
        }
        
        var dropSelections: [String: Int?] = [:]
        for s in store.subjects {
            dropSelections[s.name] = s.droppedHalfYear
        }
        
        let res = GradeCalculationService.makeFobosoSummary(
            schoolType: store.schoolType,
            gradeYear: store.gradeYear ?? 12,
            subjects: subjectsData,
            examPoints: store.examPoints,
            dropSelections: dropSelections,
            fachreferat: store.fachreferat,
            practicalPerformance: store.practicalPerformance,
            seminarPerformance: store.seminarPerformance,
            effectiveGradeWeight: store.effectiveGradeWeight
        )
        return res.grade
    }

    private func selectedHalfYear() -> Int? {
        halfYearSelection == 0 ? nil : halfYearSelection
    }

    private func parsedGrade() -> Double? {
        let cleaned = gradeText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let value = Double(cleaned) else { return nil }
        return value
    }

    private func resolvedWeight() -> Double? {
        switch weightChoice {
        case .preset(let value):
            return value
        case .custom:
            guard let custom = parsedCustomWeight(), custom > 0 else { return nil }
            return custom
        }
    }

    private func parsedCustomWeight() -> Double? {
        let cleaned = customWeightText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private func weightOptions(for gradingMode: GradingMode) -> [(title: String, value: Double)] {
        switch gradingMode {
        case .withSchulaufgaben:
            return [
                ("Schulaufgabe", 2),
                ("Kurzarbeit", 1),
                ("Mündlich / EX", 1)
            ]
        case .withoutSchulaufgaben:
            return [
                ("Kurzarbeit", 1),
                ("Mündlich / EX", 1)
            ]
        }
    }

    private func selectedWeightLabel(for gradingMode: GradingMode) -> String {
        switch weightChoice {
        case .preset(let value):
            let options = weightOptions(for: gradingMode)
            if let match = options.first(where: { $0.value == value }) {
                return match.title
            }
            return "Art auswählen"
        case .custom:
            if let weight = parsedCustomWeight() {
                return "Sonstige Leistung (\(formatWeight(weight))x)"
            }
            return "Sonstige Leistung"
        }
    }

    private func formatWeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func formatGrade(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f", value)
    }

    private func formatDelta(_ value: Double?) -> String {
        guard let value else { return "-" }
        if abs(value) < 0.005 { return "±0.00" }
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", value))"
    }

    private func weightLabel(for weight: Double, isCustom: Bool, gradingMode: GradingMode) -> String {
        if isCustom {
            return "Sonstige Leistung (\(formatWeight(abs(weight)))x)"
        }
        if let match = weightOptions(for: gradingMode).first(where: { $0.value == weight }) {
            return match.title
        }
        return "Gewicht \(formatWeight(weight))x"
    }

    private func gradingModeForName(_ name: String) -> GradingMode {
        let subj = subjects.first(where: { $0.name == name })
        return subj?.gradingMode ?? ((subj?.type == 1) ? .withSchulaufgaben : .withoutSchulaufgaben)
    }

    private func halfYearLabel(for halfYear: Int?) -> String {
        guard let halfYear else { return "" }
        return " · \(halfYear). Hj"
    }

    private static func defaultHalfYear(referenceDate: Date = Date()) -> Int {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: referenceDate)
        return month < 2 ? 1 : 2
    }
}
