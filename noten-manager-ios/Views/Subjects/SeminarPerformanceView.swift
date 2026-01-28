import SwiftUI
import CryptoKit

struct SeminarPerformanceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var topic: String = ""
    @State private var individualPoints: Double?
    @State private var paperPoints: Double?
    @State private var presentationPoints: Double?
    @State private var submissionDate: Date = Date()
    @State private var presentationDate: Date?
    @State private var note: String = ""
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var showDeleteAlert: Bool = false
    @FocusState private var focusedField: Field?
    @State private var hasCustomSubmissionDate: Bool = false

    private var gradeYear: Int { store.gradeYear ?? 12 }

    private enum Field: Hashable {
        case topic, note
    }

    private var canSave: Bool {
        store.encryptionKey != nil && !isSaving
    }

    private var hasExisting: Bool {
        store.seminarPerformance != nil
    }

    private var computedSeminarPoints: Double? {
        let zeroDetected = [individualPoints, paperPoints, presentationPoints].contains { $0 == 0 }
        if zeroDetected { return 0 }
        guard let individual = individualPoints,
              let paper = paperPoints,
              let presentation = presentationPoints else { return nil }
        let raw = (individual + presentation + (2 * paper)) / 4.0
        let rounded = raw.rounded(.toNearestOrAwayFromZero)
        return max(0, min(15, rounded))
    }

    private var seminarStatusText: String {
        if let value = computedSeminarPoints {
            if value == 0 { return "Seminarfach aktuell nicht bestanden (0 Punkte in einem Teil)." }
            return "Gewichtetes Ergebnis: \(formatAverage(value)) Punkte (Seminararbeit zählt doppelt)."
        }
        return "Trage alle drei Teilnoten ein, um die Seminarbewertung zu sehen."
    }

    private var submissionYearForSchoolStart: Int {
        if let id = store.activeSchoolYearId,
           let startYear = Int(id.prefix(4)) {
            return gradeYear == 12 ? (startYear + 1) : startYear
        }
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: Date())
        let month = cal.component(.month, from: Date())
        let base = month >= 8 ? year : year - 1
        return gradeYear == 12 ? (base + 1) : base
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Seminarfach",
                        subtitle: "Bewertung & Termine nach FOBOSO",
                        systemImage: "doc.text.fill",
                        accent: .indigo
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Teilnoten")
                                    .font(.headline)
                                pointsPickerRow(
                                    label: "Individuelle Leistung",
                                    value: $individualPoints
                                )
                                pointsPickerRow(
                                    label: "Seminararbeit (2×)",
                                    value: $paperPoints
                                )
                                pointsPickerRow(
                                    label: "Präsentation & Diskussion",
                                    value: $presentationPoints
                                )

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Berechnung")
                                            .font(.subheadline.weight(.semibold))
                                        Text(seminarStatusText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(computedSeminarPoints != nil ? formatAverage(computedSeminarPoints) : "-")
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(gradeColor(computedSeminarPoints).opacity(0.15))
                                        .foregroundStyle(gradeColor(computedSeminarPoints))
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Thema (optional)")
                                        .font(.headline)
                                    TextField("Kurztitel der Seminararbeit", text: $topic)
                                        .submitLabel(.next)
                                        .focused($focusedField, equals: .topic)
                                        .onSubmit { focusedField = .note }
                                        .padding(12)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }

                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Termine")
                                        .font(.headline)
                                    dateRow(
                                        icon: "calendar",
                                        title: "Abgabe",
                                        subtitle: "2. Dienstag im Schuljahr",
                                        date: $submissionDate,
                                        onChange: { hasCustomSubmissionDate = true }
                                    )
                                    dateRow(
                                        icon: "person.2.fill",
                                        title: "Präsentation",
                                        subtitle: "Vortrag & Diskussion",
                                        date: Binding(
                                            get: { presentationDate ?? submissionDate },
                                            set: { presentationDate = $0 }
                                        ),
                                        clearAction: {
                                            presentationDate = nil
                                        }
                                    )
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Notiz (optional)")
                                        .font(.subheadline)
                                    TextField("Zwischenstand, Quellen, To-dos …", text: $note, axis: .vertical)
                                        .lineLimit(2...4)
                                        .submitLabel(.done)
                                        .focused($focusedField, equals: .note)
                                        .padding(12)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }

                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FOBOSO-Kernpunkte")
                                    .font(.headline)
                                HelpCenterLink(
                                    title: "Seminarfach im Help Center",
                                    subtitle: "Bewertung, Termine und Pflichten",
                                    section: .exams,
                                    accent: .indigo,
                                    scrollId: "help_exams_seminar"
                                )
                                .environmentObject(store)
                            }
                        }
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if hasExisting {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Seminarfach löschen")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .red))
                        .padding(.top, 4)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .sheetNavigationTitle("Seminarfach")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    ToolbarIcon(symbol: "xmark", showDot: false)
                }
                .accessibilityLabel("Abbrechen")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ToolbarLoadingIcon()
                    } else {
                        ToolbarIcon(symbol: "checkmark", showDot: false)
                    }
                }
                .accessibilityLabel("Speichern")
                .disabled(!canSave)
            }
        }
            .onAppear {
                if topic.isEmpty, let sem = store.seminarPerformance {
                    topic = sem.topic ?? ""
                    individualPoints = sem.individualPoints
                    paperPoints = sem.paperPoints
                    presentationPoints = sem.presentationPoints
                    submissionDate = sem.submissionDate ?? submissionDate
                    presentationDate = sem.presentationDate
                    note = sem.note ?? ""
                    hasCustomSubmissionDate = true
                    Task { await adjustSubmissionIfBeforeSchoolStart() }
                } else if topic.isEmpty {
                    Task { await fillDefaultSubmissionDate() }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .alert("Seminarfach löschen?", isPresented: $showDeleteAlert) {
                Button("Löschen", role: .destructive) {
                    Task { await delete() }
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Alle gespeicherten Seminarfach-Infos werden entfernt.")
            }
        }
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return String(format: "%.1f", v)
    }

    private func gradeColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    private func pointsPickerRow(label: String, value: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Menu {
                Button("Keine Angabe") { value.wrappedValue = nil }
                Divider()
                ForEach(Array(stride(from: 15, through: 0, by: -1)), id: \.self) { val in
                    Button("\(val) Punkte") { value.wrappedValue = Double(val) }
                }
            } label: {
                HStack {
                    Text(value.wrappedValue != nil ? "\(Int(value.wrappedValue!)) Punkte" : "Nicht eingetragen")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                }
                .padding(10)
                .background(Color.gray.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func dateRow(icon: String,
                         title: String,
                         subtitle: String? = nil,
                         date: Binding<Date>,
                         onChange: (() -> Void)? = nil,
                         clearAction: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.indigo.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.indigo)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Spacer()
                DatePicker("", selection: date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .onChange(of: date.wrappedValue) { _, _ in
                        onChange?()
                    }
            }
        }
        .padding(12)
        .background(Color.formInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func save() async {
        guard !isSaving, let key = store.encryptionKey else { return }
        isSaving = true
        error = nil
        do {
            try await store.setSeminarPerformance(
                topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
                individualPoints: individualPoints,
                paperPoints: paperPoints,
                presentationPoints: presentationPoints,
                submissionDate: submissionDate,
                presentationDate: presentationDate,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                using: key
            )
            dismiss()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func delete() async {
        guard !isSaving else { return }
        isSaving = true
        await store.deleteSeminarPerformance()
        await MainActor.run {
            dismiss()
        }
        isSaving = false
    }

    private func fillDefaultSubmissionDate() async {
        guard !hasCustomSubmissionDate else { return }
        let year = submissionYearForSchoolStart
        if let bySummer = await defaultDateUsingSummerBreak(startYear: year) {
            await MainActor.run {
                submissionDate = bySummer
                hasCustomSubmissionDate = true
            }
            return
        }
        let fallback = defaultDateFallback(startYear: year)
        await MainActor.run {
            submissionDate = fallback
            hasCustomSubmissionDate = true
        }
    }

    private func defaultDateUsingSummerBreak(startYear: Int) async -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        guard let schoolStart = await HolidaysService.shared.schoolStartDate(forYear: startYear) else {
            return nil
        }
        return computeSecondTuesday(fromSchoolStart: schoolStart, calendar: cal)
    }

    private func defaultDateFallback(startYear: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let approxStart = cal.date(from: DateComponents(year: startYear, month: 9, day: 10)) ?? Date()
        return computeSecondTuesday(fromSchoolStart: approxStart, calendar: cal)
    }

    private func nextWeekday(_ weekday: Int, onOrAfter start: Date, using cal: Calendar) -> Date? {
        var date = cal.startOfDay(for: start)
        for _ in 0..<60 {
            if cal.component(.weekday, from: date) == weekday {
                return date
            }
            date = cal.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return nil
    }

    private func computeSecondTuesday(fromSchoolStart start: Date, calendar cal: Calendar) -> Date {
        let firstTuesday = nextWeekday(3, onOrAfter: start, using: cal) ?? start
        return cal.date(byAdding: .day, value: 7, to: firstTuesday) ?? firstTuesday
    }

    private func adjustSubmissionIfBeforeSchoolStart() async {
        let cal = Calendar(identifier: .gregorian)
        guard let schoolStart = await HolidaysService.shared.schoolStartDate(forYear: submissionYearForSchoolStart) else { return }
        if submissionDate < schoolStart {
            let corrected = computeSecondTuesday(fromSchoolStart: schoolStart, calendar: cal)
            await MainActor.run {
                submissionDate = corrected
                hasCustomSubmissionDate = false
            }
        }
    }
}
