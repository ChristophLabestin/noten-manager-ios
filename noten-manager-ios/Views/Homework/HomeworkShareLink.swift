import Foundation

struct HomeworkShareLinkPayload: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subjectName: String?
    let dueDate: Date?

    init(id: UUID = UUID(), title: String, subjectName: String?, dueDate: Date?) {
        self.id = id
        self.title = title
        self.subjectName = subjectName
        self.dueDate = dueDate
    }
}

enum HomeworkShareLinkBuilder {
    private static let legacyScheme = "notenmanager"
    private static let legacyHost = "homework"
    private static let legacyPath = "/share"

    private static let webScheme = "https"
    private static let primaryWebHost = "fosbos-notenmanager.de"
    private static let additionalWebHosts: [String] = [
        "www.fosbos-notenmanager.de",
        // Kompatibilität für bestehende Links
        "noten-manager-v2.web.app",
        "www.noten-manager-v2.web.app"
    ]
    private static let webPath = "/homework/share"

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func url(for homework: Homework) -> URL? {
        url(
            title: homework.title,
            subjectName: homework.subjectName,
            dueDate: homework.dueDate
        )
    }

    static func url(title: String, subjectName: String?, dueDate: Date?) -> URL? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = webScheme
        components.host = primaryWebHost
        components.path = webPath

        var items: [URLQueryItem] = [
            URLQueryItem(name: "title", value: trimmedTitle)
        ]
        if let subject = subjectName?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            items.append(URLQueryItem(name: "subject", value: subject))
        }
        if let dueDate {
            let dueString = isoFormatter.string(from: dueDate)
            items.append(URLQueryItem(name: "due", value: dueString))
        }
        items.append(URLQueryItem(name: "v", value: "1"))
        components.queryItems = items

        return components.url
    }

    static func payload(from url: URL) -> HomeworkShareLinkPayload? {
        let lowerScheme = url.scheme?.lowercased()
        let lowerHost = url.host?.lowercased()
        let path = url.path
        let acceptedHosts = [primaryWebHost] + additionalWebHosts
        let isWebLink = (
            lowerScheme == webScheme &&
            (lowerHost.map { acceptedHosts.contains($0) } ?? false) &&
            (path == webPath || path == webPath + "/")
        )
        let isLegacy = (lowerScheme == legacyScheme && lowerHost == legacyHost && (path.isEmpty || path == legacyPath))
        guard isWebLink || isLegacy else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let title = components.queryItems?.first(where: { $0.name == "title" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleanedTitle = title, !cleanedTitle.isEmpty else { return nil }

        let subject = components.queryItems?.first(where: { $0.name == "subject" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dueString = components.queryItems?.first(where: { $0.name == "due" })?.value
        let dueDate = parseDate(from: dueString)

        return HomeworkShareLinkPayload(title: cleanedTitle, subjectName: subject, dueDate: dueDate)
    }

    private static func parseDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let date = isoFormatter.date(from: value) {
            return date
        }
        let fallbackFormatter = ISO8601DateFormatter()
        if let date = fallbackFormatter.date(from: value) {
            return date
        }
        if let timestamp = Double(value) {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }
}
