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

    private var subjectType: Int {
        subjects.first(where: { $0.name == subjectName })?.type ?? 0
    }

    private var currentAverage: Double? {
        overallAverage(using: baseGradesBySubject)
    }

    private var simulatedAverage: Double? {
        overallAverage(using: combinedGradesBySubject)
    }

    private var deltaAverage: Double? {
        guard let simulatedAverage else { return nil }
        guard let currentAverage else { return simulatedAverage }
        return simulatedAverage - currentAverage
    }

    private var baseGradesBySubject: [String: [Grade]] {
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

    private var combinedGradesBySubject: [String: [Grade]] {
        var dict = baseGradesBySubject
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
        return subjects.filter { names.contains($0.name) }
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
                                        ForEach(weightOptions(for: subjectType), id: \.value) { option in
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
                                            Text(selectedWeightLabel(for: subjectType))
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
                                            if subjectType == 1 {
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

                    SettingsCard(
                        title: "Simulierte Noten",
                        subtitle: "Nur hier sichtbar",
                        systemImage: "tray.full.fill",
                        accent: .orange
                    ) {
                        if simulatedGrades.isEmpty {
                            Text("Noch keine fiktiven Noten erfasst. Ergänze oben eine Note, um den Effekt auf deinen Schnitt zu sehen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            SettingsSectionBox {
                                VStack(spacing: 10) {
                                    ForEach(simulatedGrades) { entry in
                                        HStack(alignment: .top, spacing: 10) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(entry.subjectName)
                                                    .font(.subheadline.weight(.semibold))
                                                Text("Note \(formatGrade(entry.grade)) · \(weightLabel(for: entry.weight, isCustom: entry.isCustomWeight, subjectType: subjectTypeForName(entry.subjectName)))\(halfYearLabel(for: entry.halfYear))")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Button {
                                                remove(entry)
                                            } label: {
                                                Image(systemName: "trash")
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
                                        let current = subjectAverage(subject, using: baseGradesBySubject)
                                        let simulated = subjectAverage(subject, using: combinedGradesBySubject)
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
        guard !list.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for grade in list {
            let weight = store.calculateGradeWeightForOverall(subject: subject, grade: grade)
            total += grade.grade * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func overallAverage(using dict: [String: [Grade]]) -> Double? {
        guard !subjects.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for subject in subjects where !subject.isElective {
            let list = dict[subject.name] ?? []
            for grade in list {
                let weight = store.calculateGradeWeightForOverall(subject: subject, grade: grade)
                total += grade.grade * weight
                totalWeight += weight
            }
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
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

    private func weightOptions(for subjectType: Int) -> [(title: String, value: Double)] {
        if subjectType == 0 {
            return [
                ("Kurzarbeit", 1),
                ("Mündlich / EX", 0)
            ]
        }
        return [
            ("Schulaufgabe", 2),
            ("Kurzarbeit", 1),
            ("Mündlich / EX", 0)
        ]
    }

    private func selectedWeightLabel(for subjectType: Int) -> String {
        switch weightChoice {
        case .preset(let value):
            let options = weightOptions(for: subjectType)
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
        return String(format: "%.2f", value)
    }

    private func formatDelta(_ value: Double?) -> String {
        guard let value else { return "-" }
        if abs(value) < 0.005 { return "0.00" }
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", value))"
    }

    private func weightLabel(for weight: Double, isCustom: Bool, subjectType: Int) -> String {
        if isCustom {
            return "Sonstige Leistung (\(formatWeight(abs(weight)))x)"
        }
        if let match = weightOptions(for: subjectType).first(where: { $0.value == weight }) {
            return match.title
        }
        return "Gewicht \(formatWeight(weight))x"
    }

    private func subjectTypeForName(_ name: String) -> Int {
        subjects.first(where: { $0.name == name })?.type ?? 0
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
