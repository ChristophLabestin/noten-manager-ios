import Foundation

struct HalfYearComputation {
    let status: HalfYearStatus
    let otherAvg: Double?
    let schulaufgaben: [Double]
    let rawFinal: Double?
    let finalRounded: Int?
    let missingReasons: [String]
    let rawMin: Double?
    let rawMax: Double?
    let pointsMin: Int?
    let pointsMax: Int?
}

final class GradeEngine {
    func computeHalfYear(subject: SubjectV2, term: TermV2, assessments: [Assessment]) -> HalfYearComputation {
        // Callers already provide assessments filtered for the subject/term; avoid subjectId mismatch
        // when legacy subject IDs are not valid UUIDs.
        let sa = assessments.filter { $0.type == .schulaufgabe }
        let other = assessments.filter { $0.type != .schulaufgabe }

        let otherAvg = computeOtherAvg(other)
        let saPoints = sa.map { Double($0.points) }

        var missingReasons: [String] = []
        let hasOther = otherAvg != nil
        let hasSA = !saPoints.isEmpty

        let status: HalfYearStatus
        var rawFinal: Double? = nil
        var finalRounded: Int? = nil

        switch subject.gradingMode {
        case .withSchulaufgaben:
            if hasOther && hasSA {
                let raw = combineBlocks(otherAvg: otherAvg!, schulaufgaben: saPoints)
                rawFinal = raw
                finalRounded = roundHalfYearPoints(raw)
                status = .finalResult
            } else {
                if !hasSA { missingReasons.append("MissingSchulaufgabe") }
                if !hasOther { missingReasons.append("MissingOther") }
                status = .interim
            }
        case .withoutSchulaufgaben:
            if hasOther {
                rawFinal = otherAvg
                finalRounded = rawFinal.map(roundHalfYearPoints)
                status = .finalResult
            } else {
                missingReasons.append("MissingOther")
                status = .missing
            }
        }

        // Range
        let expectedSA: Int = {
            switch subject.gradingMode {
            case .withSchulaufgaben:
                return max(1, saPoints.count)
            case .withoutSchulaufgaben:
                return 0
            }
        }()
        let missingSA = max(0, expectedSA - saPoints.count)
        let range = computeRange(gradingMode: subject.gradingMode,
                                 otherAvg: otherAvg,
                                 existingSA: saPoints,
                                 missingSA: missingSA)

        return HalfYearComputation(
            status: status,
            otherAvg: otherAvg,
            schulaufgaben: saPoints,
            rawFinal: rawFinal,
            finalRounded: finalRounded,
            missingReasons: missingReasons,
            rawMin: range.rawMin,
            rawMax: range.rawMax,
            pointsMin: range.pointsMin,
            pointsMax: range.pointsMax
        )
    }

    private func computeOtherAvg(_ assessments: [Assessment]) -> Double? {
        guard !assessments.isEmpty else { return nil }
        var total = 0.0
        var weightSum = 0.0
        for a in assessments {
            let w = a.weight
            guard w > 0 else { continue }
            total += Double(a.points) * w
            weightSum += w
        }
        guard weightSum > 0 else { return nil }
        return total / weightSum
    }

    private func combineBlocks(otherAvg: Double, schulaufgaben: [Double]) -> Double {
        guard !schulaufgaben.isEmpty else { return otherAvg }
        let sumSA = schulaufgaben.reduce(0, +)
        let blocks = Double(schulaufgaben.count) + 1
        return (otherAvg + sumSA) / blocks
    }

    func roundHalfYearPoints(_ raw: Double) -> Int {
        guard raw.isFinite else { return 0 }
        if raw < 1.0 { return 0 }
        let fractional = raw - floor(raw)
        if fractional < 0.50 {
            return Int(floor(raw))
        } else {
            return Int(ceil(raw))
        }
    }

    private struct RangeResult {
        let rawMin: Double?
        let rawMax: Double?
        let pointsMin: Int?
        let pointsMax: Int?
    }

    private func computeRange(
        gradingMode: GradingMode,
        otherAvg: Double?,
        existingSA: [Double],
        missingSA: Int
    ) -> RangeResult {
        switch gradingMode {
        case .withSchulaufgaben:
            let m = Double(max(0, missingSA))
            let saCount = existingSA.count
            let sumSA = existingSA.reduce(0, +)

            let den = Double(saCount) + m + 1.0
            let rawMin: Double
            let rawMax: Double
            if let other = otherAvg {
                rawMin = (other + sumSA + 0.0 * m) / den
                rawMax = (other + sumSA + 15.0 * m) / den
            } else {
                rawMin = (0.0 + sumSA + 0.0 * m) / den
                rawMax = (15.0 + sumSA + 15.0 * m) / den
            }
            return RangeResult(
                rawMin: rawMin,
                rawMax: rawMax,
                pointsMin: roundHalfYearPoints(rawMin),
                pointsMax: roundHalfYearPoints(rawMax)
            )
        case .withoutSchulaufgaben:
            if otherAvg != nil {
                // Final already possible; range optional/omitted.
                return RangeResult(rawMin: nil, rawMax: nil, pointsMin: nil, pointsMax: nil)
            } else {
                let rawMin = 0.0
                let rawMax = 15.0
                return RangeResult(
                    rawMin: rawMin,
                    rawMax: rawMax,
                    pointsMin: roundHalfYearPoints(rawMin),
                    pointsMax: roundHalfYearPoints(rawMax)
                )
            }
        }
    }
}
