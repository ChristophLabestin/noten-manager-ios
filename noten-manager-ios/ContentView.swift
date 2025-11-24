//
//  ContentView.swift
//  noten-manager-ios
//
//  Created by Christoph Labestin on 18.11.25.
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @StateObject private var authManager = AuthManager()
    @EnvironmentObject private var offlineManager: OfflineModeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showOfflinePrompt: Bool = false
    @State private var offlineSnapshotForPrompt: OfflineSnapshot?

    var body: some View {
        ZStack {
            backgroundGradient

            Group {
                if authManager.isAuthenticated || offlineManager.isOfflineModeActive {
                    MainView(onLogout: {
                        authManager.signOut()
                    })
                    .environmentObject(offlineManager)
                } else {
                    AuthView(authManager: authManager)
                }
            }
        }
        .onAppear {
            offlineManager.startMonitoring()
            authManager.startListeningAuthState()
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                evaluateOfflineOffer()
            }
        }
        .onChange(of: offlineManager.isOnline) { online in
            if !online {
                evaluateOfflineOffer()
            }
        }
        .onChange(of: authManager.isAuthenticated) { isAuth in
            if isAuth && offlineManager.isOfflineModeActive {
                offlineManager.deactivateOfflineMode()
            }
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
        offlineManager.activateOfflineMode()
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
}

#Preview {
    ContentView()
        .environmentObject(OfflineModeManager.shared)
}
