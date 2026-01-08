import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PDFKit

struct ReportCardSheet: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    
    // State
    @State private var pdfURL: URL?
    @State private var selectedTitle: String = "Jahresübersicht"
    @State private var isLoading: Bool = false
    
    // Configurations
    private let availableTitles = ["Jahresübersicht", "Notenübersicht", "Zwischenstand", "Leistungsnachweis"]
    
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
                    ProgressView("PDF wird erstellt …")
                } else if let url = pdfURL {
                    // Content
                    VStack(spacing: 0) {
                        // Floating Paper Look
                        PDFKitView(url: url)
                            .clipShape(RoundedRectangle(cornerRadius: 8)) // Subtle rounded corners for the "paper"
                            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                            .padding(.top, 20)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 100) // Space for button
                    }
                } else {
                    ContentUnavailableView("Keine Vorschau", systemImage: "doc.text.magnifyingglass")
                }
                
                // Floating Action Button for Export
                if pdfURL != nil {
                    VStack {
                        Spacer()
                        ShareLink(item: pdfURL!) {
                            Label("PDF Exportieren", systemImage: "square.and.arrow.up")
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                        .padding(.horizontal, 40)
                        .padding(.bottom, 20)
                        .shadow(color: .indigo.opacity(0.15), radius: 8, x: 0, y: 4)
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
            }
            .onChange(of: selectedTitle) { _ in
                Task { await preparePDF() }
            }
            .task {
                await preparePDF()
            }
        }
    }
    
    @MainActor
    private func preparePDF() async {
        isLoading = true
        defer { isLoading = false }
        
        // Use GradeCalculator to get metrics
        let calculator = GradeCalculator(
            subjects: store.subjects,
            gradesBySubject: store.gradesBySubject,
            fachreferat: store.fachreferat,
            practicalPerformance: store.practicalPerformance,
            seminarPerformance: store.seminarPerformance,
            gradeYear: store.gradeYear ?? 12,
            schoolType: store.schoolType
        )
        
        let result = calculator.calculate()
        
        // Prepare display data
        let subjects: [(name: String, average: Double?, isAdvanced: Bool)] = store.subjects.sorted(by: { $0.order ?? 0 < $1.order ?? 0 }).map { subject in
            let calc = result.subjects.first(where: { $0.subjectName == subject.name })
            return (subject.name, calc?.average, subject.isElective)
        }
        
        // Setup Icon and Name
        let icon = UIImage(named: "AppIcon") ?? UIImage(named: "AppIcon60x60")
        
        var name = store.userName ?? Auth.auth().currentUser?.displayName
        if name == nil {
            if let uid = Auth.auth().currentUser?.uid {
                if let snapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
                   let data = snapshot.data(),
                   let fetchedName = data["name"] as? String {
                    name = fetchedName
                    await MainActor.run { store.userName = fetchedName }
                }
            }
        }

        let reportCard = ReportCardView(
            schoolYear: store.activeSchoolYearId ?? "Unbekannt",
            subjects: subjects,
            seminarGrade: store.seminarPerformance?.individualPoints,
            seminarTopic: store.seminarPerformance?.topic,
            practicalGrade: nil,
            studentName: name ?? "Schüler/in",
            averageBeforeDrops: result.averageBeforeDrops,
            averageAfterDrops: result.averageAfterDrops,
            creationDate: Date(),
            appIcon: icon,
            title: selectedTitle
        )
        
        // Construct meaningful filename
        let safeName = (name ?? "Schüler").replacingOccurrences(of: " ", with: "")
        let safeTitle = selectedTitle.replacingOccurrences(of: " ", with: "")
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
}

// Reuse existing PDFKitView struct (assumed to be in file or usually separate, but was inline before)
// Since I overwrite the file, I must simpler keep PDFKitView here.
struct PDFKitView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.backgroundColor = .systemGroupedBackground // Match background
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
