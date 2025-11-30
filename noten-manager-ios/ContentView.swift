//
//  ContentView.swift
//  noten-manager-ios
//
//  Created by Christoph Labestin on 18.11.25.
//

import SwiftUI
import FirebaseAuth
import LocalAuthentication

@MainActor
struct ContentView: View {
    @StateObject private var authManager = AuthManager()
    @StateObject private var biometricManager = BiometricAuthManager.shared
    @EnvironmentObject private var offlineManager: OfflineModeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOfflinePrompt: Bool = false
    @State private var offlineSnapshotForPrompt: OfflineSnapshot?
    @State private var biometricUnlocked: Bool = false
    @State private var biometricMessage: String?
    @State private var isRequestingBiometric: Bool = false
    @State private var incomingHomeworkShare: HomeworkShareLinkPayload?
    @State private var incomingExamId: String?

    var body: some View {
        ZStack {
            backgroundGradient

            Group {
                if authManager.isAuthenticated || offlineManager.isOfflineModeActive {
                    if biometricRequired && !biometricUnlocked {
                        biometricLockScreen
                    } else {
                        MainView(onLogout: {
                            authManager.signOut()
                        }, incomingHomeworkShare: $incomingHomeworkShare, incomingExamId: $incomingExamId)
                        .environmentObject(authManager)
                        .environmentObject(offlineManager)
                        .environmentObject(biometricManager)
                    }
                } else {
                    NavigationStack {
                        AuthView(authManager: authManager)
                            .navigationBarHidden(true)
                    }
                    .environmentObject(biometricManager)
                }
            }
        }
        .onAppear {
            offlineManager.startMonitoring()
            authManager.startListeningAuthState()
            refreshBiometricState(triggerUnlock: true)
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                evaluateOfflineOffer()
            }
        }
        .onChange(of: offlineManager.isOnline) { _, online in
            if !online {
                evaluateOfflineOffer()
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuth in
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
                let snapshot = offlineManager.cachedSnapshot ?? offlineManager.availableSnapshot()
                let exams = snapshot.map { $0.exams + $0.sharedExams }
                BackgroundRefreshManager.schedule(for: exams)
            } else if phase == .active {
                Task { await attemptBiometricUnlockIfNeeded(force: false) }
                Task { await BackgroundRefreshManager.refreshLiveActivitiesFromSnapshot() }
            }
        }
        .onChange(of: biometricManager.isEnabledForActiveUser) { _, _ in
            refreshBiometricState(triggerUnlock: false)
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
            return
        }
        if !triggerUnlock && biometricUnlocked {
            biometricMessage = biometricManager.biometricsAvailable ? nil : "\(biometricManager.biometryName()) ist aktuell nicht verfügbar."
            return
        }
        biometricUnlocked = false
        biometricMessage = biometricManager.biometricsAvailable ? nil : "\(biometricManager.biometryName()) ist aktuell nicht verfügbar."
        if triggerUnlock {
            Task { await attemptBiometricUnlockIfNeeded(force: true) }
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
           url.host?.lowercased() == "exam" {
            let components = url.pathComponents.filter { $0 != "/" }
            if let id = components.first {
                incomingExamId = id
                NotificationCenter.default.post(name: .openExamDetail, object: id)
            }
        }
    }
}

extension Notification.Name {
    static let openExamDetail = Notification.Name("openExamDetail")
}

#Preview {
    ContentView()
        .environmentObject(OfflineModeManager.shared)
        .environmentObject(BiometricAuthManager.shared)
}
