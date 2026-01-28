import SwiftUI

struct SocialGroupDetailView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let groupId: String
    
    @State private var showShareSheet: Bool = false
    @State private var showLeaveAlert: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var isOwner: Bool = false
    
    private var groupName: String {
        store.groupNames[groupId] ?? "Gruppe"
    }
    
    private var memberCount: Int {
        store.groupMemberIds[groupId]?.count ?? 0
    }
    
    private var animationsOn: Bool { store.animationsEnabled }
    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header section
                headerSection
                    .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 12)
                
                // Info Card
                infoSection
                    .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                
                // Actions
                actionsSection
                    .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                
                // Danger Zone
                dangerSection
                    .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 12)
            }
            .padding(20)
        }
        .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
        .navigationTitle("Gruppen-Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showShareSheet = true
                } label: {
                    ToolbarIcon(symbol: "square.and.arrow.up", showDot: false)
                }
                .accessibilityLabel("Teilen")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareCodeSheet(code: groupId, name: groupName, type: .socialGroup)
                .environmentObject(store)
        }
        .onAppear {
            Task {
                isOwner = await store.isCurrentUserOwner(of: groupId)
            }
        }
        .alert("Gruppe verlassen?", isPresented: $showLeaveAlert) {
            Button("Abbrechen", role: .cancel) { }
            Button("Verlassen", role: .destructive) {
                Task {
                    await store.leaveSharedGroup(code: groupId)
                    dismiss()
                }
            }
        } message: {
            Text("Bist du sicher, dass du diese Gruppe verlassen möchtest? Du verlierst Zugriff auf alle geteilten Inhalte.")
        }
        .alert("Gruppe löschen?", isPresented: $showDeleteAlert) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                Task {
                    try? await store.deleteSharedGroup(code: groupId)
                    dismiss()
                }
            }
        } message: {
            Text("Diese Aktion kann nicht rückgängig gemacht werden. Die Gruppe wird für alle Mitglieder gelöscht.")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.indigo)
            }
            
            VStack(spacing: 4) {
                Text(groupName)
                    .font(.title2.weight(.bold))
                
                HStack(spacing: 6) {
                    Image(systemName: "person.2.crop.square.stack")
                        .font(.caption)
                    Text("Soziale Gruppe")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var infoSection: some View {
        SettingsCard(
            title: "Informationen",
            subtitle: "Details zur Gruppe",
            systemImage: "info.circle.fill",
            accent: .indigo
        ) {
            VStack(spacing: 16) {
                HStack {
                    Label("Mitglieder", systemImage: "person.3.fill")
                        .font(.body)
                    Spacer()
                    Text("\(memberCount)")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.indigo)
                }
                
                Divider()
                
                HStack {
                    Label("Gruppencode", systemImage: "number")
                        .font(.body)
                    Spacer()
                    Text(groupId)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
    
    private var actionsSection: some View {
        SettingsCard(
            title: "Aktionen",
            subtitle: "Gruppe verwalten",
            systemImage: "hand.tap.fill",
            accent: .blue
        ) {
            VStack(spacing: 12) {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Gruppe teilen", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                    Text("In einer sozialen Gruppe kannst du Hausaufgaben und Termine teilen, ohne dass die Gruppe feste Fächer vorgibt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.orange.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var dangerSection: some View {
        SettingsCard(
            title: "Gefahrenzone",
            subtitle: "Kritische Aktionen",
            systemImage: "exclamationmark.triangle.fill",
            accent: .red
        ) {
            VStack(spacing: 12) {
                Button(role: .destructive) {
                    showLeaveAlert = true
                } label: {
                    Label("Gruppe verlassen", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: .red))
                
                if isOwner {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Gruppe löschen", systemImage: "trash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .red))
                    
                    Text("Als Ersteller löscht du die Gruppe für alle Mitglieder.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}
