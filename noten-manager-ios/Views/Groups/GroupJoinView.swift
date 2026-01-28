import SwiftUI

struct GroupJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let initialCode: String
    
    @State private var code: String = ""
    @State private var isJoining: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var animationsOn: Bool { store.animationsEnabled }
    
    @State private var joinPreview: JoinPreview?
    @State private var showConfirmation: Bool = false
    
    init(initialCode: String = "") {
        self.initialCode = initialCode
        self._code = State(initialValue: initialCode)
    }
    
    @State private var showScanner: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Area
                    VStack(spacing: 4) {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.indigo)
                            .padding(.bottom, 4)
                            .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 12)
                        
                        Text("Gruppe beitreten")
                            .font(.title3.weight(.bold))
                            .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                        
                        Text("Gib einen oder mehrere Codes ein, um beizutreten (z.B. per Komma getrennt).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .fixedSize(horizontal: false, vertical: true)
                            .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                    }
                    .padding(.top, 16)
                    
                    // Input Card
                    SettingsCard(
                        title: "Gruppencodes",
                        subtitle: "Codes eingeben",
                        systemImage: "qrcode",
                        accent: .indigo
                    ) {
                        VStack(spacing: 12) {
                            TextField("Code(s)...", text: $code, axis: .vertical)
                                .font(.title3.monospaced())
                                .multilineTextAlignment(.leading)
                                .lineLimit(1...5)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled(true)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.formInputBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                                )
                            
                            Button {
                                showScanner = true
                            } label: {
                                Label("QR-Code scannen", systemImage: "viewfinder")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(.indigo)
                        }
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 12)
                    
                    // Messages
                    if let error = errorMessage {
                        StatusLabel(text: error, color: .red, icon: "exclamationmark.triangle.fill")
                            .softFadeIn(enabled: true)
                    }
                    
                    if let success = successMessage {
                        StatusLabel(text: success, color: .green, icon: "checkmark.circle.fill")
                            .softFadeIn(enabled: true)
                    }
                    
                    // Join Button
                    Button {
                        Task { await fetchPreview() }
                    } label: {
                        if isJoining {
                            ProgressView()
                                .tint(.indigo)
                        } else {
                            Text("Weiter")
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
                    .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 12)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(
                ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundStyle(isDark ? .white : .black)
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedCode in
                    let newCode = extractCode(from: scannedCode)
                    if !code.isEmpty {
                        code += ", \(newCode)"
                    } else {
                        code = newCode
                    }
                }
            }
            .sheet(isPresented: $showConfirmation) {
                if let preview = joinPreview {
                    JoinConfirmationSheet(preview: preview) {
                        Task { await joinGroup() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // Extrahiert den reinen Code aus potentiellen URL-Schemes
    private func extractCode(from raw: String) -> String {
        // Simple logic: if it's a URL, last component is likely the code.
        // E.g. notenmanager://group/ABCDEF
        if raw.contains("://") || raw.contains("http"), let url = URL(string: raw) {
            return url.lastPathComponent
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractCodes(from text: String) -> [String] {
        // Regex für 6-stellige alphanumerische Codes (grob)
        // Oder einfach Split by Komma/Space/Newline und filtern
        let components = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return components.filter { $0.count >= 4 } // Erlaube etwas Flexibilität, aber min 4 Chars
    }
    
    @MainActor
    private func fetchPreview() async {
        let codesToJoin = extractCodes(from: code)
        guard let singleCode = codesToJoin.first else { return }
        
        // If multiple codes, just bypass and join directly or handle differently?
        // User said "joining a class or social group", usually singular.
        if codesToJoin.count > 1 {
            await joinGroup()
            return
        }
        
        isJoining = true
        errorMessage = nil
        do {
            let preview = try await store.fetchJoinPreview(code: singleCode)
            self.joinPreview = preview
            self.showConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        isJoining = false
    }

    @MainActor
    private func joinGroup() async {
        let codesToJoin = extractCodes(from: code)
        guard !codesToJoin.isEmpty else { return }
        
        isJoining = true
        errorMessage = nil
        successMessage = nil
        
        let (joined, errors) = await store.joinSharedGroups(codes: codesToJoin)
        
        if !errors.isEmpty {
            // Fehlermeldung bauen
            let failureText = errors.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            if !joined.isEmpty {
                // Teilweise erfolgreich
                successMessage = "\(joined.count) Gruppen beigetreten."
                errorMessage = "Fehler bei:\n" + failureText
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            } else {
                // Alles fehlgeschlagen
                errorMessage = failureText
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        } else {
            // Alles gut
            successMessage = "Allen Gruppen erfolgreich beigetreten!"
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismiss()
        }
        
        isJoining = false
    }
}

private struct StatusLabel: View {
    let text: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
            Text(text)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
