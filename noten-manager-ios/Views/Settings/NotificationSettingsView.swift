import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var store: GradesStore
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Intro Text
                VStack(alignment: .leading, spacing: 8) {
                    Text("Benachrichtigungen")
                        .font(.title2.weight(.bold))
                    Text("Verwalte, worüber du informiert werden möchtest.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top)

                // 1. Tägliche Erinnerung (Daily Reminder)
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(.mint)
                                .font(.title2)
                            Text("Tägliche Übersicht")
                                .font(.headline)
                        }
                        
                        Toggle("Aktivieren", isOn: Binding(
                            get: { store.standardRemindersEnabled },
                            set: { newVal in
                                store.standardRemindersEnabled = newVal
                                Task { await store.updatePreferences(standardRemindersEnabled: newVal) }
                            }
                        ))
                        .tint(.mint)
                        
                        if store.standardRemindersEnabled {
                            Divider()
                            
                            HStack {
                                Text("Uhrzeit")
                                Spacer()
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: {
                                            var comps = DateComponents()
                                            comps.hour = store.homeworkReminderHour
                                            comps.minute = store.homeworkReminderMinute
                                            return Calendar.current.date(from: comps) ?? Date()
                                        },
                                        set: { newDate in
                                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                            if let h = comps.hour, let m = comps.minute {
                                                store.homeworkReminderHour = h
                                                store.homeworkReminderMinute = m
                                                Task {
                                                    await store.updatePreferences(
                                                        homeworkReminderHour: h,
                                                        homeworkReminderMinute: m
                                                    )
                                                }
                                            }
                                        }
                                    ),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                            
                            Text("Du erhältst zu Deiner gewähllten Uhrzeit eine Übersicht über anstehende Hausaufgaben und Klausuren für den nächsten Tag falls welche anstehen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                // 2. Support Benachrichtigungen
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "ladybug.fill")
                                .foregroundStyle(.orange)
                                .font(.title2)
                            Text("Support & Updates")
                                .font(.headline)
                        }
                        
                        Toggle("Ticket-Updates", isOn: Binding(
                            get: { store.supportNotificationUpdates },
                            set: { newVal in
                                store.supportNotificationUpdates = newVal
                                Task { await store.updatePreferences(supportNotificationUpdates: newVal) }
                            }
                        ))
                        .tint(.orange)
                        
                        Text("Benachrichtigung, wenn der Support auf deine Anfragen antwortet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        Divider()

                        Toggle("Support-Zugriff", isOn: Binding(
                            get: { store.supportNotificationAccess },
                            set: { newVal in
                                store.supportNotificationAccess = newVal
                                Task { await store.updatePreferences(supportNotificationAccess: newVal) }
                            }
                        ))
                        .tint(.orange)
                        
                        Text("Benachrichtigung, wenn ein Admin temporären Zugriff auf deinen Account anfordert oder nutzt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // 3. Allgemeine Mitteilungen
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "megaphone.fill")
                                .foregroundStyle(.blue)
                                .font(.title2)
                            Text("Mitteilungen")
                                .font(.headline)
                        }

                        Toggle("Allgemeine Hinweise", isOn: Binding(
                            get: { store.broadcastNotificationsEnabled },
                            set: { newVal in
                                store.broadcastNotificationsEnabled = newVal
                                Task { await store.updatePreferences(broadcastNotificationsEnabled: newVal) }
                            }
                        ))
                        .tint(.blue)

                        Text("Wichtige Hinweise, Änderungen oder Ankündigungen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()

                        Toggle("Individuelle Nachrichten", isOn: Binding(
                            get: { store.customNotificationsEnabled },
                            set: { newVal in
                                store.customNotificationsEnabled = newVal
                                Task { await store.updatePreferences(customNotificationsEnabled: newVal) }
                            }
                        ))
                        .tint(.blue)

                        Text("Direkte Nachrichten speziell für deinen Account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // 3. Hilfe & Support Link
                SettingsSectionBox {
                    NavigationLink {
                        HelpCenterView(initialSection: .special)
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.teal.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(.teal)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hilfe & Anleitungen")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("FAQ und Support-Kontakt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
        .background(
            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
        )
        .navigationBarTitleDisplayMode(.inline)
    }
}
