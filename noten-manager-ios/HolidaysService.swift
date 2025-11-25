import Foundation

struct HolidayPeriod: Decodable {
    let start: String
    let end: String
    let year: Int
    let name: String
}

struct HolidayWindow {
    let name: String
    let start: Date
    let end: Date
}

final class HolidaysService {
    static let shared = HolidaysService()

    private let session: URLSession
    private let dateFormatter: DateFormatter
    private var pfingstferienCache: [Int: Date] = [:]
    private var holidaysCache: [HolidayPeriod]?

    private init(session: URLSession = .shared) {
        self.session = session
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "de_DE_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        self.dateFormatter = formatter
    }

    private func fetchHolidays() async throws -> [HolidayPeriod] {
        if let cached = holidaysCache { return cached }
        guard let url = URL(string: "https://ferien-api.de/api/v1/holidays/BY") else { return [] }
        let (data, _) = try await session.data(from: url)
        let decoder = JSONDecoder()
        let holidays = try decoder.decode([HolidayPeriod].self, from: data)
        holidaysCache = holidays
        return holidays
    }

    func pfingstferienEndDate(forYear year: Int) async -> Date? {
        if let cached = pfingstferienCache[year] { return cached }
        do {
            let holidays = try await fetchHolidays()
            let pfingst = holidays.filter { entry in
                entry.year == year && entry.name.lowercased().contains("pfingstferien")
            }
            let endDate = pfingst
                .compactMap { dateFormatter.date(from: $0.end) }
                .max()
            if let endDate {
                pfingstferienCache[year] = endDate
            }
            return endDate
        } catch {
            return nil
        }
    }

    func upcomingHolidayWithin(days: Int = 7, from date: Date = Date()) async -> HolidayWindow? {
        do {
            let holidays = try await fetchHolidays()
            let calendar = Calendar(identifier: .gregorian)
            guard let windowEnd = calendar.date(byAdding: .day, value: days, to: date) else { return nil }

            let candidates: [HolidayWindow] = holidays.compactMap { entry in
                guard let start = dateFormatter.date(from: entry.start),
                      let end = dateFormatter.date(from: entry.end) else { return nil }
                guard start >= date, start <= windowEnd else { return nil }
                return HolidayWindow(name: entry.name, start: start, end: end)
            }

            return candidates.sorted(by: { $0.start < $1.start }).first
        } catch {
            return nil
        }
    }
}
