import Foundation
import SwiftUI

// MARK: - Data Models
struct ReportCardData {
    let studentName: String
    let schoolYear: String
    let creationDate: Date
    let appIcon: UIImage?
    let title: String
    
    // Stats
    let averageBeforeDrops: Double?
    let averageAfterDrops: Double?
    let finalGrade: Double?
    let totalPoints: Double?
    let maxPoints: Int?
    
    // Content
    let subjects: [ReportCardSubject]
    let specialItems: [ReportCardSpecialItem]
    let abiturExams: [ReportCardAbiturExam]
    
    // Config
    let showAbiturExams: Bool
    let showPoints: Bool
    let showGrades: Bool
    let showIndividualGrades: Bool
    let mssDecimalPrecision: Int
}

struct ReportCardSubject: Identifiable {
    var id: String { name }
    let name: String
    let average: Double?
    let gradingMode: GradingMode?
    let isAdvanced: Bool
    let grades: [ReportCardView.GradeDetail]
}

struct ReportCardSpecialItem: Identifiable {
    let id: String
    let title: String
    let value: Double?
    let detail: String?
}

struct ReportCardAbiturExam: Identifiable {
    var id: String { name }
    let name: String
    let points: Double?
}

struct ReportCardPage {
    let pageIndex: Int
    let totalPages: Int
    let data: ReportCardData
    
    // Content for this specific page
    let subjectsWithSA: [ReportCardSubject]
    let subjectsWithoutSA: [ReportCardSubject]
    let specialItems: [ReportCardSpecialItem]
    let abiturExams: [ReportCardAbiturExam]
    
    var isFirstPage: Bool { pageIndex == 0 }
    var isLastPage: Bool { pageIndex == totalPages - 1 }
}

// MARK: - Paginator
class ReportCardPaginator {
    // A4 constants (approximate points)
    // Page Height: 842
    // Margins (Top 50/30, Bottom 40/20) -> Safe Area ~ 760
    
    private let maxPageHeight: CGFloat = 780 
    private let headerHeightFirstPage: CGFloat = 180
    private let headerHeightSubsequent: CGFloat = 80
    private let footerHeight: CGFloat = 40
    private let rowBaseHeight: CGFloat = 35 // Subject Name + Divider
    private let gradeRowHeight: CGFloat = 20 // If individual grades shown
    private let sectionHeaderHeight: CGFloat = 30
    
    func paginate(data: ReportCardData) -> [ReportCardPage] {
        var pages: [ReportCardPage] = []
        
        // 1. Prepare Content Queues
        var pendingSubjectsWithSA = data.subjects.filter { $0.gradingMode == .withSchulaufgaben || $0.gradingMode == nil }
        var pendingSubjectsWithoutSA = data.subjects.filter { $0.gradingMode == .withoutSchulaufgaben }
        
        let pendingSpecialItems = data.specialItems
        let pendingAbitur = data.showAbiturExams ? data.abiturExams : []
        
        var currentPageIndex = 0
        
        // Loop until all content is placed
        while !pendingSubjectsWithSA.isEmpty || !pendingSubjectsWithoutSA.isEmpty {
            
            var currentY: CGFloat = (currentPageIndex == 0) ? headerHeightFirstPage : headerHeightSubsequent
            let limitY = maxPageHeight - footerHeight
            
            var pageSubjectsWithSA: [ReportCardSubject] = []
            var pageSubjectsWithoutSA: [ReportCardSubject] = []
            
            // Add Section Headers overhead if needed
            if !pendingSubjectsWithSA.isEmpty { currentY += sectionHeaderHeight }
            // Note: We assume parallel columns roughly, but for pagination calculation we treat them as filling vertical space together or assume the taller column dictates the break. 
            // Simplified approach: We fill them somewhat balanced or just track the max Y of the two columns.
            // Let's assume we fill them row by row. Since they are side-by-side, 1 row cost applies to both if we have both.
            // Actually, usually one column is longer. We need to track space for each column or just be conservative and sum them if they were stacked, but they are HStacked.
            // Better Check: Track accumulated height for Left and Right column separately.
            
            var heightLeft: CGFloat = 0
            var heightRight: CGFloat = 0
            
            // Fill Left (With SA)
            while let sub = pendingSubjectsWithSA.first {
                let h = heightForSubject(sub, showIndividualGrades: data.showIndividualGrades)
                if (currentY + max(heightLeft + h, heightRight)) > limitY { break }
                heightLeft += h
                pageSubjectsWithSA.append(sub)
                pendingSubjectsWithSA.removeFirst()
            }
            
            // Fill Right (Without SA)
            while let sub = pendingSubjectsWithoutSA.first {
                let h = heightForSubject(sub, showIndividualGrades: data.showIndividualGrades)
                if (currentY + max(heightLeft, heightRight + h)) > limitY { break }
                heightRight += h
                pageSubjectsWithoutSA.append(sub)
                pendingSubjectsWithoutSA.removeFirst()
            }
            
            // If we didn't add anything but still have pending, we must force add one to progress or we are stuck (entry too big?)
            // In this logic, we assume an entry fits on an empty page.
             if pageSubjectsWithSA.isEmpty && pageSubjectsWithoutSA.isEmpty && (!pendingSubjectsWithSA.isEmpty || !pendingSubjectsWithoutSA.isEmpty) {
                 // Force one
                 if let sub = pendingSubjectsWithSA.first {
                     pageSubjectsWithSA.append(sub)
                     pendingSubjectsWithSA.removeFirst()
                 } else if let sub = pendingSubjectsWithoutSA.first {
                     pageSubjectsWithoutSA.append(sub)
                     pendingSubjectsWithoutSA.removeFirst()
                 }
             }
            
            currentY += max(heightLeft, heightRight)
            
            // Special Items & Abitur (Only try to add on the very last page of subjects, or if we ran out of subjects)
            var pageSpecialItems: [ReportCardSpecialItem] = []
            var pageAbitur: [ReportCardAbiturExam] = []
            
            if pendingSubjectsWithSA.isEmpty && pendingSubjectsWithoutSA.isEmpty {
                // Try to fit Extras
                var extrasHeight: CGFloat = 0
                if !pendingSpecialItems.isEmpty {
                    extrasHeight += sectionHeaderHeight
                    for _ in pendingSpecialItems { extrasHeight += rowBaseHeight } // approx
                }
                
                var abiturHeight: CGFloat = 0
                if !pendingAbitur.isEmpty {
                    abiturHeight += sectionHeaderHeight
                    for _ in pendingAbitur { abiturHeight += rowBaseHeight }
                }
                
                if currentY + extrasHeight + abiturHeight <= limitY {
                    pageSpecialItems = pendingSpecialItems
                    pageAbitur = pendingAbitur
                } else {
                    // split? For now, if it doesn't fit, push ALL extras to next page
                    // This creates a dedicated last page for extras
                    // logic handles this by loop continuing if we don't add them here? 
                    // No, we need to explicitly handle "Extras Only" page if they remain.
                }
            }
            
            pages.append(ReportCardPage(
                pageIndex: currentPageIndex,
                totalPages: 0, // update later
                data: data,
                subjectsWithSA: pageSubjectsWithSA,
                subjectsWithoutSA: pageSubjectsWithoutSA,
                specialItems: pageSpecialItems,
                abiturExams: pageAbitur
            ))
            
            currentPageIndex += 1
        }
        
        // Handle standalone Extras Page if they weren't added
        let lastPageHasExtras = !pages.isEmpty && (!pages.last!.specialItems.isEmpty || !pages.last!.abiturExams.isEmpty)
        if !lastPageHasExtras && (!pendingSpecialItems.isEmpty || !pendingAbitur.isEmpty) {
             pages.append(ReportCardPage(
                pageIndex: currentPageIndex,
                totalPages: 0,
                data: data,
                subjectsWithSA: [],
                subjectsWithoutSA: [],
                specialItems: pendingSpecialItems,
                abiturExams: pendingAbitur
            ))
        }
        
        // Update total pages
        let total = pages.count
        for i in 0..<total {
            var p = pages[i]
            // We can't modify 'let', need to reconstruct or make it a var. 
            // Reconstruct:
            pages[i] = ReportCardPage(
                pageIndex: p.pageIndex,
                totalPages: total,
                data: p.data,
                subjectsWithSA: p.subjectsWithSA,
                subjectsWithoutSA: p.subjectsWithoutSA,
                specialItems: p.specialItems,
                abiturExams: p.abiturExams
            )
        }
        
        return pages
    }
    
    private func heightForSubject(_ subject: ReportCardSubject, showIndividualGrades: Bool) -> CGFloat {
        var h = rowBaseHeight
        if showIndividualGrades && !subject.grades.isEmpty {
            // Rough calculation: grades wrap. 
            // Assume 1 line of grades
            h += gradeRowHeight
            // If many grades, maybe more? For now assume 1 extra line covers most.
        }
        return h
    }
}
