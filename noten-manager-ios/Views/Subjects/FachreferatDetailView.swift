import SwiftUI

struct FachreferatDetailView: View {
    @EnvironmentObject var store: GradesStore

    let subject: Subject
    @State private var showEditSheet: Bool = false
    
    // Fixed Grade State
    @State private var showFixedGradeSheet: Bool = false
    @State private var fixedGradeText: String = ""
    @State private var isSavingFixedGrade: Bool = false
    @State private var error: String?

    private var referat: Fachreferat? {
        store.fachreferat
    }
    
    private var displayedGrade: Double? {
        // Fixed grade takes priority
        if let fixed = referat?.fixedGrade {
            return fixed
        }
        return referat?.grade
    }
    
    private var hasFixedGrade: Bool {
        referat?.fixedGrade != nil
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df
    }

    private func formatGrade(_ grade: Double?) -> String {
        guard let grade else { return "–" }
        return String(format: "%.2f", grade)
    }

    private func gradeColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsCard(
                    title: "Fachreferat",
                    subtitle: referat?.subjectName ?? "Noch nicht eingetragen",
                    systemImage: "doc.text.fill",
                    accent: .pink
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatGrade(displayedGrade))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(gradeColor(displayedGrade).opacity(0.16))
                                    .foregroundStyle(gradeColor(displayedGrade))
                                    .clipShape(Capsule())
                                if hasFixedGrade {
                                    Text("(festgelegt)")
                                        .font(.caption)
                                        .foregroundStyle(.pink)
                                }
                            }
                            Spacer()
                        }

                        if let pg = referat?.presentationGrade, let sg = referat?.paperGrade, let w = referat?.presentationWeight {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Zusammensetzung")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                HStack(spacing: 0) {
                                    VStack(alignment: .leading) {
                                        Text("Vortrag")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(formatGrade(pg))
                                            .font(.headline)
                                        Text("\(Int(w * 100))%")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Divider()
                                        .frame(height: 30)
                                    
                                    VStack(alignment: .leading) {
                                        Text("Schriftlich")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(formatGrade(sg))
                                            .font(.headline)
                                        Text("\(Int((1 - w) * 100))%")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 12)
                                }
                                .padding(12)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        if let subjectName = referat?.subjectName, !subjectName.isEmpty {
                            Label(subjectName, systemImage: "text.book.closed")
                                .font(.subheadline.weight(.semibold))
                        }

                        if let date = referat?.date {
                            Label(dateFormatter.string(from: date), systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let note = referat?.note, !note.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notiz")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(note)
                                    .font(.body)
                            }
                        }
                        
                        // Fixed Grade Section
                        if referat != nil {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Festgelegte Note")
                                    .font(.subheadline.weight(.semibold))
                                Text("Optional: Überschreibt die berechnete Note.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    fixedGradeText = referat?.fixedGrade.map { String(format: "%.1f", $0) } ?? ""
                                    showFixedGradeSheet = true
                                } label: {
                                    HStack {
                                        Text(hasFixedGrade ? "Festgelegte Note bearbeiten" : "Festgelegte Note setzen")
                                        Spacer()
                                        if let fixed = referat?.fixedGrade {
                                            Text(String(format: "%.1f", fixed))
                                                .foregroundStyle(.pink)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if referat == nil {
                            Text("Es ist noch keine Fachreferat-Note hinterlegt. Lege sie jetzt an.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Fachreferat eintragen") { showEditSheet = true }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.pink.opacity(0.14))
                                .foregroundStyle(Color.pink)
                                .clipShape(Capsule())
                        }
                    }
                }
                
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .sheetNavigationTitle("Fachreferat")
        .sheet(isPresented: $showEditSheet) {
            AddFachreferatView(preselectedSubjectName: referat?.subjectName)
                .environmentObject(store)
        }
        .sheet(isPresented: $showFixedGradeSheet) {
            fixedGradeSheet
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if referat != nil {
                    Button {
                        showEditSheet = true
                    } label: {
                        ToolbarIcon(symbol: "slider.horizontal.3", showDot: false)
                    }
                    .accessibilityLabel("Bearbeiten")
                }
            }
        }
    }
    
    // MARK: - Fixed Grade Sheet
    
    @ViewBuilder
    private var fixedGradeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Festgelegte Note",
                        subtitle: "Überschreibt die berechnete Note",
                        systemImage: "lock.fill",
                        accent: .pink
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Gib die finale Fachreferat-Note ein, wie sie auf dem Zeugnis stehen soll. Diese überschreibt die berechnete Note.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            TextField("z. B. 12.0", text: $fixedGradeText)
                                .keyboardType(.decimalPad)
                                .padding(12)
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            if hasFixedGrade {
                                Button(role: .destructive) {
                                    Task { await clearFixedGrade() }
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Festgelegte Note entfernen")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .red))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .sheetNavigationTitle("Festgelegte Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showFixedGradeSheet = false
                    } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveFixedGrade() }
                    } label: {
                        if isSavingFixedGrade {
                            ToolbarLoadingIcon()
                        } else {
                            ToolbarIcon(symbol: "checkmark", showDot: false)
                        }
                    }
                    .disabled(isSavingFixedGrade)
                }
            }
        }
    }
    
    private func saveFixedGrade() async {
        guard let key = store.encryptionKey else { return }
        isSavingFixedGrade = true
        do {
            let value = fixedGradeText.isEmpty ? nil : Double(fixedGradeText.replacingOccurrences(of: ",", with: "."))
            try await store.setFachreferatFixedGrade(value, using: key)
            await MainActor.run {
                showFixedGradeSheet = false
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
        isSavingFixedGrade = false
    }
    
    private func clearFixedGrade() async {
        guard let key = store.encryptionKey else { return }
        isSavingFixedGrade = true
        do {
            try await store.setFachreferatFixedGrade(nil, using: key)
            await MainActor.run {
                showFixedGradeSheet = false
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
        isSavingFixedGrade = false
    }
}
