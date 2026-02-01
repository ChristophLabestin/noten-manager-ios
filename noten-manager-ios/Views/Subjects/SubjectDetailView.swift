import SwiftUI
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

struct SubjectDetailView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    let subject: Subject
    
    enum HalfYearFilter: Hashable { case all, one, two }
    enum SchulaufgabeReplacement: Double, CaseIterable, Identifiable {
        case kurzarbeit = 1
        case muendlichEx = 0
        
        var id: Double { rawValue }
        
        var title: String {
            switch self {
            case .kurzarbeit: return "Kurzarbeit"
            case .muendlichEx: return "Mündlich / EX"
            }
        }
    }
    
    // Aktueller Fachzustand (lokal, damit Umbenennen direkt sichtbar ist)
    @State private var currentSubjectName: String
    @State private var currentTeacher: String?
    @State private var currentRoom: String?
    @State private var currentEmail: String?
    @State private var currentAlias: String?
@State private var currentSubjectType: Int
@State private var currentGradingMode: GradingMode
    @State private var currentIsElective: Bool
    
    @State private var halfYear: HalfYearFilter = .all
    
    // Grade sheet states
    @State private var gradeToEdit: GradeWithId? = nil
    @State private var gradeDetail: GradeWithId? = nil
    
    // Notiz Sheet
    @State private var showNoteSheet: Bool = false
    @State private var noteEditGradeId: String? = nil
    @State private var noteEditText: String = ""
    
    // Löschen
    @State private var deleteConfirmGradeId: String? = nil
    
    // Toolbar State
    @State private var isSigningOut: Bool = false
    
    // Fach bearbeiten
    @State private var showEditSubjectSheet: Bool = false
    @State private var editName: String = ""
    @State private var editTeacher: String = ""
    @State private var editRoom: String = ""
    @State private var editEmail: String = ""
    @State private var editAlias: String = ""
    @State private var editType: Int = 1
    @State private var editIsElective: Bool = false
    @State private var editError: String? = nil
    @State private var isSavingSubject: Bool = false
    @State private var showDeleteSubjectAlert: Bool = false
    @State private var showSchulaufgabeMergeSheet: Bool = false
    @State private var schulaufgabeGradesToConvert: [GradeWithId] = []
    @State private var schulaufgabeConversions: [String: SchulaufgabeReplacement] = [:]
    @State private var isConvertingSchulaufgaben: Bool = false
    @State private var conversionError: String? = nil
    
    // BottomNav Navigation
    @State private var navigateToSettings: Bool = false
    @State private var navigateToFinal: Bool = false
    @State private var showAddGradeSheet: Bool = false
    @State private var showAddHomeworkSheet: Bool = false
    @State private var showAddExamSheet: Bool = false
    @State private var showAddActions: Bool = false
    @State private var showExamListSheet: Bool = false
    @State private var examForNewGrade: Exam? = nil
    @State private var detailExam: Exam? = nil
    @State private var detailHomework: Homework? = nil
    @State private var editingExam: Exam? = nil

    @State private var editingHomework: Homework? = nil
    @State private var showSetFixedAverageSheet: Bool = false
    
    private var editSheetTitle: String {
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let current = currentSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? "Fach bearbeiten" : current
    }

    private var resolvedGradingMode: GradingMode {
        currentGradingMode
    }

    private var accentPrimary: Color {
        store.theme == "feminine" ? Color(hex: "#ec4899") : .indigo
    }
    
    init(subject: Subject) {
        self.subject = subject
        _currentSubjectName = State(initialValue: subject.name)
        _currentTeacher = State(initialValue: subject.teacher)
        _currentRoom = State(initialValue: subject.room)
        _currentEmail = State(initialValue: subject.email)
        _currentAlias = State(initialValue: subject.alias)
        _currentSubjectType = State(initialValue: subject.type)
        _currentIsElective = State(initialValue: subject.isElective)
        let gm = subject.gradingMode ?? (subject.type == 1 ? .withSchulaufgaben : .withoutSchulaufgaben)
        _currentGradingMode = State(initialValue: gm)
    }
    
    private var activeSubject: Subject {
        store.subjects.first(where: { $0.name == currentSubjectName }) ?? subject
    }
    

    
    private var allGrades: [GradeWithId] {
        store.gradesBySubject[currentSubjectName] ?? []
    }
    
    private var filteredGrades: [GradeWithId] {
        allGrades.filter { g in
            switch halfYear {
            case .all: return true
            case .one: return g.halfYear == 1
            case .two: return g.halfYear == 2
            }
        }
    }
    
    private var sortedGrades: [GradeWithId] {
        filteredGrades.sorted { $0.date > $1.date }
    }

    private var schulaufgabeGrades: [GradeWithId] {
        sortedGrades.filter { isSchulaufgabe($0) }
    }

    private var otherGrades: [GradeWithId] {
        sortedGrades.filter { !isSchulaufgabe($0) }
    }
    
    private func weightOptions() -> [(title: String, value: Double, type: AssessmentType)] {
        switch currentGradingMode {
        case .withSchulaufgaben:
            return [
                ("Schulaufgabe", 2, .schulaufgabe),
                ("Kurzarbeit", 2, .kurzarbeit),
                ("Mündlich / EX", 1, .muendlich)
            ]
        case .withoutSchulaufgaben:
            return [
                ("Kurzarbeit", 1, .kurzarbeit),
                ("Mündlich / EX", 1, .muendlich)
            ]
        }
    }
    
    private func formatWeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
    
    private func averageForSubject(filter: HalfYearFilter = .all) -> Double? {
        if let vYear = activeSubject.fixedAverageYearly, filter == .all {
            return vYear
        }
    
        let droppedHalf = activeSubject.droppedHalfYear
        switch filter {
        case .all:
            let v1 = droppedHalf == 1 ? nil : store.bestAvailableHalfYearValue(subject: activeSubject, halfYear: 1)
            let v2 = droppedHalf == 2 ? nil : store.bestAvailableHalfYearValue(subject: activeSubject, halfYear: 2)
            switch (v1, v2) {
            case let (a?, b?):
                return (a + b) / 2.0
            case let (a?, nil):
                return a
            case let (nil, b?):
                return b
            default:
                return nil
            }
        case .one:
            if droppedHalf == 1 { return nil }
            return store.bestAvailableHalfYearValue(subject: activeSubject, halfYear: 1)
        case .two:
            if droppedHalf == 2 { return nil }
            return store.bestAvailableHalfYearValue(subject: activeSubject, halfYear: 2)
        }
    }
    
    private func formatAverage(_ v: Double?) -> String {
        guard let v else { return "-" }
        return String(format: "%.\(store.mssDecimalPrecision)f", v)
    }
    
    private func fobosoValueText(_ comp: HalfYearComputation, subject: Subject, halfYear: Int) -> String {
        // Always show a calculated grade value, never a range
        if let raw = comp.rawFinal {
            return String(format: "%.\(store.mssDecimalPrecision)f", raw)
        }
        if let final = comp.finalRounded {
            return "\(final)"
        }
        // Fall back to bestAvailableHalfYearValue for consistent display
        if let value = store.bestAvailableHalfYearValue(subject: subject, halfYear: halfYear) {
            return String(format: "%.\(store.mssDecimalPrecision)f", value)
        }
        return "-"
    }

    private func gradeColor(_ value: Double) -> Color {
        if store.isPrivacyModeActive { return .primary }
        if value >= 7 { return .green }
        if value >= 4 { return .orange }
        return .red
    }
    
    private func avgColor(_ value: Double?) -> Color {
        if store.isPrivacyModeActive { return .primary }
        guard let v = value else { return .secondary }
        return gradeColor(v)
    }
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var animationsOn: Bool { store.animationsEnabled }
    
    private var subjectExams: [Exam] {
        store.allExams
            .filter { matchesSubject(name: $0.subjectName) && !$0.isCompleted }
            .sorted { $0.date < $1.date }
    }
    
    private var subjectHomeworks: [Homework] {
        let openHomeworks = store.allHomeworks.filter { hw in
            matchesSubject(name: hw.subjectName)
            && !hw.isCompleted
            && !isAutoCompletedPastDue(hw)
        }
        return openHomeworks.sorted { lhs, rhs in
            let l = homeworkSortKey(lhs)
            let r = homeworkSortKey(rhs)
            if l.priority != r.priority { return l.priority < r.priority }
            return l.date < r.date
        }
    }
    
    private var upcomingExamsCount: Int {
        subjectExams.filter { $0.isActive }.count
    }
    
    private var subjectFilterNames: [String] {
        var names: [String] = []
        names.append(currentSubjectName)
        names.append(subject.name)
        if let alias = currentAlias, !alias.isEmpty {
            names.append(alias)
        }
        return Array(Set(names))
    }
    
    private func matchesSubject(name: String) -> Bool {
        let target = currentSubjectName.lowercased()
        let alias = currentAlias?.lowercased()
        let original = activeSubject.name.lowercased()
        let lookup = name.lowercased()
        return lookup == target || lookup == original || (alias != nil && lookup == alias)
    }
    
    private var chipForegroundColor: Color {
        if isFeminine {
            return Color(hex: isDark ? "#f472b6" : "#ec4899")
        }
        return .blue
    }
    
    private var chipBackgroundColor: Color {
        if isFeminine {
            return chipForegroundColor.opacity(isDark ? 0.30 : 0.15)
        }
        return Color.blue.opacity(0.1)
    }
    
    private var pageBackground: some View {
        ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var hasDetails: Bool {
        (currentTeacher?.isEmpty == false) ||
        (currentAlias?.isEmpty == false) ||
        (currentEmail?.isEmpty == false) ||
        (currentRoom?.isEmpty == false)
    }
    
    private var detailItems: [(label: String, value: String, isEmail: Bool)] {
        var items: [(label: String, value: String, isEmail: Bool)] = []
        if let t = currentTeacher, !t.isEmpty { items.append(("Lehrkraft", t, false)) }
        if let a = currentAlias, !a.isEmpty { items.append(("Kürzel", a, false)) }
        if let e = currentEmail, !e.isEmpty { items.append(("E-Mail", e, true)) }
        if let r = currentRoom, !r.isEmpty { items.append(("Raum", r, false)) }
        
        // Add Grading Mode
        let modeLabel = (currentGradingMode == .withSchulaufgaben) ? "Schulaufgaben" : "Ohne Schulaufgaben"
        items.append(("Art", modeLabel, false))

        return items
    }
    
    // MARK: - Cards
    
    @ViewBuilder
    private var overviewCard: some View {
        SettingsCard(
            title: currentSubjectName,
            subtitle: "Fachübersicht",
            systemImage: "text.book.closed",
            accent: .indigo
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    
                    // Always show "Gesamt" or the single smart half year
                    let halfYears = Set(allGrades.compactMap { $0.halfYear })
                    if halfYears.count == 1, let onlyHalf = halfYears.first {
                        let comp = store.computeHalfYearFoboso(subject: activeSubject, halfYear: onlyHalf)
                        let value = fobosoValueText(comp, subject: activeSubject, halfYear: onlyHalf)
                        StatChip(title: "\(onlyHalf). Hj", value: value, accent: .teal)
                    } else {
                        // Pass .all specifically so this chip never changes based on filter
                        let avg = averageForSubject(filter: .all)
                        StatChip(title: "Gesamt", value: formatAverage(avg), accent: .indigo)
                    }

                    StatChip(title: "Noten", value: "\(allGrades.count)", accent: .orange)
                    StatChip(title: "Klausuren", value: "\(upcomingExamsCount)", accent: .mint)
                }

                if halfYear != .all {
                    let half = (halfYear == .one) ? 1 : 2
                    // Always show the calculated grade value
                    if let value = store.bestAvailableHalfYearValue(subject: activeSubject, halfYear: half) {
                        StatChip(title: "\(half). Hj", value: String(format: "%.\(store.mssDecimalPrecision)f Punkte", value), accent: .teal)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Halbjahr filtern")
                        .font(.headline)
                    SegmentedPicker(
                        selection: $halfYear,
                        options: [
                            SegmentedPickerOption(title: "Alle", value: .all),
                            SegmentedPickerOption(title: "1. Hj", value: .one),
                            SegmentedPickerOption(title: "2. Hj", value: .two)
                        ],
                        accent: .indigo
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var detailsCard: some View {
        SettingsCard(
            title: "Details",
            subtitle: "Lehrkraft & Raum",
            systemImage: "info.circle",
            accent: .cyan
        ) {
            SettingsSectionBox {
                VStack(spacing: 10) {
                    ForEach(Array(detailItems.enumerated()), id: \.offset) { idx, item in
                        detailRow(label: item.label, value: item.value, isEmail: item.isEmail)
                        if idx < detailItems.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var examsCard: some View {
        SettingsCard(
            title: "Klausurtermine",
            subtitle: nil,
            systemImage: "calendar.badge.clock",
            accent: .mint,
            trailing: {
                Button {
                    showExamListSheet = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        ) {
            if subjectExams.isEmpty {
                Text("Keine Klausurtermine für dieses Fach.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(subjectExams.enumerated()), id: \.element.id) { entry in
                        let exam = entry.element
                        let delay = 0.14 + Double(entry.offset) * 0.05
                        examRow(exam, onAddGrade: { examForNewGrade = exam })
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                detailExam = exam
                            }
                            .contextMenu {
                                Button("Note hinzufügen") {
                                    examForNewGrade = exam
                                }
                            }
                            .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var homeworksCard: some View {
        SettingsCard(
            title: "Hausaufgaben",
            subtitle: nil,
            systemImage: "checklist",
            accent: .orange
        ) {
            if subjectHomeworks.isEmpty {
                Text("Keine Hausaufgaben für dieses Fach.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(subjectHomeworks.enumerated()), id: \.element.id) { entry in
                        let hw = entry.element
                        let delay = 0.20 + Double(entry.offset) * 0.05
                        homeworkRow(hw)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var gradesSection: some View {
        SettingsCard(
            title: "Noten",
            subtitle: nil,
            systemImage: "list.bullet.rectangle.portrait.fill",
            accent: .indigo,
            trailing: {
                PillBadge(
                    text: "\(sortedGrades.count)",
                    systemImage: "number.circle",
                    foreground: .indigo,
                    background: Color.indigo.opacity(0.14)
                )
            }
        ) {
            if sortedGrades.isEmpty {
                Text("Keine Noten für dieses Fach.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 14) {
                    if !schulaufgabeGrades.isEmpty {
                        gradeGroupHeader(title: "Schulaufgaben", count: schulaufgabeGrades.count, accent: .orange)
                        gradeList(schulaufgabeGrades, baseDelay: 0.26)
                    }
                    if !otherGrades.isEmpty {
                        gradeGroupHeader(title: "Sonstige Leistungen", count: otherGrades.count, accent: .indigo)
                        let baseDelay = 0.26 + Double(schulaufgabeGrades.count) * 0.04
                        gradeList(otherGrades, baseDelay: baseDelay)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var schulaufgabeMergeView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                SettingsCard(
                    title: "Schulaufgaben umwandeln",
                    subtitle: currentSubjectName.isEmpty ? "Fach" : currentSubjectName,
                    systemImage: "arrow.triangle.2.circlepath",
                    accent: .orange
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Beim Wechsel zu Nebenfach müssen Schulaufgaben angepasst werden.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        if schulaufgabeGradesToConvert.isEmpty {
                            Text("Keine Schulaufgaben gefunden.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(schulaufgabeGradesToConvert) { grade in
                                    schulaufgabeConversionRow(grade)
                                }
                            }
                        }
                        
                        HStack(spacing: 10) {
                            Button {
                                setSchulaufgabeConversions(.kurzarbeit)
                            } label: {
                                Text("Alle: Kurzarbeit")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .orange, font: .subheadline.weight(.semibold), verticalPadding: 10))
                            .disabled(isConvertingSchulaufgaben)
                            
                            Button {
                                setSchulaufgabeConversions(.muendlichEx)
                            } label: {
                                Text("Alle: Mündlich / EX")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .indigo, font: .subheadline.weight(.semibold), verticalPadding: 10))
                            .disabled(isConvertingSchulaufgaben)
                        }
                    }
                }
                
                if let conversionError {
                    Text(conversionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                
                Button {
                    Task { await applySchulaufgabeConversionsAndSave() }
                } label: {
                    HStack(spacing: 10) {
                        if isConvertingSchulaufgaben {
                            ProgressView()
                        }
                        Text(isConvertingSchulaufgaben ? "Umwandeln…" : "Umwandeln & Speichern")
                    }
                }
                .buttonStyle(SoftTintButtonStyle(accent: .orange, font: .headline.weight(.semibold), verticalPadding: 14))
                .disabled(isConvertingSchulaufgaben || schulaufgabeGradesToConvert.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .sheetNavigationTitle("Schulaufgaben")
        .interactiveDismissDisabled(isConvertingSchulaufgaben)
    }
    
    private func schulaufgabeReplacementBinding(for grade: GradeWithId) -> Binding<SchulaufgabeReplacement> {
        Binding(
            get: { schulaufgabeConversions[grade.id] ?? .kurzarbeit },
            set: { schulaufgabeConversions[grade.id] = $0 }
        )
    }
    
    @ViewBuilder
    private func schulaufgabeConversionRow(_ grade: GradeWithId) -> some View {
        let selection = schulaufgabeReplacementBinding(for: grade)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.1f", grade.grade))
                    .font(.headline)
                    .foregroundStyle(gradeColor(grade.grade))
                Text(grade.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(SchulaufgabeReplacement.allCases) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        HStack {
                            Text(option.title)
                            if option == selection.wrappedValue {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selection.wrappedValue.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minWidth: 140, maxWidth: 190, alignment: .leading)
                .background(Color.formInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .tint(.primary)
            .disabled(isConvertingSchulaufgaben)
        }
        .padding(12)
        .background(Color.formSectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func setSchulaufgabeConversions(_ replacement: SchulaufgabeReplacement) {
        for grade in schulaufgabeGradesToConvert {
            schulaufgabeConversions[grade.id] = replacement
        }
    }
    
    private func clearSchulaufgabeConversionState() {
        showSchulaufgabeMergeSheet = false
        schulaufgabeGradesToConvert = []
        schulaufgabeConversions = [:]
        conversionError = nil
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                overviewCard
                    .softFadeIn(enabled: animationsOn, delay: 0.03, offset: 12)

                if hasDetails {
                    detailsCard
                        .softFadeIn(enabled: animationsOn, delay: 0.06, offset: 12)
                }
                
                examsCard
                    .softFadeIn(enabled: animationsOn, delay: 0.12, offset: 12)
                homeworksCard
                    .softFadeIn(enabled: animationsOn, delay: 0.16, offset: 12)
                gradesSection
                    .softFadeIn(enabled: animationsOn, delay: 0.20, offset: 12)

                HelpCenterLink(
                    title: "FOBOSO Halbjahre & Gewichtungen",
                    subtitle: "Wann final, Zwischenstand oder Spannweite",
                    section: .calc,
                    accent: .teal,
                    scrollId: "help_calc_foboso"
                )
                .environmentObject(store)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .background(pageBackground)
        .sheet(isPresented: $showEditSubjectSheet) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        SettingsCard(
                            title: "Fach bearbeiten",
                            subtitle: "Name & Details anpassen",
                            systemImage: "slider.horizontal.3",
                            accent: .indigo
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                SettingsSectionBox {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Name")
                                            .font(.headline)
                                        TextField("z. B. Mathematik", text: $editName)
                                            .textInputAutocapitalization(.words)
                                            .padding(12)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                                
                                SettingsSectionBox {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Schulaufgaben in diesem Fach?")
                                            .font(.headline)
                                        Picker("", selection: $currentGradingMode) {
                                            Text("Ja").tag(GradingMode.withSchulaufgaben)
                                            Text("Nein").tag(GradingMode.withoutSchulaufgaben)
                                        }
                                        .pickerStyle(.segmented)
                                        .onChange(of: currentGradingMode) { _, newVal in
                                            if newVal == .withoutSchulaufgaben {
                                                editType = 0
                                            } else {
                                                editType = 1
                                            }
                                        }

                                        Toggle("Wahlfach / nicht einbringbar", isOn: $editIsElective)
                                            .onChange(of: editIsElective) { _, newVal in
                                                if newVal { editType = 0 }
                                            }
                                        Text("Wahlfächer fließen nicht in die Abschlussnote ein. Für Sport/Musik bitte als Wahlfach markieren.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                SettingsSectionBox {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Details")
                                            .font(.headline)
                                        detailField(label: "Lehrkraft", value: $editTeacher)
                                        detailField(label: "Raum", value: $editRoom)
                                        detailField(label: "Kürzel", value: $editAlias)
                                        detailField(label: "E-Mail", value: $editEmail, keyboard: .emailAddress, autocap: .never)
                                    }
                                }
                                
                                if let editError {
                                    Text(editError)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                                
                                SettingsSectionBox {
                                    Button(role: .destructive) {
                                        showDeleteSubjectAlert = true
                                    } label: {
                                        Text("Fach löschen")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(SoftTintButtonStyle(accent: .red))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
                .sheetNavigationTitle(editSheetTitle)

                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            cancelEditSubject()
                        } label: {
                            ToolbarIcon(symbol: "chevron.down", showDot: false)
                        }
                        .accessibilityLabel("Abbrechen")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await handleSaveSubject() }
                        } label: {
                            if isSavingSubject {
                                ToolbarLoadingIcon()
                            } else {
                                ToolbarIcon(symbol: "checkmark", showDot: false)
                            }
                        }
                        .accessibilityLabel("Speichern")
                        .disabled(isSavingSubject)
                    }
                }
                .navigationDestination(isPresented: $showSchulaufgabeMergeSheet) {
                    schulaufgabeMergeView
                }
                .scrollDismissesKeyboard(.interactively)
                .keyboardDismissToolbar()
                .hideKeyboardOnTap()
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            NavigationStack {
                Form {
                    Section("Notiz") {
                        TextEditor(text: $noteEditText)
                            .frame(minHeight: 120)
                    }
                }
                .sheetNavigationTitle("Notiz bearbeiten")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            showNoteSheet = false
                        } label: {
                            Image(systemName: "xmark")
                                .imageScale(.medium)
                        }
                        .accessibilityLabel("Abbrechen")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await saveNote() }
                        } label: {
                            Image(systemName: "checkmark")
                                .imageScale(.medium)
                        }
                        .accessibilityLabel("Speichern")
                        .disabled(noteEditGradeId == nil)
                    }
                }
            }
        }
        .sheet(item: $gradeToEdit) { grade in
            EditGradeView(
                grade: grade,
                subjectName: currentSubjectName,
                subjectType: currentSubjectType,
                gradingMode: currentGradingMode
            )
            .environmentObject(store)
        }
        .sheet(item: $gradeDetail) { grade in
            GradeDetailSheet(
                grade: grade,
                subjectName: currentSubjectName,
                subjectType: currentSubjectType,
                onEdit: { gradeToEdit = $0 },
                onDelete: { grade in deleteConfirmGradeId = grade.id }
            )
            .environmentObject(store)
        }
        .alert(
            "Note löschen?",
            isPresented: Binding(
                get: { deleteConfirmGradeId != nil },
                set: { newValue in
                    if !newValue {
                        deleteConfirmGradeId = nil
                    }
                }
            )
        ) {
            Button("Löschen", role: .destructive) {
                if let gid = deleteConfirmGradeId {
                    Task { await deleteGrade(gradeId: gid) }
                }
            }
            Button("Abbrechen", role: .cancel) {
                deleteConfirmGradeId = nil
            }
        } message: {
            Text("Diese Note wird dauerhaft gelöscht.")
        }
        .alert(
            "Fach löschen?",
            isPresented: $showDeleteSubjectAlert
        ) {
            Button("Löschen", role: .destructive) {
                Task { await deleteSubjectCompletely() }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Dieses Fach und alle zugehörigen Noten werden dauerhaft gelöscht.")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 0) {
                    Button {
                        startEditSubject()
                    } label: {
                        ToolbarIcon(symbol: "slider.horizontal.3", showDot: false)
                    }
                    
                    Button {
                        showAddActions = true
                    } label: {
                        ToolbarIcon(symbol: "plus", showDot: false)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddActions) {
            AddActionChooserView(
                onHomework: { showAddHomeworkSheet = true },
                onGrade: { showAddGradeSheet = true },
                onExam: { showAddExamSheet = true },
                onSetAverage: { showSetFixedAverageSheet = true }
            )
            .environmentObject(store)
#if os(iOS)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
#endif
        }
        .sheet(isPresented: $showAddGradeSheet) {
            NavigationStack {
                AddGradeView(preselectedSubjectName: currentSubjectName)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showAddHomeworkSheet) {
            NavigationStack {
                AddHomeworkView(preselectedSubjectName: currentSubjectName)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showAddExamSheet) {
            NavigationStack {
                AddExamView(preselectedSubjectName: currentSubjectName)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showSetFixedAverageSheet) {
            SetFixedAverageView(
                subjectName: currentSubjectName,
                currentHalfYear1: activeSubject.fixedAverageHalfYear1,
                currentHalfYear2: activeSubject.fixedAverageHalfYear2,
                currentYearly: activeSubject.fixedAverageYearly,
                calculatedHalfYear1: store.computeHalfYearFoboso(subject: activeSubject, halfYear: 1).rawFinal ?? store.bestAvailableHalfYearValue(subject: activeSubject, halfYear: 1), // simplified logic usage
                calculatedHalfYear2: store.computeHalfYearFoboso(subject: activeSubject, halfYear: 2).rawFinal ?? store.bestAvailableHalfYearValue(subject: activeSubject, halfYear: 2),
                calculatedYearly: nil // Yearly dynamic usually needs complex recalc, leaving nil for now or could implement simplified version
            ) { v1, v2, vY in
                await store.updateSubjectFixedAverages(subjectName: currentSubjectName, val1: v1, val2: v2, valYear: vY)
            }
            .presentationDetents([.large])
        }
        .sheet(item: $examForNewGrade) { exam in
            let note = noteForExam(exam)
            AddGradeView(
                preselectedSubjectName: exam.subjectName,
                preselectedWeight: exam.weight,
                preselectedCustomWeight: exam.customWeight,
                preselectedAssessmentType: exam.assessmentType,
                prefilledNote: note,
                linkedExamId: exam.id,
                markLinkedExamCompletedByDefault: true
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showExamListSheet) {
            ExamListView(subjectFilter: currentSubjectName, alternateSubjectNames: subjectFilterNames)
                .environmentObject(store)
        }
        .sheet(item: $detailExam) { exam in
            ExamDetailSheet(
                exam: exam,
                onEdit: { editingExam = $0 }
            )
            .environmentObject(store)
        }
        .sheet(item: $detailHomework) { homework in
            HomeworkDetailSheet(
                homework: homework,
                onEdit: { editingHomework = $0 }
            )
            .environmentObject(store)
        }
        .sheet(item: $editingExam) { exam in
            EditExamView(exam: exam)
                .environmentObject(store)
        }
        .sheet(item: $editingHomework) { hw in
            EditHomeworkView(homework: hw)
                .environmentObject(store)
        }
        .navigationDestination(isPresented: $navigateToSettings) {
            AppSettingsView().environmentObject(store)
        }
        .navigationDestination(isPresented: $navigateToFinal) {
            AbiturExamView().environmentObject(store)
        }
        // Nur den aktuellen Fachnamen an den Container melden
        .preference(key: QuickAddSubjectPreferenceKey.self, value: currentSubjectName)
    }
    
    @ViewBuilder
    private func detailRow(label: String, value: String, isEmail: Bool = false) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if isEmail, let url = URL(string: "mailto:\(value)") {
                Link(value, destination: url).font(.subheadline)
            } else {
                Text(value).font(.subheadline)
            }
        }
    }
    
    @ViewBuilder
    private func detailField(label: String, value: Binding<String>, keyboard: UIKeyboardType = .default, autocap: TextInputAutocapitalization = .sentences) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(label, text: value)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .padding(12)
                .background(Color.formInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    
    @ViewBuilder
    private func examRow(_ exam: Exam, onAddGrade: @escaping () -> Void) -> some View {
        let now = Date()
        let isPast = !exam.isActive
        let canMarkCompleted = !exam.isCompleted && exam.date <= now
        let checkmarkSize: CGFloat = 18
        let badge = statusBadge(
            exam.isCompleted ? "Erledigt" : (isPast ? "Wartet auf Note" : "Geplant"),
            color: exam.isCompleted ? .green : (isPast ? .red : .blue)
        )
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exam.title.isEmpty ? "Klausur" : exam.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(exam.date.formatted(date: .abbreviated, time: exam.hasTime ? .shortened : .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let sharing = store.resolveContextName(groupId: exam.groupId, courseId: exam.courseId)
                if !sharing.isEmpty {
                    Text("Geteilt mit \(sharing)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                if let notes = exam.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                badge
                HStack(spacing: 8) {
                    if canMarkCompleted {
                        Button {
                            Task { await markExamCompleted(exam) }
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.primary)
                                .font(.system(size: checkmarkSize, weight: .semibold))
                                .padding(8)
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Als erledigt markieren")
                    }
                    
                    Button {
                        detailExam = exam
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.primary)
                            .font(.system(size: 18, weight: .semibold))
                            .padding(8)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Details anzeigen")
                    
                    Button {
                        onAddGrade()
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .foregroundStyle(.primary)
                            .font(.system(size: 18, weight: .semibold))
                            .padding(8)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Note hinzufügen")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.15), lineWidth: 1)
        )
    }
    
    private func noteForExam(_ exam: Exam) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = exam.hasTime ? .short : .none
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        let dateString = formatter.string(from: exam.date)
        return "Geschrieben am \(dateString)"
    }
    
    @ViewBuilder
    private func homeworkRow(_ homework: Homework) -> some View {
        let badge = homeworkBadge(for: homework)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(homework.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let due = homework.dueDate {
                        Text("Fällig: \(due.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Kein Fälligkeitsdatum")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let badge {
                        attentionBadge(badge.text, color: badge.color, icon: badge.icon)
                    }
                }
                let sharing = store.resolveContextName(groupId: homework.groupId, courseId: homework.courseId)
                if !sharing.isEmpty {
                    Text("Geteilt mit \(sharing)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                let iconSize: CGFloat = 18
                
                Button {
                    detailHomework = homework
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(Color.formInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                
                Button {
                    Task { await toggleHomeworkCompletion(homework) }
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(Color.formInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { detailHomework = homework }
    }
    
    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    
    private func attentionBadge(_ text: String, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
    
    private func homeworkBadge(for hw: Homework) -> (text: String, color: Color, icon: String?)? {
        let cal = Calendar.current
        let now = Date()
        guard let due = hw.dueDate else { return nil }
        if cal.isDateInToday(due) {
            return ("Fällig", .red, nil)
        }
        if cal.isDateInTomorrow(due) {
            return ("Morgen fällig", .orange, nil)
        }
        if due > now {
            return ("Geplant", .green, nil)
        }
        return nil
    }
    
    private func isAutoCompletedPastDue(_ hw: Homework) -> Bool {
        guard let due = hw.dueDate else { return false }
        let startToday = Calendar.current.startOfDay(for: Date())
        return due < startToday
    }
    
    private func homeworkSortKey(_ hw: Homework) -> (priority: Int, date: Date) {
        let cal = Calendar.current
        let now = Date()
        if let due = hw.dueDate {
            let startToday = cal.startOfDay(for: now)
            if due < startToday {
                return (3, due)
            }
            if cal.isDateInToday(due) {
                return (0, due)
            }
            if cal.isDateInTomorrow(due) {
                return (1, due)
            }
            return (2, due)
        }
        return (2, hw.createdAt)
    }
    
    private func gradeActionButton(icon: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
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
    
    // MARK: - FAB-Action Sheet
    
    private struct AddActionChooserView: View {
        let onHomework: () -> Void
        let onGrade: () -> Void
        let onExam: () -> Void
        let onSetAverage: () -> Void
        @EnvironmentObject private var store: GradesStore
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.dismiss) private var dismiss
        
        private var isFeminine: Bool { store.theme == "feminine" }
        private var isDark: Bool { store.darkMode }
        
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        // Action List
                        VStack(spacing: 12) {
                            listActionRow(
                                title: "Hausaufgabe",
                                icon: "checklist",
                                color: .cyan,
                                action: onHomework
                            )
                            listActionRow(
                                title: "Note",
                                icon: "list.bullet.rectangle.portrait.fill",
                                color: .indigo,
                                action: onGrade
                            )
                            listActionRow(
                                title: "Klausur",
                                icon: "calendar.badge.clock",
                                color: .orange,
                                action: onExam
                            )
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            listActionRow(
                                title: "Festen Schnitt setzen",
                                icon: "slider.horizontal.3",
                                color: .teal,
                                action: onSetAverage
                            )
                        }
                    }
                    .padding(20)
                }
                .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Hinzufügen")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryText)
                    }
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
            }
        }
        
        private func listActionRow(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
            Button {
                dismiss()
                // Call after slight delay to allow sheet to dismiss smoothly
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    action()
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(isDark ? 0.2 : 0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryText)
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    cardSurface(accent: color, cornerRadius: 18)
                        .shadow(color: rowShadow, radius: 10, x: 0, y: 6)
                )
                .overlay(
                    cardBorder(accent: color, cornerRadius: 18)
                )
            }
            .buttonStyle(.plain)
        }
        
        private var primaryText: Color {
            isDark ? .white : Color(hex: "#0f172a")
        }
        
        private var secondaryText: Color {
            isDark ? Color.white.opacity(0.75) : Color.secondary
        }
        
        private var rowShadow: Color {
            Color.black.opacity(isDark ? 0.36 : 0.08)
        }
        
        private var cardTop: Color {
            if isDark {
                return isFeminine ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
            }
            return isFeminine ? Color(hex: "#fff1f7") : Color(hex: "#eef2ff")
        }
        
        private var cardBottom: Color {
            if isDark {
                return isFeminine ? Color(hex: "#120a16") : Color(hex: "#111827")
            }
            return isFeminine ? Color(hex: "#fff7fb") : Color(hex: "#f8fafc")
        }
        
        private func cardSurface(accent: Color, cornerRadius: CGFloat) -> some View {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [cardTop, cardBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(isDark ? 0.14 : 0.08),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        }
        
        private func cardBorder(accent: Color, cornerRadius: CGFloat) -> some View {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(accent.opacity(isDark ? 0.22 : 0.12), lineWidth: 1)
        }
        
        struct ScaleButtonStyle: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .scaleEffect(configuration.isPressed ? 0.95 : 1)
                    .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            }
        }
    }
        
        private func toggleHomeworkCompletion(_ homework: Homework) async {
            if homework.isShared {
                await store.setUserCompletedForSharedHomework(homeworkId: homework.id, completed: !homework.isCompleted, groupId: homework.groupId)
            } else {
                await store.setHomeworkCompleted(id: homework.id, completed: !homework.isCompleted)
            }
        }
        
        private func markExamCompleted(_ exam: Exam) async {
            if exam.isShared {
                await store.setUserCompletedForSharedExam(examId: exam.id, completed: true, groupId: exam.groupId)
            } else {
                await store.setExamCompleted(id: exam.id, completed: true)
            }
        }
        
        @ViewBuilder
        private func gradeCard(_ grade: GradeWithId) -> some View {
            let typeLabel = gradeTypeLabel(grade)
            let halfYearText = halfYearLabel(grade.halfYear)
            let noteText = grade.note ?? ""
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(typeLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let halfYearLabel = halfYearText {
                                attentionBadge(halfYearLabel, color: .indigo, icon: "calendar")
                            }
                        }
                        HStack(spacing: 6) {
                            Text(grade.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if !noteText.isEmpty {
                                attentionBadge("Notiz", color: .orange, icon: "note.text")
                            }
                        }
                    }
                    
                    Spacer(minLength: 0)
                    
                    Text(String(format: "%.1f", grade.grade))
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(gradeColor(grade.grade).opacity(0.18))
                        .foregroundStyle(gradeColor(grade.grade))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .privacyBlur()
                }
                
                HStack(spacing: 10) {
                    gradeActionButton(icon: "slider.horizontal.3", tint: .orange, label: "Bearbeiten") {
                        gradeToEdit = grade
                    }
                    
                    gradeActionButton(icon: "info.circle", tint: .indigo, label: "Info") {
                        gradeDetail = grade
                    }
                    
                    gradeActionButton(icon: "trash", tint: .red, label: "Löschen") {
                        deleteConfirmGradeId = grade.id
                    }
                }
            }
            .padding(10)
            .background(Color.formSectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                gradeDetail = grade
            }
        }
        
        private func gradeTypeLabel(_ grade: GradeWithId) -> String {
            if let type = grade.assessmentType {
                return type.prettyName
            }
            let weight = grade.weight
            if weight == 3 { return "Fachreferat" }
            if let match = weightOptions().first(where: { $0.value == weight }) {
                return match.title
            }
            let effective = abs(weight)
            if let match = weightOptions().first(where: { $0.value == effective }) {
                return match.title
            }
            return "Sonstige Leistung (\(formatWeight(effective))x)"
        }

        private func isSchulaufgabe(_ grade: GradeWithId) -> Bool {
            grade.assessmentType == .schulaufgabe
        }

        @ViewBuilder
        private func gradeGroupHeader(title: String, count: Int, accent: Color) -> some View {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                PillBadge(
                    text: "\(count)",
                    systemImage: "number.circle",
                    foreground: accent,
                    background: accent.opacity(0.12)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder
        private func gradeList(_ grades: [GradeWithId], baseDelay: Double) -> some View {
            VStack(spacing: 10) {
                ForEach(Array(grades.enumerated()), id: \.element.id) { entry in
                    let g = entry.element
                    let delay = baseDelay + Double(entry.offset) * 0.04
                    gradeCard(g)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                }
            }
        }
        
        private func halfYearLabel(_ value: Int?) -> String? {
            guard let v = value else { return nil }
            return v == 1 ? "1. Halbjahr" : "2. Halbjahr"
        }
        
        private func openNoteEditor(for gradeId: String, current: String) {
            noteEditGradeId = gradeId
            noteEditText = current
            showNoteSheet = true
        }
        
        private func saveNote() async {
            guard let gid = noteEditGradeId else { return }
            do {
                try await store.updateGradeNoteInFirestore(subjectId: currentSubjectName, gradeId: gid, note: noteEditText.isEmpty ? nil : noteEditText)
                showNoteSheet = false
                noteEditGradeId = nil
                noteEditText = ""
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // Optional: Fehler anzeigen
            }
        }
        
        private func deleteGrade(gradeId: String) async {
            do {
                try await store.deleteGradeFromFirestore(subjectId: currentSubjectName, gradeId: gradeId)
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // Optional: Fehler anzeigen
            }
            deleteConfirmGradeId = nil
        }
        
        // MARK: - Fach bearbeiten
        
    private func startEditSubject() {
        editName = currentSubjectName
        editTeacher = currentTeacher ?? ""
        editRoom = currentRoom ?? ""
        editEmail = currentEmail ?? ""
        editAlias = currentAlias ?? ""
        editType = currentSubjectType
        editIsElective = currentIsElective
        currentGradingMode = subject.gradingMode ?? (subject.type == 1 ? .withSchulaufgaben : .withoutSchulaufgaben)
        editError = nil
        showEditSubjectSheet = true
    }
        
        private func cancelEditSubject() {
            showEditSubjectSheet = false
            clearSchulaufgabeConversionState()
            editName = ""
            editTeacher = ""
            editRoom = ""
            editEmail = ""
            editAlias = ""
        editType = currentSubjectType
        editIsElective = false
        editError = nil
    }
        
        private func handleSaveSubject() async {
            guard !isSavingSubject else { return }
            
            editError = nil
            conversionError = nil
            
            if editIsElective { editType = 0 }
            
            let originalName = currentSubjectName
            let newName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty else {
                editError = "Bitte gib einen Namen ein."
                return
            }
            
            let resolvedType = editIsElective ? 0 : editType
            
            if newName.lowercased() != originalName.lowercased(),
               store.subjects.contains(where: { $0.name.lowercased() == newName.lowercased() }) {
                editError = "Ein Fach mit diesem Namen existiert bereits."
                return
            }
            
            let lower = newName.lowercased()
            if ["sport", "musik"].contains(lower) && !editIsElective {
                editError = "Bitte markiere Sport oder Musik als nicht einbringbar (Wahlfach)."
                return
            }
            
            if currentSubjectType == 1 && resolvedType == 0 {
                let schulaufgaben = allGrades.filter { $0.weight == 2 }.sorted { $0.date > $1.date }
                if !schulaufgaben.isEmpty {
                    schulaufgabeGradesToConvert = schulaufgaben
                    schulaufgabeConversions = Dictionary(uniqueKeysWithValues: schulaufgaben.map { ($0.id, .kurzarbeit) })
                    showSchulaufgabeMergeSheet = true
                    return
                }
            }
            
            clearSchulaufgabeConversionState()
            await performSubjectSave(
                originalName: originalName,
                newName: newName,
                newType: resolvedType,
                newIsElective: editIsElective
            )
        }
        
        private func applySchulaufgabeConversionsAndSave() async {
            guard !isConvertingSchulaufgaben else { return }
            isConvertingSchulaufgaben = true
            conversionError = nil
            
            do {
                try await applySchulaufgabeConversions()
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                conversionError = "Schulaufgaben konnten nicht umgewandelt werden."
                isConvertingSchulaufgaben = false
                return
            }
            
            isConvertingSchulaufgaben = false
            showSchulaufgabeMergeSheet = false
            
            let originalName = currentSubjectName
            let newName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedType = editIsElective ? 0 : editType
            await performSubjectSave(
                originalName: originalName,
                newName: newName,
                newType: resolvedType,
                newIsElective: editIsElective
            )
        }
        
        private func applySchulaufgabeConversions() async throws {
            guard let uid = Auth.auth().currentUser?.uid else {
                throw NSError(domain: "SubjectDetailView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
            }
            guard let schoolYearId = store.activeSchoolYearId else {
                throw NSError(domain: "SubjectDetailView", code: -2, userInfo: [NSLocalizedDescriptionKey: "Kein Schuljahr"])
            }
            
            let db = Firestore.firestore()
            let yearRef = db.collection("users").document(uid).collection("schoolYears").document(schoolYearId)
            let gradesRef = yearRef.collection("subjects").document(currentSubjectName).collection("grades")
            
            for grade in schulaufgabeGradesToConvert {
                let replacement = schulaufgabeConversions[grade.id] ?? .kurzarbeit
                try await gradesRef.document(grade.id).updateData([
                    "weight": replacement.rawValue
                ])
            }
            
            if var list = store.gradesBySubject[currentSubjectName] {
                var changed = false
                for idx in list.indices {
                    let grade = list[idx]
                    guard let replacement = schulaufgabeConversions[grade.id] else { continue }
                    let newWeight = replacement.rawValue
                    if grade.weight != newWeight {
                        list[idx] = GradeWithId(
                            id: grade.id,
                            grade: grade.grade,
                            weight: newWeight,
                            date: grade.date,
                            note: grade.note,
                            halfYear: grade.halfYear,
                            linkedExamId: grade.linkedExamId
                        )
                        changed = true
                    }
                }
                if changed {
                    store.gradesBySubject[currentSubjectName] = list
                }
            }
        }
        
    private func performSubjectSave(
        originalName: String,
        newName: String,
        newType: Int,
        newIsElective: Bool
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let schoolYearId = store.activeSchoolYearId else { return }
        guard !isSavingSubject else { return }
            
            isSavingSubject = true
            defer { isSavingSubject = false }
            
            let db = Firestore.firestore()
            let yearRef = db.collection("users").document(uid).collection("schoolYears").document(schoolYearId)
            guard let original = store.subjects.first(where: { $0.name == originalName }) else { return }
            
            do {
                if newName == originalName {
                    let subjectDocRef = yearRef.collection("subjects").document(originalName)
                    try await subjectDocRef.updateData([
                        "teacher": editTeacher.isEmpty ? NSNull() : editTeacher,
                        "room": editRoom.isEmpty ? NSNull() : editRoom,
                        "email": editEmail.isEmpty ? NSNull() : editEmail,
                        "alias": editAlias.isEmpty ? NSNull() : editAlias,
                        "type": newType,
                        "isElective": newIsElective,
                        "gradingMode": resolvedGradingMode.rawValue,
                        "expectedSchulaufgabenPerTerm": FieldValue.delete()
                    ])
                } else {
                    let oldRef = yearRef.collection("subjects").document(originalName)
                    let newRef = yearRef.collection("subjects").document(newName)
                    
                    let payload: [String: Any] = [
                        "type": newType,
                        "date": original.date,
                        "order": original.order as Any,
                        "teacher": editTeacher.isEmpty ? NSNull() : editTeacher,
                        "room": editRoom.isEmpty ? NSNull() : editRoom,
                        "email": editEmail.isEmpty ? NSNull() : editEmail,
                        "alias": editAlias.isEmpty ? NSNull() : editAlias,
                        "droppedHalfYear": original.droppedHalfYear as Any,
                        "examSubject": original.examSubject as Any,
                        "examType": original.examType?.rawValue as Any,
                        "examPointsEncrypted": original.examPointsEncrypted as Any,
                        "writtenExamPointsEncrypted": original.writtenExamPointsEncrypted as Any,
                        "oralExamPointsEncrypted": original.oralExamPointsEncrypted as Any,
                        "isElective": newIsElective,
                        "gradingMode": resolvedGradingMode.rawValue,
                        "expectedSchulaufgabenPerTerm": FieldValue.delete()
                    ]
                    
                    try await newRef.setData(payload, merge: true)
                    
                    let oldGradesRef = oldRef.collection("grades")
                    let newGradesRef = newRef.collection("grades")
                    let oldGradesSnap = try await oldGradesRef.getDocuments()
                    
                    for gdoc in oldGradesSnap.documents {
                        try await newGradesRef.document(gdoc.documentID).setData(gdoc.data())
                    }
                    for gdoc in oldGradesSnap.documents {
                        try await gdoc.reference.delete()
                    }
                    try await oldRef.delete()
                }
                
                currentSubjectName = newName
                currentTeacher = editTeacher.isEmpty ? nil : editTeacher
                currentRoom = editRoom.isEmpty ? nil : editRoom
                currentEmail = editEmail.isEmpty ? nil : editEmail
                currentAlias = editAlias.isEmpty ? nil : editAlias
                currentSubjectType = newType
                currentIsElective = newIsElective
                
                cancelEditSubject()
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                editError = error.localizedDescription
            }
        }
        
        private func signOut() async {
            guard !isSigningOut else { return }
            isSigningOut = true
            defer { isSigningOut = false }
            do {
                store.stopListening()
                try Auth.auth().signOut()
                OfflineModeManager.shared.clearOfflineData()
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional: Fehlerbehandlung
            }
        }
        
        private func deleteSubjectCompletely() async {
            await store.deleteSubjectFromFirestore(subjectName: currentSubjectName)
            await MainActor.run { dismiss() }
        }
}
