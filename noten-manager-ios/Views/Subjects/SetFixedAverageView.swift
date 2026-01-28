import SwiftUI

struct SetFixedAverageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    // Theme access for ThemedBackground
    @AppStorage("appTheme") private var appTheme: String = "default"
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("themeBackgroundIntensity") private var backgroundIntensity: Double = 0.5
    
    let currentSubjectName: String
    let currentHalfYear1: Double?
    let currentHalfYear2: Double?
    let currentYearly: Double?
    
    // Calculated values for reference
    let calculatedHalfYear1: Double?
    let calculatedHalfYear2: Double?
    let calculatedYearly: Double?
    
    let onSave: (Double?, Double?, Double?) async -> Void
    
    @State private var halfYear1Text: String = ""
    @State private var halfYear2Text: String = ""
    @State private var yearlyText: String = ""
    @State private var isSaving: Bool = false
    
    init(subjectName: String,
         currentHalfYear1: Double?,
         currentHalfYear2: Double?,
         currentYearly: Double?,
         calculatedHalfYear1: Double?,
         calculatedHalfYear2: Double?,
         calculatedYearly: Double?,
         onSave: @escaping (Double?, Double?, Double?) async -> Void) {
        self.currentSubjectName = subjectName
        self.currentHalfYear1 = currentHalfYear1
        self.currentHalfYear2 = currentHalfYear2
        self.currentYearly = currentYearly
        self.calculatedHalfYear1 = calculatedHalfYear1
        self.calculatedHalfYear2 = calculatedHalfYear2
        self.calculatedYearly = calculatedYearly
        self.onSave = onSave
        
        _halfYear1Text = State(initialValue: format(currentHalfYear1))
        _halfYear2Text = State(initialValue: format(currentHalfYear2))
        _yearlyText = State(initialValue: format(currentYearly))
    }
    
    private func format(_ val: Double?) -> String {
        guard let v = val else { return "" }
        if v == floor(v) { return String(Int(v)) }
        return String(v)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Info Card
                    SettingsCard(
                        title: "Festen Schnitt setzen",
                        subtitle: "Manuelle Anpassung",
                        systemImage: "slider.horizontal.3",
                        accent: .indigo
                    ) {
                        Text("Hier kannst du den berechneten Schnitt manuell überschreiben. Lasse das Feld leer, um die automatische Berechnung zu nutzen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                    
                    // 1. Halbjahr
                    inputSection(
                        title: "1. Halbjahr",
                        text: $halfYear1Text,
                        calculated: calculatedHalfYear1,
                        icon: "1.circle"
                    )
                    
                    // 2. Halbjahr
                    inputSection(
                        title: "2. Halbjahr",
                        text: $halfYear2Text,
                        calculated: calculatedHalfYear2,
                        icon: "2.circle"
                    )
                    
                    // Jahresschnitt
                    inputSection(
                        title: "Jahresschnitt (Gesamt)",
                        text: $yearlyText,
                        calculated: calculatedYearly,
                        icon: "sum"
                    )
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(ThemedBackground(isDark: isDarkMode, isFeminine: appTheme == "feminine", intensity: backgroundIntensity))
            .navigationTitle("Schnitt anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true
                            await onSave(toDouble(halfYear1Text), toDouble(halfYear2Text), toDouble(yearlyText))
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ToolbarLoadingIcon()
                        } else {
                            ToolbarIcon(symbol: "checkmark", showDot: false)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
    
    private func inputSection(title: String, text: Binding<String>, calculated: Double?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                TextField("Punkte (z.B. 10)", text: text)
                    .keyboardType(.decimalPad)
                    .padding()
                    .background(Color.formInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                if let calc = calculated {
                    Text("Berechnet: \(String(format: "%.2f", calc))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .padding()
        .background(Color.formSectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func toDouble(_ str: String) -> Double? {
        let clean = str.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(clean)
    }
}
