import AppIntents
import Foundation
import WidgetKit

struct SelectedExamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Termin auswählen" }
    static var description: IntentDescription { "Zeigt einen Termin oder eine Klausur aus deiner Liste." }

    @Parameter(title: "Termin")
    var exam: ExamSelectionEntity?
}

struct ExamSelectionEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Termin")
    static var defaultQuery = ExamQuery()

    let id: String
    let title: String
    let subtitle: String?
    let date: Date
    let subject: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: subtitle.map { LocalizedStringResource(stringLiteral: $0) }
        )
    }

    init(id: String, title: String, subtitle: String?, date: Date, subject: String?) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.date = date
        self.subject = subject
    }

    init(from exam: WidgetExam) {
        self.id = exam.id
        self.title = exam.title
        let trimmedSubject = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.subtitle = trimmedSubject.isEmpty ? nil : trimmedSubject
        self.date = exam.date
        self.subject = subtitle
    }
}

struct ExamQuery: EntityQuery {
    func entities(for identifiers: [ExamSelectionEntity.ID]) async throws -> [ExamSelectionEntity] {
        let exams = loadExams()
        return exams.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ExamSelectionEntity] {
        Array(loadExams().prefix(8))
    }

    func defaultResult() async -> ExamSelectionEntity? {
        loadExams().first
    }

    private func loadExams() -> [ExamSelectionEntity] {
        let snapshot = WidgetDataSource.loadSnapshot() ?? WidgetDataSource.placeholderSnapshot()
        let now = Date()
        return snapshot.allExams
            .filter { !$0.isCompleted && $0.date >= now }
            .sorted { $0.date < $1.date }
            .map { ExamSelectionEntity(from: $0) }
    }
}
