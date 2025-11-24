// MainView.swift
import SwiftUI

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
    @Environment(\.colorScheme) private var colorScheme
    @State private var navPath = NavigationPath()
    @State private var showOnboardingFunnel: Bool = false

    // Von SubjectDetail per Preference gemeldetes Fach für „Note hinzufügen“
    @State private var quickAddSubjectName: String? = nil
    @State private var navigateToAbiturExam: Bool = false

    var body: some View {
        ZStack {
            themedBackground

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
                        AppSettingsView()
                            .environmentObject(gradesStore)
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
                SubjectDetailView(subject: subject)
                    .environmentObject(gradesStore)
            }
            // Platz für die BottomNav im Safe-Area-Bereich reservieren
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 100)
            }
            // BottomNav soll bei geöffneter Tastatur unten bleiben
            .ignoresSafeArea(.keyboard, edges: .bottom)
            // Statische BottomNav als Overlay über allen Seiten
            .overlay(alignment: .bottom) {
                BottomNavView(
                    currentTab: currentTab,
                    onOpenHome: { currentTab = .home },
                    onOpenFinalGrade: { currentTab = .final },
                    onOpenSettings: { currentTab = .settings },
                    onOpenInsights: { currentTab = .insights },
                    onOpenAbitur: { navigateToAbiturExam = true },
                    // Vorauswahl für „Note hinzufügen“ (kommt von SubjectDetail)
                    quickAddPreselectedSubjectName: quickAddSubjectName
                )
                .environmentObject(gradesStore)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
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
        .fullScreenCover(isPresented: $showOnboardingFunnel) {
            OnboardingFunnelView {
                showOnboardingFunnel = false
            }
            .environmentObject(gradesStore)
        }
        .task {
            // Live-Updates starten
            await gradesStore.startListening()
        }
        .overlay(alignment: .center) {
            if gradesStore.isLoading {
                loadingOverlay
            }
        }
    }

    private var loadingOverlayLabel: String {
        if gradesStore.loadingLabel.isEmpty {
            return "Noten werden synchronisiert …"
        }
        return gradesStore.loadingLabel
    }

    private var loadingOverlay: some View {
        ZStack {
            // Verschwommener Hintergrund über der aktuellen View-Hierarchie
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Noten werden synchronisiert")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(loadingOverlayLabel)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
                .multilineTextAlignment(.center)

                if gradesStore.progress > 0 {
                    VStack(spacing: 8) {
                        ProgressView(value: gradesStore.progress, total: 100)
                            .tint(.white)
                        Text("\(Int(gradesStore.progress.rounded()))%")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .frame(maxWidth: 220)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.55))
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: Color.black.opacity(0.45), radius: 30, x: 0, y: 18)
            )
        }
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
