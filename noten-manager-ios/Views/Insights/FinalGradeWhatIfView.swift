import SwiftUI

struct FinalGradeWhatIfView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let subjects: [Subject]
    let existingPoints: [String: Double?]
    let existingSimulation: [String: Double]
    let baselineGradeText: String
    let baselineGradeValue: Double?
    let computePreview: ([String: Double]) -> (text: String, value: Double?)
    let gradeColor: (Double?) -> Color
    let onApply: ([String: Double]) -> Void
    let onReset: () -> Void

    @State private var inputs: [String: String]
    @State private var previewText: String = "-"
    @State private var previewValue: Double? = nil
    @State private var error: String? = nil

    init(subjects: [Subject],
         existingPoints: [String: Double?],
         existingSimulation: [String: Double],
         baselineGradeText: String,
         baselineGradeValue: Double?,
         computePreview: @escaping ([String: Double]) -> (text: String, value: Double?),
         gradeColor: @escaping (Double?) -> Color,
         onApply: @escaping ([String: Double]) -> Void,
         onReset: @escaping () -> Void) {
        self.subjects = subjects
        self.existingPoints = existingPoints
        self.existingSimulation = existingSimulation
        self.baselineGradeText = baselineGradeText
        self.baselineGradeValue = baselineGradeValue
        self.computePreview = computePreview
        self.gradeColor = gradeColor
        self.onApply = onApply
        self.onReset = onReset
        _inputs = State(initialValue: FinalGradeWhatIfView.buildInitialInputs(subjects: subjects, existingPoints: existingPoints, existingSimulation: existingSimulation))
    }

    private var accentColor: Color {
        store.theme == "feminine" ? Color(hex: "#ec4899") : .indigo
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header Card
                    headerCard
                        .softFadeIn(enabled: store.animationsEnabled, delay: 0.05)

                    // Subjects Section
                    subjectsList
                        .softFadeIn(enabled: store.animationsEnabled, delay: 0.1)

                    // Error Display
                    if let error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.shield.fill")
                            Text(error)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                        .softFadeIn(enabled: store.animationsEnabled, delay: 0.15)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button {
                            applySimulation()
                        } label: {
                            HStack {
                                Text("Simulation übernehmen")
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: accentColor, verticalPadding: 16))

                        Button {
                            resetSimulation()
                        } label: {
                            Text("Alles zurücksetzen")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    .softFadeIn(enabled: store.animationsEnabled, delay: 0.2)
                }
                .padding(16)
            }

            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Schließen")
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(accentColor)
                }
            }
        }
        .presentationBackground {
            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
        }
        .onAppear {
            refreshPreview()
        }
    }

    // MARK: - Views

    private var headerCard: some View {
        SettingsCard(
            title: "Simuliertes Ergebnis",
            subtitle: "Jahreszeugnis / Abschluss",
            systemImage: "wand.and.stars",
            accent: accentColor
        ) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    // Current
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AKTUELL")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(baselineGradeText)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Arrow
                    Image(systemName: "arrow.right")
                        .font(.headline)
                        .foregroundStyle(.secondary.opacity(0.5))

                    // Simulated
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SIMULATION")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(accentColor)
                        Text(previewText)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Delta
                let delta = formatDelta(base: baselineGradeValue, simulated: previewValue)
                if delta != "-" {
                    HStack {
                        Text("Differenz:")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(delta)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(previewValue ?? 0 <= baselineGradeValue ?? 0 ? .green : .orange)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private var subjectsList: some View {
        let grouped = Dictionary(grouping: subjects) { sub in
            if sub.examType == .oral { return "Mündliche Prüfungen" }
            return "Schriftliche Prüfungen"
        }
        let sortedKeys = grouped.keys.sorted(by: >) // Simple sort, tweak if specific order needed

        return VStack(spacing: 20) {
            ForEach(sortedKeys, id: \.self) { section in
                SettingsCard(
                    title: section,
                    subtitle: nil,
                    systemImage: section.contains("Mündlich") ? "person.wave.2.fill" : "doc.text.fill",
                    accent: section.contains("Mündlich") ? .orange : .blue
                ) {
                    VStack(spacing: 12) {
                        if let subs = grouped[section] {
                            ForEach(subs, id: \.id) { subject in
                                subjectRow(subject)
                            }
                        }
                    }
                }
            }
        }
    }

    private func subjectRow(_ subject: Subject) -> some View {
        let currentPoints = inputs[subject.name] ?? ""
        let val = Double(currentPoints)
        let isSimulated = !currentPoints.isEmpty
        
        return SettingsSectionBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.name)
                        .font(.subheadline.weight(.semibold))
                    Text(isSimulated ? "Simuliert: \(currentPoints) P" : "Keine Simulation")
                        .font(.caption)
                        .foregroundStyle(isSimulated ? accentColor : .secondary)
                }
                
                Spacer()
                
                Menu {
                    ForEach(Array(stride(from: 15, through: 0, by: -1)), id: \.self) { p in
                        Button {
                            updatePoints(subject: subject, points: "\(p)")
                        } label: {
                            if let v = val, Int(v) == p {
                                Label("\(p) Punkte", systemImage: "checkmark")
                            } else {
                                Text("\(p) Punkte")
                            }
                        }
                    }
                    
                    if isSimulated {
                        Divider()
                        Button(role: .destructive) {
                            updatePoints(subject: subject, points: "")
                        } label: {
                            Label("Zurücksetzen", systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isSimulated ? "\(currentPoints)" : "-")
                            .font(.headline)
                            .monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(isSimulated ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isSimulated ? accentColor : Color.secondary.opacity(0.15)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain) // Important for Menu inside button-heavy views
            }
        }
    }

    // MARK: - Logic

    private func updatePoints(subject: Subject, points: String) {
        inputs[subject.name] = points
        refreshPreview()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func applySimulation() {
        let parsed = parsedOverrides(requireValid: true)
        if let err = parsed.error {
            error = err
            return
        }
        error = nil
        onApply(parsed.overrides)
        dismiss()
    }

    private func resetSimulation() {
        inputs = FinalGradeWhatIfView.buildInitialInputs(subjects: subjects, existingPoints: existingPoints, existingSimulation: [:])
        refreshPreview()
        onReset()
    }

    private func refreshPreview() {
        let parsed = parsedOverrides(requireValid: false)
        let result = computePreview(parsed.overrides)
        previewText = result.text
        previewValue = result.value
    }

    private func parsedOverrides(requireValid: Bool) -> (overrides: [String: Double], error: String?) {
        var overrides: [String: Double] = [:]
        var firstError: String?
        for sub in subjects {
            let name = sub.name
            let raw = inputs[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty { continue }
            let cleaned = raw.replacingOccurrences(of: ",", with: ".")
            guard let value = Double(cleaned) else {
                if requireValid { firstError = "Bitte gültige Punkte für \(name) eingeben." }
                continue
            }
            if value < 0 || value > 15 {
                if requireValid {
                    firstError = "Punkte für \(name) müssen zwischen 0 und 15 liegen."
                }
                continue
            }
            overrides[name] = value
        }
        return (overrides, firstError)
    }

    private func formatDelta(base: Double?, simulated: Double?) -> String {
        guard let base, let simulated else { return "-" }
        let delta = simulated - base
        if abs(delta) < 0.005 { return "0.00" }
        let prefix = delta > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", delta))"
    }

    private static func buildInitialInputs(subjects: [Subject],
                                           existingPoints: [String: Double?],
                                           existingSimulation: [String: Double]) -> [String: String] {
        var dict: [String: String] = [:]
        for sub in subjects {
            let name = sub.name
            if let sim = existingSimulation[name] {
                dict[name] = Self.format(sim)
            }
        }
        return dict
    }

    private static func format(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.0f", value)
    }
}
