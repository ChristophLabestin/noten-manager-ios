// MainView.swift
import SwiftUI
import FirebaseAuth

// PreferenceKey, mit dem Detailseiten (SubjectDetail) den aktuellen Fachnamen
// an den Container melden, damit die global überlagerte BottomNav die Vorauswahl kennt.
struct QuickAddSubjectPreferenceKey: PreferenceKey {
    static var defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

struct MainView: View {
    let onLogout: () -> Void
    @StateObject private var gradesStore = GradesStore()
    @State private var currentTab: BottomNavView.Tab = .home
    @EnvironmentObject private var offlineManager: OfflineModeManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var biometricManager: BiometricAuthManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var navPath = NavigationPath()
    @State private var showOnboardingFunnel: Bool = false
    @State private var offlineBannerVisible: Bool = false
    @State private var offlineBannerDismissTask: Task<Void, Never>?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var showPfingstferienPrompt: Bool = false
    @State private var nextSchoolYearSuggestion: String?
    @State private var spinnerAnimating: Bool = false
    @State private var emailBannerVisible: Bool = false
    @State private var emailBannerDismissTask: Task<Void, Never>?
    @State private var needsEmailVerification: Bool = false
    @State private var scrollToAccountOnOpen: Bool = false

    // Von SubjectDetail per Preference gemeldetes Fach für „Note hinzufügen“
    @State private var quickAddSubjectName: String? = nil
    @State private var navigateToAbiturExam: Bool = false

    var body: some View {
        ZStack {
            themedBackground
            navigationContainer
        }
        // Änderungen am gemeldeten Fachnamen von SubjectDetail entgegennehmen
        .onPreferenceChange(QuickAddSubjectPreferenceKey.self) { value in
            quickAddSubjectName = value
        }
        // Wenn der Nutzer „System“ gewählt hat, den Dark-Mode-Status mit dem aktuellen
        // ColorScheme des Geräts synchronisieren, sobald es sich ändert.
        .onAppear {
            gradesStore.syncDarkModeWithSystem(colorScheme: colorScheme)
        }
        .onChange(of: colorScheme) { newScheme in
            gradesStore.syncDarkModeWithSystem(colorScheme: newScheme)
        }
        // Dark-Mode-Verhalten wie im React-Client:
        // nutze die gespeicherte darkMode-Präferenz des Nutzers
        .preferredColorScheme(gradesStore.preferredColorScheme)
        .onChange(of: gradesStore.onboardingRequired) { required in
            showOnboardingFunnel = required
        }
        .onChange(of: gradesStore.gradeYear) { _ in
            Task { await evaluatePfingstferienPrompt() }
        }
        .onChange(of: gradesStore.activeSchoolYearId) { _ in
            Task { await evaluatePfingstferienPrompt() }
        }
        .onChange(of: gradesStore.isLoading) { loading in
            spinnerAnimating = loading
        }
        .fullScreenCover(isPresented: $showOnboardingFunnel) {
            OnboardingFunnelView {
                showOnboardingFunnel = false
            }
            .environmentObject(gradesStore)
        }
        .task {
            await handleDataLoading()
            await refreshEmailVerification()
        }
        .onChange(of: offlineManager.isOfflineModeActive) { active in
            Task {
                await handleOfflineToggle(active: active)
            }
        }
        .onChange(of: authManager.isAuthenticated) { _ in
            Task { await refreshEmailVerification() }
        }
        .onChange(of: currentTab) { newTab in
            if newTab != .settings {
                scrollToAccountOnOpen = false
            }
        }
        .overlay(alignment: .center) {
            if gradesStore.isLoading {
                loadingOverlay
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if emailBannerVisible {
                    emailVerificationBanner
                }
                offlineBanner
            }
            .animation(.easeInOut(duration: 0.2), value: emailBannerVisible)
        }
        .toolbar {
            if offlineManager.isOfflineModeActive, navPath.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    offlineToolbarButton
                }
            }
            if needsEmailVerification, navPath.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    emailVerificationToolbarButton
                }
            }
        }
        .alert("Neues Schuljahr anlegen?", isPresented: $showPfingstferienPrompt, presenting: nextSchoolYearSuggestion) { yearId in
            Button("Ja, \(yearId) erstellen") {
                Task {
                    await createNextSchoolYear(id: yearId)
                }
            }
            Button("Später", role: .cancel) {
                showPfingstferienPrompt = false
            }
        } message: { yearId in
            Text("Die Pfingstferien sind vorbei. Möchtest du das neue Schuljahr \(yearId) jetzt anlegen?")
        }
    }

    @MainActor
    private func handleDataLoading() async {
        if offlineManager.isOfflineModeActive {
            if let snapshot = offlineManager.cachedSnapshot ?? offlineManager.availableSnapshot() {
                gradesStore.loadOfflineSnapshot(snapshot)
            }
            showOfflineBannerTemporarily()
            await refreshEmailVerification()
            await evaluatePfingstferienPrompt()
            return
        }

        // Fallback: wenn kein Internet, aber ein Snapshot existiert und innerhalb 3 Tage ist, direkt offline laden
        if !offlineManager.isOnline {
            if let snapshot = offlineManager.availableSnapshot(),
               offlineManager.isOfflineLoginAllowed(for: snapshot.userId) {
                gradesStore.loadOfflineSnapshot(snapshot)
                showOfflineBannerTemporarily()
                await refreshEmailVerification()
                await evaluatePfingstferienPrompt()
                return
            }
        }

        OfflineModeManager.shared.enableFirestoreNetworkIfNeeded()
        await gradesStore.syncOfflinePendingChanges(forceLocalOverride: true)

        gradesStore.leaveOfflineModePreservingState()
        await gradesStore.startListening()
        hideOfflineBanner()
        await evaluatePfingstferienPrompt()
    }

    @MainActor
    private func handleOfflineToggle(active: Bool) async {
        if active {
            if let snapshot = offlineManager.cachedSnapshot ?? offlineManager.availableSnapshot() {
                gradesStore.loadOfflineSnapshot(snapshot)
            }
            showOfflineBannerTemporarily()
        } else {
            OfflineModeManager.shared.enableFirestoreNetworkIfNeeded()
            await gradesStore.syncOfflinePendingChanges(forceLocalOverride: true)
            if offlineManager.isOnline {
                gradesStore.leaveOfflineModePreservingState()
                await gradesStore.startListening()
                hideOfflineBanner()
            } else {
                await attemptReconnectOrFallback()
            }
        }
    }

    @MainActor
    private func evaluatePfingstferienPrompt() async {
        guard !showPfingstferienPrompt else { return }
        if let suggestion = await gradesStore.shouldOfferNextSchoolYearAfterPfingstferien() {
            nextSchoolYearSuggestion = suggestion
            showPfingstferienPrompt = true
        }
    }

    @MainActor
    private func createNextSchoolYear(id: String) async {
        let created = await gradesStore.createSchoolYear(name: id)
        if created == nil {
            await gradesStore.setActiveSchoolYear(id: id)
        }
        showPfingstferienPrompt = false
        nextSchoolYearSuggestion = nil
    }

    private var offlineBanner: some View {
        Group {
            if offlineManager.isOfflineModeActive, offlineBannerVisible {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.slash")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offline-Modus aktiv")
                            .font(.subheadline)
                            .bold()
                        Text(offlineStatusSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        hideOfflineBanner()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Offline-Hinweis schließen")
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
    }

    private var offlineStatusSubtitle: String {
        let lastText = lastOnlineText
        return "\(lastText) – synchronisieren, sobald du wieder online bist und dich anmeldest."
    }

    private var lastOnlineText: String {
        if let last = offlineManager.lastLoginDate {
            return "Letzter Online-Login: \(Self.offlineDateFormatter.string(from: last))"
        }
        return "Letzter Online-Login unbekannt"
    }

    private static let offlineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var offlineToolbarButton: some View {
        Button {
            showOfflineBannerTemporarily()
        } label: {
            Image(systemName: "wifi.slash")
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func showOfflineBannerTemporarily() {
        offlineBannerDismissTask?.cancel()
        // Toggle: wenn bereits sichtbar, dann schließen
        if offlineBannerVisible {
            hideOfflineBanner()
            return
        }
        offlineBannerVisible = true
        offlineBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            offlineBannerVisible = false
        }
    }

    private func hideOfflineBanner() {
        offlineBannerDismissTask?.cancel()
        offlineBannerDismissTask = nil
        offlineBannerVisible = false
    }

    private var emailVerificationBanner: some View {
        VStack(spacing: 10) {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("E-Mail noch nicht bestätigt")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.white)
                Text("Bitte bestätige deine Adresse über die E-Mail, die wir gesendet haben.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(1))
            }
            Spacer()

            Button {
                hideEmailBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(1))
            }
            .buttonStyle(.plain)
        }
            Button {
                scrollToAccountOnOpen = true
                currentTab = .settings
                hideEmailBanner()
            } label: {
                Label("Zu Einstellungen", systemImage: "arrow.right.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.25))
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(1))
        )
        .padding(.horizontal, 16)
    }

    private var emailVerificationToolbarButton: some View {
        Button {
            showEmailBannerTemporarily()
        } label: {
            Image(systemName: "info.circle.fill")
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.red)
    }

    private func showEmailBannerTemporarily() {
        emailBannerDismissTask?.cancel()
        // Toggle: wenn bereits sichtbar, dann schließen
        if emailBannerVisible {
            hideEmailBanner()
            return
        }
        emailBannerVisible = true
        emailBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            emailBannerVisible = false
        }
    }

    private func hideEmailBanner() {
        emailBannerDismissTask?.cancel()
        emailBannerDismissTask = nil
        emailBannerVisible = false
    }

    @MainActor
    private func refreshEmailVerification() async {
        guard let user = Auth.auth().currentUser else {
            needsEmailVerification = false
            emailBannerVisible = false
            return
        }
        do {
            try await user.reload()
            needsEmailVerification = !user.isEmailVerified
            if !needsEmailVerification {
                hideEmailBanner()
            }
        } catch {
            needsEmailVerification = false
            hideEmailBanner()
        }
    }

    @ViewBuilder
    private var navigationContainer: some View {
        NavigationStack(path: $navPath) {
            Group {
                switch currentTab {
                case .home:
                    HomeView()
                        .environmentObject(gradesStore)
                case .insights:
                    InsightsView()
                        .environmentObject(gradesStore)
                case .final:
                    FinalGradeView()
                        .environmentObject(gradesStore)
                case .settings:
                    AppSettingsView(scrollToAccount: scrollToAccountOnOpen)
                        .environmentObject(gradesStore)
                        .environmentObject(authManager)
                        .environmentObject(offlineManager)
                        .environmentObject(biometricManager)
                }
            }
            NavigationLink(
                destination: AbiturExamView().environmentObject(gradesStore),
                isActive: $navigateToAbiturExam
            ) {
                EmptyView()
            }
        }
        .navigationDestination(for: Subject.self) { subject in
            if subject.name == "Fachreferat" {
                FachreferatDetailView(subject: subject)
                    .environmentObject(gradesStore)
            } else {
                SubjectDetailView(subject: subject)
                    .environmentObject(gradesStore)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 100)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .bottom) {
            BottomNavView(
                currentTab: currentTab,
                onOpenHome: { currentTab = .home },
                onOpenFinalGrade: { currentTab = .final },
                onOpenSettings: { currentTab = .settings },
                onOpenInsights: { currentTab = .insights },
                onOpenAbitur: { navigateToAbiturExam = true },
                quickAddPreselectedSubjectName: quickAddSubjectName
            )
            .environmentObject(gradesStore)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    @MainActor
    private func attemptReconnectOrFallback() async {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            gradesStore.isLoading = true
            for remaining in stride(from: 15, through: 1, by: -1) {
                gradesStore.loadingLabel = "Verbinde … (\(remaining)s)"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if offlineManager.isOnline {
                    OfflineModeManager.shared.enableFirestoreNetworkIfNeeded()
                    await gradesStore.syncOfflinePendingChanges(forceLocalOverride: true)
                    gradesStore.leaveOfflineModePreservingState()
                    await gradesStore.startListening()
                    hideOfflineBanner()
                    gradesStore.isLoading = false
                    reconnectTask = nil
                    return
                }
            }
            // Timeout -> im Offline-Modus bleiben
            if let snapshot = offlineManager.cachedSnapshot ?? offlineManager.availableSnapshot() {
                gradesStore.loadOfflineSnapshot(snapshot)
                showOfflineBannerTemporarily()
            }
            gradesStore.isLoading = false
            reconnectTask = nil
        }
    }

    private var loadingOverlayLabel: String {
        if gradesStore.loadingLabel.isEmpty {
            return "Daten werden geladen …"
        }
        return gradesStore.loadingLabel
    }

    private var loadingAccent: Color {
        if gradesStore.theme == "feminine" {
            return Color(hex: "#ec4899")
        }
        return .indigo
    }

    private var loadingAccentSecondary: Color {
        gradesStore.darkMode ? .white.opacity(0.8) : .primary.opacity(0.85)
    }

    private var loadingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            Color.black.opacity(gradesStore.darkMode ? 0.18 : 0.10)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [loadingAccent.opacity(0.18), loadingAccent.opacity(0.34)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(loadingAccent)
                        .rotationEffect(.degrees(spinnerAnimating ? 360 : 0))
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spinnerAnimating)
                }

                VStack(spacing: 4) {
                    Text("Synchronisiere deine Daten")
                        .font(.headline)
                        .foregroundStyle(loadingAccentSecondary)
                    Text(loadingOverlayLabel)
                        .font(.subheadline)
                        .foregroundStyle(loadingAccentSecondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 4)

                if gradesStore.progress > 0 {
                    VStack(spacing: 8) {
                        ProgressView(value: gradesStore.progress, total: 100)
                            .tint(loadingAccent)
                        Text("\(Int(gradesStore.progress.rounded()))% abgeschlossen")
                            .font(.caption)
                            .foregroundStyle(loadingAccentSecondary.opacity(0.8))
                    }
                    .frame(maxWidth: 240)
                } else {
                    ProgressView()
                        .tint(loadingAccent)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(loadingAccent.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(gradesStore.darkMode ? 0.5 : 0.2), radius: 20, x: 0, y: 12)
            )
            .padding(.horizontal, 32)
        }
        .onAppear { spinnerAnimating = true }
        .onDisappear { spinnerAnimating = false }
        .zIndex(50)
    }

    private var themedBackground: some View {
        Group {
            if gradesStore.darkMode {
                // Entspricht body.dark-mode: radialer Verlauf, unabhängig vom Theme
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#1f2937"), // $color-bg-light-dark
                        Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255)
                    ]),
                    center: .top,
                    startRadius: 0,
                    endRadius: 800
                )
            } else if gradesStore.theme == "feminine" {
                // Entspricht body.theme-feminine: pinker Gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#fdf2ff"), // $color-bg-feminine-top
                        Color(hex: "#fdf2f8"), // $color-bg-feminine-mid
                        Color(hex: "#fef2f2")  // $color-bg-feminine-bottom
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                // Standard-Gradient wie im Web body.theme-default
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 238 / 255, green: 242 / 255, blue: 255 / 255),
                        Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255),
                        Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}
