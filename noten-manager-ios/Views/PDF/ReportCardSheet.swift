import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PDFKit

struct ReportCardSheet: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    
    // State
    @State private var pdfURL: URL?
    @State private var isLoading: Bool = false
    @State private var showAbiturExams: Bool = true
    @State private var showPoints: Bool = true
    @State private var showGrades: Bool = true
    @State private var showIndividualGrades: Bool = false
    @State private var includeDroppedHalfYears: Bool = false
    @State private var showSettings: Bool = false
    
    @State private var userName: String?
    @State private var calculatorResult: GradeCalculator.CalculationResult?
    @State private var creationDate: Date = Date()
    @State private var appIcon: UIImage? = UIImage(named: "AppIcon") ?? UIImage(named: "AppIcon60x60")
    
    // Configurations
    private let documentTitle = "Jahresübersicht"
    
    var body: some View {
        NavigationStack {
            ZStack {
                // App Theme Background
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
                
                if isLoading {
                    ProgressView("Vorschau wird geladen …")
                } else {

                    VStack(spacing: 0) {
                        // 1. Settings Section (Pinned)
                        settingsSection
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                            .zIndex(10)
                        
                        Divider()
                        
                        ScrollView {
                            VStack(spacing: 32) {
                                // 2. Preview Section
                                if let result = calculatorResult {
                                    previewSection(result: result)
                                } else {
                                    ContentUnavailableView("Daten fehlen", systemImage: "exclamationmark.triangle")
                                        .padding(.top, 40)
                                }
                            }
                            .padding(.top, 24)
                        }
                        .clipped()
                    }
                }
            }
            .navigationTitle("Zeugnis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(store.darkMode ? .white : .black)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if let url = pdfURL {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(store.darkMode ? .white : .black)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                    } else if isLoading {
                        ProgressView().scaleEffect(0.6)
                    }
                }
            }
            .onChange(of: showAbiturExams) { _, _ in updatePDFAsync() }
            .onChange(of: showPoints) { _, _ in updatePDFAsync() }
            .onChange(of: showGrades) { _, _ in updatePDFAsync() }
            .onChange(of: showIndividualGrades) { _, _ in updatePDFAsync() }
            .onChange(of: includeDroppedHalfYears) { _, _ in updatePDFAsync() }
            .task {
                await initialSetup()
            }
        }
    }
    
    // Extracted Preview Section for cleaner body
    @ViewBuilder
    private func previewSection(result: GradeCalculator.CalculationResult) -> some View {
        let containerWidth = UIScreen.main.bounds.width - 32
        let scale = containerWidth / 595.0
        
        VStack {
            Text("ZEUGNIS-VORSCHAU")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1)
                .padding(.bottom, 8)
            
            VStack {
                // Create Preview Data
                let reportData = ReportCardData(
                    studentName: userName ?? "Schüler/in",
                    schoolYear: store.activeSchoolYearId ?? "Unbekannt",
                    creationDate: creationDate,
                    appIcon: appIcon,
                    title: documentTitle,
                    averageBeforeDrops: result.averageBeforeDrops,
                    averageAfterDrops: result.averageAfterDrops,
                    finalGrade: result.finalGrade,
                    totalPoints: result.totalPoints,
                    maxPoints: result.maxPoints,
                    subjects: subjectsForReportCard(result: result),
                    specialItems: [
                        result.fachreferatGrade.map { ReportCardSpecialItem(id: "fr", title: "Fachreferat", value: $0, detail: nil) },
                        result.seminarGrade.map { ReportCardSpecialItem(id: "sem", title: "Seminarfach", value: $0, detail: store.seminarPerformance?.topic) },
                        result.practicalGrade.map { ReportCardSpecialItem(id: "prac", title: "Fachpraktische Ausbildung", value: $0, detail: nil) }
                    ].compactMap { $0 },
                    abiturExams: result.abiturResults.map { ReportCardAbiturExam(name: $0.subjectName, points: $0.points) },
                    showAbiturExams: showAbiturExams,
                    showPoints: showPoints,
                    showGrades: showGrades,
                    showIndividualGrades: showIndividualGrades
                )
                
                let pages = ReportCardPaginator().paginate(data: reportData)
                
                // Render Pages
                ForEach(pages, id: \.pageIndex) { page in
                    ReportCardView(page: page)
                        .frame(width: 595, height: 842)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.12), radius: 15, x: 0, y: 8)
                        .scaleEffect(scale) // Default anchor is center
                        .frame(width: 595 * scale, height: 842 * scale) // Wrap closely around the scaled visual
                        .padding(.bottom, 20)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 80)
        }
    }
    
    private func subjectsForReportCard(result: GradeCalculator.CalculationResult) -> [ReportCardSubject] {
        return store.subjects.sorted(by: { $0.order ?? 0 < $1.order ?? 0 }).map { subject in
            let calc = result.subjects.first(where: { $0.subjectName == subject.name })
            
            // Filter grades if dropped half-years should be excluded
            var rawGrades = store.gradesBySubject[subject.id] ?? []
            if !includeDroppedHalfYears, let dropped = subject.droppedHalfYear {
                rawGrades = rawGrades.filter { $0.halfYear != dropped }
            }
            
            let grades = rawGrades.map { grade in
                ReportCardView.GradeDetail(value: grade.grade, type: grade.assessmentType, weight: grade.weight)
            }
            return ReportCardSubject(
                name: subject.name,
                average: calc?.average,
                gradingMode: subject.gradingMode,
                isAdvanced: subject.isElective,
                grades: grades
            )
        }
    }
    
    @MainActor
    private func initialSetup() async {
        isLoading = true
        // 1. Calculate Results (Initial)
        calculateResults()
        
        // 2. Fetch Name
        var name = store.userName ?? Auth.auth().currentUser?.displayName
        if name == nil {
            if let uid = Auth.auth().currentUser?.uid {
                if let snapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
                   let data = snapshot.data(),
                   let fetchedName = data["name"] as? String {
                    name = fetchedName
                    store.userName = fetchedName
                }
            }
        }
        self.userName = name
        
        // 3. Initial PDF Generation
        await preparePDF()
        isLoading = false
    }

    private func calculateResults() {
        // Prepare subjects based on the includeDroppedHalfYears flag
        let processedSubjects = store.subjects.map { sub in
            if includeDroppedHalfYears {
                return Subject(
                    name: sub.name,
                    type: sub.type,
                    gradingMode: sub.gradingMode,
                    expectedSchulaufgabenPerTerm: sub.expectedSchulaufgabenPerTerm,
                    date: sub.date,
                    order: sub.order,
                    teacher: sub.teacher,
                    room: sub.room,
                    email: sub.email,
                    alias: sub.alias,
                    droppedHalfYear: nil,
                    examSubject: sub.examSubject,
                    examType: sub.examType,
                    examPointsEncrypted: sub.examPointsEncrypted,
                    writtenExamPointsEncrypted: sub.writtenExamPointsEncrypted,
                    oralExamPointsEncrypted: sub.oralExamPointsEncrypted,
                    isElective: sub.isElective
                )
            }
            return sub
        }

        let calculator = GradeCalculator(
            subjects: processedSubjects,
            gradesBySubject: store.gradesBySubject,
            fachreferat: store.fachreferat,
            practicalPerformance: store.practicalPerformance,
            seminarPerformance: store.seminarPerformance,
            examPoints: store.examPoints,
            gradeYear: store.gradeYear ?? 12,
            schoolType: store.schoolType
        )
        self.calculatorResult = calculator.calculate()
    }

    private func updatePDFAsync() {
        Task { @MainActor in
            calculateResults()
            await preparePDF()
        }
    }
    
    @MainActor
    private func preparePDF() async {
        guard let result = calculatorResult else { return }
        
        // 1. Prepare Data
        let subjects: [ReportCardSubject] = subjectsForReportCard(result: result)
        
        var specialItems: [ReportCardSpecialItem] = []
        if let fr = result.fachreferatGrade {
            specialItems.append(ReportCardSpecialItem(id: "fr", title: "Fachreferat", value: fr, detail: nil))
        }
        if let seminar = result.seminarGrade {
            specialItems.append(ReportCardSpecialItem(id: "sem", title: "Seminarfach", value: seminar, detail: store.seminarPerformance?.topic))
        }
        if let practical = result.practicalGrade {
            specialItems.append(ReportCardSpecialItem(id: "prac", title: "Fachpraktische Ausbildung", value: practical, detail: nil))
        }
        
        let abiturExams: [ReportCardAbiturExam] = result.abiturResults.map {
            ReportCardAbiturExam(name: $0.subjectName, points: $0.points)
        }
        
        let reportData = ReportCardData(
            studentName: userName ?? "Schüler/in",
            schoolYear: store.activeSchoolYearId ?? "Unbekannt",
            creationDate: creationDate,
            appIcon: appIcon,
            title: documentTitle,
            averageBeforeDrops: result.averageBeforeDrops,
            averageAfterDrops: result.averageAfterDrops,
            finalGrade: result.finalGrade,
            totalPoints: result.totalPoints,
            maxPoints: result.maxPoints,
            subjects: subjects,
            specialItems: specialItems,
            abiturExams: abiturExams,
            showAbiturExams: showAbiturExams,
            showPoints: showPoints,
            showGrades: showGrades,
            showIndividualGrades: showIndividualGrades
        )
        
        // 2. Paginate
        let paginator = ReportCardPaginator()
        let pages = paginator.paginate(data: reportData)
        
        // 3. Render
        // Construct meaningful filename
        let safeName = (userName ?? "Schüler").replacingOccurrences(of: " ", with: "")
        let safeTitle = documentTitle.replacingOccurrences(of: " ", with: "")
        let dateString = formatDateForFile(Date())
        let filename = "Noten_\(safeTitle)_\(safeName)_\(dateString).pdf"
        
        if let url = renderPDF(pages: pages, filename: filename) {
            self.pdfURL = url
        }
    }
    
    @MainActor
    private func renderPDF(pages: [ReportCardPage], filename: String) -> URL? {
        let paperSize = CGSize(width: 595, height: 842)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Use a renderer for the dimensions (content doesn't matter yet)
        // We will misuse ImageRenderer here slightly by creating new ones per page or drawing inside the callback manually.
        // Actually, ImageRenderer handles one view. We need to create a PDFContext and draw into it multiple times.
        guard let consumer = CGDataConsumer(url: tempURL as CFURL) else { return nil }
        var box = CGRect(origin: .zero, size: paperSize)
        
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        
        for page in pages {
            let view = ReportCardView(page: page)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.0 // MainActor safe
            
            pdfContext.beginPDFPage(nil)
            renderer.render { size, context in
                // Draw the view into the PDF context
                context(pdfContext)
            }
            pdfContext.endPDFPage()
        }
        
        pdfContext.closePDF()
        
        return tempURL
    }
    
    private func formatDateForFile(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private var settingsSection: some View {
        SettingsCard(
            title: "Konfiguration",
            subtitle: "Titel & Anzeige anpassen",
            systemImage: "slider.horizontal.3",
            accent: .indigo,
            isExpanded: $showSettings
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 12) {
                    Toggle(isOn: $showIndividualGrades) {
                        Label("Einzelnoten anzeigen", systemImage: "list.number")
                    }
                    Toggle(isOn: $showAbiturExams) {
                        Label("Abiturnoten anzeigen", systemImage: "graduationcap")
                    }
                    Toggle(isOn: $showPoints) {
                        Label("Gesamtpunkte anzeigen", systemImage: "sum")
                    }
                    Toggle(isOn: $showGrades) {
                        Label("Notenschnitt anzeigen", systemImage: "percent")
                    }
                    Toggle(isOn: $includeDroppedHalfYears) {
                        Label("Gestrichene HJ einbeziehen", systemImage: "list.bullet.indent")
                    }
                }
                .tint(.indigo)
                .font(.subheadline.weight(.medium))
            }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.backgroundColor = .systemGroupedBackground
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
