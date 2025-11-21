import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct BurgerMenuView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    // Props analog React
    var isSmall: Bool = false
    var title: String? = nil
    var subjectType: Int? = nil
    var subtitle: String? = nil

    // State
    @State private var greeting: String = ""
    @State private var displayName: String = ""
    @State private var isHome: Bool = false

    var body: some View {
        HStack(alignment: .center) {
            // Links: Greeting oder Back
            if isHome {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting)
                        .font(isSmall ? .subheadline : .headline)
                        .foregroundStyle(.secondary)
                    Text(displayName.isEmpty ? "" : "\(displayName)!")
                        .font(isSmall ? .title3.bold() : .title.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                BackToHomeView()
            }

            Spacer()

            // Mitte: Titel + Fach-Typ oder Untertitel
            if !isHome, let title {
                VStack(alignment: .center, spacing: 6) {
                    Text(title)
                        .font(isSmall ? .headline : .title3.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subjectType {
                        Tag(
                            text: subjectType == 1 ? "Hauptfach" : "Nebenfach",
                            style: subjectType == 1 ? .main : .minor
                        )
                    } else if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()

            // Rechts: Logout
            LogoutButtonView()
        }
        .padding(.horizontal)
        .padding(.vertical, isSmall ? 8 : 12)
        .background(.clear)
        .onAppear {
            computeGreeting()
            Task { await loadUserDisplayName() }
            // Heuristik: wenn kein Titel übergeben -> Home
            isHome = (title == nil)
        }
    }

    private func computeGreeting() {
        let hours = Calendar.current.component(.hour, from: Date())
        if hours >= 6 && hours < 11 {
            greeting = "Guten Morgen"
        } else if hours >= 11 && hours < 17 {
            greeting = "Hallo"
        } else if hours >= 17 && hours < 22 {
            greeting = "Guten Abend"
        } else {
            greeting = "Gute Nacht"
        }
    }

    private func loadUserDisplayName() async {
        // Versuche zuerst FirebaseAuth.displayName
        if let dn = Auth.auth().currentUser?.displayName, !dn.isEmpty {
            displayName = dn
            return
        }
        // Optional: aus Firestore "users/{uid}" -> displayName oder name
        guard let uid = Auth.auth().currentUser?.uid else {
            displayName = ""
            return
        }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            if let data = snap.data() {
                if let dn = data["displayName"] as? String, !dn.isEmpty {
                    displayName = dn
                } else if let n = data["name"] as? String, !n.isEmpty {
                    displayName = n
                } else {
                    displayName = ""
                }
            }
        } catch {
            displayName = ""
        }
    }
}

struct LogoutButtonView: View {
    @EnvironmentObject var store: GradesStore
    @State private var isSigningOut: Bool = false
    var body: some View {
        Button {
            Task { await signOut() }
        } label: {
            if isSigningOut {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abmelden")
        .disabled(isSigningOut)
    }

    private func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            // Listener stoppen, dann abmelden
            store.stopListening()
            try Auth.auth().signOut()
        } catch {
            // Optional: Fehler anzeigen
        }
    }
}
