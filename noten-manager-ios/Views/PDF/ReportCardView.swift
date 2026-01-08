import SwiftUI

struct ReportCardView: View {
    let schoolYear: String
    let subjects: [(name: String, average: Double?, isAdvanced: Bool)]
    let seminarGrade: Double?
    let seminarTopic: String?
    let practicalGrade: Double?
    let studentName: String
    let averageBeforeDrops: Double?
    let averageAfterDrops: Double?
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
                
                // Final Grade Circle
                ZStack {
                    Circle()
                        .strokeBorder(Color.indigo, lineWidth: 3)
                        .background(Circle().fill(Color.indigo.opacity(0.03)))
                    
                    VStack(spacing: 0) {
                        Text(formatGrade(averageAfterDrops))
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
            .padding(.horizontal, 40)
            .padding(.top, 50)
            .padding(.bottom, 30)
            
            // --- INFO STRIP ---
            HStack(spacing: 40) {
                infoItem(label: "Schuljahr", value: schoolYear)
                infoItem(label: "Stand", value: formatDate(creationDate))
                if let before = averageBeforeDrops {
                    infoItem(label: "Vor Streichung", value: formatGrade(before))
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
            
            // --- LIST ---
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("FACH")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.gray)
                        .tracking(1)
                    Spacer()
                    Text("PUNKTE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.gray)
                        .tracking(1)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 10)
                
                // Rows
                ForEach(subjects, id: \.name) { subject in
                    HStack {
                        Text(subject.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        // Dot Leader
                        Spacer()
                        
                        if let g = subject.average {
                            Text(formatGrade(g))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(colorForGrade(g))
                        } else {
                            Text("-")
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundStyle(.gray.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 10)
                    
                    Divider()
                        .opacity(0.5)
                        .padding(.horizontal, 40)
                }
                
                // Extras
                if seminarGrade != nil || practicalGrade != nil {
                    Spacer().frame(height: 10)
                    
                    if let seminar = seminarGrade {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Seminarfach")
                                    .font(.system(size: 14, weight: .medium))
                                if let topic = seminarTopic {
                                    Text(topic)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(formatGrade(seminar))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 10)
                        Divider().opacity(0.5).padding(.horizontal, 40)
                    }
                    
                    if let practical = practicalGrade {
                        HStack {
                            Text("Fachpraktische Ausbildung")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(formatGrade(practical))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 10)
                        Divider().opacity(0.5).padding(.horizontal, 40)
                    }
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
        if v >= 5 { return .black }
        return .red // Only warn bad grades
    }
    
    private func formatGrade(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return String(format: "%.2f", v)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
}
