import SwiftUI

struct ClassJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    @State private var code: String = ""
    @State private var isJoining: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showScanner: Bool = false
    
    // Reuse QR Scanner logic if desired, but let's stick to manual first for Classes to simplify scope
    
    private var animationsOn: Bool { store.animationsEnabled }
    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                     // Header Area
                     VStack(spacing: 4) {
                         Image(systemName: "person.badge.plus.fill")
                             .font(.system(size: 40))
                             .foregroundStyle(.indigo)
                             .padding(.bottom, 4)
                             .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 12)
                         
                         Text("Klasse beitreten")
                             .font(.title3.weight(.bold))
                             .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                         
                         Text("Gib den Code der Klasse ein, um beizutreten.")
                             .font(.callout)
                             .foregroundStyle(.secondary)
                             .multilineTextAlignment(.center)
                             .padding(.horizontal, 16)
                             .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                     }
                     .padding(.top, 16)
                    
                    // Input Card
                    SettingsCard(
                        title: "Klassencode",
                        subtitle: "Code eingeben",
                        systemImage: "qrcode",
                        accent: .indigo
                    ) {
                        VStack(spacing: 12) {
                            TextField("Code", text: $code)
                                .font(.title3.monospaced())
                                .multilineTextAlignment(.center)
                                .textInputAutocapitalization(.characters)
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
                         Text(error)
                             .foregroundStyle(.red)
                             .font(.caption)
                             .softFadeIn(enabled: true)
                    }
                    if let success = successMessage {
                        Text(success)
                            .foregroundStyle(.green)
                            .font(.caption)
                            .softFadeIn(enabled: true)
                    }
                    
                    // Join Button
                    Button {
                        Task { await joinClass() }
                    } label: {
                        if isJoining {
                            ProgressView().tint(.indigo)
                        } else {
                            Text("Beitreten")
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                    .disabled(code.isEmpty || isJoining)
                    .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 12)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scannedCode in
                    code = extractCode(from: scannedCode)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
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
        }
        .presentationDetents([.medium, .large])
    }
    
    private func extractCode(from raw: String) -> String {
        if raw.contains("://") || raw.contains("http"), let url = URL(string: raw) {
            return url.lastPathComponent
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @MainActor
    private func joinClass() async {
        isJoining = true
        errorMessage = nil
        successMessage = nil
        do {
            try await store.joinClass(with: code)
            successMessage = "Erfolgreich beigetreten!"
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        isJoining = false
    }
}
