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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 32) {
                            settingsSection
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                            
                            // Real-time SwiftUI Preview
                            if let result = calculatorResult {
                                let containerWidth = UIScreen.main.bounds.width - 32
                                let scale = containerWidth / 595.0
                                
                                VStack {
                                    Text("ZEUGNIS-VORSCHAU")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .tracking(1)
                                        .padding(.bottom, 8)
                                    
                                    VStack {
                                        ReportCardView(
                                            schoolYear: store.activeSchoolYearId ?? "Unbekannt",
                                            subjects: subjectsForReportCard(result: result),
                                            seminarGrade: result.seminarGrade,
                                            seminarTopic: store.seminarPerformance?.topic,
                                            fachreferatGrade: result.fachreferatGrade,
                                            practicalGrade: result.practicalGrade,
                                            abiturGrades: result.abiturResults.map { ($0.subjectName, $0.points) },
                                            studentName: userName ?? "Schüler/in",
                                            averageBeforeDrops: result.averageBeforeDrops,
                                            averageAfterDrops: result.averageAfterDrops,
                                            finalGrade: result.finalGrade,
                                            totalPoints: result.totalPoints,
                                            maxPoints: result.maxPoints,
                                            creationDate: creationDate,
                                            appIcon: appIcon,
                                            title: documentTitle,
                                            showAbiturExams: showAbiturExams,
                                            showPoints: showPoints,
                                            showGrades: showGrades,
                                            showIndividualGrades: showIndividualGrades
                                        )
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .shadow(color: .black.opacity(0.12), radius: 15, x: 0, y: 8)
                                        .scaleEffect(scale, anchor: .top)
                                    }
                                    .frame(width: containerWidth, height: 842 * scale, alignment: .top)
                                    .padding(.top, 12)
                                    .padding(.bottom, 80)
                                }
                            } else {
                                ContentUnavailableView("Daten fehlen", systemImage: "exclamationmark.triangle")
                            }
                        }
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
                        }
                    } else if isLoading {
                        ProgressView().scaleEffect(0.6)
                    }
                }
            }
            .onChange(of: showAbiturExams) { _ in
                updatePDFAsync()
            }
            .onChange(of: showPoints) { _ in
                updatePDFAsync()
            }
            .onChange(of: showGrades) { _ in
                updatePDFAsync()
            }
            .onChange(of: showIndividualGrades) { _ in
                updatePDFAsync()
            }
            .onChange(of: includeDroppedHalfYears) { _ in
                updatePDFAsync()
            }
            .task {
                await initialSetup()
            }
        }
    }
    
    private func subjectsForReportCard(result: GradeCalculator.CalculationResult) -> [(name: String, average: Double?, gradingMode: GradingMode?, isAdvanced: Bool, grades: [ReportCardView.GradeDetail])] {
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
            return (subject.name, calc?.average, subject.gradingMode, subject.isElective, grades)
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
        
        // Prepare display data
        let subjects = subjectsForReportCard(result: result)
        
        let abiturGrades: [(name: String, points: Double?)] = result.abiturResults.map { ($0.subjectName, $0.points) }

        let reportCard = ReportCardView(
            schoolYear: store.activeSchoolYearId ?? "Unbekannt",
            subjects: subjects,
            seminarGrade: result.seminarGrade,
            seminarTopic: store.seminarPerformance?.topic,
            fachreferatGrade: result.fachreferatGrade,
            practicalGrade: result.practicalGrade,
            abiturGrades: abiturGrades,
            studentName: userName ?? "Schüler/in",
            averageBeforeDrops: result.averageBeforeDrops,
            averageAfterDrops: result.averageAfterDrops,
            finalGrade: result.finalGrade,
            totalPoints: result.totalPoints,
            maxPoints: result.maxPoints,
            creationDate: creationDate,
            appIcon: appIcon,
            title: documentTitle,
            showAbiturExams: showAbiturExams,
            showPoints: showPoints,
            showGrades: showGrades,
            showIndividualGrades: showIndividualGrades
        )
        
        // Construct meaningful filename
        let safeName = (userName ?? "Schüler").replacingOccurrences(of: " ", with: "")
        let safeTitle = documentTitle.replacingOccurrences(of: " ", with: "")
        let dateString = formatDateForFile(Date())
        let filename = "Noten_\(safeTitle)_\(safeName)_\(dateString).pdf"
        
        // Render
        if let url = renderPDF(view: reportCard, filename: filename) {
            self.pdfURL = url
        }
    }
    
    @MainActor
    private func renderPDF(view: some View, filename: String) -> URL? {
        let renderer = ImageRenderer(content: view)
        let paperSize = CGSize(width: 595, height: 842)
        renderer.scale = 1.0
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: paperSize)
            guard let pdfContext = CGContext(tempURL as CFURL, mediaBox: &box, nil) else { return }
            pdfContext.beginPDFPage(nil)
            context(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
        }
        
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
