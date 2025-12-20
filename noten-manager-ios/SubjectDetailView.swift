import SwiftUI
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

struct SubjectDetailView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    let subject: Subject

    enum HalfYearFilter: Hashable { case all, one, two }

    // Aktueller Fachzustand (lokal, damit Umbenennen direkt sichtbar ist)
    @State private var currentSubjectName: String
    @State private var currentTeacher: String?
    @State private var currentRoom: String?
    @State private var currentEmail: String?
    @State private var currentAlias: String?

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
    @State private var isSavingSubject: Bool = false
    @State private var showDeleteSubjectAlert: Bool = false

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

    private var editSheetTitle: String {
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let current = currentSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return current.isEmpty ? "Fach bearbeiten" : current
    }

    init(subject: Subject) {
        self.subject = subject
        _currentSubjectName = State(initialValue: subject.name)
        _currentTeacher = State(initialValue: subject.teacher)
        _currentRoom = State(initialValue: subject.room)
        _currentEmail = State(initialValue: subject.email)
        _currentAlias = State(initialValue: subject.alias)
    }

    private var subjectTitle: String {
        let trimmed = currentSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Fach" : trimmed
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

    private func weightOptions() -> [(title: String, value: Double)] {
        if subject.type == 0 {
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

    private func formatWeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func averageForSubject() -> Double? {
        guard !filteredGrades.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in filteredGrades {
            let w = store.effectiveGradeWeight(subjectType: subject.type, rawWeight: g.weight)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func formatAverage(_ v: Double?) -> String {
        guard let v else { return "-" }
        return String(format: "%.2f", v)
    }

    private func gradeColor(_ value: Double) -> Color {
        if value >= 7 { return .green }
        if value >= 4 { return .orange }
        return .red
    }

    private func avgColor(_ value: Double?) -> Color {
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
        let original = subject.name.lowercased()
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
                    StatChip(title: "Gesamt", value: formatAverage(averageForSubject()), accent: .indigo)
                    StatChip(title: "Noten", value: "\(allGrades.count)", accent: .orange)
                    StatChip(title: "Klausuren", value: "\(upcomingExamsCount)", accent: .mint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Halbjahr filtern")
                        .font(.headline)
                    HStack {
                        HStack(spacing: 6) {
                            SegmentButton(title: "Alle", active: halfYear == .all) { halfYear = .all }
                            SegmentButton(title: "1. Hj", active: halfYear == .one) { halfYear = .one }
                            SegmentButton(title: "2. Hj", active: halfYear == .two) { halfYear = .two }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .fill(toggleBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .stroke(toggleStroke, lineWidth: 1)
                        )
                        .shadow(color: toggleShadow, radius: 8, x: 0, y: 4)

                        Spacer(minLength: 0)
                    }
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
                VStack(spacing: 10) {
                    ForEach(Array(sortedGrades.enumerated()), id: \.element.id) { entry in
                        let g = entry.element
                        let delay = 0.26 + Double(entry.offset) * 0.04
                        gradeCard(g)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                overviewCard
                    .softFadeIn(enabled: animationsOn, delay: 0.03, offset: 12)

                if hasDetails {
                    detailsCard
                        .softFadeIn(enabled: animationsOn, delay: 0.08, offset: 12)
                }

                examsCard
                    .softFadeIn(enabled: animationsOn, delay: 0.12, offset: 12)
                homeworksCard
                    .softFadeIn(enabled: animationsOn, delay: 0.16, offset: 12)
                gradesSection
                    .softFadeIn(enabled: animationsOn, delay: 0.20, offset: 12)
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
                                        Text("Details")
                                            .font(.headline)
                                        detailField(label: "Lehrkraft", value: $editTeacher)
                                        detailField(label: "Raum", value: $editRoom)
                                        detailField(label: "Kürzel", value: $editAlias)
                                        detailField(label: "E-Mail", value: $editEmail, keyboard: .emailAddress, autocap: .never)
                                    }
                                }

                                SettingsSectionBox {
                                    Button(role: .destructive) {
                                        showDeleteSubjectAlert = true
                                    } label: {
                                        Text("Fach löschen")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
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
                    Button("Abbrechen") {
                        cancelEditSubject()
                    }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSavingSubject ? "Speichern…" : "Speichern") {
                            Task { await handleSaveSubject() }
                        }
                        .disabled(isSavingSubject)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
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
                        Button("Abbrechen") { showNoteSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") { Task { await saveNote() } }
                            .disabled(noteEditGradeId == nil)
                    }
                }
            }
        }
        .sheet(item: $gradeToEdit) { grade in
            EditGradeView(
                grade: grade,
                subjectName: currentSubjectName,
                subjectType: subject.type
            )
            .environmentObject(store)
        }
        .sheet(item: $gradeDetail) { grade in
            GradeDetailSheet(
                grade: grade,
                subjectName: currentSubjectName,
                subjectType: subject.type,
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
        .navigationTitle(subjectTitle)
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
                onExam: { showAddExamSheet = true }
            )
            .environmentObject(store)
            #if os(iOS)
            .presentationDetents([.medium])
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
        .sheet(item: $examForNewGrade) { exam in
            let note = noteForExam(exam)
            AddGradeView(
                preselectedSubjectName: exam.subjectName,
                preselectedWeight: exam.weight,
                preselectedCustomWeight: exam.customWeight,
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
        .keyboardDismissToolbar()
        .navigationDestination(isPresented: $navigateToSettings) {
            AppSettingsView().environmentObject(store)
        }
        .navigationDestination(isPresented: $navigateToFinal) {
            AbiturExamView().environmentObject(store)
        }
        // Nur den aktuellen Fachnamen an den Container melden
        .preference(key: QuickAddSubjectPreferenceKey.self, value: currentSubjectName)
    }

    // MARK: - Helpers (Optik)

    private var toggleBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color(.systemBackground)
    }

    private var toggleShadow: Color {
        Color.black.opacity(colorScheme == .dark ? 0.5 : 0.12)
    }

    private var toggleStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
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
        @EnvironmentObject private var store: GradesStore
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            NavigationStack {
                ZStack {
                    ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                        .ignoresSafeArea()

                    VStack(spacing: 18) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 46, height: 5)
                            .padding(.top, 8)

                        VStack(spacing: 6) {
                            Text("Hinzufügen")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(primaryText)
                            Text("Was möchtest du anlegen?")
                                .font(.subheadline)
                                .foregroundStyle(secondaryText)
                        }

                        VStack(spacing: 12) {
                            actionRow(icon: "checklist", title: "Hausaufgabe", subtitle: "Aufgabe mit Fälligkeit", action: onHomework)
                            actionRow(icon: "list.bullet.rectangle.portrait.fill", title: "Note", subtitle: "Leistung eintragen", action: onGrade)
                            actionRow(icon: "calendar.badge.clock", title: "Klausurtermin", subtitle: "Prüfung mit Datum", action: onExam)
                        }
                        .padding(.top, 4)

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") {
                            dismissSheet()
                        }
                    }
                }
            }
        }

        private func actionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
            Button {
                dismissSheet()
                // Call after slight delay to allow sheet to dismiss smoothly
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    action()
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(accentPrimary.opacity(0.14))
                            .frame(width: 42, height: 42)
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accentPrimary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryText)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tileBackground)
                        .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
                )
            }
            .buttonStyle(.plain)
        }

        private var accentPrimary: Color {
            if store.theme == "feminine" {
                return Color(hex: store.darkMode ? "#f472b6" : "#ec4899")
            }
            return .indigo
        }

        private var primaryText: Color {
            store.darkMode ? Color.white : Color(hex: "#0f172a")
        }

        private var secondaryText: Color {
            store.darkMode ? Color.white.opacity(0.75) : Color.secondary
        }

        private var tileBackground: LinearGradient {
            let top = accentPrimary.opacity(store.darkMode ? 0.16 : 0.08)
            let bottom = Color(.secondarySystemBackground)
            return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }

        private var shadowColor: Color {
            Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12)
        }

        @Environment(\.dismiss) private var dismiss
        private func dismissSheet() {
            dismiss()
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
        let typeLabel = gradeTypeLabel(weight: grade.weight)
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

    private func gradeTypeLabel(weight: Double) -> String {
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
        showEditSubjectSheet = true
    }

    private func cancelEditSubject() {
        showEditSubjectSheet = false
        editName = ""
        editTeacher = ""
        editRoom = ""
        editEmail = ""
        editAlias = ""
    }

    private func handleSaveSubject() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let schoolYearId = store.activeSchoolYearId else { return }
        guard !isSavingSubject else { return }

        let originalName = subject.name
        let newName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }

        if newName.lowercased() != originalName.lowercased(),
           store.subjects.contains(where: { $0.name.lowercased() == newName.lowercased() }) {
            return
        }

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
                    "alias": editAlias.isEmpty ? NSNull() : editAlias
                ])
            } else {
                let oldRef = yearRef.collection("subjects").document(originalName)
                let newRef = yearRef.collection("subjects").document(newName)

                var payload: [String: Any] = [
                    "type": original.type,
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
                    "isElective": original.isElective
                ]
                payload["type"] = original.type
                payload["date"] = original.date

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

            cancelEditSubject()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // Optional: Fehler anzeigen
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
