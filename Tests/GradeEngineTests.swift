import XCTest
@testable import noten_manager_ios

@MainActor
final class GradeEngineTests: XCTestCase {
    private let engine = GradeEngine()
    private let subjectWithSA = SubjectV2(id: UUID(), name: "Math", gradingMode: .withSchulaufgaben, expectedSchulaufgabenPerTerm: 1)
    private let subjectWithoutSA = SubjectV2(id: UUID(), name: "Ethics", gradingMode: .withoutSchulaufgaben, expectedSchulaufgabenPerTerm: nil)
    private let term = TermV2(id: UUID(), label: "12/1")

    func testWithoutSA_finalEqualsOtherAvg() {
        let assessments = [
            Assessment(subjectId: subjectWithoutSA.id, termId: term.id, type: .muendlich, points: 12, weight: 1)
        ]
        let result = engine.computeHalfYear(subject: subjectWithoutSA, term: term, assessments: assessments)
        XCTAssertEqual(result.status, .finalResult)
        XCTAssertEqual(result.finalRounded, 12)
    }

    func testWithOneSA_blockAverage() {
        let assessments = [
            Assessment(subjectId: subjectWithSA.id, termId: term.id, type: .muendlich, points: 10, weight: 1),
            Assessment(subjectId: subjectWithSA.id, termId: term.id, type: .schulaufgabe, points: 12, weight: 1)
        ]
        let result = engine.computeHalfYear(subject: subjectWithSA, term: term, assessments: assessments)
        XCTAssertEqual(result.status, .finalResult)
        // raw = (10 + 12)/2 = 11 -> rounds down to 11
        XCTAssertEqual(result.finalRounded, 11)
    }

    func testWithTwoSA_blockAverage() {
        let assessments = [
            Assessment(subjectId: subjectWithSA.id, termId: term.id, type: .muendlich, points: 15, weight: 1),
            Assessment(subjectId: subjectWithSA.id, termId: term.id, type: .schulaufgabe, points: 10, weight: 1),
            Assessment(subjectId: subjectWithSA.id, termId: term.id, type: .schulaufgabe, points: 11, weight: 1)
        ]
        let result = engine.computeHalfYear(subject: subjectWithSA, term: term, assessments: assessments)
        // raw = (15 + 10 + 11)/3 = 12
        XCTAssertEqual(result.finalRounded, 12)
    }

    func testWeightedOtherAvg() {
        let assessments = [
            Assessment(subjectId: subjectWithoutSA.id, termId: term.id, type: .muendlich, points: 10, weight: 1),
            Assessment(subjectId: subjectWithoutSA.id, termId: term.id, type: .muendlich, points: 14, weight: 2)
        ]
        let result = engine.computeHalfYear(subject: subjectWithoutSA, term: term, assessments: assessments)
        // otherAvg = (10*1 + 14*2)/(1+2) = 12.666...
        XCTAssertEqual(result.status, .finalResult)
        XCTAssertEqual(result.finalRounded, 13)
    }

    func testRoundingThresholds() {
        XCTAssertEqual(engine.roundHalfYearPoints(6.49), 6)
        XCTAssertEqual(engine.roundHalfYearPoints(6.50), 7)
        XCTAssertEqual(engine.roundHalfYearPoints(0.99), 0)
        XCTAssertEqual(engine.roundHalfYearPoints(1.00), 1)
    }

    func testWithSA_missingOther_isInterim() {
        let assessments = [
            Assessment(subjectId: subjectWithSA.id, termId: term.id, type: .schulaufgabe, points: 10, weight: 1)
        ]
        let result = engine.computeHalfYear(subject: subjectWithSA, term: term, assessments: assessments)
        XCTAssertEqual(result.status, .interim)
        XCTAssertTrue(result.missingReasons.contains("MissingOther"))
        XCTAssertNotNil(result.rawMin)
        XCTAssertNotNil(result.rawMax)
        XCTAssertNotNil(result.pointsMin)
        XCTAssertNotNil(result.pointsMax)
    }

    func testWithSA_missingSA_isInterim() {
        let assessments = [
            Assessment(subjectId: subjectWithSA.id, termId: term.id, type: .muendlich, points: 13, weight: 1)
        ]
        let result = engine.computeHalfYear(subject: subjectWithSA, term: term, assessments: assessments)
        XCTAssertEqual(result.status, .interim)
        XCTAssertTrue(result.missingReasons.contains("MissingSchulaufgabe"))
        XCTAssertNotNil(result.rawMin)
        XCTAssertNotNil(result.rawMax)
    }

    func testWithoutSA_missingOther_isMissing() {
        let assessments: [Assessment] = []
        let result = engine.computeHalfYear(subject: subjectWithoutSA, term: term, assessments: assessments)
        XCTAssertEqual(result.status, .missing)
        XCTAssertEqual(result.pointsMin, 0)
        XCTAssertEqual(result.pointsMax, 15)
    }
}
