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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundGradient

            Group {
                if authManager.isAuthenticated {
                    MainView(onLogout: {
                        authManager.signOut()
                    })
                } else {
                    AuthView(authManager: authManager)
                }
            }
        }
        .onAppear {
            authManager.startListeningAuthState()
        }
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
}

#Preview {
    ContentView()
}
