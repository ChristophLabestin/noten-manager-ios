import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct HomeworkDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let homework: Homework
    let onEdit: ((Homework) -> Void)?
    @State private var titleCopied: Bool = false
    @State private var noteCopied: Bool = false

    init(homework: Homework, onEdit: ((Homework) -> Void)? = nil) {
        self.homework = homework
        self.onEdit = onEdit
    }

    private var resolvedSubjectName: String {
        store.resolveLocalSubjectNameForHomework(homework) ?? homework.subjectName
    }

    private var formattedDueDate: String {
        guard let due = homework.dueDate else { return "Kein Fälligkeitsdatum" }
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        fmt.timeStyle = .none
        return fmt.string(from: due)
    }

    private var reminderLabel: String {
        guard let reminder = homework.reminderAt else { return "Keine Erinnerung" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: reminder)
    }

    private var statusLabel: (text: String, tint: Color, icon: String) {
        if homework.isCompleted {
            return ("Erledigt", .green, "checkmark.circle.fill")
        }
        return ("Offen", .orange, "circle")
    }

    private var personalNote: String? {
        store.userNoteForHomework(homework)
    }

    private var groupName: String {
        guard let gid = homework.groupId else { return "" }
        return store.groupNames[gid] ?? gid
    }

    private var createdAtLabel: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return "\(fmt.string(from: homework.createdAt))"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: resolvedSubjectName.isEmpty ? "Unbekanntes Fach" : resolvedSubjectName,
                        subtitle: createdAtLabel,
                        systemImage: "checklist",
                        accent: .indigo,
                        trailing: {
                            Button {
                                copyToClipboard(homework.title)
                                titleCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    titleCopied = false
                                }
                            } label: {
                                Label(titleCopied ? "kopiert" : "Kopieren",
                                      systemImage: titleCopied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(TinyTintButtonStyle(accent: titleCopied ? .green : .indigo))
                            .animation(.easeInOut(duration: 0.2), value: titleCopied)
                        }
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(homework.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .textSelection(.enabled)
                                detailRow(title: "Fällig", value: formattedDueDate, icon: "calendar", tint: .indigo)
                                detailRow(title: "Status", value: statusLabel.text, icon: statusLabel.icon, tint: statusLabel.tint)
                            }
                        }
                    }

                    SettingsCard(
                        title: "Details",
                        subtitle: "Erinnerung & Quelle",
                        systemImage: "bell.badge",
                        accent: .orange
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                detailRow(title: "Erinnerung", value: reminderLabel, icon: homework.reminderAt == nil ? "bell" : "bell.fill", tint: homework.reminderAt == nil ? .secondary : .green)
                                if homework.isShared {
                                    detailRow(title: "Typ", value: "Gruppen-Hausaufgabe", icon: "person.2.fill", tint: .blue)
                                    if !groupName.isEmpty {
                                        detailRow(title: "Gruppe", value: groupName, icon: "person.3.fill", tint: .orange)
                                    }
                                } else if homework.isImportedFromShare {
                                    detailRow(title: "Typ", value: "Geteilte Hausaufgabe", icon: "link.badge.plus", tint: .green)
                                } else {
                                    detailRow(title: "Typ", value: "Eigene Hausaufgabe", icon: "person.fill", tint: .mint)
                                }
                            }
                        }
                    }

                    if let personalNote, !personalNote.isEmpty {
                        SettingsCard(
                            title: "Notiz",
                            subtitle: "Nur für dich",
                            systemImage: "note.text",
                            accent: .teal,
                            trailing: {
                                Button {
                                    copyToClipboard(personalNote)
                                    noteCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        noteCopied = false
                                    }
                                } label: {
                                    Label(noteCopied ? "kopiert" : "Kopieren",
                                          systemImage: noteCopied ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(TinyTintButtonStyle(accent: noteCopied ? .green : .teal))
                                .animation(.easeInOut(duration: 0.2), value: noteCopied)
                            }
                        ) {
                            SettingsSectionBox {
                                Text(personalNote)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .sheetNavigationTitle("Hausaufgabe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                if let onEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Bearbeiten") {
                            onEdit(homework)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func detailRow(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.formInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func copyToClipboard(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#else
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
#endif
    }
}

private struct TinyTintButtonStyle: ButtonStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(accent.opacity(0.12))
            .foregroundStyle(accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
