import SwiftUI

struct ReportCardView: View {
    let page: ReportCardPage
    
    // Shortcuts to data
    private var data: ReportCardData { page.data }
    
    // A4 Dimensions
    private let pageWidth: CGFloat = 595
    private let pageHeight: CGFloat = 842
    
    var body: some View {
        VStack(spacing: 0) {
            
            // --- HEADER SECTION ---
            if page.isFirstPage {
                // Large Header for First Page
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(data.title)
                            .font(.custom("HelveticaNeue-Medium", size: 12))
                            .foregroundStyle(.gray)
                            .textCase(.uppercase)
                            .tracking(1.5)
                        
                        Text(data.studentName)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    // Final Grade Circles
                    HStack(spacing: 12) {
                        // Points Circle
                        if data.showPoints {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.indigo.opacity(0.3), lineWidth: 2)
                                
                                VStack(spacing: 0) {
                                    Text(formatPoints(data.averageAfterDrops))
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text("Punkte")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                }
                            }
                            .frame(width: 60, height: 60)
                        }

                        // Grade Circle
                        if data.showGrades {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.indigo, lineWidth: 3)
                                    .background(Circle().fill(Color.indigo.opacity(0.05)))
                                
                                VStack(spacing: 0) {
                                    Text(formatGrade(data.finalGrade))
                                        .font(.system(size: 26, weight: .black, design: .rounded))
                                        .foregroundStyle(.indigo)
                                    Text("Schnitt")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                }
                            }
                            .frame(width: 80, height: 80)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 50)
                .padding(.bottom, 30)
                
                // --- INFO STRIP ---
                HStack(spacing: 40) {
                    infoItem(label: "Schuljahr", value: data.schoolYear)
                    infoItem(label: "Stand", value: formatDate(data.creationDate))
                    if let total = data.totalPoints, let max = data.maxPoints {
                        infoItem(label: "Gesamtpunkte", value: "\(Int(total.rounded())) / \(max)")
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        if let icon = data.appIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text("Noten Manager")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
                
                Divider()
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                
            } else {
                // Compressed Header for subsequent pages
                HStack {
                    Text("\(data.studentName) • \(data.title)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Seite \(page.pageIndex + 1) von \(page.totalPages)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 40)
                .padding(.top, 30)
                .padding(.bottom, 20)
                
                Divider()
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
            }
            
            // --- SUBJECTS COLUMNS ---
            HStack(alignment: .top, spacing: 30) {
                // Column 1: With Schulaufgaben
                VStack(alignment: .leading, spacing: 0) {
                    if !page.subjectsWithSA.isEmpty {
                        sectionHeader("MIT SCHULAUFGABEN")
                        
                        ForEach(page.subjectsWithSA) { subject in
                            subjectRow(subject: subject)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Column 2: Without Schulaufgaben
                VStack(alignment: .leading, spacing: 0) {
                    if !page.subjectsWithoutSA.isEmpty {
                        sectionHeader("OHNE SCHULAUFGABEN")
                        
                        ForEach(page.subjectsWithoutSA) { subject in
                            subjectRow(subject: subject)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 40)
            
            // --- EXTRAS ---
            if !page.specialItems.isEmpty {
                Spacer().frame(height: 20)
                VStack(spacing: 0) {
                    sectionHeader("WEITERE LEISTUNGEN")
                    
                    ForEach(page.specialItems) { item in
                        specialItemRow(item: item)
                    }
                }
                .padding(.horizontal, 40)
            }
            
            // Abitur Exams
            if !page.abiturExams.isEmpty {
                Spacer().frame(height: 20)
                VStack(spacing: 0) {
                    sectionHeader("ABITUR / ABSCHLUSSPRÜFUNG")
                    
                    ForEach(page.abiturExams) { exam in
                        HStack {
                            Text(exam.name.uppercased())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            if let p = exam.points {
                                Text(formatPoints(p))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(colorForGrade(p))
                            } else {
                                Text("-")
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Divider().opacity(0.3)
                    }
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // --- FOOTER ---
            if page.isLastPage {
                Text("Inoffizieller Auszug • Alle Angaben ohne Gewähr")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray.opacity(0.6))
                    .padding(.bottom, 40)
            } else {
                Text("Fortsetzung auf nächster Seite …")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 40)
            }
        }
        .frame(width: pageWidth, height: pageHeight)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
    
    // MARK: - Subviews & Helpers
    
    private func infoItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.gray)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
    
    private func colorForGrade(_ value: Double?) -> Color {
        guard let v = value else { return .black }
        // Subtle coloring text only
        if v >= 10 { return .black } // Good grades just black
        if v >= 4 { return .black }
        return .red // Only warn bad grades
    }
    
    private func formatGrade(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        // For Schnitt (1-6) typically
        return String(format: "%.2f", v)
    }
    
    private func formatPoints(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        // If it's effectively an integer (0-15 points), show no decimals
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", v)
        } else {
            return String(format: "%.\(data.mssDecimalPrecision)f", v)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.indigo.opacity(0.8))
                .tracking(1)
            Divider()
                .background(Color.indigo.opacity(0.3))
        }
        .padding(.bottom, 8)
    }
    
    private func subjectRow(subject: ReportCardSubject) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    if data.showIndividualGrades && !subject.grades.isEmpty {
                        // Compact list of individual grades
                        FlowLayout(spacing: 4) {
                            ForEach(0..<subject.grades.count, id: \.self) { index in
                                let g = subject.grades[index]
                                Text("\(formatGradeValue(g.value))\(assessmentTypeSuffix(g.type))")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }
                }
                
                Spacer()
                
                Text(formatPoints(subject.average))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(colorForGrade(subject.average))
            }
            .padding(.vertical, 8)
            
            Divider()
                .opacity(0.3)
        }
    }
    
    private func specialItemRow(item: ReportCardSpecialItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                    if let d = item.detail {
                        Text(d)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let v = item.value {
                    Text(formatPoints(v))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }
            .padding(.vertical, 8)
            Divider().opacity(0.3)
        }
    }
    
    private func formatGradeValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
    
    private func assessmentTypeSuffix(_ type: AssessmentType?) -> String {
        guard let type = type else { return "" }
        switch type {
        case .schulaufgabe: return " (SA)"
        case .kurzarbeit: return " (KA)"
        case .stegreifaufgabe: return " (EX)"
        case .muendlich: return " (MU)"
        case .praktisch: return " (PR)"
        case .projekt: return " (PJ)"
        }
    }
    
    // Legacy struct kept for compatibility if needed elsewhere, though now we use ReportCardView.GradeDetail from wrapper usually
    struct GradeDetail {
        let value: Double
        let type: AssessmentType?
        let weight: Double
    }
}
