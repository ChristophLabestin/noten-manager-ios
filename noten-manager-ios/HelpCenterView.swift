import SwiftUI
import FirebaseAuth

struct HelpCenterView: View {
    @EnvironmentObject private var store: GradesStore

    @State private var contactSubject: String = ""
    @State private var contactMessage: String = ""
    @State private var contactEmail: String = ""
    @State private var isSendingTicket: Bool = false
    @State private var ticketSuccess: Bool = false
    @State private var ticketError: String?
    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool

    private let helperFont: Font = .subheadline
    private var animationsOn: Bool { store.animationsEnabled }
    private var normalizedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var contactFormValid: Bool {
        contactSubject.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        contactMessage.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerCard
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
            }
            .hideKeyboardOnTap()
            .safeAreaInset(edge: .bottom) {
                searchBar(proxy: proxy)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
            }
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

    private func searchBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Suchen", text: $searchQuery)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.none)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { scrollToFirstMatch(using: proxy) }

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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 320)
            .background(
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)

            if searchFocused || !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchFocused = false
                    hideKeyboard()
                    scrollToFirstMatch(using: proxy)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: searchFocused || !searchQuery.isEmpty)
        .contentShape(Rectangle())
        .onTapGesture {
            searchFocused = true
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
        let q = normalizedQuery
        guard !q.isEmpty else { return attr }

        let lower = text.lowercased()
        let needle = q.lowercased()
        var startIndex = lower.startIndex
        while startIndex < lower.endIndex,
              let found = lower[startIndex...].range(of: needle) {
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
        return attr
    }

    private func scrollToFirstMatch(using proxy: ScrollViewProxy) {
        guard let id = firstMatchId() else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private func firstMatchId() -> String? {
        let q = normalizedQuery
        guard !q.isEmpty else { return nil }
        for target in searchTargets {
            if target.text.lowercased().contains(q) {
                return target.id
            }
        }
        return nil
    }

    private var searchTargets: [(id: String, text: String)] {
        [
            ("help_intro", "Help Center Antworten Regeln Support FOS BOS Berechnung Workflows"),
            ("help_steps", "Erste Schritte Schulart Jahrgang Fächer Noten Hausaufgaben Prüfungen Darstellung Sortierung"),
            ("help_calc", "Berechnungen Fach-Durchschnitt Gesamtdurchschnitt Insight Praktikum Halbjahres Filter"),
            ("help_pass", "Abschluss Prüfungen BayFOBOSO Abschlussnote Punkte Fremdsprache Seminarfach"),
            ("help_pass", "Bestehen Kriterien Prüfungen Punkte Durchschnitt"),
            ("help_special", "Offline Modus Ferien Hinweis Schuljahres Wechsel Insights Animationen Gruppen Teilen"),
            ("help_faq", "FAQ Tipps Durchschnitt Offline Halbjahre Sortieren Erinnerung Hausaufgaben Gruppen Ferien"),
            ("help_contact", "Kontakt Support Ticket Email Nachricht")
        ]
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
}
