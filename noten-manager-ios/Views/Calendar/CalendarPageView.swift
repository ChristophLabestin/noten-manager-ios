import SwiftUI

struct CalendarPageView: View {
    @EnvironmentObject var store: GradesStore
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    
    // Navigation triggers
    @State private var showExamList = false
    @State private var showHomeworkList = false
    @State private var detailExam: Exam?
    @State private var detailHomework: Homework?

    // Action sheets state
    @State private var examForNewGrade: Exam?
    @State private var fachreferatExam: Exam?
    @State private var reminderExam: Exam?
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var shareError: String?
    @State private var showLegend = false
    @State private var examToDelete: Exam?
    @State private var editingExam: Exam?
    @State private var editingHomework: Homework?
    @State private var holidays: [HolidayPeriod] = []
    // showNextExamCard is now managed by GradesStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // Header
                headerSection
                    .padding(.horizontal, 16)
                
                // MARK: - Month Calendar
                VStack(spacing: 16) {
                    // Header (Month Name + Arrows)
                    HStack {
                        Text(monthFormatter.string(from: currentMonth).capitalized)
                            .font(.title2.weight(.bold))
                        Text(yearFormatter.string(from: currentMonth))
                            .font(.title2.weight(.regular))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button {
                                changeMonth(by: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 32, height: 32)
                                    .background(Color.formInputBackground)
                                    .clipShape(Circle())
                            }
                            
                            Button {
                                changeMonth(by: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 32, height: 32)
                                    .background(Color.formInputBackground)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    // Weekday Headers
                    HStack {
                        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                            Text(symbol)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    // Days Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                        ForEach(Array(daysInMonth().enumerated()), id: \.offset) { _, date in
                            if let date = date {
                                DayCell(
                                    date: date,
                                    isSelected: isSameDay(date, selectedDate),
                                    isToday: isSameDay(date, Date()),
                                    isHoliday: isHoliday(date),
                                    hasExam: hasExam(on: date),
                                    hasHomework: hasHomework(on: date)
                                )
                                .onTapGesture {
                                    withAnimation(.snappy) {
                                        selectedDate = date
                                    }
                                }
                            } else {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fill)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.formSectionBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                
                // MARK: - Selected Day / Upcoming
                VStack(alignment: .leading, spacing: 16) {
                    Text(isSameDay(selectedDate, Date()) ? "Heute anstehend" : "Am \(dateFormatter.string(from: selectedDate))")
                        .font(.headline)
                        .padding(.horizontal, 20)
                    
                    let events = eventsForDate(selectedDate)
                    
                    if events.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("Keine Einträge")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(Color.formSectionBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(events) { item in
                                calendarItemRow(for: item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // MARK: - Upcoming Exams Preview (Always visible below selected day?)
                    // Or we just show upcoming only if today is selected and empty?
                    // User said: "below the calendar it should list the next exams"
                    // Let's add a separate section for "Nächste Klausuren" regardless of selection, or maybe just if selection is empty/past?
                    // Let's stick to Selected Day first, and maybe add "Demnächst" below.
                    
                    // Always show upcoming exams relative to selected date
                    Divider().padding(.vertical, 8)
                    Text("Demnächst")
                        .font(.headline)
                        .padding(.horizontal, 20)
                    
                    let upcoming = upcomingExams(from: selectedDate).prefix(3)
                    if upcoming.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.title2)
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("Keine anstehenden Klausuren")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color.formSectionBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(upcoming) { exam in
                                ExamRowView(exam: exam, onTap: {
                                    detailExam = exam
                                }) {
                                     contextMenuContent(for: exam)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // MARK: - Settings Toggle
                    HStack {
                        Label("Vorschau auf Startseite", systemImage: "calendar.badge.clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { store.showNextExamCard },
                            set: { newValue in
                                Task {
                                    await store.updatePreferences(showNextExamCard: newValue)
                                }
                            }
                        ))
                            .labelsHidden()
                            .scaleEffect(0.8)
                            .tint(.blue)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
            }
            .padding(.vertical, 16)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    Button {
                        showExamList = true
                    } label: {
                        ToolbarIcon(symbol: "calendar.badge.clock", showDot: false)
                    }
                    .accessibilityLabel("Klausurenliste öffnen")
                    
                    Button {
                        showHomeworkList = true
                    } label: {
                        ToolbarIcon(symbol: "checklist", showDot: false)
                    }
                    .accessibilityLabel("Hausaufgabenliste öffnen")
                    
                    Button {
                        showLegend = true
                    } label: {
                        ToolbarIcon(symbol: "info.circle", showDot: false)
                    }
                    .accessibilityLabel("Legende anzeigen")
                }
            }
        }
        .sheet(isPresented: $showLegend) {
            CalendarLegendView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showExamList) {
            ExamListView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showHomeworkList) {
            HomeworkListView()
                .environmentObject(store)
        }
        .sheet(item: $detailExam) { exam in
            ExamDetailSheet(exam: exam, onEdit: { editingExam = $0 })
                .environmentObject(store)
        }
        .sheet(item: $detailHomework) { homework in
           HomeworkDetailSheet(homework: homework, onEdit: { editingHomework = $0 })
                .environmentObject(store)
        }
        .sheet(item: $editingExam) { exam in
            EditExamView(exam: exam)
                .environmentObject(store)
        }
        .sheet(item: $editingHomework) { homework in
            EditHomeworkView(homework: homework)
                .environmentObject(store)
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
        .sheet(item: $fachreferatExam, onDismiss: completeFachreferatExamIfNeeded) { exam in
            NavigationStack {
                AddFachreferatView(preselectedSubjectName: exam.subjectKey ?? exam.subjectName)
                    .environmentObject(store)
            }
        }
        .sheet(item: $reminderExam) { exam in
            ExamReminderView(exam: exam)
                .environmentObject(store)
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL])
            } else {
                Text("Kein Link verfügbar")
            }
        }
        .alert("Link konnte nicht erstellt werden", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: {
            if let shareError { Text(shareError) }
        }
        .alert("Prüfung löschen?", isPresented: Binding(
            get: { examToDelete != nil },
            set: { if !$0 { examToDelete = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                if let exam = examToDelete {
                    Task { await deleteExamConfirmed(exam) }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Bist du sicher? Dies kann nicht widerrufen werden.")
        }
        .task {
            await loadHolidays()
        }
        .onChange(of: currentMonth) { _ in
            Task { await loadHolidays() }
        }
    }

    @ViewBuilder
    private func calendarItemRow(for item: CalendarItem) -> some View {
        switch item {
        case .exam(let exam):
            ExamRowView(exam: exam, onToggleReminder: {
                reminderExam = exam
            }, onMarkCompleted: {
                Task { await markExamCompleted(exam) }
            }, onUndoCompleted: {
                Task { await markExamNotCompleted(exam) }
            }, onTap: {
                detailExam = exam
            }) {
                contextMenuContent(for: exam)
            }
        case .homework(let homework):
            // Placeholder for Homework Row - reusing ExamRow style or custom
            SettingsCard(
                title: homework.title,
                subtitle: store.resolveLocalSubjectNameForHomework(homework) ?? homework.subjectName,
                systemImage: "doc.text",
                accent: .green
            ) {
                EmptyView()
            }
            .onTapGesture {
                detailHomework = homework
            }
        case .holiday(let name, _):
            SettingsCard(
                title: name,
                subtitle: "Schulferien",
                systemImage: "beach.umbrella.fill",
                accent: .orange
            ) {
                EmptyView()
            }
        }
    }
    
    // MARK: - Logic
    
    enum CalendarItem: Identifiable {
        case exam(Exam)
        case homework(Homework)
        case holiday(name: String, date: Date)
        
        var id: String {
            switch self {
            case .exam(let e): return "exam_\(e.id)"
            case .homework(let h): return "hw_\(h.id)"
            case .holiday(let name, let d): return "hol_\(name)_\(d)"
            }
        }
        
        var date: Date {
            switch self {
            case .exam(let e): return e.date
            case .homework(let h): return h.dueDate ?? Date.distantFuture
            case .holiday(_, let d): return d
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Kalender")
                .font(.title2.weight(.bold))
            Text("Deine Termine und Ferien")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func eventsForDate(_ date: Date) -> [CalendarItem] {
        let exams = store.allExams.filter { isSameDay($0.date, date) }.map { CalendarItem.exam($0) }
        let homeworks = store.allHomeworks.filter {
            guard let dueDate = $0.dueDate else { return false }
            return isSameDay(dueDate, date)
        }.map { CalendarItem.homework($0) }
        
        var holidayItems: [CalendarItem] = []
        let matchingHolidays = getHolidays(for: date)
        
        for holiday in matchingHolidays {
            // Use nameCp (capitalized/pretty name) if available, otherwise name
            var displayName = holiday.nameCp ?? holiday.name
            
            // Renaming logic removed as we now fetch "Buß- und Bettag" correctly from the API.
            // If "Herbstferien" (school) and "Buß- und Bettag" (public) overlap, both will be shown.
            
            holidayItems.append(.holiday(name: displayName, date: date))
        }
        
        return (exams + homeworks + holidayItems).sorted { $0.date < $1.date }
    }
    
    private func getHolidays(for date: Date) -> [HolidayPeriod] {
        holidays.filter { period in
            let start = Calendar.current.startOfDay(for: period.start)
            let end = Calendar.current.startOfDay(for: period.end)
            let check = Calendar.current.startOfDay(for: date)
            return check >= start && check <= end
        }
    }
    
    private func hasExam(on date: Date) -> Bool {
        store.allExams.contains { isSameDay($0.date, date) }
    }
    
    private func upcomingExams(from date: Date) -> [Exam] {
        store.allExams.filter { exam in
            // upcoming means strictly after the selected date (to avoid duplication with the selected day list)
            // Verify if user wants "from selected date on" including selected date?
            // "showing upcoming stuff if today is selected... list the next three from the selected date on"
            // If I select today, I see today's exams. Below, I see exams AFTER today.
            // If I include the same day, they appear twice.
            // Let's assume strict inequality for "Demnächst" (Upcoming).
            Calendar.current.compare(exam.date, to: date, toGranularity: .day) == .orderedDescending
        }
        .sorted { $0.date < $1.date }
    }
    
    private func loadHolidays() async {
        let year = Calendar.current.component(.year, from: currentMonth)
        do {
            async let currentSchool = HolidaysService.shared.fetchHolidays(year: year)
            async let nextSchool = HolidaysService.shared.fetchHolidays(year: year + 1)
            async let prevSchool = HolidaysService.shared.fetchHolidays(year: year - 1)
            
            async let currentPublic = HolidaysService.shared.fetchPublicHolidays(year: year)
            async let nextPublic = HolidaysService.shared.fetchPublicHolidays(year: year + 1)
            async let prevPublic = HolidaysService.shared.fetchPublicHolidays(year: year - 1)
            
            let allSchool = await (prevSchool + currentSchool + nextSchool)
            let allPublic = await (prevPublic + currentPublic + nextPublic)
            
            await MainActor.run {
                // Prioritize public holidays so their specific names appear first
                self.holidays = allPublic + allSchool
            }
        } catch {
            print("Failed to load holidays: \(error)")
        }
    }

    private func isHoliday(_ date: Date) -> Bool {
        holidays.contains { period in
            // Normalize to start of day for comparison to be safe, though usage usually ignores time
            let start = Calendar.current.startOfDay(for: period.start)
            let end = Calendar.current.startOfDay(for: period.end)
            let check = Calendar.current.startOfDay(for: date)
            return check >= start && check <= end
        }
    }
    
    private func hasHomework(on date: Date) -> Bool {
        store.allHomeworks.contains {
            guard let dueDate = $0.dueDate else { return false }
            return isSameDay(dueDate, date)
        }
    }
    
    private func changeMonth(by value: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }
    
    private func daysInMonth() -> [Date?] {
        guard let range = Calendar.current.range(of: .day, in: .month, for: currentMonth),
              let firstDay = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: currentMonth)) else {
            return []
        }
        
        let weekday = Calendar.current.component(.weekday, from: firstDay)
        // Adjust for Monday start (ISO 8601) usually desired in EU
        // Calendar.current.firstWeekday depends on locale, let's assume Monday start for consistency if "de" locale
        let offset = (weekday + 5) % 7 // Monday=0, Sunday=6
        
        var days: [Date?] = Array(repeating: nil, count: offset)
        
        for day in range {
            if let date = Calendar.current.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        return days
    }
    
    private func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    
    private var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f
    }
    
    private var yearFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }
    
    private var weekdaySymbols: [String] {
        var symbols = Calendar.current.shortWeekdaySymbols
        // Shift to start with Monday if needed, usually system locale handles this.
        // Assuming German/EU locale where Monday is first.
        let first = Calendar.current.firstWeekday
        if first == 2 { // Monday
             // symbols are usually [Sun, Mon, Tue...]
             // rotate to [Mon, Tue... Sun]
             let sun = symbols.removeFirst()
             symbols.append(sun)
        }
        return symbols.map { $0.prefix(1).uppercased() } // Just first letter
    }
    
    // MARK: - Actions Logic
    
    @ViewBuilder
    private func contextMenuContent(for exam: Exam) -> some View {
        if !exam.isCompleted {
            Button {
                if isFachreferatExam(exam) { fachreferatExam = exam } else { examForNewGrade = exam }
            } label: {
                Label("Note eintragen", systemImage: "pencil")
            }
            Button {
                reminderExam = exam
            } label: {
                Label("Erinnerung", systemImage: reminderIconName(exam))
            }
        } else {
             Button {
                Task { await markExamNotCompleted(exam) }
            } label: {
                Label("Als offen markieren", systemImage: "arrow.uturn.backward")
            }
        }
        
        Button {
            presentShareLink(for: exam)
        } label: {
            Label("Teilen", systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        Button(role: .destructive) {
            examToDelete = exam
        } label: {
            Label("Löschen", systemImage: "trash")
        }
    }
    
    private func markExamCompleted(_ exam: Exam) async {
        if exam.isShared {
            await store.setUserCompletedForSharedExam(examId: exam.id, completed: true, groupId: exam.groupId)
        } else {
            await store.setExamCompleted(id: exam.id, completed: true)
        }
    }
    
    private func markExamNotCompleted(_ exam: Exam) async {
        if exam.isShared {
            await store.setUserCompletedForSharedExam(examId: exam.id, completed: false, groupId: exam.groupId)
        } else {
            await store.setExamCompleted(id: exam.id, completed: false)
        }
    }
    
    private func deleteExamConfirmed(_ exam: Exam) async {
        if exam.isShared {
            if let gid = exam.groupId {
                await store.deleteSharedExamFromGroup(groupId: gid, id: exam.id)
            }
        } else {
            await store.deleteExamFromFirestore(id: exam.id)
        }
    }
    
    private func presentShareLink(for exam: Exam) {
        shareError = nil
        let subject = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = HomeworkShareLinkBuilder.url(
            title: exam.title,
            subjectName: subject.isEmpty ? exam.subjectKey : subject,
            dueDate: exam.date
        ) else {
            shareError = "Der Link konnte nicht erstellt werden."
            return
        }
        shareURL = url
        showShareSheet = true
    }
    
    private func isFachreferatExam(_ exam: Exam) -> Bool {
        exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fachreferat" && (store.gradeYear == 12)
    }
    
    private func completeFachreferatExamIfNeeded() {
        guard let exam = fachreferatExam else { return }
        fachreferatExam = nil
        guard store.fachreferat != nil else { return }
        Task {
            await store.setExamCompleted(id: exam.id, completed: true)
        }
    }
    
    private func noteForExam(_ exam: Exam) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = exam.hasTime ? .short : .none
        let dateString = formatter.string(from: exam.date)
        return "Geschrieben am \(dateString)"
    }
    
    private func reminderIconName(_ exam: Exam) -> String {
        return exam.reminderAt == nil ? "bell" : "bell.fill"
    }
}

// MARK: - Subviews

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isHoliday: Bool
    let hasExam: Bool
    let hasHomework: Bool
    
    private var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(dayNumber)
                .font(.body.weight(isSelected || isToday || isHoliday ? .bold : .regular))
                .foregroundStyle(isSelected ? .white : (isToday ? .blue : (isHoliday ? .orange : .primary)))
                .frame(width: 32, height: 32)
                .background(
                    isSelected ? Color.blue :
                    (isToday ? Color.blue.opacity(0.2) :
                    (isHoliday ? Color.orange.opacity(0.3) : Color.clear))
                )
                .clipShape(Circle())
            
            HStack(spacing: 3) {
                if hasExam {
                    Circle().fill(Color.red).frame(width: 4, height: 4)
                }
                if hasHomework {
                    Circle().fill(Color.green).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct CalendarLegendView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: GradesStore
    
    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        Text("Bedeutung der Symbole")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            // Heute
                            legendTile(
                                title: "Heute",
                                subtitle: "Das aktuelle Datum",
                                icon: {
                                    Circle().fill(Color.blue.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(Text("12").font(.body.weight(.semibold)).foregroundStyle(.blue))
                                }
                            )
                            
                            // Ferien
                            legendTile(
                                title: "Ferien",
                                subtitle: "Schulferien",
                                icon: {
                                    Text("12")
                                        .font(.body.weight(.bold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 40, height: 40)
                                        .background(Color.orange.opacity(0.3))
                                        .clipShape(Circle())
                                }
                            )
                            
                            // Klausur
                            legendTile(
                                title: "Klausur",
                                subtitle: "Roter Punkt",
                                icon: {
                                    Circle().fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .frame(width: 40, height: 40, alignment: .center)
                                }
                            )
                            
                            // Hausaufgabe
                            legendTile(
                                title: "Hausaufgabe",
                                subtitle: "Grüner Punkt",
                                icon: {
                                    Circle().fill(Color.green)
                                        .frame(width: 8, height: 8)
                                        .frame(width: 40, height: 40, alignment: .center)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Legende")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func legendTile<Icon: View>(title: String, subtitle: String, icon: () -> Icon) -> some View {
        VStack(spacing: 12) {
            icon()
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.formCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.1), lineWidth: 1)
        )
    }
}
