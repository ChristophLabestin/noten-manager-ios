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
            
            // Extract just the date part (yyyy-MM-dd) to avoid timezone issues
            let dateString = String(string.prefix(10))
            
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            // Ensure we stick to noon to avoid boundary issues, or just standard start of day
            // By default DateFormatter uses local time 00:00 if no time is present.
            // This is safer than parsing 23:59Z which might be next day in local time.
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ungültiges Datumsformat: \(string)")
        }
        return decoder
    }

    func fetchHolidays(year: Int) async -> [HolidayPeriod] {
        if let cached = holidaysCache[year] { return cached }
        guard let url = URL(string: "https://schulferien-api.de/api/v1/\(year)/BY") else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            let holidays = try decoder().decode([HolidayPeriod].self, from: data)
            holidaysCache[year] = holidays
            return holidays
        } catch {
            print("Error fetching school holidays for year \(year): \(error)")
            return []
        }
    }

    private func combinedHolidays(around date: Date = Date()) async -> [HolidayPeriod] {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        var result: [HolidayPeriod] = []
        let current = await fetchHolidays(year: year)
        result.append(contentsOf: current)
        let next = await fetchHolidays(year: year + 1)
        result.append(contentsOf: next)
        return result
    }

    func pfingstferienEndDate(forYear year: Int) async -> Date? {
        if let cached = pfingstferienCache[year] { return cached }
        guard let holidays = await fetchHolidays(year: year).first(where: { _ in true }) != nil ? holidaysCache[year] : nil else { return nil }
        
        // Use cached directly since fetchHolidays returns [HolidayPeriod] and populates cache
        let list = holidaysCache[year] ?? []
        let endDate = list
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
        _ = await fetchHolidays(year: year) // Ensure loaded
        let list = holidaysCache[year] ?? []
        let endDate = list
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

    // MARK: - Public Holidays (Feiertage)
    
    // Response is [StateCode: [HolidayName: HolidayDetail]]
    // e.g. "BY": { "Neujahrstag": { "datum": "2026-01-01", "hinweis": "" } }
    private typealias FeiertagResponse = [String: [String: FeiertagDetail]]
    
    private struct FeiertagDetail: Decodable {
        let datum: String
        let hinweis: String
    }
    
    private var feiertageCache: [Int: [HolidayPeriod]] = [:] // year -> periods

    func fetchPublicHolidays(year: Int) async -> [HolidayPeriod] {
        if let cached = feiertageCache[year] { return cached }
        // New API: https://feiertage-api.de/api/?jahr=2026
        guard let url = URL(string: "https://feiertage-api.de/api/?jahr=\(year)") else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await session.data(for: request)
            
            let decoder = JSONDecoder()
            let response = try decoder.decode(FeiertagResponse.self, from: data)
            
            // Extract Bavaria (BY)
            guard let bayern = response["BY"] else {
                return []
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            
            let periods = bayern.compactMap { (name, detail) -> HolidayPeriod? in
                guard let date = dateFormatter.date(from: detail.datum) else { return nil }
                
                // New API already provides nice names as keys (e.g. "Heilige Drei Könige")
                // So we can use 'name' directly and also set as 'nameCp'
                return HolidayPeriod(
                    start: date,
                    end: date,
                    year: year,
                    name: name,
                    stateCode: "BY",
                    nameCp: name
                )
            }
            
            let sortedPeriods = periods.sorted { $0.start < $1.start }
            feiertageCache[year] = sortedPeriods
            return sortedPeriods
        } catch {
            print("Error fetching public holidays for year \(year): \(error)")
            return []
        }
    }
}
