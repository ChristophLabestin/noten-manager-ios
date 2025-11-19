import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AbiturExamView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    struct ExamStateItem {
        var writtenPoints: Double?
        var oralPoints: Double?
        var combinedPoints: Double?
        var isSaving: Bool
    }

    // Identifiable Wrapper für .sheet(item:)
    private struct SheetKey: Identifiable, Equatable {
        let id: String
    }

    @State private var examState: [String: ExamStateItem] = [:]
    @State private var showWrittenPickerFor: SheetKey? = nil
    @State private var showOralPickerFor: SheetKey? = nil

    // BottomNav Navigation
    @State private var navigateToSettings: Bool = false
    @State private var navigateToSubjects: Bool = false

    private var hasFachreferat: Bool { store.fachreferat != nil }

    private var examSubjects: [Subject] {
        store.subjects.filter { $0.examSubject == true }
    }

    private func calculateGradeWeightForSubject(_ subjectType: Int, _ grade: GradeWithId) -> Double {
        if subjectType == 1 {
            return grade.weight == 3 ? 2 : (grade.weight == 2 ? 2 : 1)
        }
        if subjectType == 0 {
            return grade.weight == 3 ? 2 : (grade.weight == 1 ? 2 : 1)
        }
        return 1
    }

    private func calculateHalfYearAverageForSubject(_ grades: [GradeWithId], _ subjectType: Int, _ halfYear: Int) -> Double? {
        let filtered = grades.filter { $0.halfYear == halfYear }
        guard !filtered.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in filtered {
            let w = calculateGradeWeightForSubject(subjectType, g)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return String(format: "%.2f", v)
    }

    private func getGradeClassColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    private func computeExamPoints(written: Double?, oral: Double?) -> Double? {
        if written == nil && oral == nil { return nil }
        if let w = written, let o = oral {
            return (2 * w + o) / 3.0
        }
        if let w = written { return w }
        return oral
    }

    // Durchschnitt eines Fachs
    private func averageForSubject(_ subject: Subject) -> Double? {
        let grades = store.gradesBySubject[subject.name] ?? []
        if grades.isEmpty { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in grades {
            let w = calculateGradeWeightForSubject(subject.type, g)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private var halfYearSummary: (totalPoints: Double, count: Int) {
        var totalPoints = 0.0
        var count = 0
        for subject in store.subjects {
            if subject.name == "Fachreferat" { continue }
            let subjectGrades = store.gradesBySubject[subject.name] ?? []
            let dropOption = subject.droppedHalfYear
            let isHalfYear1Dropped = (dropOption == 1)
            let isHalfYear2Dropped = (dropOption == 2)
            let first = isHalfYear1Dropped ? nil : calculateHalfYearAverageForSubject(subjectGrades, subject.type, 1)
            let second = isHalfYear2Dropped ? nil : calculateHalfYearAverageForSubject(subjectGrades, subject.type, 2)
            if let f = first { totalPoints += f; count += 1 }
            if let s = second { totalPoints += s; count += 1 }
        }
        return (totalPoints, count)
    }

    private var totalYearPoints: Double {
        halfYearSummary.totalPoints + (store.fachreferat?.grade ?? 0)
    }

    private var oralExamCount: Int {
        examSubjects.reduce(0) { sum, s in
            let state = examState[s.name]
            let hasOral = state?.oralPoints != nil
            return sum + (hasOral ? 1 : 0)
        }
    }

    private var oralLimitReached: Bool { oralExamCount >= 3 }

    private var totalExamPoints: Double {
        examSubjects.reduce(0) { sum, s in
            let state = examState[s.name]
            guard let combined = state?.combinedPoints else { return sum }
            return sum + combined * 2.0
        }
    }

    private var maxYearPoints: Int {
        halfYearSummary.count * 15 + (hasFachreferat ? 15 : 0)
    }
    private var maxExamPoints: Int {
        examSubjects.count * 30
    }

    private var totalPoints: Double { totalYearPoints + totalExamPoints }
    private var maxTotalPoints: Int { maxYearPoints + maxExamPoints }

    private var overallAverage: Double? {
        maxTotalPoints > 0 ? (totalPoints / Double(maxTotalPoints)) * 15.0 : nil
    }

    // MARK: - Extracted small views to help type checker

    @ViewBuilder
    private func overviewCard(subject: Subject, avg: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(subject.name).font(.headline)
                Spacer()
                Text(subject.type == 1 ? "Hauptfach" : "Nebenfach")
                    .font(.caption)
                    .foregroundStyle(subject.type == 1 ? .blue : .secondary)
            }
            HStack {
                Text("Jahresdurchschnitt").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                let color: Color = getGradeClassColor(avg)
                Text(formatAverage(avg))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func inputCard(subject: Subject, state: ExamStateItem?, oralLimitReached: Bool) -> some View {
        let written = state?.writtenPoints
        let oral = state?.oralPoints
        let combined = state?.combinedPoints
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(subject.name) - Abiturnote").font(.headline)
                Spacer()
                let color: Color = getGradeClassColor(combined)
                Text(formatAverage(combined))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }

            HStack {
                Button {
                    showWrittenPickerFor = SheetKey(id: subject.name)
                } label: {
                    Text(written != nil ? "Schriftliche Note anpassen" : "Schriftliche Note eintragen")
                        .font(.subheadline)
                }
                Spacer()
                Text(written != nil ? "\(Int(written!)) Punkte" : "Nicht eingetragen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    if oral == nil && oralLimitReached { return }
                    showOralPickerFor = SheetKey(id: subject.name)
                } label: {
                    Text(oral != nil ? "Mündliche Note anpassen" : "Mündliche Note eintragen")
                        .font(.subheadline)
                }
                .disabled(oral == nil && oralLimitReached)
                Spacer()
                Text(oral != nil ? "\(Int(oral!)) Punkte" : "Nicht eingetragen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if written != nil || oral != nil {
                Button(role: .destructive) {
                    Task { await handleClearAllExamPoints(subject) }
                } label: {
                    Text("Schriftliche & mündliche Note löschen")
                        .font(.footnote)
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // BurgerMenu-Header
                    BurgerMenuView(
                        isSmall: true,
                        title: "Abschlussprüfung",
                        subjectType: nil,
                        subtitle: "Abiturnoten verwalten"
                    )
                    .environmentObject(store)

                    if store.isLoading {
                        VStack(spacing: 8) {
                            ProgressView(value: store.progress, total: 100)
                            Text(store.loadingLabel).font(.footnote)
                        }
                        .padding(.horizontal)
                    }

                    // Gesamtpunkte
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gesamtpunkte").font(.headline)
                        let color: Color = getGradeClassColor(overallAverage)
                        let totalPointsDisplay: String = {
                            if maxTotalPoints > 0 {
                                let left = Int(round(totalPoints))
                                let right = Int(round(Double(maxTotalPoints)))
                                return "\(left) / \(right)"
                            } else {
                                return "-"
                            }
                        }()
                        Text(totalPointsDisplay)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(color.opacity(0.15))
                            .foregroundStyle(color)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal)

                    HStack {
                        SummaryCard(title: "Jahresleistungen") {
                            let yearPointsDisplay: String = {
                                if maxYearPoints > 0 {
                                    return "\(Int(round(totalYearPoints))) / \(maxYearPoints)"
                                } else {
                                    return "-"
                                }
                            }()
                            Text(yearPointsDisplay)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                        SummaryCard(title: "Abiturprüfungen") {
                            let examPointsDisplay: String = {
                                if maxExamPoints > 0 {
                                    return "\(Int(round(totalExamPoints))) / \(maxExamPoints)"
                                } else {
                                    return "-"
                                }
                            }()
                            Text(examPointsDisplay)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)

                    // Prüfungsfächer Übersicht
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prüfungsfächer").font(.headline)
                        Text("Übersicht deiner Prüfungsfächer. Die Auswahl kannst du in den Einstellungen anpassen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if store.subjects.isEmpty {
                            Text("Lege zuerst Fächer und Noten an, um deine Abiturpunkte zu berechnen.")
                                .foregroundStyle(.secondary)
                        } else if examSubjects.isEmpty {
                            Text("Du hast noch keine Prüfungsfächer ausgewählt. Du kannst sie in den Einstellungen festlegen.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(examSubjects, id: \.name) { subject in
                                    let avg = averageForSubject(subject)
                                    overviewCard(subject: subject, avg: avg)
                                }
                            }
                        }

                        if oralLimitReached {
                            Text("Du hast bereits drei mündliche Prüfungsnoten eingetragen. Es können maximal drei mündliche Prüfungen berücksichtigt werden.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    // Abiturnoten Eingabe
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Abiturnoten").font(.headline)
                        Text("Trage die schriftliche und optional die mündliche Note pro Prüfungsfach ein. Die Abiturnote wird berechnet als ((2 × schriftlich) + mündlich) / 3.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if examSubjects.isEmpty {
                            Text("Lege in den Einstellungen zunächst deine Prüfungsfächer fest, um Abiturnoten einzutragen.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(examSubjects, id: \.name) { subject in
                                    let state = examState[subject.name]
                                    inputCard(subject: subject, state: state, oralLimitReached: oralLimitReached)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    if oralLimitReached {
                        Text("Du hast bereits drei mündliche Prüfungsnoten eingetragen. Es können maximal drei mündliche Prüfungen berücksichtigt werden.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    // Hinweis
                    Text("Hinweis: Die hier berechneten Punkte dienen dir als Orientierung für dein Abitur an der FOS/BOS in Bayern. Es handelt sich nicht um eine offizielle Berechnung nach FOBOSO. Für verbindliche Auskünfte wende dich bitte an deine Schule.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                }
                .padding(.vertical, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { }
            .sheet(item: $showWrittenPickerFor) { key in
                let name = key.id
                PickerSheet(title: "Schriftliche Note", initial: examState[name]?.writtenPoints, onSelect: { value in
                    if let subject = store.subjects.first(where: { $0.name == name }) {
                        Task { await handleWrittenPointsChange(subject, points: value) }
                    }
                }, onClear: {
                    if let subject = store.subjects.first(where: { $0.name == name }) {
                        Task { await handleClearWrittenPoints(subject) }
                    }
                })
            }
            .sheet(item: $showOralPickerFor) { key in
                let name = key.id
                PickerSheet(title: "Mündliche Note", initial: examState[name]?.oralPoints, onSelect: { value in
                    if let subject = store.subjects.first(where: { $0.name == name }) {
                        Task { await handleOralPointsChange(subject, points: value) }
                    }
                }, onClear: {
                    if let subject = store.subjects.first(where: { $0.name == name }) {
                        Task { await handleClearOralPoints(subject) }
                    }
                })
            }
            .onAppear {
                Task { await loadExamState() }
            }
            .onChange(of: store.subjects) { _ in
                Task { await loadExamState() }
            }
            .onChange(of: store.encryptionKey) { _ in
                Task { await loadExamState() }
            }
            .background(
                NavigationLinksBackground(
                    navigateToSettings: $navigateToSettings,
                    navigateToSubjects: $navigateToSubjects
                )
                .environmentObject(store)
            )
        }
    }

    // MARK: - Actions & Persistence
    // ... (unverändert unterhalb)

    private func loadExamState() async {
        guard store.encryptionKey != nil else {
            examState = [:]
            return
        }
        var next: [String: ExamStateItem] = [:]
        for s in store.subjects {
            var written: Double? = nil
            var oral: Double? = nil
            var combined: Double? = nil

            if let enc = s.writtenExamPointsEncrypted, let key = store.encryptionKey {
                if let dec = try? CryptoService.decryptString(enc, key: key), let num = Double(dec), num.isFinite {
                    written = num
                }
            }
            if let enc = s.oralExamPointsEncrypted, let key = store.encryptionKey {
                if let dec = try? CryptoService.decryptString(enc, key: key), let num = Double(dec), num.isFinite {
                    oral = num
                }
            }
            if written != nil || oral != nil {
                combined = computeExamPoints(written: written, oral: oral)
            } else if let enc = s.examPointsEncrypted, let key = store.encryptionKey {
                if let dec = try? CryptoService.decryptString(enc, key: key), let num = Double(dec), num.isFinite {
                    combined = num
                    if written == nil, combined != nil {
                        written = combined
                    }
                }
            }
            next[s.name] = ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: false)
        }
        examState = next
    }

    private func persistExamPoints(subject: Subject, written: Double?, oral: Double?, combined: Double?) async {
        guard let uid = Auth.auth().currentUser?.uid, let key = store.encryptionKey else { return }
        let db = Firestore.firestore()
        let subjectDocRef = db.collection("users").document(uid).collection("subjects").document(subject.name)

        var writtenEncrypted: String? = nil
        var oralEncrypted: String? = nil
        var combinedEncrypted: String? = nil

        if let w = written {
            writtenEncrypted = try? CryptoService.encryptString(String(Int(w)), key: key)
        }
        if let o = oral {
            oralEncrypted = try? CryptoService.encryptString(String(Int(o)), key: key)
        }
        if let c = combined {
            combinedEncrypted = try? CryptoService.encryptString(String(c), key: key)
        }

        do {
            try await subjectDocRef.updateData([
                "writtenExamPointsEncrypted": writtenEncrypted as Any,
                "oralExamPointsEncrypted": oralEncrypted as Any,
                "examPointsEncrypted": combinedEncrypted as Any
            ])
            store.subjects = store.subjects.map { s in
                if s.name == subject.name {
                    return Subject(name: s.name,
                                   type: s.type,
                                   date: s.date,
                                   order: s.order,
                                   teacher: s.teacher,
                                   room: s.room,
                                   email: s.email,
                                   alias: s.alias,
                                   droppedHalfYear: s.droppedHalfYear,
                                   examSubject: s.examSubject,
                                   examType: s.examType,
                                   examPointsEncrypted: combinedEncrypted,
                                   writtenExamPointsEncrypted: writtenEncrypted,
                                   oralExamPointsEncrypted: oralEncrypted)
                }
                return s
            }
        } catch {
            // optional: Fehlerbehandlung
        }
    }

    private func updateExamState(_ subjectName: String, _ updater: (ExamStateItem?) -> ExamStateItem) {
        examState[subjectName] = updater(examState[subjectName])
    }

    private func handleWrittenPointsChange(_ subject: Subject, points: Double) async {
        let current = examState[subject.name]
        let oral = current?.oralPoints
        let written = points
        let combined = computeExamPoints(written: written, oral: oral)

        updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: true) }
        defer {
            updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: false) }
        }
        await persistExamPoints(subject: subject, written: written, oral: oral, combined: combined)
    }

    private func handleOralPointsChange(_ subject: Subject, points: Double) async {
        let current = examState[subject.name]
        let written = current?.writtenPoints
        let oral = points
        let combined = computeExamPoints(written: written, oral: oral)

        updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: true) }
        defer {
            updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: false) }
        }
        await persistExamPoints(subject: subject, written: written, oral: oral, combined: combined)
    }

    private func handleClearWrittenPoints(_ subject: Subject) async {
        let current = examState[subject.name]
        let oral = current?.oralPoints
        let written: Double? = nil
        let combined = computeExamPoints(written: written, oral: oral)

        updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: true) }
        defer {
            updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: false) }
        }
        await persistExamPoints(subject: subject, written: written, oral: oral, combined: combined)
    }

    private func handleClearOralPoints(_ subject: Subject) async {
        let current = examState[subject.name]
        let written = current?.writtenPoints
        let oral: Double? = nil
        let combined = computeExamPoints(written: written, oral: oral)

        updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: true) }
        defer {
            updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: false) }
        }
        await persistExamPoints(subject: subject, written: written, oral: oral, combined: combined)
    }

    private func handleClearAllExamPoints(_ subject: Subject) async {
        let written: Double? = nil
        let oral: Double? = nil
        let combined: Double? = nil

        updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: true) }
        defer {
            updateExamState(subject.name) { _ in ExamStateItem(writtenPoints: written, oralPoints: oral, combinedPoints: combined, isSaving: false) }
        }
        await persistExamPoints(subject: subject, written: written, oral: oral, combined: combined)
    }
}

// PickerSheet unverändert...
private struct PickerSheet: View {
    let title: String
    let initial: Double?
    let onSelect: (Double) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(stride(from: 15, through: 0, by: -1)), id: \.self) { value in
                        Button {
                            onSelect(Double(value))
                            dismiss()
                        } label: {
                            HStack {
                                Text("\(value) Punkte")
                                if Int(initial ?? -999) == value {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                if initial != nil {
                    Section {
                        Button(role: .destructive) {
                            onClear()
                            dismiss()
                        } label: {
                            Text("Eintrag löschen")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
}

private struct NavigationLinksBackground: View {
    @EnvironmentObject var store: GradesStore
    @Binding var navigateToSettings: Bool
    @Binding var navigateToSubjects: Bool

    var body: some View {
        Group {
            NavigationLink(
                destination: AppSettingsView().environmentObject(store),
                isActive: $navigateToSettings
            ) { EmptyView() }
            NavigationLink(
                destination: SubjectsManageView().environmentObject(store),
                isActive: $navigateToSubjects
            ) { EmptyView() }
        }
    }
}
