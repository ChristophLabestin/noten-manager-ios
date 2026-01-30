import SwiftUI

struct ClassJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    @State private var code: String = ""
    @State private var isJoining: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showScanner: Bool = false
    
    @State private var joinContext: ClassJoinContext?
    @State private var showCourseSelection: Bool = false
    @State private var joinPreview: JoinPreview?
    @State private var showConfirmation: Bool = false
    
    struct ClassJoinContext: Identifiable {
        let id: String
        let name: String
        let config: ClassConfiguration
        let linkedClassIds: [String]
    }
    
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
                        Task { await fetchPreview() }
                    } label: {
                        if isJoining {
                            ProgressView().tint(.indigo)
                        } else {
                            Text("Weiter")
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
            .sheet(isPresented: $showConfirmation) {
                if let preview = joinPreview {
                    JoinConfirmationSheet(preview: preview) {
                        Task { await checkAndJoin() }
                    }
                }
            }
            .navigationDestination(isPresented: $showCourseSelection) {
                if let ctx = joinContext {
                    CourseJoinView(
                        classId: ctx.id,
                        className: ctx.name,
                        config: ctx.config,
                         linkedClassIds: ctx.linkedClassIds,
                        onJoinSuccess: {
                            dismiss()
                        }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "chevron.down", showDot: false)
                    }
                }
            }
        }
    }
    
    private func extractCode(from raw: String) -> String {
        if raw.contains("://") || raw.contains("http"), let url = URL(string: raw) {
            return url.lastPathComponent
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @MainActor
    private func fetchPreview() async {
        isJoining = true
        errorMessage = nil
        do {
            let preview = try await store.fetchJoinPreview(code: code)
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
    private func checkAndJoin() async {
        isJoining = true
        errorMessage = nil
        successMessage = nil
        do {
            // Check Class Details first
            let info = try await store.fetchClassInfo(with: code)
            
            if let config = info.config {
                // New System -> Course Selection
                self.joinContext = ClassJoinContext(
                    id: info.id,
                    name: info.name,
                    config: config,
                    linkedClassIds: info.linkedClassIds ?? []
                )
                self.showCourseSelection = true
            } else {
                // Legacy System -> Direct Join
                try await store.joinClass(with: code)
                
                // Handle linked classes for legacy join?
                if let linkedIds = info.linkedClassIds, !linkedIds.isEmpty {
                    // Ideally we prompt here too, but for now focusing on New System as requested
                    // Or auto-join? No, "opt in".
                    // Since legacy flow has no UI for options, we might skip it or show an alert after success.
                    // For simplicity, I'll ignore linked classes for legacy join unless I want to create a separate sheet.
                }

                successMessage = "Erfolgreich beigetreten!"
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        isJoining = false
    }
}
