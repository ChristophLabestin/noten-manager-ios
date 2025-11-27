import Foundation

struct HolidayPeriod: Decodable {
    let start: Date
    let end: Date
    let year: Int
    let name: String
    let stateCode: String?
    let nameCp: String?

    private enum CodingKeys: String, CodingKey {
        case start, end, year, name
        case stateCode
        case nameCp = "name_cp"
    }
}

struct HolidayWindow {
    let name: String
    let start: Date
    let end: Date
}

final class HolidaysService {
    static let shared = HolidaysService()

    private let session: URLSession
    private var pfingstferienCache: [Int: Date] = [:]
    private var summerEndCache: [Int: Date] = [:]
    private var holidaysCache: [Int: [HolidayPeriod]] = [:] // year -> periods

    private init(session: URLSession = .shared) {
        self.session = session
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            let iso = ISO8601DateFormatter()
            iso.timeZone = TimeZone(secondsFromGMT: 0)
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: string) { return date }

            let fallback = DateFormatter()
            fallback.calendar = Calendar(identifier: .gregorian)
            fallback.locale = Locale(identifier: "de_DE_POSIX")
            fallback.dateFormat = "yyyy-MM-dd"
            if let date = fallback.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ungültiges Datumsformat: \(string)")
        }
        return decoder
    }

    private func fetchHolidays(year: Int) async throws -> [HolidayPeriod] {
        if let cached = holidaysCache[year] { return cached }
        guard let url = URL(string: "https://schulferien-api.de/api/v1/\(year)/BY") else { return [] }
        let (data, _) = try await session.data(from: url)
        let holidays = try decoder().decode([HolidayPeriod].self, from: data)
        holidaysCache[year] = holidays
        return holidays
    }

    private func combinedHolidays(around date: Date = Date()) async -> [HolidayPeriod] {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        var result: [HolidayPeriod] = []
        if let current = try? await fetchHolidays(year: year) {
            result.append(contentsOf: current)
        }
        if let next = try? await fetchHolidays(year: year + 1) {
            result.append(contentsOf: next)
        }
        return result
    }

    func pfingstferienEndDate(forYear year: Int) async -> Date? {
        if let cached = pfingstferienCache[year] { return cached }
        guard let holidays = try? await fetchHolidays(year: year) else { return nil }
        let endDate = holidays
            .filter { $0.name.lowercased().contains("pfingstferien") }
            .map { $0.end }
            .max()
        if let endDate {
            pfingstferienCache[year] = endDate
        }
        return endDate
    }

    func summerHolidayEnd(forYear year: Int) async -> Date? {
        if let cached = summerEndCache[year] { return cached }
        guard let holidays = try? await fetchHolidays(year: year) else { return nil }
        let endDate = holidays
            .filter { $0.name.lowercased().contains("sommerferien") }
            .map { $0.end }
            .max()
        if let endDate {
            summerEndCache[year] = endDate
        }
        return endDate
    }

    func schoolStartDate(forYear year: Int) async -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        if let summerEnd = await summerHolidayEnd(forYear: year) {
            var start = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: summerEnd)) ?? summerEnd
            while cal.isDateInWeekend(start) {
                start = cal.date(byAdding: .day, value: 1, to: start) ?? start
            }
            return start
        }

        // Fallback: grob Mitte September nehmen und auf Montag nach vorne schieben
        let approx = cal.date(from: DateComponents(year: year, month: 9, day: 10)) ?? Date()
        var start = approx
        for _ in 0..<7 {
            if cal.component(.weekday, from: start) == 2 { // Montag
                return start
            }
            start = cal.date(byAdding: .day, value: 1, to: start) ?? start
        }
        return approx
    }

    func upcomingHolidayWithin(days: Int = 7, from date: Date = Date()) async -> HolidayWindow? {
        let holidays = await combinedHolidays(around: date)
        let calendar = Calendar(identifier: .gregorian)
        guard let windowEnd = calendar.date(byAdding: .day, value: days, to: date) else { return nil }

        let candidates: [HolidayWindow] = holidays
            .filter { $0.start >= date && $0.start <= windowEnd }
            .map { HolidayWindow(name: $0.nameCp ?? $0.name, start: $0.start, end: $0.end) }

        return candidates.sorted(by: { $0.start < $1.start }).first
    }
}
