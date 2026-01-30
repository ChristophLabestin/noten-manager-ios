//
//  ContentView.swift
//  noten-manager-ios
//
//  Created by Christoph Labestin on 18.11.25.
//

import SwiftUI
import UIKit
import FirebaseAuth
import LocalAuthentication

enum DeeplinkDestination: Equatable {
    case examList
    case homeworkList
    case notifications
    case support
    case launchMessage
}

@MainActor
struct ContentView: View {
    @StateObject private var authManager = AuthManager()
    @StateObject private var gradesStore = GradesStore()
    @StateObject private var biometricManager = BiometricAuthManager.shared
    @StateObject private var storeKitManager = StoreKitManager()
    @EnvironmentObject private var offlineManager: OfflineModeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("preAuthOnboardingCompleted") private var preAuthOnboardingCompleted = false
    @State private var showOfflinePrompt: Bool = false
    @State private var offlineSnapshotForPrompt: OfflineSnapshot?
    @State private var biometricUnlocked: Bool = false
    @State private var biometricMessage: String?
    @State private var isRequestingBiometric: Bool = false
    @State private var pendingBiometricAfterUnlock: Bool = false
    @State private var incomingHomeworkShare: HomeworkShareLinkPayload?
    @State private var incomingExamId: String?
    @State private var incomingHomeworkId: String?
    @State private var deeplinkDestination: DeeplinkDestination?

    private var shouldShowPreAuth: Bool {
        !preAuthOnboardingCompleted
        && authManager.currentUser == nil
        && offlineManager.lastLoginUserId == nil
    }

    var body: some View {
        ZStack {
            backgroundGradient

            Group {
                if (authManager.isAuthenticated || offlineManager.isOfflineModeActive) && !authManager.isLoading {
                    if biometricRequired && !biometricUnlocked {
                        biometricLockScreen
                    } else if authManager.isNewRegistration && !offlineManager.isOfflineModeActive {
                        OnboardingFunnelView {
                            authManager.isNewRegistration = false
                        }
                        .environmentObject(gradesStore)
                        .environmentObject(authManager)
                        .transition(.opacity)
                    } else if !offlineManager.isOfflineModeActive && !gradesStore.initialSyncSettled {
                        EnhancedLoadingScreen()
                            .environmentObject(gradesStore)
                    } else if (authManager.isNewRegistration || gradesStore.onboardingRequired || gradesStore.legacyMigrationSummary != nil) && !offlineManager.isOfflineModeActive {
                        OnboardingFunnelView {
                            authManager.isNewRegistration = false
                        }
                        .environmentObject(gradesStore)
                        .environmentObject(authManager)
                        .transition(.opacity)
                    } else {
                        MainView(onLogout: {
                            gradesStore.stopListening()
                            authManager.signOut()
                        }, incomingHomeworkShare: $incomingHomeworkShare, incomingExamId: $incomingExamId, incomingHomeworkId: $incomingHomeworkId, deeplinkDestination: $deeplinkDestination)
                        .environmentObject(authManager)
                        .environmentObject(offlineManager)
                        .environmentObject(biometricManager)
                        .environmentObject(storeKitManager)
                        .environmentObject(storeKitManager)
                        .environmentObject(gradesStore)
                        .transition(.opacity)
                    }

                } else {
                    NavigationStack {
                        Group {
                            if shouldShowPreAuth {
                                PreAuthOnboardingView {
                                    preAuthOnboardingCompleted = true
                                }
                            } else {
                                AuthView(authManager: authManager)
                            }
                        }
                        .navigationBarHidden(true)
                    }
                    .environmentObject(biometricManager)
                    .transition(.opacity)
                }

            }
        }
        .onAppear {
            offlineManager.startMonitoring()
            authManager.startListeningAuthState()
            if authManager.isAuthenticated {
                startOnlineListeningIfNeeded()
            }
            refreshBiometricState(triggerUnlock: true)
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                evaluateOfflineOffer()
            }
        }
        .onChange(of: offlineManager.isOnline) { _, online in
            if online {
                attemptResumeOnlineIfPossible()
            } else {
                evaluateOfflineOffer()
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuth in
            if isAuth {
                preAuthOnboardingCompleted = true
                startOnlineListeningIfNeeded()
            } else {
                // Ensure store is reset on any logout
                gradesStore.stopListening()
            }
            if isAuth && offlineManager.isOfflineModeActive && !offlineManager.isManualOfflinePinned {
                offlineManager.deactivateOfflineMode()
            }
            refreshBiometricState(triggerUnlock: isAuth)
        }
        .onChange(of: offlineManager.isOfflineModeActive) { _, _ in
            refreshBiometricState(triggerUnlock: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                biometricUnlocked = false
                pendingBiometricAfterUnlock = biometricRequired
            } else if phase == .active {
                requestBiometricUnlockIfNeeded(force: false)
                Task { _ = await storeKitManager.refreshAllStatus() }
            }
        }
        .onChange(of: biometricManager.isEnabledForActiveUser) { _, _ in
            refreshBiometricState(triggerUnlock: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            guard pendingBiometricAfterUnlock else { return }
            pendingBiometricAfterUnlock = false
            requestBiometricUnlockIfNeeded(force: false)
        }
        .alert("Offline-Modus nutzen?", isPresented: $showOfflinePrompt) {
            Button("Offline starten") {
                startOfflineMode()
            }
            Button("Abbrechen", role: .cancel) {
                offlineSnapshotForPrompt = nil
            }
        } message: {
            Text(offlinePromptMessage)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openHomeworkDetail)) { notification in
            if let id = notification.object as? String {
                self.incomingHomeworkId = id
            }
        }
        .hideKeyboardOnTap()
    }

    private var backgroundGradient: some View {
        Group {
            if colorScheme == .dark {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255),
                        Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255)
                    ]),
                    center: .top,
                    startRadius: 0,
                    endRadius: 800
                )
            } else {
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

    private func evaluateOfflineOffer() {
        guard !offlineManager.isOfflineModeActive else { return }
        guard !showOfflinePrompt else { return }
        guard offlineManager.networkStatusReady else { return }
        guard !offlineManager.isOnline else { return }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !offlineManager.isOnline else { return }
            guard offlineManager.networkStatusReady else { return }
            guard !offlineManager.isOfflineModeActive else { return }
            guard !authManager.isAuthenticated else { return }
            guard !showOfflinePrompt else { return }
            guard let snapshot = offlineManager.availableSnapshot() else { return }
            guard offlineManager.isOfflineLoginAllowed(for: snapshot.userId) else {
                authManager.errorMessage = "Offline-Modus nicht möglich: letzter Online-Login ist älter als 3 Tage."
                return
            }
            offlineSnapshotForPrompt = snapshot
            showOfflinePrompt = true
        }
    }

    private func startOfflineMode() {
        if offlineSnapshotForPrompt == nil {
            offlineSnapshotForPrompt = offlineManager.availableSnapshot()
        }
        guard offlineSnapshotForPrompt != nil else { return }
        offlineManager.activateOfflineMode(manual: true)
        showOfflinePrompt = false
    }

    private func attemptResumeOnlineIfPossible() {
        guard offlineManager.isOfflineModeActive else { return }
        guard !offlineManager.isManualOfflinePinned else { return }
        guard authManager.isAuthenticated else { return }
        Task {
            OfflineModeManager.shared.enableFirestoreNetworkIfNeeded()
            await gradesStore.syncOfflinePendingChanges(forceLocalOverride: true)
            gradesStore.leaveOfflineModePreservingState()
            await gradesStore.startListening()
        }
    }

    private func startOnlineListeningIfNeeded() {
        guard !offlineManager.isOfflineModeActive else { return }
        Task {
            await gradesStore.syncOfflinePendingChanges(forceLocalOverride: true)
            await gradesStore.startListening()
        }
    }

    private var offlinePromptMessage: String {
        let lastLoginText: String
        if let last = offlineManager.lastLoginDate {
            lastLoginText = "Letzter Online-Login: \(offlineDateFormatter.string(from: last))"
        } else {
            lastLoginText = "Letzter Online-Login unbekannt."
        }
        return """
        Keine Internetverbindung erkannt. Möchtest du mit den zuletzt gespeicherten Daten weiterarbeiten?
        \(lastLoginText)
        Offline bleibt bis zu 3 Tage nach dem letzten Login freigeschaltet.
        """
    }

    private var offlineDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private var currentUserId: String? {
        authManager.currentUser?.uid
        ?? offlineManager.cachedSnapshot?.userId
        ?? offlineManager.lastLoginUserId
    }

    private var biometricRequired: Bool {
        let sessionActive = authManager.isAuthenticated || offlineManager.isOfflineModeActive
        guard sessionActive else { return false }
        return biometricManager.isEnabled(for: currentUserId)
    }

    private func refreshBiometricState(triggerUnlock: Bool) {
        biometricManager.setActiveUser(id: currentUserId)
        let requires = biometricRequired
        if !requires {
            biometricUnlocked = true
            biometricMessage = nil
            pendingBiometricAfterUnlock = false
            return
        }
        if !triggerUnlock && biometricUnlocked {
            biometricMessage = biometricManager.biometricsAvailable ? nil : "\(biometricManager.biometryName()) ist aktuell nicht verfügbar."
            return
        }
        biometricUnlocked = false
        biometricMessage = biometricManager.biometricsAvailable ? nil : "\(biometricManager.biometryName()) ist aktuell nicht verfügbar."
        if triggerUnlock {
            requestBiometricUnlockIfNeeded(force: true)
        }
    }

    private func attemptBiometricUnlockIfNeeded(force: Bool) async {
        biometricManager.refreshEnabledState()
        let requires = biometricRequired
        guard requires else {
            biometricUnlocked = true
            biometricMessage = nil
            return
        }
        guard UIApplication.shared.isProtectedDataAvailable else {
            pendingBiometricAfterUnlock = true
            return
        }
        if !biometricManager.biometricsAvailable {
            disableBiometricRequirement(with: "\(biometricManager.biometryName()) nicht verfügbar – Face ID/Touch ID wurde deaktiviert. Aktiviere es erneut in den Einstellungen.")
            return
        }
        guard force || !biometricUnlocked else { return }
        guard !isRequestingBiometric else { return }
        isRequestingBiometric = true
        let reason = "\(biometricManager.biometryName()) entsperrt deinen Zugang zu den Noten."
        let success = await biometricManager.authenticate(reason: reason)
        await MainActor.run {
            biometricUnlocked = success
            biometricMessage = success ? nil : "\(biometricManager.biometryName()) fehlgeschlagen oder abgebrochen."
            isRequestingBiometric = false
        }
    }

    private func requestBiometricUnlockIfNeeded(force: Bool) {
        guard biometricRequired else { return }
        guard UIApplication.shared.isProtectedDataAvailable else {
            pendingBiometricAfterUnlock = true
            return
        }
        Task { await attemptBiometricUnlockIfNeeded(force: force) }
    }

    private var biometricLockScreen: some View {
        VStack(spacing: 18) {
            Image(systemName: biometricManager.biometryType == .touchID ? "touchid" : "faceid")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("\(biometricManager.biometryName()) erforderlich")
                    .font(.title3.weight(.semibold))
                Text("Entsperre den Noten Manager, um fortzufahren.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            if isRequestingBiometric {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("\(biometricManager.biometryName()) wird geprüft ...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let message = biometricMessage, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await attemptBiometricUnlockIfNeeded(force: true) }
                } label: {
                    Label("Mit \(biometricManager.biometryName()) entsperren", systemImage: biometricManager.biometryType == .touchID ? "touchid" : "faceid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(isRequestingBiometric)

                if !isRequestingBiometric && (biometricMessage?.isEmpty == false) {
                    Button {
                        disableBiometricRequirement()
                    } label: {
                        Label("\(biometricManager.biometryName()) deaktivieren", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    handleLogoutFromLock()
                } label: {
                    Text("Abmelden")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private func handleLogoutFromLock() {
        biometricUnlocked = false
        authManager.signOut()
    }

    private func disableBiometricRequirement(with message: String? = nil) {
        biometricManager.setEnabled(false, for: currentUserId)
        biometricManager.refreshEnabledState()
        biometricUnlocked = true
        biometricMessage = message
    }

    private func handleIncomingURL(_ url: URL) {
        if let payload = HomeworkShareLinkBuilder.payload(from: url) {
            incomingHomeworkShare = payload
        }
        if url.scheme?.lowercased() == "notenmanager",
           let host = url.host?.lowercased() {
            switch host {
            case "exam":
                let components = url.pathComponents.filter { $0 != "/" }
                if let id = components.first {
                    incomingExamId = id
                    NotificationCenter.default.post(name: .openExamDetail, object: id)
                }
            case "exams":
                deeplinkDestination = .examList
            case "homework":
                deeplinkDestination = .homeworkList
            case "group":
                // notenmanager://group/join?code=XYZ
                if let action = url.pathComponents.filter({ $0 != "/" }).first,
                   action == "join",
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    // Send notification to open join sheet with code
                    NotificationCenter.default.post(name: .openGroupJoin, object: code)
                }
            default:
                break
            }
        }
    }
}

extension Notification.Name {
    static let openExamDetail = Notification.Name("openExamDetail")
    static let openLaunchOffer = Notification.Name("openLaunchOffer")
    static let openGroupJoin = Notification.Name("openGroupJoin")
    static let openHomeworkDetail = Notification.Name("openHomeworkDetail")
    static let openNotificationItem = Notification.Name("openNotificationItem")
    static let toggleSubscriptionOfferSheet = Notification.Name("toggleSubscriptionOfferSheet")
}

private struct PreAuthOnboardingView: View {
    private enum Step {
        case welcome
        case errorLogging
    }

    let onFinished: () -> Void

    @AppStorage("allowAnonymousErrorLogging") private var storedAllowAnonymousErrorLogging = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var step: Step = .welcome
    @State private var allowAnonymousErrorLogging: Bool = false
    @State private var didLoadPreference: Bool = false
    @State private var animateDecorations: Bool = true
    private let contentMaxWidth: CGFloat = 600
    private let buttonMaxWidth: CGFloat = 520

    var body: some View {
        VStack(spacing: 20) {
            contentContainer
            Spacer(minLength: 0)
            bottomButton
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .animation(.easeInOut(duration: 0.25), value: step)
        .onAppear {
            if !didLoadPreference {
                allowAnonymousErrorLogging = storedAllowAnonymousErrorLogging
                didLoadPreference = true
            }
        }
    }

    private var contentContainer: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: step == .welcome ? 360 : 380)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeContent
        case .errorLogging:
            errorLoggingContent
        }
    }

    private var welcomeContent: some View {
        ZStack {
            welcomeDecorations
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                welcomeHero

                Text("Willkommen im Noten Manager")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text("Deine Noten klar organisiert.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var welcomeHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.indigo.opacity(colorScheme == .dark ? 0.5 : 0.35),
                            Color.cyan.opacity(colorScheme == .dark ? 0.28 : 0.22),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 170, height: 170)
                .rotationEffect(.degrees(animateDecorations ? 4 : -4))
                .opacity(colorScheme == .dark ? 0.9 : 0.75)
                .blur(radius: 1)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.25 : 0.4),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
                .frame(width: 158, height: 158)
                .rotationEffect(.degrees(animateDecorations ? -3 : 3))

            Image("AppIconPreviewDefault")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18),
                    radius: 14,
                    x: 0,
                    y: 8
                )
        }
    }

    private var welcomeDecorations: some View {
        GeometryReader { geo in
            let size = geo.size
            let base = min(size.width, size.height)
            let large = base * 0.95
            let medium = base * 0.6
            let small = base * 0.18

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.indigo.opacity(colorScheme == .dark ? 0.5 : 0.45),
                                Color.cyan.opacity(colorScheme == .dark ? 0.18 : 0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: large, height: large)
                    .position(x: size.width * 0.92, y: size.height * 0.04)
                    .blur(radius: 20)
                    .opacity(colorScheme == .dark ? 0.28 : 0.45)
                    .offset(
                        x: animateDecorations ? -14 : 14,
                        y: animateDecorations ? 10 : -10
                    )

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.orange.opacity(colorScheme == .dark ? 0.28 : 0.2),
                                Color.indigo.opacity(colorScheme == .dark ? 0.18 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: medium, height: medium)
                    .position(x: size.width * 0.1, y: size.height * 0.92)
                    .blur(radius: 12)
                    .opacity(colorScheme == .dark ? 0.3 : 0.4)
                    .offset(
                        x: animateDecorations ? 10 : -10,
                        y: animateDecorations ? -6 : 6
                    )

                Circle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.3))
                    .frame(width: small, height: small)
                    .position(x: size.width * 0.78, y: size.height * 0.62)
                    .blur(radius: 1)
                    .offset(
                        x: animateDecorations ? 6 : -6,
                        y: animateDecorations ? -8 : 8
                    )

                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.22))
                    .frame(width: base * 0.3, height: base * 0.06)
                    .position(x: size.width * 0.2, y: size.height * 0.24)
                    .rotationEffect(.degrees(animateDecorations ? -12 : 12))
            }
        }
        .allowsHitTesting(false)
    }

    private var errorLoggingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anonyme Fehlerberichte")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Wenn aktiviert, senden wir anonyme Fehlerberichte in unsere Datenbank, damit wir Probleme schneller beheben können. Es werden keine Noten oder persönlichen Inhalte übertragen.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            errorLoggingToggle
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var errorLoggingToggle: some View {
        Button {
            allowAnonymousErrorLogging.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: allowAnonymousErrorLogging ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(allowAnonymousErrorLogging ? Color.green : Color.secondary)
                    .padding(.top, 1)

                Text("Ich erlaube anonyme Fehlerberichte.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private var bottomButton: some View {
        Button {
            switch step {
            case .welcome:
                step = .errorLogging
            case .errorLogging:
                storedAllowAnonymousErrorLogging = allowAnonymousErrorLogging
                onFinished()
            }
        } label: {
            Text(step == .welcome ? "Weiter" : "Einstellungen speichern")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SoftTintButtonStyle(accent: .indigo))
        .frame(maxWidth: buttonMaxWidth)
        .frame(maxWidth: .infinity)
    }

}

#Preview {
    ContentView()
        .environmentObject(OfflineModeManager.shared)
        .environmentObject(BiometricAuthManager.shared)
}
