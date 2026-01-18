import SwiftUI

struct ReportCardView: View {
    let schoolYear: String
    let subjects: [(name: String, average: Double?, gradingMode: GradingMode?, isAdvanced: Bool)]
    let seminarGrade: Double?
    let seminarTopic: String?
    let fachreferatGrade: Double?
    let practicalGrade: Double?
    let abiturGrades: [(name: String, points: Double?)]
    let studentName: String
    let averageBeforeDrops: Double?
    let averageAfterDrops: Double?
    let finalGrade: Double?
    let totalPoints: Double?
    let maxPoints: Int?
    let creationDate: Date
    let appIcon: UIImage?
    let title: String
    
    // A4 Dimensions
    private let pageWidth: CGFloat = 595
    private let pageHeight: CGFloat = 842
    
    var body: some View {
        VStack(spacing: 0) {
            
            // --- HEADER SECTION ---
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.custom("HelveticaNeue-Medium", size: 12))
                        .foregroundStyle(.gray)
                        .textCase(.uppercase)
                        .tracking(1.5)
                    
                    Text(studentName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                // Final Grade Circles
                HStack(spacing: 12) {
                    // Points Circle
                    ZStack {
                        Circle()
                            .strokeBorder(Color.indigo.opacity(0.3), lineWidth: 2)
                        
                        VStack(spacing: 0) {
                            Text(formatPoints(averageAfterDrops))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Punkte")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                        }
                    }
                    .frame(width: 60, height: 60)

                    // Grade Circle
                    ZStack {
                        Circle()
                            .strokeBorder(Color.indigo, lineWidth: 3)
                            .background(Circle().fill(Color.indigo.opacity(0.05)))
                        
                        VStack(spacing: 0) {
                            Text(formatGrade(finalGrade))
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
            .padding(.horizontal, 40)
            .padding(.top, 50)
            .padding(.bottom, 30)
            
            // --- INFO STRIP ---
            HStack(spacing: 40) {
                infoItem(label: "Schuljahr", value: schoolYear)
                infoItem(label: "Stand", value: formatDate(creationDate))
                if let total = totalPoints, let max = maxPoints {
                    infoItem(label: "Gesamtpunkte", value: "\(Int(total.rounded())) / \(max)")
                }
                Spacer()
                HStack(spacing: 6) {
                    if let icon = appIcon {
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
            
            // --- SUBJECTS COLUMNS ---
            HStack(alignment: .top, spacing: 30) {
                // Column 1: With Schulaufgaben
                let withSA = subjects.filter { $0.gradingMode == .withSchulaufgaben || $0.gradingMode == nil }
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("MIT SCHULAUFGABEN")
                    
                    ForEach(withSA, id: \.name) { subject in
                        subjectRow(name: subject.name, average: subject.average)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Column 2: Without Schulaufgaben
                let withoutSA = subjects.filter { $0.gradingMode == .withoutSchulaufgaben }
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("OHNE SCHULAUFGABEN")
                    
                    ForEach(withoutSA, id: \.name) { subject in
                        subjectRow(name: subject.name, average: subject.average)
                    }
                    
                    // Extras in right column if space allows, or below
                    // Let's keep them below for consistency with user request
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 40)
            
            // --- EXTRAS ---
            if seminarGrade != nil || practicalGrade != nil || fachreferatGrade != nil {
                Spacer().frame(height: 20)
                VStack(spacing: 0) {
                    sectionHeader("WEITERE LEISTUNGEN")
                    
                    if let fr = fachreferatGrade {
                        subjectRow(name: "Fachreferat", average: fr)
                    }
                    
                    if let seminar = seminarGrade {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Seminarfach")
                                    .font(.system(size: 13, weight: .semibold))
                                if let topic = seminarTopic {
                                    Text(topic)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(formatPoints(seminar))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .padding(.vertical, 8)
                        Divider().opacity(0.3)
                    }
                    
                    if let practical = practicalGrade {
                        subjectRow(name: "Fachpraktische Ausbildung", average: practical)
                    }
                }
                .padding(.horizontal, 40)
            }
            
            // Abitur Exams
            if !abiturGrades.isEmpty {
                Spacer().frame(height: 20)
                HStack {
                    Text("ABITUR / ABSCHLUSSPRÜFUNG")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.gray)
                        .tracking(1)
                    Spacer()
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 10)
                
                ForEach(abiturGrades, id: \.name) { exam in
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
                    .padding(.horizontal, 40)
                    .padding(.vertical, 8)
                    
                    Divider()
                        .opacity(0.3)
                        .padding(.horizontal, 40)
                }
            }
            
            Spacer()
            
            // --- FOOTER ---
            Text("Inoffizieller Auszug • Alle Angaben ohne Gewähr")
                .font(.system(size: 9))
                .foregroundStyle(.gray.opacity(0.6))
                .padding(.bottom, 40)
        }
        .frame(width: pageWidth, height: pageHeight)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
    
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
            return String(format: "%.2f", v)
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
    
    private func subjectRow(name: String, average: Double?) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text(formatPoints(average))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(colorForGrade(average))
            }
            .padding(.vertical, 8)
            Divider()
                .opacity(0.3)
        }
    }
}
