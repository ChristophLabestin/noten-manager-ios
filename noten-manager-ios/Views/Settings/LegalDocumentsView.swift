import SwiftUI

struct PrivacyPolicyView: View {
    @EnvironmentObject private var store: GradesStore

    private var helperFont: Font { .subheadline }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsCard(
                    title: "Datenschutz",
                    subtitle: "So verarbeiten wir deine Daten",
                    systemImage: "lock.shield.fill",
                    accent: .indigo
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        legalSection("Allgemeine Hinweise") {
                            Text("Diese Datenschutzerklärung informiert dich darüber, welche personenbezogenen Daten bei der Nutzung der Noten Manager iOS-App verarbeitet werden.")
                                .font(helperFont)
                        }

                        legalSection("Verantwortlicher") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Christoph Labestin")
                                Text("Ödwieser Weg 7")
                                Text("84082 Laberweinting")
                                Link("mail@fosbos-notenmanager.de", destination: URL(string: "mailto:mail@fosbos-notenmanager.de")!)
                            }
                            .font(helperFont)
                        }

                        legalSection("Art der Anwendung und Backend (Firebase)") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Die App ist eine mobile Anwendung zur Verwaltung von Schulnoten. Sie nutzt Firebase (Google Ireland Limited, Gordon House, Barrow Street, Dublin 4, Irland) als Backend für Authentifizierung und Datenspeicherung. Bei der Kommunikation werden technisch notwendige Daten (z. B. IP-Adresse, Zeitpunkt der Anfrage, Gerätetyp) verarbeitet, um die Inhalte auszuliefern und die Sicherheit der Systeme zu gewährleisten.")
                                Text("Eine Verarbeitung kann auch auf Servern in Drittländern, insbesondere den USA, stattfinden. Google nutzt hierfür geeignete Garantien wie die EU-Standardvertragsklauseln.")
                                Link(
                                    "Mehr Informationen: https://firebase.google.com/support/privacy",
                                    destination: URL(string: "https://firebase.google.com/support/privacy")!
                                )
                            }
                            .font(helperFont)
                        }

                        legalSection("Anmeldung mit Google/Apple") {
                            Text("Für die Anmeldung kannst du wahlweise E-Mail/Passwort, Google Sign-In oder Apple Sign-In nutzen. Dabei werden Name, E-Mail-Adresse, Nutzer-ID und die von Google/Apple bereitgestellten Signaturdaten zur Kontoanlage und Anmeldung verarbeitet (Rechtsgrundlage: Art. 6 Abs. 1 lit. b DSGVO). Google und Apple können Daten auf Servern in den USA verarbeiten (SCC).")
                                .font(helperFont)
                        }

                        legalSection("Welche Daten werden verarbeitet?") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Registrierungs- und Kontodaten")
                                    .font(.subheadline.weight(.semibold))
                                bulletList([
                                    "Anzeigename",
                                    "E-Mail-Adresse",
                                    "Firebase-Nutzer-ID (technische Kennung)",
                                    "Verschlüsselungs-Salt für deine Noten-Daten"
                                ])
                                Text("Die Registrierung und Anmeldung erfolgt über Firebase Authentication (E-Mail/Passwort).")
                                    .font(helperFont)

                                Text("Noten- und Fachdaten")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.top, 6)
                                Text("Von dir eingegebene Inhalte (Fächer, Noten, Prüfungen, Berechnungen) werden in Google Firestore gespeichert. Vor der Speicherung werden sie mit einem aus deiner Nutzerkennung und einem individuellen Salt abgeleiteten Schlüssel (AES-GCM) verschlüsselt.")
                                    .font(helperFont)

                                Text("App-Einstellungen und Nutzungsdaten")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.top, 6)
                                Text("Wir speichern Einstellungen wie Farbschema, Darstellungsoptionen, Benachrichtigungspräferenzen und Sortierungen, um dir eine konsistente Darstellung über mehrere Geräte hinweg zu ermöglichen.")
                                    .font(helperFont)

                                Text("Live Activities")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.top, 6)
                                Text("Wenn du Live Activities (Countdowns auf dem Sperrbildschirm) aktivierst, speichern wir in Firebase ein Push-Token sowie Prüfungs-ID, Titel, Fach und Zeiten, um die Aktivität aktuell zu halten. Diese Daten werden nach Ende der Prüfung bzw. Deaktivierung entfernt.")
                                    .font(helperFont)
                            }
                        }

                        legalSection("Lokale Speicherung & Mitteilungen") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Die App nutzt lokale Speicherbereiche deines Geräts (z. B. UserDefaults) für Einstellungen sowie lokale Mitteilungen für Erinnerungen an Hausaufgaben und Prüfungen. Benachrichtigungsdaten bleiben auf deinem Gerät; es werden keine Tracking- oder Marketing-Cookies eingesetzt.")
                                Text("Für den Offline-Modus sowie Widgets/Live Activities wird zusätzlich ein Snapshot deiner Noten, Termine, Hausaufgaben und Einstellungen als JSON-Datei im App-Dokumentenordner gespeichert. Diese Datei bleibt lokal und wird beim Abmelden oder Account-Löschen entfernt.")
                            }
                            .font(helperFont)
                        }

                        legalSection("Weitergabe an Dritte und Drittlandtransfer") {
                            Text("Eine Weitergabe deiner Daten an Dritte erfolgt nur, wenn dies zur Bereitstellung der App erforderlich ist, eine gesetzliche Verpflichtung besteht oder du eingewilligt hast. Dienstleister wie Google Firebase handeln auf Basis von Auftragsverarbeitungsverträgen und verarbeiten Daten ausschließlich nach unseren Weisungen. Eine Übermittlung in Drittländer (insbesondere die USA) kann nicht ausgeschlossen werden; in diesen Fällen nutzen wir geeignete Garantien wie die EU-Standardvertragsklauseln.")
                                .font(helperFont)
                        }

                        legalSection("Speicherdauer") {
                            Text("Daten werden nur so lange gespeichert, wie dies für die bereitgestellten Funktionen erforderlich ist oder gesetzliche Aufbewahrungspflichten bestehen. Deine Kontodaten und Noten bleiben grundsätzlich gespeichert, solange dein Nutzerkonto besteht. Auf Anfrage löschen wir dein Profil und die zugehörigen Daten, sofern dem keine Aufbewahrungspflichten entgegenstehen.")
                                .font(helperFont)
                        }

                        legalSection("Deine Rechte") {
                            VStack(alignment: .leading, spacing: 10) {
                                bulletList([
                                    "Auskunft (Art. 15 DSGVO)",
                                    "Berichtigung (Art. 16 DSGVO)",
                                    "Löschung (Art. 17 DSGVO)",
                                    "Einschränkung der Verarbeitung (Art. 18 DSGVO)",
                                    "Datenübertragbarkeit (Art. 20 DSGVO)",
                                    "Widerspruch (Art. 21 DSGVO)"
                                ])
                                HStack(alignment: .top, spacing: 6) {
                                    Text("Kontakt:")
                                        .font(.subheadline.weight(.semibold))
                                    Link("mail@fosbos-notenmanager.de", destination: URL(string: "mailto:mail@fosbos-notenmanager.de")!)
                                        .font(helperFont)
                                }
                            }
                        }

                        legalSection("Sicherheit") {
                            Text("Wir setzen technische und organisatorische Maßnahmen ein, um deine Daten vor Verlust, Missbrauch und unbefugtem Zugriff zu schützen.")
                                .font(helperFont)
                        }

                        legalSection("Support") {
                            Text("Wenn du den Support kontaktierst, speichern wir Betreff, Nachricht und optional deine E-Mail-Adresse in Firebase, um dein Anliegen zu bearbeiten.")
                                .font(helperFont)
                        }

                        legalSection("Teilen von Hausaufgaben") {
                            Text("Beim Erstellen eines Teilungslinks werden Titel, Fach und Fälligkeitsdatum in einer URL kodiert (fosbos-notenmanager.de; bestehende Links auf noten-manager-v2.web.app funktionieren weiterhin). Jeder, der den Link erhält oder verarbeitet, kann diese Inhalte sehen.")
                                .font(helperFont)
                        }

                        legalSection("Externe Inhalte") {
                            Text("Für Ferieninformationen ruft die App schulferien-api.de per HTTPS auf. Dabei wird technisch deine IP-Adresse an diesen Anbieter übertragen. Eine Protokollierung durch uns erfolgt nicht.")
                                .font(helperFont)
                        }

                        legalSection("Löschung in der App") {
                            Text("Du kannst deinen Account jederzeit in den Einstellungen unter \"Daten zurücksetzen\" > \"Account löschen\" entfernen. Alternativ kannst du uns per E-Mail zur Löschung auffordern.")
                                .font(helperFont)
                        }

                        legalSection("Änderungen dieser Datenschutzerklärung") {
                            Text("Wir behalten uns vor, diese Datenschutzerklärung bei Bedarf anzupassen, insbesondere wenn wir neue Funktionen einführen oder sich rechtliche Rahmenbedingungen ändern. Die aktuelle Fassung findest du jederzeit in den App-Einstellungen unter \"Datenschutz\".")
                                .font(helperFont)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
        )
        .sheetNavigationTitle("Datenschutz")
    }

    @ViewBuilder
    private func legalSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        SettingsSectionBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content()
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.subheadline.weight(.bold))
                        .padding(.top, 1)
                    Text(item)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct ImprintView: View {
    @EnvironmentObject private var store: GradesStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsCard(
                    title: "Impressum",
                    subtitle: "Angaben gemäß § 5 TMG",
                    systemImage: "doc.text.fill",
                    accent: .gray
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        legalSection("Anbieter") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Christoph Labestin")
                                Text("Ödwieser Weg 7")
                                Text("84082 Laberweinting")
                            }
                            .font(.subheadline)
                        }

                        legalSection("Kontakt") {
                            Link("mail@fosbos-notenmanager.de", destination: URL(string: "mailto:mail@fosbos-notenmanager.de")!)
                                .font(.subheadline)
                        }

                        legalSection("Haftung für Inhalte") {
                            Text("Als Diensteanbieter bin ich gemäß § 7 Abs. 1 TMG für eigene Inhalte in der App nach den allgemeinen Gesetzen verantwortlich. Nach §§ 8 bis 10 TMG bin ich jedoch nicht verpflichtet, übermittelte oder gespeicherte fremde Informationen zu überwachen oder nach Umständen zu forschen, die auf eine rechtswidrige Tätigkeit hinweisen. Verpflichtungen zur Entfernung oder Sperrung der Nutzung von Informationen nach den allgemeinen Gesetzen bleiben hiervon unberührt. Eine diesbezügliche Haftung ist jedoch erst ab dem Zeitpunkt der Kenntnis einer konkreten Rechtsverletzung möglich. Bei Bekanntwerden entsprechender Rechtsverletzungen werde ich diese Inhalte umgehend entfernen.")
                                .font(.subheadline)
                        }

                        legalSection("Haftung für Links") {
                            Text("Die App kann Links zu externen Websites Dritter enthalten, auf deren Inhalte ich keinen Einfluss habe. Für diese fremden Inhalte übernehme ich keine Gewähr. Für die Inhalte der verlinkten Seiten ist stets der jeweilige Anbieter oder Betreiber verantwortlich. Eine permanente inhaltliche Kontrolle der verlinkten Seiten ist ohne konkrete Anhaltspunkte einer Rechtsverletzung nicht zumutbar. Bei Bekanntwerden von Rechtsverletzungen werden derartige Links umgehend entfernt.")
                                .font(.subheadline)
                        }

                        legalSection("Urheberrecht") {
                            Text("Die durch den Betreiber erstellten Inhalte in dieser App unterliegen dem deutschen Urheberrecht. Die Vervielfältigung, Bearbeitung, Verbreitung und jede Art der Verwertung außerhalb der Grenzen des Urheberrechts bedürfen der schriftlichen Zustimmung des jeweiligen Autors. Downloads und Kopien dieser App sind nur für den privaten, nicht kommerziellen Gebrauch gestattet.")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
        )
        .sheetNavigationTitle("Impressum")
    }

    @ViewBuilder
    private func legalSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        SettingsSectionBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content()
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct TermsOfUseView: View {
    @EnvironmentObject private var store: GradesStore

    private var helperFont: Font { .subheadline }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsCard(
                    title: "Nutzungsbedingungen",
                    subtitle: "Regeln für die Nutzung der App",
                    systemImage: "doc.plaintext.fill",
                    accent: .indigo
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        legalSection("Geltungsbereich") {
                            Text("Diese Bedingungen regeln die Nutzung der Noten Manager iOS-App. Mit der Verwendung der App erkennst du sie an.")
                                .font(helperFont)
                        }

                        legalSection("Leistungsumfang") {
                            Text("Die App dient der Verwaltung von Schulnoten, Hausaufgaben und Prüfungen. Ein Anspruch auf bestimmte Verfügbarkeiten oder Funktionen besteht nicht; Wartung und Weiterentwicklung können zu Änderungen führen.")
                                .font(helperFont)
                        }

                        legalSection("Nutzerkonto") {
                            Text("Für personalisierte Funktionen ist ein Konto erforderlich. Du bist dafür verantwortlich, Zugangsdaten geheim zu halten und dein Konto nicht missbräuchlich zu verwenden.")
                                .font(helperFont)
                        }

                        legalSection("Zulässige Nutzung") {
                            bulletList([
                                "App nur für private, schulische Zwecke verwenden.",
                                "Keine rechtswidrigen Inhalte speichern oder teilen.",
                                "Keine Sicherheitsmechanismen umgehen oder automatisiert Daten abgreifen.",
                                "Bei Missbrauch oder Sicherheitsverdacht Support informieren."
                            ])
                        }

                        legalSection("Kosten") {
                            Text("Die App ist aktuell kostenlos. Sollte sich dies ändern, informieren wir dich vorab; eine Fortsetzung setzt deine Zustimmung voraus.")
                                .font(helperFont)
                        }

                        legalSection("Verfügbarkeit & Haftung") {
                            Text("Wir bemühen uns um eine stabile Bereitstellung, können Unterbrechungen jedoch nicht ausschließen. Für Datenverluste oder Schäden aus Nichtverfügbarkeit haften wir nur bei Vorsatz oder grober Fahrlässigkeit, sowie bei Verletzung von Leben, Körper oder Gesundheit.")
                                .font(helperFont)
                        }

                        legalSection("Datenschutz") {
                            Text("Informationen zur Verarbeitung personenbezogener Daten findest du in der Datenschutzerklärung in den App-Einstellungen.")
                                .font(helperFont)
                        }

                        legalSection("Änderungen der Bedingungen") {
                            Text("Wir können diese Bedingungen anpassen, wenn berechtigte Gründe bestehen (z. B. neue Funktionen oder rechtliche Anforderungen). Wesentliche Änderungen teilen wir in der App mit; setzt du die Nutzung fort, gelten die neuen Bedingungen.")
                                .font(helperFont)
                        }

                        legalSection("Kündigung") {
                            Text("Du kannst die Nutzung jederzeit beenden, indem du dein Konto löschst oder die App deinstallierst. Wir können den Zugang sperren oder kündigen, wenn du gegen diese Bedingungen verstößt.")
                                .font(helperFont)
                        }

                        legalSection("Kontakt") {
                            Link("mail@fosbos-notenmanager.de", destination: URL(string: "mailto:mail@fosbos-notenmanager.de")!)
                                .font(helperFont)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
        )
        .sheetNavigationTitle("Nutzungsbedingungen")
    }

    @ViewBuilder
    private func legalSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        SettingsSectionBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content()
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.subheadline.weight(.bold))
                        .padding(.top, 1)
                    Text(item)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
