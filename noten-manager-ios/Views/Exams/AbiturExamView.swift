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

    @State private var examState: [String: ExamStateItem] = [:]

    // BottomNav Navigation
    @State private var navigateToSettings: Bool = false

    private var hasFachreferat: Bool { store.fachreferat != nil }
    private var hasSeminarRequirement: Bool { (store.gradeYear ?? 12) >= 13 }

    private var examSubjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.examSubject == true })
    }

    private var examWeightFactor: Double {
        let gy = store.gradeYear ?? 12
        if store.schoolType == .fos {
            return gy >= 13 ? 2 : 3
        }
        return 2
    }

    private func calculateGradeWeightForSubject(_ subjectType: Int, _ grade: GradeWithId) -> Double {
        store.effectiveGradeWeight(subjectType: subjectType, rawWeight: grade.weight)
    }

    private func calculateHalfYearAverageForSubject(_ subject: Subject, _ halfYear: Int) -> Double? {
        store.bestAvailableHalfYearValue(subject: subject, halfYear: halfYear)
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
            let dropOption = subject.droppedHalfYear
            let isHalfYear1Dropped = (dropOption == 1)
            let isHalfYear2Dropped = (dropOption == 2)
            let first = isHalfYear1Dropped ? nil : calculateHalfYearAverageForSubject(subject, 1)
            let second = isHalfYear2Dropped ? nil : calculateHalfYearAverageForSubject(subject, 2)
            if let f = first { totalPoints += f; count += 1 }
            if let s = second { totalPoints += s; count += 1 }
        }
        return (totalPoints, count)
    }

    private var totalYearPoints: Double {
        halfYearSummary.totalPoints + (store.fachreferat?.grade ?? 0) + seminarPointsDouble
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
            let rounded = combined.rounded()
            return sum + rounded * examWeightFactor
        }
    }

    private var maxYearPoints: Int {
        halfYearSummary.count * 15 + (hasFachreferat ? 15 : 0) + (hasSeminarRequirement ? 30 : 0)
    }
    private var maxExamPoints: Int {
        Int(examWeightFactor * Double(examSubjects.count) * 15)
    }

    private var totalPoints: Double { totalYearPoints + totalExamPoints }
    private var maxTotalPoints: Int { maxYearPoints + maxExamPoints }

    private var animationsOn: Bool { store.animationsEnabled }

    private var seminarFinalPoints: Double? {
        guard let sem = store.seminarPerformance else { return nil }
        let zero = [sem.individualPoints, sem.paperPoints, sem.presentationPoints].contains { $0 == 0 }
        if zero { return 0 }
        guard let individual = sem.individualPoints,
              let paper = sem.paperPoints,
              let presentation = sem.presentationPoints else { return nil }
        let raw = (individual + presentation + (2 * paper)) / 4.0
        let rounded = raw.rounded(.toNearestOrAwayFromZero)
        return max(0, min(15, rounded))
    }

    private var seminarPointsDouble: Double {
        guard hasSeminarRequirement, let value = seminarFinalPoints else { return 0 }
        return value * 2
    }

    // MARK: - Extracted views

    private func subjectAccent(for subject: Subject) -> Color {
        if subject.isElective { return Color(hex: "#6b7280") }
        return subject.type == 1 ? Color(hex: "#2563eb") : Color(hex: "#0ea5e9")
    }

    private func scoreSelectorRow(label: String,
                                  icon: String,
                                  value: Double?,
                                  accent: Color,
                                  disabled: Bool = false,
                                  onSelect: @escaping (Double) -> Void,
                                  onClear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Menu {
                ForEach(Array(stride(from: 15, through: 0, by: -1)), id: \.self) { val in
                    Button("\(val) Punkte") { onSelect(Double(val)) }
                }
                if value != nil {
                    Button(role: .destructive) {
                        onClear()
                    } label: {
                        Label("Eintrag löschen", systemImage: "trash")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.yellow.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(Color.yellow.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value != nil ? "\(Int(value!)) Punkte" : "Nicht eingetragen")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                        Text("0 bis 15 Punkte")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                }
                .padding(10)
                .background(Color.gray.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(disabled)
        }
    }

    private func examInputCard(subject: Subject, state: ExamStateItem?, oralLimitReached: Bool) -> some View {
        let accent = subjectAccent(for: subject)
        let combined = state?.combinedPoints
        let written = state?.writtenPoints
        let oral = state?.oralPoints

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.name)
                        .font(.headline.weight(.semibold))
                }
                Spacer()
                let color: Color = getGradeClassColor(combined)
                Text(formatAverage(combined))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(color.opacity(0.16))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }

            scoreSelectorRow(
                label: "Schriftliche Note",
                icon: "doc.text.fill",
                value: written,
                accent: accent,
                onSelect: { pts in Task { await handleWrittenPointsChange(subject, points: pts) } },
                onClear: { Task { await handleClearWrittenPoints(subject) } }
            )

            scoreSelectorRow(
                label: "Mündliche Note",
                icon: "person.wave.2.fill",
                value: oral,
                accent: accent,
                disabled: oral == nil && oralLimitReached,
                onSelect: { pts in Task { await handleOralPointsChange(subject, points: pts) } },
                onClear: { Task { await handleClearOralPoints(subject) } }
            )

            if written != nil || oral != nil {
                Button(role: .destructive) {
                    Task { await handleClearAllExamPoints(subject) }
                } label: {
                    Label("Alle Einträge löschen", systemImage: "trash")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if oral == nil && oralLimitReached {
                Text("Maximal drei mündliche Prüfungen möglich. Lösche eine bestehende mündliche Note, um Platz zu schaffen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if state?.isSaving == true {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Speichere …")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.20), lineWidth: 1)
        )
    }

    private func examSubjectSummaryRow(_ subject: Subject) -> some View {
        let avg = averageForSubject(subject)
        let combined = examState[subject.name]?.combinedPoints
        func chip(title: String, value: Double?) -> some View {
            let color = getGradeClassColor(value)
            return VStack(alignment: .trailing, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(formatAverage(value))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.14))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }
        }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(subject.name)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text("Jahresdurchschnitt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                chip(title: "Jahr", value: avg)
                chip(title: "Abitur", value: combined)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var headerCard: some View {
        let yearBadge = {
            if let year = store.activeSchoolYearId {
                return PillBadge(
                    text: year,
                    systemImage: "calendar",
                    foreground: .indigo,
                    background: Color.indigo.opacity(0.14)
                )
            }
            return PillBadge(
                text: "Aktuelles Schuljahr",
                systemImage: "calendar",
                foreground: .indigo,
                background: Color.indigo.opacity(0.14)
            )
        }()

        let examDisplay: String = {
            if maxExamPoints > 0 {
                return "\(Int(round(totalExamPoints))) / \(maxExamPoints)"
            }
            return "-"
        }()

        return SettingsCard(
            title: "Prüfungspunkte",
            subtitle: store.schoolType == .fos ? "FOS (3× Gewichtung)" : "BOS (2× Gewichtung)",
            systemImage: "graduationcap.fill",
            accent: .indigo,
            trailing: { yearBadge }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Ergebnis")
                        .font(.headline)
                    Spacer()
                    Text(examDisplay)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.15))
                        .foregroundStyle(Color.indigo)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var examSubjectsCard: some View {
        SettingsCard(
            title: "Prüfungsfächer",
            subtitle: "Jahresleistungen & Abiturnoten",
            systemImage: "text.book.closed",
            accent: .cyan
        ) {
            if store.subjects.isEmpty {
                Text("Lege zuerst Fächer und Noten an, um deine Abiturpunkte zu berechnen.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else if examSubjects.isEmpty {
                Text("Du hast noch keine Prüfungsfächer ausgewählt. Passe die Auswahl in den Einstellungen an.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(examSubjects.enumerated()), id: \.element.name) { entry in
                        let subject = entry.element
                        let delay = 0.12 + Double(entry.offset) * 0.05
                        examSubjectSummaryRow(subject)
                            .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                    }
                }
            }
        }
    }

    private var examInputSection: some View {
        SettingsCard(
            title: "Abiturnoten eintragen",
            subtitle: "Schriftlich + optional mündlich",
            systemImage: "square.and.pencil",
            accent: .orange
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pro Fach: Schriftliche Punkte (doppelt) und optional eine mündliche Note (einfach).")
                    Text("Abiturnote: (2 × schriftlich + mündlich) / 3")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HelpCenterLink(
                    title: "Hilfe zu Prüfungen",
                    subtitle: "Gewichtung schriftlich/mündlich, Mindestpunkte & Zulassung",
                    section: .exams,
                    accent: .mint
                )

                if examSubjects.isEmpty {
                    Text("Lege in den Einstellungen deine Prüfungsfächer fest, um Abiturnoten einzutragen.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(examSubjects.enumerated()), id: \.element.name) { entry in
                            let subject = entry.element
                            let delay = 0.18 + Double(entry.offset) * 0.05
                            examInputCard(subject: subject, state: examState[subject.name], oralLimitReached: oralLimitReached)
                                .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                        }
                    }
                }

                if oralLimitReached {
                    Text("Maximal drei mündliche Prüfungen werden berücksichtigt. Entferne eine mündliche Note, um Platz zu schaffen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isLoading {
                    VStack(spacing: 8) {
                        ProgressView(value: store.progress, total: 100)
                        Text(store.loadingLabel).font(.footnote)
                    }
                    .padding(.horizontal)
                }

                headerCard
                    .softFadeIn(enabled: animationsOn, delay: 0.03, offset: 12)
                examSubjectsCard
                    .softFadeIn(enabled: animationsOn, delay: 0.08, offset: 12)
                examInputSection
                    .softFadeIn(enabled: animationsOn, delay: 0.12, offset: 12)

                Text("Hinweis: Die Berechnung dient als Orientierung für dein Abitur (FOS/BOS Bayern) und ersetzt keine offiziellen Angaben deiner Schule.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softFadeIn(enabled: animationsOn, delay: 0.18, offset: 12)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Abschlussprüfung")
                        .font(.headline)
                    Text("Abiturnoten verwalten")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            Task { await loadExamState() }
        }
        .onChange(of: store.subjects) { _, _ in
            Task { await loadExamState() }
        }
        .onChange(of: store.encryptionKey) { _, _ in
            Task { await loadExamState() }
        }
        .background(
            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
        )
        .background(
            NavigationLinksBackground(
                navigateToSettings: $navigateToSettings
            )
            .environmentObject(store)
        )
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
        guard let schoolYearId = store.activeSchoolYearId else { return }
        let db = Firestore.firestore()
        let subjectDocRef = db.collection("users").document(uid).collection("schoolYears").document(schoolYearId).collection("subjects").document(subject.name)

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
            store.examPoints[subject.name] = combined
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
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

private struct NavigationLinksBackground: View {
    @EnvironmentObject var store: GradesStore
    @Binding var navigateToSettings: Bool

    var body: some View {
        Color.clear
            .navigationDestination(isPresented: $navigateToSettings) {
                AppSettingsView().environmentObject(store)
            }
    }
}
