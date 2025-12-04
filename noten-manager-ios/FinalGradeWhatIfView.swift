import SwiftUI

struct FinalGradeWhatIfView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let subjectNames: [String]
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
    @FocusState private var focusedField: SubjectField?

    init(subjectNames: [String],
         existingPoints: [String: Double?],
         existingSimulation: [String: Double],
         baselineGradeText: String,
         baselineGradeValue: Double?,
         computePreview: @escaping ([String: Double]) -> (text: String, value: Double?),
         gradeColor: @escaping (Double?) -> Color,
         onApply: @escaping ([String: Double]) -> Void,
         onReset: @escaping () -> Void) {
        self.subjectNames = subjectNames
        self.existingPoints = existingPoints
        self.existingSimulation = existingSimulation
        self.baselineGradeText = baselineGradeText
        self.baselineGradeValue = baselineGradeValue
        self.computePreview = computePreview
        self.gradeColor = gradeColor
        self.onApply = onApply
        self.onReset = onReset
        _inputs = State(initialValue: FinalGradeWhatIfView.buildInitialInputs(subjectNames: subjectNames, existingPoints: existingPoints, existingSimulation: existingSimulation))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Abschlussnote simulieren",
                        subtitle: "Fiktive Prüfungsnoten 0–15 Punkte",
                        systemImage: "wand.and.stars",
                        accent: .pink
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                StatChip(title: "Aktuell", value: baselineGradeText, accent: .indigo)
                                StatChip(title: "Simulation", value: previewText, accent: .pink)
                                StatChip(title: "Δ", value: formatDelta(base: baselineGradeValue, simulated: previewValue), accent: .orange)
                            }
                            Text("Alle Eingaben bleiben lokal und werden nicht gespeichert. Du kannst sie jederzeit zurücksetzen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

            SettingsCard(
                title: "Abiturnoten eingeben",
                subtitle: "Punkte werden nur simuliert",
                systemImage: "graduationcap.fill",
                accent: .indigo
            ) {
                SettingsSectionBox {
                    VStack(spacing: 12) {
                        ForEach(subjectNames, id: \.self) { name in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(name)
                                    .font(.subheadline.weight(.semibold))
                                TextField("Punkte 0–15", text: Binding(
                                    get: { inputs[name, default: "" ] },
                                    set: { newValue in
                                        inputs[name] = newValue
                                        refreshPreview()
                                    }
                                ))
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .subject(name))
                                .padding(12)
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                        }

                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        VStack(spacing: 10) {
                            Button {
                                applySimulation()
                            } label: {
                                Label("Simulation anwenden", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .pink))

                            Button {
                                resetSimulation()
                            } label: {
                                Label("Simulation zurücksetzen", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .sheetNavigationTitle("Was-wäre-wenn (Abitur)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .keyboardNavigationToolbar(
                focus: $focusedField,
                fields: subjectFields,
                label: nil,
                onDone: { hideKeyboard() }
            )
            .onAppear {
                refreshPreview()
            }
        }
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
        inputs = FinalGradeWhatIfView.buildInitialInputs(subjectNames: subjectNames, existingPoints: existingPoints, existingSimulation: [:])
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
        for name in subjectNames {
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

    private static func buildInitialInputs(subjectNames: [String],
                                           existingPoints: [String: Double?],
                                           existingSimulation: [String: Double]) -> [String: String] {
        var dict: [String: String] = [:]
        for name in subjectNames {
            if let sim = existingSimulation[name] {
                dict[name] = Self.format(sim)
            } else if let current = existingPoints[name] ?? nil {
                dict[name] = Self.format(current)
            }
        }
        return dict
    }

    private static func format(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private enum SubjectField: Hashable {
        case subject(String)
    }

    private var subjectFields: [SubjectField] {
        subjectNames.map { SubjectField.subject($0) }
    }
}
