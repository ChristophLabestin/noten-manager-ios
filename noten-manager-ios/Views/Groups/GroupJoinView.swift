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
    
    init(initialCode: String = "") {
        self.initialCode = initialCode
        self._code = State(initialValue: initialCode)
    }
    
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
                        
                        Text("Gib den Code ein, um der Gruppe beizutreten.")
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
                        title: "Gruppencode",
                        subtitle: "Code eingeben",
                        systemImage: "qrcode",
                        accent: .indigo
                    ) {
                        TextField("Code", text: $code)
                            .font(.title3.monospaced())
                            .multilineTextAlignment(.center)
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
                        Task { await joinGroup() }
                    } label: {
                        if isJoining {
                            ProgressView()
                                .tint(.indigo)
                        } else {
                            Text("Beitreten")
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
        }
        .presentationDetents([.medium, .large])
    }
    
    @MainActor
    private func joinGroup() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isJoining = true
        errorMessage = nil
        successMessage = nil
        
        do {
            try await store.joinSharedGroup(with: trimmed)
            successMessage = "Erfolgreich beigetreten!"
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismiss()
        } catch {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            errorMessage = error.localizedDescription
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
