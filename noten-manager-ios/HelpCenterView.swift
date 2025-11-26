import SwiftUI
import FirebaseAuth

enum HelpCenterSection: String {
    case intro
    case steps
    case calc
    case exams
    case pass
    case special
    case faq
    case contact

    var scrollId: String {
        switch self {
        case .intro: return "help_intro"
        case .steps: return "help_steps"
        case .calc: return "help_calc"
        case .exams: return "help_exams"
        case .pass: return "help_pass"
        case .special: return "help_special"
        case .faq: return "help_faq"
        case .contact: return "help_contact"
        }
    }
}

private struct HelpSearchEntry: Identifiable {
    let id: String
    let section: HelpCenterSection
    let title: String
    let summary: String
    let keywords: [String]
    let icon: String

    var searchText: String {
        (title + " " + summary + " " + keywords.joined(separator: " ")).lowercased()
    }
}

struct HelpCenterView: View {
    let initialSection: HelpCenterSection?

    @EnvironmentObject private var store: GradesStore

    @State private var contactSubject: String = ""
    @State private var contactMessage: String = ""
    @State private var contactEmail: String = ""
    @State private var isSendingTicket: Bool = false
    @State private var ticketSuccess: Bool = false
    @State private var ticketError: String?
    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool
    @State private var didScrollToInitialSection: Bool = false

    private let searchIndex: [HelpSearchEntry] = [
        HelpSearchEntry(
            id: "setup",
            section: .steps,
            title: "Erste Schritte & Setup",
            summary: "Schulart und Jahrgang festlegen, Fächer und Prüfungsfächer einrichten und die Übersicht anpassen.",
            keywords: ["onboarding", "start", "schulart", "jahrgangsstufe", "fächer", "prüfungsfächer", "setup", "sortieren", "darstellung", "übersicht", "fos", "bos"],
            icon: "hands.clap.fill"
        ),
        HelpSearchEntry(
            id: "grades",
            section: .steps,
            title: "Noten erfassen & verknüpfen",
            summary: "Leistungen mit Art und Halbjahr anlegen, mit Prüfungen verknüpfen und die Darstellung steuern.",
            keywords: ["noten", "leistungen", "kurzarbeit", "schulaufgabe", "mündlich", "prüfung", "verknüpfen", "halbjahr", "tabelle", "anzeige"],
            icon: "square.and.pencil"
        ),
        HelpSearchEntry(
            id: "homework",
            section: .steps,
            title: "Hausaufgaben & Erinnerungen",
            summary: "Aufgabenlisten nutzen, Erinnerungszeit ändern und Mitteilungen snoozen oder erledigen.",
            keywords: ["hausaufgaben", "erinnerung", "benachrichtigung", "snooze", "uhrzeit", "fällig", "toolbar"],
            icon: "bell.badge.fill"
        ),
        HelpSearchEntry(
            id: "calc",
            section: .calc,
            title: "Gewichtungen & Durchschnitte",
            summary: "Berechnung von Fach- und Gesamtschnitt, Wahlfächer und Halbjahresfilter.",
            keywords: ["gewichtung", "durchschnitt", "wahlfach", "kurzarbeit", "schulaufgabe", "halbjahr", "filter", "gesamtschnitt", "insights", "abschlussnote", "fos", "bos", "bayfoboso"],
            icon: "function"
        ),
        HelpSearchEntry(
            id: "exams",
            section: .exams,
            title: "Prüfungen nach BayFOBOSO",
            summary: "Gewichtungen von schriftlich/mündlich, Prüfungsdurchschnitt und Schwächenregel.",
            keywords: ["prüfung", "bayfoboso", "schwach", "prüfungsschnitt", "profilfach", "zulassung", "abschlussnote", "fos", "bos", "fachabitur", "abitur"],
            icon: "graduationcap.fill"
        ),
        HelpSearchEntry(
            id: "pass",
            section: .pass,
            title: "Bestehensregeln & Punkte",
            summary: "Grenzwerte für FOS/BOS 12/13, 0-Punkte-Regel und Abschlussnote richtig lesen.",
            keywords: ["bestehen", "punkte", "punktesumme", "0 punkte", "zulassung", "abschluss", "schwellen", "foboso", "abschlussnote", "fos", "bos", "fachabitur", "abitur"],
            icon: "checkmark.seal.fill"
        ),
        HelpSearchEntry(
            id: "offline",
            section: .special,
            title: "Offline, Sync & Schuljahreswechsel",
            summary: "Offline-Modus verwenden, Synchronisation verstehen und ein neues Schuljahr anlegen.",
            keywords: ["offline", "synchronisieren", "sync", "schuljahr", "wechsel", "pfingstferien", "letzter stand", "fos", "bos"],
            icon: "wifi.slash"
        ),
        HelpSearchEntry(
            id: "insights",
            section: .special,
            title: "Insights & Darstellung",
            summary: "Trends lesen, nach Halbjahr oder Fachtyp filtern und Animationen steuern.",
            keywords: ["insights", "filter", "halbjahr", "fachtypen", "darstellung", "animationen", "ferien hinweis", "fos", "bos"],
            icon: "chart.line.uptrend.xyaxis"
        ),
        HelpSearchEntry(
            id: "groups",
            section: .special,
            title: "Gruppen & Teilen",
            summary: "Gruppe erstellen oder per Code beitreten und erfahren, was synchronisiert wird.",
            keywords: ["gruppen", "teilen", "code", "einladen", "synchronisation", "hausaufgaben", "prüfungen", "erinnerungen", "fos", "bos"],
            icon: "person.2.wave.2.fill"
        ),
        HelpSearchEntry(
            id: "faq",
            section: .faq,
            title: "FAQ & schnelle Antworten",
            summary: "Kurzantworten zu Durchschnitt, Offline-Modus, Sortierung und Erinnerungen.",
            keywords: ["faq", "durchschnitt", "offline", "sortieren", "erinnerung", "hausaufgabe", "filter", "frage", "fos", "bos"],
            icon: "lightbulb.fill"
        ),
        HelpSearchEntry(
            id: "contact",
            section: .contact,
            title: "Support kontaktieren",
            summary: "Ticket direkt aus der App mit Betreff, Nachricht und E-Mail senden.",
            keywords: ["kontakt", "support", "ticket", "hilfe", "email", "fehler", "meldung", "fos", "bos"],
            icon: "envelope.fill"
        )
    ]

    private let helperFont: Font = .subheadline
    private var animationsOn: Bool { store.animationsEnabled }
    private var normalizedQuery: String {
        normalizedText(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var hasQuery: Bool { !normalizedQuery.isEmpty }
    private var queryTokens: [String] {
        normalizedQuery
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private var searchResults: [HelpSearchEntry] {
        guard !queryTokens.isEmpty else { return [] }

        let scored = searchIndex.compactMap { entry -> (HelpSearchEntry, Int)? in
            let score = searchScore(for: entry)
            return score > 0 ? (entry, score) : nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title < rhs.0.title
                }
                return lhs.1 > rhs.1
            }
            .map { $0.0 }
    }

    private var quickSuggestions: [HelpSearchEntry] {
        let ids: Set<String> = ["setup", "calc", "exams", "pass", "faq", "contact"]
        return searchIndex.filter { ids.contains($0.id) }
    }

    private var contactFormValid: Bool {
        contactSubject.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        contactMessage.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    init(initialSection: HelpCenterSection? = nil) {
        self.initialSection = initialSection
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerCard
                    searchCard(proxy: proxy)
                    stepsCard
                    calcCard
                    examsCard
                    passCard
                    specialCard
                    faqCard
                    contactCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine"))
            .navigationTitle("Help Center")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if contactEmail.isEmpty {
                    contactEmail = Auth.auth().currentUser?.email ?? ""
                }
                scrollToInitialSection(using: proxy)
            }
            .hideKeyboardOnTap()
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        SettingsCard(
            title: "Help Center",
            subtitle: "Antworten, Regeln und Support",
            systemImage: "questionmark.circle.fill",
            accent: .indigo
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(highlighted("Hier findest du verständliche Erklärungen zur Bedienung, den Berechnungen sowie den Regeln für den Abschluss."))
                        .font(helperFont)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        PillBadge(
                            text: "FOS / BOS",
                            systemImage: "graduationcap.fill",
                            foreground: .indigo,
                            background: Color.indigo.opacity(0.14)
                        )
                        PillBadge(
                            text: "Berechnung",
                            systemImage: "function",
                            foreground: .cyan,
                            background: Color.cyan.opacity(0.14)
                        )
                        PillBadge(
                            text: "Workflows",
                            systemImage: "sparkles",
                            foreground: .orange,
                            background: Color.orange.opacity(0.14)
                        )
                    }
                }
            }
        }
        .softFadeIn(enabled: animationsOn, delay: 0.03, offset: 12)
        .id("help_intro")
    }

    private var stepsCard: some View {
        SettingsCard(
            title: "Erste Schritte",
            subtitle: "So nutzt du den Noten Manager",
            systemImage: "hands.clap.fill",
            accent: .teal
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow(
                        title: "Schulart, Jahrgang und Fächer festlegen",
                        text: "Nutze das Onboarding oder Einstellungen ▸ Schuljahr. Dort stellst du Schulart, Jahrgangsstufe und deine Fächer ein. Prüfungsfächer wählst du im Abschnitt „Prüfungsfächer“."
                    )
                    infoRow(
                        title: "Noten erfassen",
                        text: "Füge Noten in der Fachansicht oder im Fach-Detail hinzu. Wähle Art der Leistung, Halbjahr sowie optional eine Verknüpfung zu einer Prüfung."
                    )
                    infoRow(
                        title: "Hausaufgaben und Prüfungen verwalten",
                        text: "Listen für Aufgaben und Klausuren erreichst du über die Buttons in der Toolbar. Erinnerungen und Uhrzeit stellst du unter Einstellungen ▸ Hausaufgaben-Erinnerung ein."
                    )
                    infoRow(
                        title: "Darstellung und Sortierung",
                        text: "In der Übersicht kannst du nach Notendurchschnitt, Name oder eigener Reihenfolge sortieren. Kompakte Tabellen-Ansicht und Animationen lassen sich unter „Darstellung & Animationen“ anpassen."
                    )
                }
            }
        }
        .softFadeIn(enabled: animationsOn, delay: 0.08, offset: 12)
        .id("help_steps")
    }

    private var calcCard: some View {
        SettingsCard(
            title: "Berechnungen",
            subtitle: "So werden Noten und Durchschnitte ermittelt",
            systemImage: "function",
            accent: .cyan
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(highlighted("Fach-Durchschnitt"))
                        .font(.headline)
                    infoRow(
                        title: "Hauptfach",
                        text: "Schulaufgaben werden doppelt gezählt. Kurzarbeiten und mündliche Leistungen gehen einfach ein."
                    )
                    infoRow(
                        title: "Nebenfach",
                        text: "Kurzarbeiten werden doppelt gezählt. Mündliche Leistungen bzw. Extemporale zählen einfach."
                    )
                    infoRow(
                        title: "Wahlfach",
                        text: "Wahlfächer erscheinen im Fach-Detail, fließen aber nicht in den Gesamt-Durchschnitt ein."
                    )
                }
            }
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(highlighted("Gesamtdurchschnitt in Übersicht & Insights"))
                        .font(.headline)
                    infoRow(
                        title: "Grundlage",
                        text: "Alle Noten eines Fachs werden mit der oben beschriebenen Gewichtung zusammengeführt."
                    )
                    infoRow(
                        title: "Fachreferat",
                        text: "Zählt als eigenes Fach und geht einfach in die Durchschnittsberechnung ein."
                    )
                    infoRow(
                        title: "Praktikum (nur FOS)",
                        text: "Erscheint als eigenes Fach für FOS (Jahrgangsstufe 11/12). Praktikumsleistungen gehen einfach in den Schnitt ein."
                    )
                    infoRow(
                        title: "Halbjahres-Filter",
                        text: "Wenn du in der Übersicht ein Halbjahr filterst, berücksichtigt der Durchschnitt ausschließlich die Noten des gewählten Halbjahres."
                    )
                }
            }
        }
        .softFadeIn(enabled: animationsOn, delay: 0.13, offset: 12)
        .id("help_calc")
    }

    private var examsCard: some View {
        SettingsCard(
            title: "Abschluss & Prüfungen",
            subtitle: "Berechnung für Abschlussnote und Prüfungen",
            systemImage: "graduationcap.fill",
            accent: .mint
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(highlighted("Prüfungen nach BayFOBOSO"))
                        .font(.headline)
                    infoRow(
                        title: "Gewichtung",
                        text: "FOS 12: Deutsch, Englisch, Mathe und dein Profilfach zählen je dreifach. BOS 12 sowie FOS/BOS 13: vier Prüfungen zählen je zweifach. Schriftliche Teile zählen doppelt so stark wie mündliche."
                    )
                    infoRow(
                        title: "Schwache Prüfungen",
                        text: "FOS/BOS 12: Es dürfen höchstens zwei Prüfungen unter 4 Punkten sein. Wenn eine Prüfung 0 Punkte hat, wird sie doppelt als „schwach“ gezählt. FOS/BOS 13: Keine Prüfung darf 0 Punkte haben; höchstens zwei Prüfungen dürfen 1–3 Punkte haben."
                    )
                    infoRow(
                        title: "In der App",
                        text: "Die App zeigt deinen Prüfungsdurchschnitt (muss mindestens 4,0 sein) und markiert mündliche Prüfungen. Entscheidend für Bestehen/Zulassung sind die Grenzen oben."
                    )
                }
            }
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(highlighted("Abschlussnote nach BayFOBOSO"))
                        .font(.headline)
                    infoRow(
                        title: "Was einfließt",
                        text: "FOS 12: 25 Halbjahresergebnisse (inkl. 11. Klasse), Fachreferat und zwei Praxisnoten. BOS 12: 17 Halbjahresergebnisse plus Fachreferat. FOS/BOS 13: 16 Halbjahresergebnisse plus Seminarfach (doppelt gewertet). Aus jedem Fach darf höchstens ein Halbjahr gestrichen werden."
                    )
                    infoRow(
                        title: "Punkte & Note",
                        text: "Du kannst maximal 600 Punkte (FOS 12) bzw. 390 Punkte (BOS 12/13) erreichen. Die App rechnet daraus automatisch deine Abschlussnote und zeigt sie mit einer Nachkommastelle an."
                    )
                    infoRow(
                        title: "Zweite Fremdsprache",
                        text: "Für die allgemeine Hochschulreife (13.) müssen beide Halbjahresergebnisse der zweiten Fremdsprache eingebracht werden; Zusatzpunkte aus der Ergänzungsprüfung erhöhen die Maximal- und Mindestpunkte."
                    )
                    infoRow(
                        title: "Noch nicht automatisiert",
                        text: "Seminarfach und zweite Fremdsprache sind noch nicht vollautomatisch abgebildet – bitte in der Planung selbst mitrechnen."
                    )
                }
            }
        }
        .softFadeIn(enabled: animationsOn, delay: 0.16, offset: 12)
        .id("help_exams")
    }

    private var passCard: some View {
        SettingsCard(
            title: "Bestehen nach FOBOSO",
            subtitle: "Wesentliche Kriterien",
            systemImage: "checkmark.seal.fill",
            accent: .green
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow(
                        title: "FOS 12 (Fachabitur)",
                        text: "25 HJE + 2 Praxisleistungen + Fachreferat und vier Prüfungen je 3× gewichtet. Höchstens zwei Prüfungen unter 4 Punkten (0 Punkte zählen doppelt). Mindestens 200 Punkte nötig, wenn ein Prüfungsfach schwach ist; mindestens 240 Punkte, wenn zwei schwach sind. Abschlussnote muss 4,0 oder besser sein."
                    )
                    infoRow(
                        title: "BOS 12 (Fachabitur)",
                        text: "17 HJE + Fachreferat und vier Prüfungen je 2× gewichtet. Höchstens zwei Prüfungen unter 4 Punkten (0 Punkte zählen doppelt). Mindestens 130 Punkte bei einem schwachen Prüfungsfach, 156 Punkte bei zwei. Abschlussnote 4,0 oder besser."
                    )
                    infoRow(
                        title: "FOS/BOS 13 (Abitur)",
                        text: "16 HJE + Seminarfach (doppelt) und vier Prüfungen je 2× gewichtet. Keine 0-Punkte-Prüfung erlaubt; höchstens zwei Prüfungen dürfen 1–3 Punkte haben. Mindestens 130 bzw. 156 Punkte nötig. Mit zweiter Fremdsprache erhöht sich das Punktemaximum auf 420, die Schwellen liegen dann bei 140/168. Abschlussnote 4,0 oder besser."
                    )
                    infoRow(
                        title: "App-Prüfung aktuell",
                        text: "Die App prüft Punktesumme, Prüfungsdurchschnitt (≥ 4,0) sowie Fachreferat und Praxisnoten. Doppelwertung bei 0-Punkte-Prüfungen, Seminarfach und zweiter Fremdsprache bitte selbst mitdenken."
                    )
                }
            }
        }
        .softFadeIn(enabled: animationsOn, delay: 0.18, offset: 12)
        .id("help_pass")
    }

    private var specialCard: some View {
        SettingsCard(
            title: "Spezielle Funktionen",
            subtitle: "Offline, Ferien-Hinweis, Insights & mehr",
            systemImage: "sparkles.rectangle.stack",
            accent: .blue
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow(
                        title: "Offline-Modus",
                        text: "Wenn du zuletzt vor max. 3 Tagen online warst, kannst du mit dem letzten Stand weiterarbeiten. Aktivieren über Einstellungen ▸ Offline-Modus oder den Hinweis bei fehlender Verbindung. Änderungen werden beim nächsten Online-Start synchronisiert."
                    )
                    infoRow(
                        title: "Erinnerungen",
                        text: "Standard-Erinnerung: Ein Tag vor Fälligkeit zur Uhrzeit in Einstellungen ▸ Erinnerung (abschaltbar). Eigene Erinnerungen pro Hausaufgabe/Klausur bleiben aktiv. In den Mitteilungen kannst du snoozen oder Hausaufgaben direkt als erledigt markieren."
                    )
                    infoRow(
                        title: "Ferien-Hinweis",
                        text: "Auf der Startseite erscheint eine Karte, wenn in Bayern binnen 7 Tagen Ferien starten. Du kannst sie unter Einstellungen ▸ Darstellung & Animationen mit „Ferien-Hinweis“ ein- oder ausblenden."
                    )
                    infoRow(
                        title: "Schuljahres-Wechsel",
                        text: "Ab Pfingstferien (Jahrgang 12) fragt die App, ob das nächste Schuljahr angelegt werden soll. Du kannst Schuljahre auch jederzeit unter Einstellungen ▸ Schuljahr wechseln oder neu erstellen."
                    )
                    infoRow(
                        title: "Insights",
                        text: "Im Tab „Insights“ siehst du Trends, Schnittentwicklung und Fächer-Hotspots. Filtere dort nach Halbjahr oder Fachtypen, um gezielt Schwachstellen zu finden."
                    )
                    infoRow(
                        title: "Animationen & Darstellung",
                        text: "Unter Einstellungen ▸ Darstellung & Animationen kannst du Animationen deaktivieren, den Ferien-Hinweis umschalten und das Design-Thema wählen."
                    )
                    infoRow(
                        title: "Gruppen & Teilen",
                        text: "Unter Einstellungen ▸ Gruppen kannst du Gruppen erstellen oder per Code beitreten. Geteilte Hausaufgaben und Klausurtermine erscheinen automatisch in deiner Übersicht; Erinnerungen und Erledigt-Status werden pro Nutzer gespeichert."
                    )
                }
            }
        }
        .softFadeIn(enabled: animationsOn, delay: 0.20, offset: 12)
        .id("help_special")
    }

    private var faqCard: some View {
        SettingsCard(
            title: "FAQ & Tipps",
            subtitle: "Schnelle Antworten",
            systemImage: "lightbulb.fill",
            accent: .orange
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    faqRow(
                        question: "Warum sehe ich keinen Durchschnitt?",
                        answer: "Stelle sicher, dass Noten erfasst sind und das Fach kein Wahlfach ist. Wahlfächer erscheinen im Fach-Detail, fließen aber nicht in den Gesamt-Durchschnitt ein."
                    )
                    faqRow(
                        question: "Wie nutze ich den Offline-Modus?",
                        answer: "Warst du in den letzten 3 Tagen online, kannst du mit dem letzten Stand offline weiterarbeiten. Aktivieren unter Einstellungen ▸ Offline-Modus oder über den Hinweis, wenn keine Verbindung besteht. Änderungen werden beim nächsten Online-Start synchronisiert."
                    )
                    faqRow(
                        question: "Kann ich Halbjahre neu sortieren oder streichen?",
                        answer: "Streichen funktioniert in der Ansicht „Abschlussnote“. Die Sortierung der Fächer änderst du in der Übersicht über „Sortieren“ oder per Drag & Drop im eigenen Sortiermodus."
                    )
                    faqRow(
                        question: "Wie ändere ich die Erinnerung für Hausaufgaben?",
                        answer: "Unter Einstellungen ▸ Hausaufgaben-Erinnerung stellst du die Uhrzeit ein. Es werden nur offene Aufgaben mit Datum erinnert."
                    )
                    faqRow(
                        question: "Wie teile ich Daten mit Mitschülerinnen und Mitschülern?",
                        answer: "Lege unter Einstellungen ▸ Gruppen eine Gruppe an oder tritt mit einem Code bei. Prüfungen und Hausaufgaben werden innerhalb der Gruppe synchronisiert."
                    )
                    faqRow(
                        question: "Was bedeutet der Ferien-Hinweis auf der Startseite?",
                        answer: "Er zeigt Ferien in Bayern an, die innerhalb der nächsten 7 Tage beginnen. Du kannst ihn in Einstellungen ▸ Darstellung & Animationen mit „Ferien-Hinweis“ ein- oder ausblenden."
                    )
                }
            }
        }
        .softFadeIn(enabled: animationsOn, delay: 0.23, offset: 12)
        .id("help_faq")
    }

    private var contactCard: some View {
        SettingsCard(
            title: "Kontakt & Support",
            subtitle: "Ticket direkt aus der App erstellen",
            systemImage: "envelope.fill",
            accent: .indigo
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow(
                        title: "Anliegen schildern",
                        text: "Beschreibe dein Thema möglichst genau. Wir erstellen daraus ein Ticket und melden uns per E-Mail."
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Betreff")
                            .font(.subheadline.weight(.semibold))
                        TextField("z. B. Frage zur Abschlussnote", text: $contactSubject)
                            .textInputAutocapitalization(.sentences)
                            .padding(12)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nachricht")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $contactMessage)
                            .frame(minHeight: 120)
                            .textInputAutocapitalization(.sentences)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("E-Mail für Rückmeldung")
                            .font(.subheadline.weight(.semibold))
                        TextField("E-Mail-Adresse", text: $contactEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding(12)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("Falls leer, verwenden wir die E-Mail deines Kontos.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let ticketError {
                        Text(ticketError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if ticketSuccess {
                        Text("Dein Ticket wurde angelegt. Wir melden uns bei dir.")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }

                    Button {
                        Task { await sendTicket() }
                    } label: {
                        if isSendingTicket {
                            ProgressView()
                        } else {
                            Text("Ticket absenden")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(!contactFormValid || isSendingTicket)
                }
            }
        }
        .softFadeIn(enabled: animationsOn, delay: 0.28, offset: 12)
        .id("help_contact")
    }

    // MARK: - Suche

    private func searchCard(proxy: ScrollViewProxy) -> some View {
        SettingsCard(
            title: "Schnell finden",
            subtitle: "Suche nach Themen oder springe direkt zu einem Abschnitt",
            systemImage: "magnifyingglass.circle.fill",
            accent: .indigo
        ) {
            VStack(alignment: .leading, spacing: 12) {
                searchField(proxy: proxy)
                searchResultsView(proxy: proxy)
            }
        }
        .softFadeIn(enabled: animationsOn, delay: 0.01, offset: 10)
        .id("help_search")
    }

    private func searchField(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Thema eingeben, z. B. „Prüfungen“ oder „Offline“", text: $searchQuery)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.none)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { scrollToFirstResult(using: proxy) }

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground).opacity(store.darkMode ? 0.6 : 0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if !hasQuery {
                searchQuickActions(proxy: proxy)
            }
        }
    }

    private func searchQuickActions(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schnellzugriff")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickSuggestions) { entry in
                        Button {
                            searchQuery = entry.title
                            searchFocused = false
                            hideKeyboard()
                            scrollToSection(entry.section, using: proxy)
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: entry.icon)
                                    .font(.subheadline.weight(.semibold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.caption.weight(.semibold))
                                    Text(sectionTitle(for: entry.section))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultsView(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasQuery {
                if searchResults.isEmpty {
                    noResultsView(proxy: proxy)
                } else {
                    Text("\(searchResults.count) Treffer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(searchResults) { entry in
                        searchResultRow(entry, proxy: proxy)
                    }
                }
            } else {
                Text("Gib einen Begriff ein oder nutze die Schnellzugriffe oben.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func searchResultRow(_ entry: HelpSearchEntry, proxy: ScrollViewProxy) -> some View {
        Button {
            scrollToSection(entry.section, using: proxy)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 42, height: 42)
                    Image(systemName: entry.icon)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(highlighted(entry.title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(highlighted(entry.summary))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(sectionTitle(for: entry.section))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.indigo)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func noResultsView(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keine Treffer gefunden.")
                .font(.subheadline.weight(.semibold))
            Text("Probiere andere Begriffe oder öffne FAQ und Support.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    scrollToSection(.faq, using: proxy)
                } label: {
                    Label("FAQ öffnen", systemImage: "lightbulb.fill")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Button {
                    scrollToSection(.contact, using: proxy)
                } label: {
                    Label("Support", systemImage: "envelope.fill")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func scrollToFirstResult(using proxy: ScrollViewProxy) {
        if hasQuery, let first = searchResults.first {
            scrollToSection(first.section, using: proxy)
        }
    }

    private func scrollToSection(_ section: HelpCenterSection, using proxy: ScrollViewProxy) {
        hideKeyboard()
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(section.scrollId, anchor: .top)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func infoRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(highlighted(title))
                .font(.subheadline.weight(.semibold))
            Text(highlighted(text))
                .font(helperFont)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func faqRow(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(highlighted(question))
                .font(.subheadline.weight(.semibold))
            Text(highlighted(answer))
                .font(helperFont)
                .foregroundStyle(.secondary)
            Divider()
        }
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        let tokens = queryTokens
        guard !tokens.isEmpty else { return attr }

        let lower = normalizedText(text)
        for token in tokens {
            var startIndex = lower.startIndex
            while startIndex < lower.endIndex,
                  let found = lower[startIndex...].range(of: token) {
                let distanceStart = lower.distance(from: lower.startIndex, to: found.lowerBound)
                let distanceEnd = lower.distance(from: lower.startIndex, to: found.upperBound)
                if distanceEnd <= attr.characters.count {
                    let attrStart = attr.index(attr.startIndex, offsetByCharacters: distanceStart)
                    let attrEnd = attr.index(attr.startIndex, offsetByCharacters: distanceEnd)
                    attr[attrStart..<attrEnd].backgroundColor = Color.yellow.opacity(0.35)
                    attr[attrStart..<attrEnd].foregroundColor = Color.primary
                }
                startIndex = found.upperBound
            }
        }
        return attr
    }

    private func normalizedText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func sectionTitle(for section: HelpCenterSection) -> String {
        switch section {
        case .intro: return "Einführung"
        case .steps: return "Erste Schritte"
        case .calc: return "Berechnungen"
        case .exams: return "Prüfungen"
        case .pass: return "Bestehen"
        case .special: return "Spezielle Funktionen"
        case .faq: return "FAQ"
        case .contact: return "Kontakt & Support"
        }
    }

    private func searchScore(for entry: HelpSearchEntry) -> Int {
        guard !queryTokens.isEmpty else { return 0 }
        var score = 0
        let lowerTitle = normalizedText(entry.title)
        let lowerSummary = normalizedText(entry.summary)
        let searchText = normalizedText(entry.searchText)

        for token in queryTokens {
            if lowerTitle.contains(token) { score += 6 }
            if lowerTitle.hasPrefix(token) { score += 2 }
            if lowerSummary.contains(token) { score += 2 }
            if searchText.contains(token) { score += 3 }
        }

        return score
    }

    // MARK: - Ticket

    private func sendTicket() async {
        guard !isSendingTicket else { return }
        let trimmedSubject = contactSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = contactMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard contactFormValid else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            ticketError = "Bitte melde dich an, um ein Ticket zu senden."
            ticketSuccess = false
            return
        }

        isSendingTicket = true
        ticketError = nil
        ticketSuccess = false
        do {
            let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            try await FirestoreService.shared.createSupportTicket(
                userId: uid,
                email: email.isEmpty ? nil : email,
                subject: trimmedSubject,
                message: trimmedMessage
            )
            ticketSuccess = true
            contactSubject = ""
            contactMessage = ""
        } catch {
            ticketError = "Ticket konnte nicht angelegt werden: \(error.localizedDescription)"
        }
        isSendingTicket = false
    }

    private func scrollToInitialSection(using proxy: ScrollViewProxy) {
        guard !didScrollToInitialSection, let target = initialSection?.scrollId else { return }
        didScrollToInitialSection = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }
}
