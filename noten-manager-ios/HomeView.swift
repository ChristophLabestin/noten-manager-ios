import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct HomeView: View {
    @EnvironmentObject var store: GradesStore

    enum HalfYearFilter: Equatable {
        case all
        case one
        case two
    }

    @State private var halfYear: HalfYearFilter = .all
    @State private var isEditingOrder: Bool = false
    @State private var customOrderWorkingCopy: [String] = []

    // Navigation-States für echte Seiten (kein Sheet)
    @State private var navigateToSettings: Bool = false
    @State private var navigateToFinalGrade: Bool = false
    @State private var navigateToSubjectsManage: Bool = false

    // Toolbar-State (ersetzt BurgerMenuView am Home)
    @State private var greeting: String = ""
    @State private var displayName: String = ""
    @State private var isSigningOut: Bool = false

    private var subjectsWithoutFachreferat: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var hasFachreferat: Bool {
        store.fachreferat != nil
    }

    // MARK: - Data preparation

    private func filteredSubjectGrades() -> [String: [Grade]] {
        var result: [String: [Grade]] = [:]
        for subject in store.subjects {
            let gradesWithId = store.gradesBySubject[subject.name] ?? []
            var filtered: [Grade] = []
            filtered.reserveCapacity(gradesWithId.count)
            for gw in gradesWithId {
                let matches: Bool
                switch halfYear {
                case .all:
                    matches = true
                case .one:
                    matches = (gw.halfYear == 1)
                case .two:
                    matches = (gw.halfYear == 2)
                }
                if matches {
                    filtered.append(Grade(grade: gw.grade, weight: gw.weight, date: gw.date, note: gw.note, halfYear: gw.halfYear))
                }
            }
            result[subject.name] = filtered
        }
        if let fr = store.fachreferat {
            result["Fachreferat"] = [
                Grade(grade: fr.grade, weight: 3, date: fr.date, note: fr.note, halfYear: nil)
            ]
        }
        return result
    }

    private func getSubjectAverage(_ subject: Subject, subjectGrades: [String: [Grade]]) -> Double? {
        let grades = subjectGrades[subject.name] ?? []
        guard !grades.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in grades {
            let w = store.calculateGradeWeightForOverall(subject: subject, grade: g)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func baseSubjectsList() -> [Subject] {
        var base = subjectsWithoutFachreferat
        if hasFachreferat {
            base.append(Subject(name: "Fachreferat", type: 0, date: Date()))
        }
        return base
    }

    // MARK: - Sorting helpers

    private func comparatorNameAsc() -> (Subject, Subject) -> Bool {
        { a, b in
            a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
        }
    }

    private func comparatorNameDesc() -> (Subject, Subject) -> Bool {
        { a, b in
            a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedDescending
        }
    }

    private func comparatorAverageBestFirst(subjectGrades: [String: [Grade]]) -> (Subject, Subject) -> Bool {
        { a, b in
            let avgA = getSubjectAverage(a, subjectGrades: subjectGrades)
            let avgB = getSubjectAverage(b, subjectGrades: subjectGrades)
            switch (avgA, avgB) {
            case (nil, nil):
                return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (a1?, b1?):
                return a1 > b1
            }
        }
    }

    private func comparatorAverageWorstFirst(subjectGrades: [String: [Grade]]) -> (Subject, Subject) -> Bool {
        { a, b in
            let avgA = getSubjectAverage(a, subjectGrades: subjectGrades)
            let avgB = getSubjectAverage(b, subjectGrades: subjectGrades)
            switch (avgA, avgB) {
            case (nil, nil):
                return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
            case (nil, _):
                return true
            case (_, nil):
                return false
            case let (a1?, b1?):
                return a1 < b1
            }
        }
    }

    private func comparatorCustom(orderMap: [String: Int]) -> (Subject, Subject) -> Bool {
        { a, b in
            let ia = orderMap[a.name]
            let ib = orderMap[b.name]
            switch (ia, ib) {
            case (nil, nil):
                return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
            case (nil, _):
                return false
            case (_, nil):
                return true
            default:
                return ia! < ib!
            }
        }
    }

    private func customOrderMap() -> [String: Int]? {
        guard !store.subjectSortOrder.isEmpty else { return nil }
        var map: [String: Int] = [:]
        for (idx, name) in store.subjectSortOrder.enumerated() {
            map[name] = idx
        }
        return map
    }

    private func sortedSubjects(subjectGrades: [String: [Grade]]) -> [Subject] {
        let base = baseSubjectsList()
        switch store.subjectSortMode {
        case .name:
            return base.sorted(by: comparatorNameAsc())
        case .name_desc:
            return base.sorted(by: comparatorNameDesc())
        case .average:
            return base.sorted(by: comparatorAverageBestFirst(subjectGrades: subjectGrades))
        case .average_worst:
            return base.sorted(by: comparatorAverageWorstFirst(subjectGrades: subjectGrades))
        case .custom:
            if let map = customOrderMap() {
                return base.sorted(by: comparatorCustom(orderMap: map))
            } else {
                return base.sorted(by: comparatorNameAsc())
            }
        }
    }

    // MARK: - Overall formatting

    private func overallAverage(subjectGrades: [String: [Grade]]) -> Double? {
        guard !store.subjects.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for subject in store.subjects {
            let grades = subjectGrades[subject.name] ?? []
            for g in grades {
                let w = store.calculateGradeWeightForOverall(subject: subject, grade: g)
                total += g.grade * w
                totalWeight += w
            }
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return String(format: "%.2f", v)
    }

    private func gradeColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    private var enableDrag: Bool { store.subjectSortMode == .custom }

    // MARK: - Small subviews for body

    private func subjectRowAny(subject: Subject,
                               subjectGrades: [String: [Grade]],
                               fachreferatSubjectName: String?) -> AnyView {
        let grades = subjectGrades[subject.name] ?? []
        if subject.name == "Fachreferat" {
            return AnyView(
                SubjectRowView(
                    subject: subject,
                    grades: grades,
                    fachreferatSubjectName: fachreferatSubjectName
                )
                .contentShape(Rectangle())
            )
        } else {
            return AnyView(
                NavigationLink {
                    SubjectDetailView(subject: subject)
                        .environmentObject(store)
                } label: {
                    SubjectRowView(
                        subject: subject,
                        grades: grades,
                        fachreferatSubjectName: fachreferatSubjectName
                    )
                    .contentShape(Rectangle())
                }
            )
        }
    }

    // MARK: - Derived computed properties to simplify body

    private var subjectGradesComputed: [String: [Grade]] {
        filteredSubjectGrades()
    }

    private var sortedSubjectsComputed: [Subject] {
        sortedSubjects(subjectGrades: subjectGradesComputed)
    }

    private var overallComputed: Double? {
        overallAverage(subjectGrades: subjectGradesComputed)
    }

    private var totalGradesCountComputed: Int {
        subjectGradesComputed.values.reduce(0) { $0 + $1.count }
    }

    private var subjectByNameComputed: [String: Subject] {
        var map: [String: Subject] = [:]
        for s in baseSubjectsList() { map[s.name] = s }
        return map
    }

    private var editModeBinding: EditMode {
        isEditingOrder ? .active : .inactive
    }

    // MARK: - Body

    var body: some View {
        List {
            // Section 1: Loading, Filter, Summary
            Section {
                if store.isLoading {
                    VStack(spacing: 8) {
                        ProgressView(value: store.progress, total: 100)
                        Text(store.loadingLabel).font(.footnote)
                    }
                }

                // Halbjahresfilter + Reorder
                FilterAndReorderRow(
                    halfYear: $halfYear,
                    enableDrag: enableDrag,
                    isEditingOrder: $isEditingOrder,
                    onToggleEdit: {
                        toggleEditMode(sortedNames: sortedSubjectsComputed.map { $0.name })
                    }
                )

                // Summary
                SummaryRow(
                    overall: overallComputed,
                    subjectsCount: subjectsWithoutFachreferat.count,
                    totalGradesCount: totalGradesCountComputed,
                    gradeColor: gradeColor
                )
            }

            // Section 2: Fächerliste (inkl. Reorder)
            Section {
                SectionHeader()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)

                if isEditingOrder && enableDrag {
                    ForEach(customOrderWorkingCopy, id: \.self) { name in
                        SubjectRowView(
                            subject: subjectByNameComputed[name] ?? Subject(name: name, type: 0, date: Date()),
                            grades: subjectGradesComputed[name] ?? [],
                            fachreferatSubjectName: store.fachreferat?.subjectName
                        )
                    }
                    .onMove { indices, newOffset in
                        customOrderWorkingCopy.move(fromOffsets: indices, toOffset: newOffset)
                    }
                } else {
                    ForEach(sortedSubjectsComputed, id: \.name) { subject in
                        subjectRowAny(
                            subject: subject,
                            subjectGrades: subjectGradesComputed,
                            fachreferatSubjectName: store.fachreferat?.subjectName
                        )
                    }
                }
            }
        }
        .environment(\.editMode, .constant(editModeBinding))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)

        // Unsichtbare NavigationLinks (NavigationStack-Ziele)
        .background(
            NavigationLinksBackground(
                navigateToSettings: $navigateToSettings,
                navigateToFinalGrade: $navigateToFinalGrade,
                navigateToSubjectsManage: $navigateToSubjectsManage
            ).environmentObject(store)
        )

        // Toolbar
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ToolbarTitleView(greeting: greeting, displayName: displayName)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await signOut() }
                } label: {
                    if isSigningOut {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.title3)
                    }
                }
                .accessibilityLabel("Abmelden")
                .disabled(isSigningOut)
            }
        }
        .task {
            await store.startListening()
        }
        .onAppear {
            computeGreeting()
            Task { await loadUserDisplayName() }
        }
    }

    // MARK: - Actions

    private func toggleEditMode(sortedNames: [String]) {
        if isEditingOrder {
            Task {
                await store.updateSubjectSortPreferences(mode: .custom, order: customOrderWorkingCopy)
            }
            isEditingOrder = false
        } else {
            if store.subjectSortOrder.isEmpty {
                customOrderWorkingCopy = sortedNames
            } else {
                customOrderWorkingCopy = store.subjectSortOrder
                    .filter { sortedNames.contains($0) } +
                    sortedNames.filter { !store.subjectSortOrder.contains($0) }
            }
            isEditingOrder = true
        }
    }

    // MARK: - Toolbar helpers (Greeting/Name/Logout)

    private func computeGreeting() {
        let hours = Calendar.current.component(.hour, from: Date())
        if hours >= 6 && hours < 11 {
            greeting = "Guten Morgen"
        } else if hours >= 11 && hours < 17 {
            greeting = "Hallo"
        } else if hours >= 17 && hours < 22 {
            greeting = "Guten Abend"
        } else {
            greeting = "Gute Nacht"
        }
    }

    private func loadUserDisplayName() async {
        if let dn = Auth.auth().currentUser?.displayName, !dn.isEmpty {
            displayName = dn
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            displayName = ""
            return
        }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            if let data = snap.data() {
                if let dn = data["displayName"] as? String, !dn.isEmpty {
                    displayName = dn
                } else if let n = data["name"] as? String, !n.isEmpty {
                    displayName = n
                } else {
                    displayName = ""
                }
            }
        } catch {
            displayName = ""
        }
    }

    private func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            store.stopListening()
            try Auth.auth().signOut()
        } catch {
            // optional: Fehlerbehandlung
        }
    }
}

private struct SectionHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fächer & Noten")
                .font(.title3).bold()
            Text("Tippe auf ein Fach für Details")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SegmentButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(active ? Color.white : Color.clear)
                .foregroundStyle(active ? activeTextColor : inactiveTextColor)
                .clipShape(Capsule())
                .shadow(color: active ? shadowColor : .clear,
                        radius: active ? 4 : 0, x: 0, y: active ? 2 : 0)
        }
        .buttonStyle(.plain)
    }

    private var activeTextColor: Color {
        colorScheme == .dark ? Color.black : Color(hex: "#111827")
    }

    private var inactiveTextColor: Color {
        colorScheme == .dark ? Color(hex: "#d1d5db") : Color(hex: "#6b7280")
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.5 : 0.16)
    }
}

struct SummaryCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardBackground)
                .shadow(color: shadowColor,
                        radius: colorScheme == .dark ? 16 : 8,
                        x: 0, y: colorScheme == .dark ? 10 : 6)
        )
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.95)
            : .white
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.6 : 0.06)
    }
}

struct SubjectRowView: View {
    let subject: Subject
    let grades: [Grade]
    let fachreferatSubjectName: String?

    private func avg(_ subject: Subject) -> Double? {
        guard !grades.isEmpty else { return nil }
        func calculateGradeWeight(_ subject: Subject, _ grade: Grade) -> Double {
            if subject.name == "Fachreferat" { return 3 }
            let t = subject.type
            if t == 1 {
                return (grade.weight == 3 ? 2 : (grade.weight == 2 ? 2 : 1))
            }
            if t == 0 {
                return (grade.weight == 3 ? 2 : (grade.weight == 1 ? 2 : 1))
            }
            return 1
        }
        var total = 0.0
        var totalWeight = 0.0
        for g in grades {
            let w = calculateGradeWeight(subject, g)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "–" }
        return String(format: "%.2f", v)
    }

    private func gradeClassColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    var body: some View {
        let average = avg(subject)
        let gradesCount = grades.count

        let isFachreferat = subject.name == "Fachreferat"
        let displayName: String = {
            if isFachreferat, let frName = fachreferatSubjectName, !frName.isEmpty {
                return "Fachreferat in \(frName)"
            }
            return subject.name
        }()

        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    if isFachreferat {
                        Tag(text: "Halbjahresleistung", style: .main)
                    } else {
                        Tag(text: subject.type == 1 ? "Hauptfach" : "Nebenfach", style: subject.type == 1 ? .main : .minor)
                        Text("\(gradesCount) \(gradesCount == 1 ? "Note" : "Noten")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(formatAverage(average))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(gradeClassColor(average).opacity(0.15))
                .foregroundStyle(gradeClassColor(average))
                .clipShape(Capsule())
        }
    }
}

struct Tag: View {
    enum Style { case main, minor }
    let text: String
    let style: Style
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(style == .main ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
            .foregroundStyle(style == .main ? .blue : .gray)
            .clipShape(Capsule())
    }
}

// MARK: - Extracted small views for HomeView body

private struct FilterAndReorderRow: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var halfYear: HomeView.HalfYearFilter
    let enableDrag: Bool
    @Binding var isEditingOrder: Bool
    let onToggleEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                SegmentButton(title: "Alle", active: halfYear == .all) { halfYear = .all }
                SegmentButton(title: "1. Hj", active: halfYear == .one) { halfYear = .one }
                SegmentButton(title: "2. Hj", active: halfYear == .two) { halfYear = .two }
            }
            .padding(4)
            .background(toggleBackground)
            .clipShape(Capsule())
            .shadow(color: toggleShadow, radius: 8, x: 0, y: 4)

            Spacer()

            if enableDrag {
                Button(isEditingOrder ? "Fertig" : "Reihenfolge") {
                    onToggleEdit()
                }
                .font(.footnote)
            }
        }
    }

    private var toggleBackground: Color {
        colorScheme == .dark
            ? Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.9)
            : .white
    }

    private var toggleShadow: Color {
        Color.black.opacity(colorScheme == .dark ? 0.5 : 0.12)
    }
}


private struct SummaryRow: View {
    let overall: Double?
    let subjectsCount: Int
    let totalGradesCount: Int
    let gradeColor: (Double?) -> Color

    var body: some View {
        let overallColor = gradeColor(overall)
        HStack(spacing: 12) {
            SummaryCard(title: "Gesamt") {
                Text(formatAverage(overall))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(overallColor.opacity(0.15))
                    .foregroundStyle(overallColor)
                    .clipShape(Capsule())
            }
            SummaryCard(title: "Fächer") {
                Text("\(subjectsCount)")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
            SummaryCard(title: "Noten") {
                Text("\(totalGradesCount)")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return String(format: "%.2f", v)
    }
}

private struct ToolbarTitleView: View {
    let greeting: String
    let displayName: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !displayName.isEmpty {
                    Text("\(displayName)!")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .allowsHitTesting(false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct NavigationLinksBackground: View {
    @EnvironmentObject var store: GradesStore
    @Binding var navigateToSettings: Bool
    @Binding var navigateToFinalGrade: Bool
    @Binding var navigateToSubjectsManage: Bool

    var body: some View {
        Group {
            NavigationLink(
                destination: AppSettingsView().environmentObject(store),
                isActive: $navigateToSettings
            ) { EmptyView() }
            NavigationLink(
                destination: AbiturExamView().environmentObject(store),
                isActive: $navigateToFinalGrade
            ) { EmptyView() }
            NavigationLink(
                destination: SubjectsManageView().environmentObject(store),
                isActive: $navigateToSubjectsManage
            ) { EmptyView() }
        }
    }
}
