// MainView.swift
import SwiftUI

struct MainView: View {
    let onLogout: () -> Void
    @StateObject private var gradesStore = GradesStore()
    @State private var currentTab: BottomNavView.Tab = .home

    var body: some View {
        ZStack {
            themedBackground

            NavigationStack {
                Group {
                    switch currentTab {
                    case .home:
                        HomeView()
                            .environmentObject(gradesStore)
                    case .subjects:
                        SubjectsManageView()
                            .environmentObject(gradesStore)
                    case .final:
                        FinalGradeView()
                            .environmentObject(gradesStore)
                    case .settings:
                        AppSettingsView()
                            .environmentObject(gradesStore)
                    }
                }
            }
            // Platz für die BottomNav im Safe-Area-Bereich reservieren
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 100)
            }
            // Statische BottomNav als Overlay über allen Seiten
            .overlay(alignment: .bottom) {
                BottomNavView(
                    currentTab: currentTab,
                    onOpenHome: { currentTab = .home },
                    onOpenFinalGrade: { currentTab = .final },
                    onOpenSettings: { currentTab = .settings },
                    onOpenSubjects: { currentTab = .subjects }
                )
                .environmentObject(gradesStore)
            }
        }
        // Dark-Mode-Verhalten wie im React-Client:
        // nutze die gespeicherte darkMode-Präferenz des Nutzers
        .preferredColorScheme(gradesStore.darkMode ? .dark : .light)
        .task {
            // Live-Updates starten
            await gradesStore.startListening()
        }
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
