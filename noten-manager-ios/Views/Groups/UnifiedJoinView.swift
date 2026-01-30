import SwiftUI

struct UnifiedJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    @State private var code: String = ""
    @State private var isFetching: Bool = false
    @State private var errorMessage: String?
    
    @State private var joinPreview: JoinPreview?
    
    // For Class Join Context (Course Selection)
    @State private var showCourseSelection: Bool = false
    @State private var joinContext: ClassJoinContext?
    
    struct ClassJoinContext: Identifiable {
        let id: String
        let name: String
        let config: ClassConfiguration
        let linkedClassIds: [String]
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 40))
                            .foregroundStyle(.indigo)
                            .padding(.bottom, 4)
                        
                        Text("Code eingeben")
                            .font(.title2.bold())
                        
                        Text("Gib den Code einer Klasse oder Gruppe ein, um eine Vorschau zu sehen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 30)
                    
                    // Input
                    VStack(spacing: 12) {
                        TextField("Code", text: $code)
                            .font(.title3.monospaced().weight(.bold))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.formInputBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                            )
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Action
                    Button {
                        Task { await fetchPreview() }
                    } label: {
                        if isFetching {
                            ProgressView().tint(.white)
                        } else {
                            Text("Vorschau laden")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                    .disabled(code.isEmpty || isFetching)
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                    .accessibilityLabel("Abbrechen")
                }
            }
            .sheet(item: $joinPreview) { preview in
                JoinConfirmationSheet(preview: preview) {
                    Task { await performJoin(preview: preview) }
                }
                .environmentObject(store)
            }
            .navigationDestination(isPresented: $showCourseSelection) {
                if let ctx = joinContext {
                    CourseJoinView(
                        classId: ctx.id,
                        className: ctx.name,
                        config: ctx.config,
                        linkedClassIds: ctx.linkedClassIds,
                        onJoinSuccess: { dismiss() }
                    )
                    .environmentObject(store)
                }
            }
        }
    }
    
    @MainActor
    private func fetchPreview() async {
        isFetching = true
        errorMessage = nil
        do {
            let preview = try await store.fetchJoinPreview(code: code)
            self.joinPreview = preview
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        isFetching = false
    }
    
    @MainActor
    private func performJoin(preview: JoinPreview) async {
        isFetching = true
        do {
            if preview.type == .schoolClass {
                // 1. Join Class Immediately for Persistence
                try await store.joinClass(with: preview.id)
                
                // 2. Prepare Context for Optional Selection (check if new system with config)
                let info = try await store.fetchClassInfo(with: preview.id)
                if let config = info.config {
                    self.joinContext = ClassJoinContext(
                        id: info.id,
                        name: info.name,
                        config: config,
                        linkedClassIds: info.linkedClassIds ?? []
                    )
                    self.showCourseSelection = true
                } else {
                    // Legacy Direct Join already covered by joinClass above
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    dismiss()
                }
            } else {
                // Group Join Logic
                let (_, errors) = await store.joinSharedGroups(codes: [preview.id])
                if let error = errors.first {
                    throw NSError(domain: "Join", code: -1, userInfo: [NSLocalizedDescriptionKey: error.value])
                }
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        isFetching = false
    }
}
