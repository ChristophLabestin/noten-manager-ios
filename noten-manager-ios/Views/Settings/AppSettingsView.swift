import SwiftUI
import StoreKit
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct AppSettingsView: View {
    let scrollToAccount: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    @EnvironmentObject var offlineManager: OfflineModeManager
    @EnvironmentObject var biometricManager: BiometricAuthManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var storeKit: StoreKitManager
    @AppStorage("launchOfferPurchased") private var launchOfferPurchased = false
    @AppStorage("showSpeedometerOnLaunch") private var showSpeedometerOnLaunch: Bool = false

    @State private var newName: String = ""
    @State private var isSavingName: Bool = false
    @State private var nameSavedSuccess: Bool = false

    @State private var navigateToFinal: Bool = false
    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false
    @State private var purchaseStatusMessage: String?
    @State private var purchaseStatusIsError: Bool = false
    @State private var showNotifications: Bool = false
    @ObservedObject private var notificationInbox = NotificationInboxStore.shared
    private let onOpenCreationMenu: () -> Void

    // Gruppen
    @State private var groupJoinCode: String = ""
    @State private var groupNameInput: String = ""
    @State private var isCreatingGroup: Bool = false
    @State private var isJoiningGroup: Bool = false
    @State private var groupInfoMessage: String?
    @State private var groupErrorMessage: String?
    @State private var showMappingGroupId: String? = nil
    @State private var manageGroupId: String? = nil
    @State private var selectedSubjectsForNewGroup: Set<String> = []
    @State private var groupPendingLeave: String? = nil
    @State private var copiedGroupId: String? = nil

    // Schuljahr
    @State private var newSchoolYearName: String = ""
    @State private var isCreatingSchoolYearLocal: Bool = false
    @State private var schoolYearMessage: String?
    @State private var schoolYearError: String?
    @State private var schoolYearInputIsValid: Bool = false
    @State private var showSchoolYearWizard: Bool = false
    @State private var showSchoolYearEditor: Bool = false

    // Reset
    @State private var showResetAccountSheet: Bool = false
    @State private var showSubscriptionOffer: Bool = false
    @State private var showOfferCodeSheet: Bool = false
    @State private var resetAccountPassword: String = ""
    @State private var resetAccountSlideDone: Bool = false
    @State private var showDeleteAccountSheet: Bool = false
    @State private var deleteAccountPassword: String = ""
    @State private var deleteAccountSlideDone: Bool = false
    @State private var isResettingAccount: Bool = false
    @State private var isDeletingAccount: Bool = false
    @State private var resetAccountError: String?
    @State private var deleteError: String?
    @State private var offlineStatusMessage: String?
    @State private var biometricToggleState: Bool = false
    @State private var biometricStatusMessage: String?
    @State private var isUpdatingBiometric: Bool = false
    @State private var isEmailVerified: Bool? = nil
    @State private var isSendingVerification: Bool = false
    @State private var verificationMessage: String?
    @State private var hasScrolledToAccount: Bool = false

    @State private var showChangeEmailSheet: Bool = false
    @State private var showChangePasswordSheet: Bool = false
    @State private var showSupportAccessSheet: Bool = false
    @State private var changeEmailCurrentPassword: String = ""
    @State private var changeEmailNewEmail: String = ""
    @State private var changeEmailConfirmEmail: String = ""
    @State private var changeEmailMessage: String?
    @State private var changeEmailError: String?
    @State private var isUpdatingEmail: Bool = false

    @State private var currentDisplayName: String = ""

    @State private var changePasswordCurrent: String = ""
    @State private var changePasswordNew: String = ""
    @State private var changePasswordConfirm: String = ""
    @State private var changePasswordMessage: String?
    @State private var changePasswordError: String?
    @State private var isUpdatingPassword: Bool = false

    init(scrollToAccount: Bool = false, onOpenCreationMenu: @escaping () -> Void = {}) {
        self.scrollToAccount = scrollToAccount
        self.onOpenCreationMenu = onOpenCreationMenu
    }

    // Typografie-Hierarchie
    private let sectionHeaderFont: Font = .headline.weight(.semibold)
    private let helperFont: Font = .footnote
    private let appIconOptions: [(id: String, title: String, imageName: String)] = [
        ("default", "Standard", "AppIconPreviewDefault"),
        ("pink", "Pink", "AppIconPreviewPink")
    ]

    private var maxExamSubjects: Int { 4 }

    private var offerDisplayPrice: String {
        let price = storeKit.product?.displayPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        if let price, !price.isEmpty {
            return price
        }
        return "3,99€"
    }

    private var examEligibleSubjects: [Subject] {
        store
            .sortedSubjectsForDisplay()
            .filter { $0.type == 1 && !$0.isElective }
    }

    private var currentExamSubjectsCount: Int {
        examEligibleSubjects.filter { ($0.examSubject ?? false) }.count
    }

    private var hasOverdueHomeworks: Bool {
        let now = Date()
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate { return due < now }
            if let reminder = hw.reminderAt { return reminder < now }
            return false
        }
    }

    private var hasHomeworkDueTomorrow: Bool {
        let cal = Calendar.current
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted, let due = hw.dueDate else { return false }
            return cal.isDateInTomorrow(due)
        }
    }

    private var hasOverdueExams: Bool {
        let now = Date()
        return store.allExams.contains { exam in
            !exam.isCompleted && exam.date < now
        }
    }

    private var homeworkReminderDate: Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = store.homeworkReminderHour
        comps.minute = store.homeworkReminderMinute
        return Calendar.current.date(from: comps) ?? Date()
    }

    private var reminderTimeText: String {
        String(format: "%02d:%02d", store.homeworkReminderHour, store.homeworkReminderMinute)
    }

    private var overdueHomeworksCount: Int {
        let now = Date()
        return store.allHomeworks.filter { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate { return due < now }
            if let reminder = hw.reminderAt { return reminder < now }
            return false
        }.count
    }

    private var homeworkDueTomorrowCount: Int {
        let cal = Calendar.current
        return store.allHomeworks.filter { hw in
            guard !hw.isCompleted, let due = hw.dueDate else { return false }
            return cal.isDateInTomorrow(due)
        }.count
    }

    private var overdueExamsCount: Int {
        let now = Date()
        return store.allExams.filter { exam in
            !exam.isCompleted && exam.date < now
        }.count
    }

    private var activeSchoolYearLabel: String {
        guard let id = store.activeSchoolYearId else { return "—" }
        let name = store.schoolYearNames[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return id
    }

    private var animationsOn: Bool { store.animationsEnabled }

    private func isValidSchoolYear(_ value: String) -> Bool {
        let pattern = "^(\\d{4})-(\\d{2})$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = value as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: value, options: [], range: range), match.numberOfRanges == 3 else {
            return false
        }
        guard
            let startRange = Range(match.range(at: 1), in: value),
            let endRange = Range(match.range(at: 2), in: value)
        else { return false }
        guard let start = Int(value[startRange]), let suffix = Int(value[endRange]) else { return false }
        return ((start + 1) % 100) == suffix
    }

    private func isValidEmail(_ value: String) -> Bool {
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private var externalAuthProvider: String? {
        guard let user = Auth.auth().currentUser else { return nil }
        if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
            return "Apple"
        }
        if user.providerData.contains(where: { $0.providerID == "google.com" }) {
            return "Google"
        }
        return nil
    }

    private var isExternalAuthAccount: Bool { externalAuthProvider != nil }

    @ViewBuilder
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Einstellungen")
                .font(.title2.weight(.bold))
            Text("Profil, Design & Benachrichtigungen")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var heroChips: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatChip(
                title: "Schuljahr",
                value: activeSchoolYearLabel,
                accent: .cyan
            )
            
            StatChip(
                title: "Profil",
                value: "\(store.gradeYear.map { "\($0)." } ?? "")\(store.schoolType == .fos ? "FOS" : "BOS")",
                accent: .indigo
            )
            
            StatChip(
                title: "Abitur",
                value: "\(currentExamSubjectsCount)/\(maxExamSubjects)",
                accent: .orange
            )
            
            StatChip(
                title: "Erinnerung",
                value: reminderTimeText,
                accent: .mint
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        heroHeader
                            .softFadeIn(enabled: animationsOn, delay: 0.03, offset: 10)
                        heroChips
                            .softFadeIn(enabled: animationsOn, delay: 0.08, offset: 12)
                        generalCard
                            .softFadeIn(enabled: animationsOn, delay: 0.08, offset: 12)
                        schoolYearCard
                            .softFadeIn(enabled: animationsOn, delay: 0.12, offset: 12)

                        onboardingCard
                            .softFadeIn(enabled: animationsOn, delay: 0.20, offset: 12)
                        helpCard
                            .softFadeIn(enabled: animationsOn, delay: 0.24, offset: 12)
                        purchaseCard
                            .softFadeIn(enabled: animationsOn, delay: 0.26, offset: 12)
                        offlineCard
                            .softFadeIn(enabled: animationsOn, delay: 0.28, offset: 12)
                        resetCard
                            .softFadeIn(enabled: animationsOn, delay: 0.32, offset: 12)
                        accountCard
                            .softFadeIn(enabled: animationsOn, delay: 0.36, offset: 12)
                            .id("accountCard")
                        infoCard
                            .softFadeIn(enabled: animationsOn, delay: 0.40, offset: 12)

                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .clipped()
                }
                .onAppear {
                    maybeScrollToAccount(proxy: proxy)
                }
                .onChange(of: scrollToAccount) { _, _ in
                    maybeScrollToAccount(proxy: proxy)
                }
                .contentMargins(.horizontal, 0, for: .scrollContent)
            }
            .background(
                ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity).onTapGesture { hideKeyboard() }
            )
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(isPresented: $navigateToFinal) {
                AbiturExamView().environmentObject(store)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showNotifications = true
                    } label: {
                        ToolbarIcon(
                            symbol: "bell",
                            showDot: notificationInbox.hasUnread || (LaunchOfferNotificationManager.isOfferActive() && !launchOfferPurchased)
                        )
                    }
                    .accessibilityLabel("Benachrichtigungen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        NavigationLink(destination: CalendarPageView().environmentObject(store)) {
                            ToolbarIcon(symbol: "calendar", showDot: false)
                        }
                        .accessibilityLabel("Kalender öffnen")

                        Button {
                            onOpenCreationMenu()
                        } label: {
                            ToolbarIcon(symbol: "plus", showDot: false)
                        }
                        .accessibilityLabel("Neu hinzufügen")
                    }
                }
            }
            .onAppear {
                newName = ""
                nameSavedSuccess = false
                selectedSubjectsForNewGroup = []
                syncBiometricToggle()
                Task { await refreshEmailVerification() }
                loadCurrentDisplayName()
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsInboxView(
                    inbox: notificationInbox,
                    onSelectNotification: { item in
                        handleNotificationSelection(item)
                    },
                    onOpenImportant: {
                        NotificationCenter.default.post(name: .openLaunchOffer, object: nil)
                    }
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showSchoolYearWizard) {
                OnboardingFunnelView(
                    isSchoolYearChange: true,
                    previousSchoolYearId: store.activeSchoolYearId
                ) {
                    showSchoolYearWizard = false
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showSchoolYearEditor) {
                SchoolYearEditView()
                    .environmentObject(store)
            }

            .sheet(
                isPresented: Binding(
                    get: { manageGroupId != nil },
                    set: { if !$0 { manageGroupId = nil } }
                )
            ) {
                if let gid = manageGroupId {
                    GroupSubjectManagementView(groupId: gid)
                        .environmentObject(store)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { showMappingGroupId != nil },
                    set: { if !$0 { showMappingGroupId = nil } }
                )
            ) {
                if let gid = showMappingGroupId {
                    UnifiedMappingView(groupId: gid)
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $showResetAccountSheet) {
                ResetConfirmSheet(
                    title: "Account zurücksetzen",
                    message: "Wirklich alle Daten löschen? Dies kann nicht rückgängig gemacht werden.",
                    password: $resetAccountPassword,
                    isPresented: $showResetAccountSheet,
                    slideDone: $resetAccountSlideDone,
                    isProcessing: isResettingAccount,
                    errorMessage: resetAccountError,
                    confirmAction: confirmResetAccount
                )
            }
            .sheet(isPresented: $showDeleteAccountSheet) {
                ResetConfirmSheet(
                    title: "Account löschen",
                    message: "Konto und alle Daten dauerhaft entfernen. Dieser Schritt kann nicht rückgängig gemacht werden.",
                    password: $deleteAccountPassword,
                    isPresented: $showDeleteAccountSheet,
                    slideDone: $deleteAccountSlideDone,
                    isProcessing: isDeletingAccount,
                    errorMessage: deleteError,
                    confirmAction: confirmDeleteAccount
                )
            }
            .sheet(isPresented: $showChangeEmailSheet) {
                ChangeEmailSheet(
                    currentEmail: Auth.auth().currentUser?.email ?? "Unbekannt",
                    currentPassword: $changeEmailCurrentPassword,
                    newEmail: $changeEmailNewEmail,
                    confirmEmail: $changeEmailConfirmEmail,
                    message: $changeEmailMessage,
                    errorMessage: $changeEmailError,
                    isProcessing: isUpdatingEmail,
                    submit: { Task { await updateEmail() } },
                    cancel: { showChangeEmailSheet = false }
                )
            }
            .sheet(isPresented: $showChangePasswordSheet) {
                ChangePasswordSheet(
                    currentPassword: $changePasswordCurrent,
                    newPassword: $changePasswordNew,
                    confirmPassword: $changePasswordConfirm,
                    message: $changePasswordMessage,
                    errorMessage: $changePasswordError,
                    isProcessing: isUpdatingPassword,
                    submit: { Task { await updatePassword() } },
                    cancel: { showChangePasswordSheet = false }
                )
            }
            .alert("Gruppe verlassen?", isPresented: Binding(
                get: { groupPendingLeave != nil },
                set: { if !$0 { groupPendingLeave = nil } }
            )) {
                Button("Abbrechen", role: .cancel) { groupPendingLeave = nil }
                Button("Verlassen", role: .destructive) {
                    if let gid = groupPendingLeave {
                        Task { await store.leaveSharedGroup(code: gid) }
                    }
                    groupPendingLeave = nil
                }
            } message: {
                Text("Möchtest du diese Gruppe wirklich verlassen?")
            }
        }
    }

    private var generalCard: some View {
        SettingsCard(
            title: "Profil & Oberfläche",
            subtitle: "Name, Farben und Interaktionen",
            systemImage: "slider.horizontal.3",
            accent: .cyan
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionBox {
                    HStack(spacing: 16) {
                        // Avatar Placeholder
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: store.theme == "feminine" ? [.pink, .purple] : [.blue, .indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 64, height: 64)
                                .shadow(color: (store.theme == "feminine" ? Color.pink : Color.indigo).opacity(0.3), radius: 8, x: 0, y: 4)
                            
                            Text(currentDisplayName.prefix(1).uppercased())
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        
                        // Inputs
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Anzeigename")
                                .font(sectionHeaderFont)
                            
                            HStack {
                                TextField(
                                    "Dein Name",
                                    text: $newName,
                                    prompt: Text(currentDisplayName.isEmpty ? "Dein Name" : currentDisplayName)
                                )
                                .textContentType(.name)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                
                                if !newName.isEmpty && newName != currentDisplayName {
                                    Button {
                                        Task { await saveName() }
                                    } label: {
                                        if isSavingName {
                                            ProgressView().scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.title3)
                                        }
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(10)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    
                    if nameSavedSuccess {
                        Text("✅ Name gespeichert!")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Erscheinungsbild")
                            .font(sectionHeaderFont)
                        
                        // Theme Selector Cards
                        HStack(spacing: 12) {
                            // Card 1: Klassisch
                            Button {
                                Task { await store.updatePreferences(theme: "default") }
                            } label: {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                        .frame(height: 60)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.accentColor, lineWidth: store.theme == "default" ? 3 : 0)
                                        )
                                        .shadow(color: .indigo.opacity(0.2), radius: 4, y: 2)
                                    
                                    HStack {
                                        Text("Klassisch")
                                            .font(.subheadline.weight(.medium))
                                        if store.theme == "default" {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            // Card 2: Soft / Pink
                            Button {
                                Task { await store.updatePreferences(theme: "feminine") }
                            } label: {
                                VStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                        .frame(height: 60)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.pink, lineWidth: store.theme == "feminine" ? 3 : 0)
                                        )
                                        .shadow(color: .pink.opacity(0.2), radius: 4, y: 2)
                                    
                                    HStack {
                                        Text("Soft")
                                            .font(.subheadline.weight(.medium))
                                        if store.theme == "feminine" {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.pink)
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Divider()
                        
                        // Intensity Slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Farbintensität")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int((store.themeBackgroundIntensity * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
                            }
                            
                            Slider(
                                value: Binding(
                                    get: { store.themeBackgroundIntensity },
                                    set: { newVal in
                                        let snapped = (newVal * 100).rounded() / 100
                                        store.themeBackgroundIntensity = snapped
                                    }
                                ),
                                in: 0...1,
                                step: 0.05,
                                onEditingChanged: { editing in
                                    if !editing {
                                        Task { await store.updatePreferences(themeIntensity: store.themeBackgroundIntensity) }
                                    }
                                }
                            )
                            .tint(store.theme == "feminine" ? .pink : .blue)
                        }
                    }
                }

                SettingsSectionBox {
                    let canChangeIcon = UIApplication.shared.supportsAlternateIcons
                    VStack(alignment: .leading, spacing: 12) {
                        Text("App-Icon")
                            .font(sectionHeaderFont)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                            ForEach(appIconOptions, id: \.id) { option in
                                let isSelected = store.appIcon == option.id
                                Button {
                                    guard canChangeIcon else { return }
                                    Task { await store.updateAppIcon(to: option.id) }
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(option.imageName)
                                            .resizable()
                                            .scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                                            )
                                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                            .scaleEffect(isSelected ? 1.05 : 1.0)
                                            .animation(.spring(response: 0.3), value: isSelected)
                                        
                                        Text(option.title)
                                            .font(.caption.weight(isSelected ? .semibold : .regular))
                                            .foregroundStyle(isSelected ? .primary : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        if !canChangeIcon {
                            Text("Symbolwechsel wird auf diesem Gerät nicht unterstützt.")
                                .font(helperFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 20) {
                        // Dark Mode Selector
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Darstellung")
                                .font(sectionHeaderFont)
                            
                            HStack(spacing: 12) {
                                // Auto
                                Button {
                                    Task { await store.updatePreferences(darkModeMode: "system") }
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "iphone")
                                            .font(.title2)
                                        Text("Auto")
                                            .font(.caption.weight(.medium))
                                    }
                                    .foregroundStyle(store.darkModeMode == "system" ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 70)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(store.darkModeMode == "system" ? Color.accentColor : Color(.secondarySystemBackground))
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                // Light
                                Button {
                                    Task { await store.updatePreferences(darkModeMode: "light") }
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "sun.max.fill")
                                            .font(.title2)
                                        Text("Hell")
                                            .font(.caption.weight(.medium))
                                    }
                                    .foregroundStyle(store.darkModeMode == "light" ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 70)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(store.darkModeMode == "light" ? Color.orange : Color(.secondarySystemBackground))
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                // Dark
                                Button {
                                    Task { await store.updatePreferences(darkModeMode: "dark") }
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "moon.fill")
                                            .font(.title2)
                                    Text("Dunkel")
                                        .font(.caption.weight(.medium))
                                    }
                                    .foregroundStyle(store.darkModeMode == "dark" ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 70)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(store.darkModeMode == "dark" ? Color.indigo : Color(.secondarySystemBackground))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Divider()

                        // Feature Toggles with Icons
                        VStack(spacing: 16) {
                            // Speedometer
                            HStack(spacing: 16) {
                                Image(systemName: "speedometer")
                                    .font(.title2)
                                    .foregroundStyle(.cyan)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.cyan.opacity(0.15)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cover")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Startanimation beim Öffnen der App")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $showSpeedometerOnLaunch)
                                    .labelsHidden()
                            }
                            
                            // Animations
                            HStack(spacing: 16) {
                                Image(systemName: "sparkles")
                                    .font(.title2)
                                    .foregroundStyle(.purple)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.purple.opacity(0.15)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Animationen")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Bewegungseffekte und Übergänge")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { store.animationsEnabled },
                                        set: { val in Task { await store.updatePreferences(animationsEnabled: val) } }
                                    )
                                )
                                .labelsHidden()
                            }
                            
                            // Holiday Hints
                            HStack(spacing: 16) {
                                Image(systemName: "beach.umbrella")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.orange.opacity(0.15)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ferien-Countdown")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Hinweis auf kommende Ferien")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { store.showHolidayHints },
                                        set: { val in Task { await store.updatePreferences(holidayHintsEnabled: val) } }
                                    )
                                )
                                .labelsHidden()
                            }
                            
                            // Privacy Mode on Start
                            HStack(spacing: 16) {
                                Image(systemName: "eye.slash.fill")
                                    .font(.title2)
                                    .foregroundStyle(.indigo)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.indigo.opacity(0.15)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Privatsphäre")
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("Immer beim Start aktivieren")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                
                                Spacer()
                                
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { store.alwaysEnablePrivacyOnStart },
                                        set: { val in store.updateAlwaysEnablePrivacyOnStart(val) }
                                    )
                                )
                                .labelsHidden()
                            }
                        }
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Erinnerung")
                            .font(sectionHeaderFont)
                            
                        // Reminder Toggle Row
                        HStack(spacing: 16) {
                            Image(systemName: "bell.badge.fill")
                                .font(.title2)
                                .foregroundStyle(.indigo)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.indigo.opacity(0.15)))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Erinnerungen")
                                    .font(.subheadline.weight(.semibold))
                                    .minimumScaleFactor(0.9)
                                    .lineLimit(1)
                                Text("Für Prüfungen und Hausaufgaben")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { store.standardRemindersEnabled },
                                    set: { val in 
                                        Task { await store.updateStandardReminderEnabled(val) }
                                    }
                                )
                            )
                            .labelsHidden()
                        }
                        
                        // Time Picker (Conditional)
                        if store.standardRemindersEnabled {
                            HStack(spacing: 16) {
                                Image(systemName: "clock.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                                
                                Text("Uhrzeit")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { homeworkReminderDate },
                                        set: { newVal in
                                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newVal)
                                            let h = comps.hour ?? 19
                                            let m = comps.minute ?? 0
                                            Task { await store.updateHomeworkReminderTime(hour: h, minute: m) }
                                        }
                                    ),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .datePickerStyle(.compact)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        Divider()
                            
                        NavigationLink {
                            HelpCenterView(initialSection: .special)
                                .environmentObject(store)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                Text("Wie funktionieren Erinnerungen?")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .animation(.spring(), value: store.standardRemindersEnabled)
                }
            }
        }
    }

    private func handleNotificationSelection(_ item: NotificationInboxItem) {
        if let _ = item.homeworkId {
            showHomeworkSheet = true
        } else if let _ = item.examId {
            showExamSheet = true
        } else if item.kind == .daily {
            showHomeworkSheet = true
        }
    }


    // MARK: - Sections

    private var schoolYearCard: some View {
        SettingsCard(
            title: "Schuljahr",
            subtitle: "Aktives Schuljahr und Setup",
            systemImage: "graduationcap.fill",
            accent: .mint
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aktives Schuljahr")
                            .font(sectionHeaderFont)
                        if store.schoolYears.isEmpty {
                            Text("Noch keine Schuljahre gefunden. Lege eines an oder warte, bis es automatisch erstellt wird.")
                                .font(helperFont)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.schoolYears, id: \.self) { sy in
                                    let isActive = store.activeSchoolYearId == sy
                                    let name = (store.schoolYearNames[sy]?
                                        .trimmingCharacters(in: .whitespacesAndNewlines))
                                        .flatMap { $0.isEmpty ? nil : $0 } ?? sy
                                    Button {
                                        Task { await store.setActiveSchoolYear(id: sy) }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(name)
                                                    .font(.headline)
                                                if name != sy {
                                                    Text(sy)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                if isActive {
                                                    Text("Aktiv")
                                                        .font(helperFont)
                                                        .foregroundStyle(.green)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(isActive ? .green : .secondary)
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(isActive ? Color.green : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if store.activeSchoolYearId != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    showSchoolYearEditor = true
                                } label: {
                                    Label("Schuljahr bearbeiten", systemImage: "square.and.pencil")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .mint))

                                Text("Bezeichnung, Schulart, Jahrgangsstufe, Prüfungsfächer oder einen kompletten Reset verwalten.")
                                    .font(helperFont)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                        }
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Neues Schuljahr anlegen")
                            .font(sectionHeaderFont)
                        Text("Starte den Schuljahrs-Setup (wie im Onboarding), um Jahr, Schulart, Jahrgang und Gruppen festzulegen.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)

                        Button {
                            showSchoolYearWizard = true
                        } label: {
                            Text("Schuljahrs-Setup starten")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .mint))
                    }
                }
            }
        }
    }

    

    private var helpCard: some View {
        SettingsCard(
            title: "Hilfe & FAQ",
            subtitle: "Antworten & Berechnungen",
            systemImage: "cross.case.fill",
            accent: .teal
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Leitfäden zur App, Berechnungslogik und häufige Fragen.")
                        .font(helperFont)
                        .foregroundStyle(.secondary)

                    Text("Beinhaltet Tipps zu Workflows, Gewichtung in Dashboard/Insights und Abschlussnote sowie Gruppen-Sync.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        HelpCenterView()
                            .environmentObject(store)
                    } label: {
                        HStack(spacing: 10) {
                            Label("Help Center öffnen", systemImage: "arrow.right.circle.fill")
                                .font(.body.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Problem mit deinen Daten?")
                            .font(.subheadline.weight(.semibold))
                        Text("Erhalte Hilfe, indem du uns temporär Zugriff gewährst.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            showSupportAccessSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: store.adminAccessGranted ? "checkmark.shield.fill" : "person.badge.key.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(store.adminAccessGranted ? "Support-Zugriff aktiv" : "Support-Zugriff anfordern")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: store.adminAccessGranted ? .green : .indigo))
                    }
                }
            }
        }
        .sheet(isPresented: $showSupportAccessSheet) {
            SupportAccessRequestSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSubscriptionOffer) {
            SubscriptionOfferSheetView(
                onLater: {},
                onPurchaseSuccess: {
                    Task {
                        await storeKit.refreshSubscriptionStatus()
                        await MainActor.run {
                            showSubscriptionOffer = false
                        }
                    }
                }
            )
            .environmentObject(storeKit)
            .environmentObject(store)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .offerCodeRedemption(isPresented: $showOfferCodeSheet) { result in
            switch result {
            case .success:
                Task {
                    await storeKit.refreshSubscriptionStatus()
                    await MainActor.run {
                        showOfferCodeSheet = false
                    }
                }
            case .failure(let error):
                print("Offer code redemption failed: \(error)")
            }
        }
    }

    private var purchaseCard: some View {
        let offerActive = LaunchOfferNotificationManager.isOfferActive()
        let isSubscribed = storeKit.isSubscriptionActive
        let showsEarlyBirdOffer = !launchOfferPurchased && offerActive

        let statusTitle: String
        let statusAccent: Color
        let statusDetail: String
        let headline: String
        let subline: String
        let headerIcon: String
        let headerAccent: Color

        if launchOfferPurchased {
            statusTitle = "Status: Aktiv"
            statusAccent = .green
            statusDetail = "Kauf ist mit deiner Apple ID verknüpft und kann jederzeit wiederhergestellt werden."
            headline = "Lifetime freigeschaltet"
            subline = "Danke für deinen Kauf."
            headerIcon = "checkmark.seal.fill"
            headerAccent = .green
        } else if showsEarlyBirdOffer {
            statusTitle = "Status: Early-Bird verfügbar"
            statusAccent = .orange
            statusDetail = "Kein Kauf auf diesem Gerät aktiviert. Wenn du bereits gekauft hast, tippe auf Käufe wiederherstellen."
            headline = "Earlybird Lifetime"
            subline = "Einmalig \(offerDisplayPrice) bis 31.01.2026."
            headerIcon = "cart.badge.plus"
            headerAccent = .orange
        } else {
            statusTitle = isSubscribed ? "Status: Abo aktiv" : "Status: Kein Abo"
            statusAccent = isSubscribed ? .green : .secondary
            statusDetail = isSubscribed
                ? "Abo ist mit deiner Apple ID verknüpft und kann jederzeit wiederhergestellt werden."
                : "Early-Bird ist beendet. Pro gibt es jetzt im Abo."
            headline = "Noten Manager Pro Abo"
            subline = isSubscribed ? "Danke für dein Abo." : "Jetzt im Abo verfügbar."
            headerIcon = isSubscribed ? "checkmark.seal.fill" : "creditcard.fill"
            headerAccent = isSubscribed ? .green : .blue
        }

        return SettingsCard(
            title: "Noten Manager Pro",
            subtitle: "Kaufstatus und Wiederherstellung",
            systemImage: "cart.fill",
            accent: .green
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: headerIcon)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(headerAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(headline)
                                .font(sectionHeaderFont)
                            Text(statusTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(statusAccent)
                        }
                        Spacer()
                    }

                    Text(subline)
                        .font(helperFont)
                        .foregroundStyle(.secondary)

                    Text(statusDetail)
                        .font(helperFont)
                        .foregroundStyle(.secondary)

                    if showsEarlyBirdOffer {
                        Button {
                            Task { await purchaseLaunchOffer() }
                        } label: {
                            HStack(spacing: 10) {
                                if storeKit.isProcessingPurchase {
                                    ProgressView()
                                        .tint(.green)
                                } else {
                                    Image(systemName: "cart.fill")
                                        .font(.headline.weight(.semibold))
                                }
                                Text("Jetzt kaufen")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .green))
                        .disabled(storeKit.isProcessingPurchase)
                    } else if !isSubscribed && !launchOfferPurchased {
                         Button {
                             showSubscriptionOffer = true
                         } label: {
                             HStack(spacing: 10) {
                                 Image(systemName: "creditcard.fill")
                                     .font(.headline.weight(.semibold))
                                 Text("Jetzt abonnieren")
                             }
                             .frame(maxWidth: .infinity)
                         }
                         .buttonStyle(SoftTintButtonStyle(accent: .blue))
                    }

                    Button {
                        showOfferCodeSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "gift.fill")
                                .font(.headline.weight(.semibold))
                            Text("Code einlösen")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))

                    Button {
                        Task { await restorePurchases() }
                    } label: {
                        HStack(spacing: 10) {
                            if storeKit.isRestoring {
                                ProgressView()
                                    .tint(.green)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.headline.weight(.semibold))
                            }
                            Text("Käufe wiederherstellen")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .green))
                    .disabled(storeKit.isRestoring)


                    if let message = purchaseStatusMessage, !message.isEmpty {
                        Text(message)
                            .font(helperFont)
                            .foregroundStyle(purchaseStatusIsError ? .red : .secondary)
                    }
                }
            }
        }
    }

    @MainActor
    private func purchaseLaunchOffer() async {
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        let result = await storeKit.purchaseLaunchOffer()
        switch result {
        case .success:
            purchaseStatusMessage = "Kauf erfolgreich. Danke!"
            purchaseStatusIsError = false
        case .pending:
            purchaseStatusMessage = "Der Kauf wird noch geprüft. Wir schalten die Vollversion frei, sobald der Vorgang abgeschlossen ist."
            purchaseStatusIsError = false
        case .cancelled:
            purchaseStatusMessage = "Kauf abgebrochen."
            purchaseStatusIsError = false
        case .failed(let failure):
            purchaseStatusMessage = purchaseFailureMessage(failure)
            purchaseStatusIsError = true
        }
    }

    @MainActor
    private func restorePurchases() async {
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        let outcome = await storeKit.restorePurchases()
        switch outcome {
        case .success(let found):
            purchaseStatusMessage = found ? "Käufe wurden wiederhergestellt." : "Keine Käufe gefunden."
            purchaseStatusIsError = false
        case .failed(let failure):
            purchaseStatusMessage = restoreFailureMessage(failure)
            purchaseStatusIsError = true
        }
    }

    private func purchaseFailureMessage(_ failure: StoreKitManager.PurchaseFailure) -> String {
        switch failure {
        case .offerExpired:
            return "Das Angebot ist abgelaufen."
        case .productUnavailable:
            return "Das Produkt ist aktuell nicht verfügbar. Bitte später erneut versuchen."
        case .network:
            return "Keine Internetverbindung. Bitte später erneut versuchen."
        case .notAllowed:
            return "Käufe sind auf diesem Gerät nicht erlaubt."
        case .verificationFailed:
            return "Kauf konnte nicht bestätigt werden. Bitte später erneut versuchen."
        case .unknown:
            return "Kauf konnte nicht abgeschlossen werden. Bitte später erneut versuchen."
        }
    }

    private func restoreFailureMessage(_ failure: StoreKitManager.RestoreFailure) -> String {
        switch failure {
        case .network:
            return "Keine Internetverbindung. Bitte später erneut versuchen."
        case .notAllowed:
            return "Käufe sind auf diesem Gerät nicht erlaubt."
        case .unknown:
            return "Käufe konnten nicht wiederhergestellt werden. Bitte später erneut versuchen."
        }
    }

    private func activateOfflineManually() {
        guard let snapshot = offlineManager.cachedSnapshot ?? offlineManager.availableSnapshot() else {
            offlineStatusMessage = "Kein Offline-Cache gefunden. Bitte einmal online anmelden, damit ein Cache erstellt wird."
            return
        }
        guard offlineManager.isOfflineLoginAllowed(for: snapshot.userId) else {
            offlineStatusMessage = "Letzter Online-Login ist länger als 3 Tage her. Bitte online anmelden."
            return
        }
        offlineManager.activateOfflineMode(manual: true)
        offlineStatusMessage = "Offline-Modus aktiviert. Daten bleiben lokal verfügbar, bis du wieder online gehst."
    }

    private func deactivateOffline() {
        offlineManager.deactivateOfflineMode()
        offlineStatusMessage = "Offline-Modus beendet. Live-Synchronisation wird wiederhergestellt."
    }

    private var infoCard: some View {
        SettingsCard(
            title: "Info",
            subtitle: "Version & Hinweise",
            systemImage: "info.circle",
            accent: .gray
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("App Version 1.4")
                        .font(helperFont)
                        .foregroundStyle(.secondary)

                    Divider()

                    NavigationLink {
                        PrivacyPolicyView()
                            .environmentObject(store)
                    } label: {
                        HStack {
                            Label("Datenschutz", systemImage: "lock.shield")
                                .font(.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        TermsOfUseView()
                            .environmentObject(store)
                    } label: {
                        HStack {
                            Label("Nutzungsbedingungen", systemImage: "doc.plaintext")
                                .font(.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ImprintView()
                            .environmentObject(store)
                    } label: {
                        HStack {
                            Label("Impressum", systemImage: "doc.text")
                                .font(.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var offlineCard: some View {
        let snapshot = offlineManager.cachedSnapshot ?? offlineManager.availableSnapshot()
        let hasCache = snapshot != nil
        let lastLoginText: String = {
            if let last = offlineManager.lastLoginDate {
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                fmt.timeStyle = .short
                return fmt.string(from: last)
            }
            return "unbekannt"
        }()

        return SettingsCard(
            title: "Offline-Modus",
            subtitle: "Cache steuern & jetzt starten",
            systemImage: "wifi.slash",
            accent: .purple
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(offlineManager.isOfflineModeActive ? "Offline aktiv" : "Online & Sync", systemImage: offlineManager.isOfflineModeActive ? "bolt.slash.fill" : "bolt.horizontal.fill")
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Spacer()
                        Text(offlineManager.isOfflineModeActive ? "Offline" : "Online")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(offlineManager.isOfflineModeActive ? .orange : .green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(offlineManager.isOfflineModeActive ? Color.orange.opacity(0.18) : Color.green.opacity(0.18))
                            )
                            .fixedSize()
                    }

                    HStack {
                        Label("Letzter Login: \(lastLoginText)", systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Spacer()
                    }

                    HStack {
                        Label(hasCache ? "Offline-Daten verfügbar" : "Kein Offline-Cache", systemImage: hasCache ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(hasCache ? .green : .orange)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Spacer()
                    }

                    VStack(spacing: 10) {
                        Button {
                            activateOfflineManually()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "wifi.slash")
                                    .font(.headline.weight(.semibold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Offline aktivieren")
                                    Text("Letzten Cache nutzen")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .purple))
                        .disabled(!hasCache || offlineManager.isOfflineModeActive)

                        Button {
                            deactivateOffline()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.headline.weight(.semibold))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Offline verlassen")
                                    Text("Sync wiederherstellen")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .purple))
                        .disabled(!offlineManager.isOfflineModeActive)
                    }


                    if let message = offlineStatusMessage, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
                    HelpCenterLink(
                        title: "Hilfe zum Offline-Modus",
                        subtitle: "Cache, Grenzen & Sync-Verhalten im Help Center",
                        section: .special,
                        accent: .purple
                    )
        }
    }

    private var accountCard: some View {
        SettingsCard(
            title: "Account",
            subtitle: "Sitzung verwalten",
            systemImage: "person.crop.circle.badge.xmark",
            accent: .gray
        ) {
            if !isExternalAuthAccount, let verified = isEmailVerified, verified == false {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("E-Mail nicht bestätigt")
                            .font(sectionHeaderFont)
                        Text("Bitte bestätige deine E-Mail, um dein Konto zu sichern.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await resendVerificationEmail() }
                        } label: {
                            if isSendingVerification {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Bestätigungs-E-Mail erneut senden")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .orange))
                        .frame(maxWidth: .infinity)
                        .disabled(isSendingVerification)
                        if let info = verificationMessage {
                            Text(info)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Account-Daten")
                        .font(sectionHeaderFont)
                    if isExternalAuthAccount, let provider = externalAuthProvider {
                        Text("Dein Konto wird über \(provider) verwaltet. E-Mail und Passwort können hier nicht geändert werden.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Passe deine Anmeldedaten an. Zur Sicherheit wird dein aktuelles Passwort benötigt.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 8) {
                        Button {
                            resetChangeEmailForm()
                            showChangeEmailSheet = true
                        } label: {
                            Label("E-Mail ändern", systemImage: "envelope.badge")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .blue))
                        .disabled(isExternalAuthAccount)
                        .opacity(isExternalAuthAccount ? 0.5 : 1)

                        Button {
                            resetChangePasswordForm()
                            showChangePasswordSheet = true
                        } label: {
                            Label("Passwort ändern", systemImage: "key.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                        .disabled(isExternalAuthAccount)
                        .opacity(isExternalAuthAccount ? 0.5 : 1)
                    }
                }
            }

            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { biometricToggleState },
                        set: { handleBiometricToggle($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(biometricManager.biometryName()) zum Entsperren")
                                .font(sectionHeaderFont)
                            Text("Schütze die App mit \(biometricManager.biometryName()).")
                                .font(helperFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .disabled(isUpdatingBiometric || !biometricManager.biometricsAvailable)

                    if let status = biometricStatusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if !biometricManager.biometricsAvailable {
                        Text("\(biometricManager.biometryName()) wird auf diesem Gerät nicht unterstützt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { store.isPrivacyModeActive },
                        set: { _ in handleAppSettingsPrivacyToggle() }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Privatsphäre-Modus")
                                .font(sectionHeaderFont)
                            Text("Blende deine Noten aus. Benötigt \(biometricManager.biometryName()) zum Einblenden.")
                                .font(helperFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
            }

            SettingsSectionBox {
                Button(role: .destructive) {
                    Task {
                        store.stopListening()
                        try? Auth.auth().signOut()
                        OfflineModeManager.shared.clearOfflineData()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Abmelden")
                            .font(.body)
                        Spacer()
                    }
                }
                .buttonStyle(SoftTintButtonStyle(accent: .red))
            }
        }
    }

    private var resetCard: some View {
        SettingsCard(
            title: "Daten zurücksetzen",
            subtitle: "Account bereinigen oder löschen",
            systemImage: "exclamationmark.triangle.fill",
            accent: .red
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Account zurücksetzen")
                            .font(sectionHeaderFont)
                        Text("Löscht alle deine gespeicherten Daten und setzt dein Konto zurück. Dein Login bleibt bestehen.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            resetAccountPassword = ""
                            resetAccountSlideDone = false
                            resetAccountError = nil
                            showResetAccountSheet = true
                        } label: {
                            Text("Account zurücksetzen")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .red))
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Account löschen")
                            .font(sectionHeaderFont)
                        Text("Entfernt dein Konto und alle Daten dauerhaft. Nach der Löschung wirst du abgemeldet.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            deleteAccountPassword = ""
                            deleteAccountSlideDone = false
                            deleteError = nil
                            showDeleteAccountSheet = true
                        } label: {
                            Text("Account löschen")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .red))
                    }
                }
            }
        }
    }

    private var onboardingCard: some View {
        SettingsCard(
            title: "Onboarding",
            subtitle: "Setup-Assistent erneut durchlaufen",
            systemImage: "sparkles",
            accent: .teal
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Starte den Einrichtungs-Assistenten erneut, um Schuljahr, Gruppen und Fächer neu zu setzen. Bestehende Daten bleiben erhalten.")
                        .font(helperFont)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await store.restartOnboarding() }
                    } label: {
                        Text("Onboarding neu starten")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .teal))
                }
            }
        }
    }

    // MARK: - Actions

    private var biometricUserId: String? {
        Auth.auth().currentUser?.uid
        ?? offlineManager.cachedSnapshot?.userId
        ?? offlineManager.lastLoginUserId
    }

    private func syncBiometricToggle() {
        biometricManager.setActiveUser(id: biometricUserId)
        biometricToggleState = biometricManager.isEnabled(for: biometricUserId)
        biometricStatusMessage = nil
    }

    private func maybeScrollToAccount(proxy: ScrollViewProxy) {
        guard scrollToAccount, !hasScrolledToAccount else { return }
        hasScrolledToAccount = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                proxy.scrollTo("accountCard", anchor: .top)
            }
        }
    }

    private func resetChangeEmailForm() {
        changeEmailCurrentPassword = ""
        changeEmailNewEmail = ""
        changeEmailConfirmEmail = ""
        changeEmailMessage = nil
        changeEmailError = nil
    }

    private func resetChangePasswordForm() {
        changePasswordCurrent = ""
        changePasswordNew = ""
        changePasswordConfirm = ""
        changePasswordMessage = nil
        changePasswordError = nil
    }

    private func refreshEmailVerification() async {
        if isExternalAuthAccount {
            await MainActor.run {
                isEmailVerified = true
                verificationMessage = nil
            }
            return
        }
        guard let user = Auth.auth().currentUser else {
            await MainActor.run { isEmailVerified = nil }
            return
        }
        do {
            try await user.reload()
            await MainActor.run {
                isEmailVerified = user.isEmailVerified
                verificationMessage = nil
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            await MainActor.run {
                isEmailVerified = nil
                verificationMessage = "E-Mail-Status konnte nicht aktualisiert werden."
            }
        }
    }

    private func resendVerificationEmail() async {
        guard !isSendingVerification else { return }
        isSendingVerification = true
        verificationMessage = nil
        let message = await authManager.sendVerificationEmail()
        await MainActor.run {
            isSendingVerification = false
            verificationMessage = message ?? "Bestätigungs-E-Mail wurde gesendet."
        }
    }

    private func mapAuthErrorMessage(_ error: Error) -> String {
        guard let authError = AuthErrorCode(_bridgedNSError: error as NSError) else {
            return error.localizedDescription
        }
        switch authError.code {
        case .invalidEmail:
            return "Ungültige E-Mail-Adresse."
        case .emailAlreadyInUse:
            return "Diese E-Mail wird bereits verwendet."
        case .wrongPassword:
            return "Falsches aktuelles Passwort."
        case .requiresRecentLogin:
            return "Bitte melde dich neu an und versuche es erneut."
        case .weakPassword:
            return "Passwort ist zu schwach (mindestens 6 Zeichen)."
        default:
            return error.localizedDescription
        }
    }

    private func handleBiometricToggle(_ newValue: Bool) {
        guard let uid = biometricUserId else {
            biometricToggleState = false
            biometricStatusMessage = "Kein Nutzerkonto erkannt."
            return
        }
        biometricStatusMessage = nil
        if newValue {
            guard biometricManager.biometricsAvailable else {
                biometricToggleState = false
                biometricStatusMessage = "\(biometricManager.biometryName()) wird auf diesem Gerät nicht unterstützt."
                return
            }
            isUpdatingBiometric = true
            Task {
                let reason = "\(biometricManager.biometryName()) für den Schnellzugriff freigeben."
                let success = await biometricManager.authenticate(reason: reason)
                await MainActor.run {
                    if success {
                        biometricManager.setActiveUser(id: uid)
                        biometricManager.setEnabled(true, for: uid)
                        biometricToggleState = true
                    } else {
                        biometricToggleState = false
                        biometricStatusMessage = "\(biometricManager.biometryName()) abgebrochen oder fehlgeschlagen."
                    }
                    isUpdatingBiometric = false
                }
            }
        } else {
            biometricManager.setEnabled(false, for: uid)
            biometricToggleState = false
        }
    }


    private func saveName() async {
        guard !isSavingName else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingName = true
        await store.updateUserDisplayName(name: trimmed)
        isSavingName = false
        nameSavedSuccess = true
        currentDisplayName = trimmed
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            nameSavedSuccess = false
        }
        newName = ""
    }

    private func loadCurrentDisplayName() {
        if let local = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !local.isEmpty {
            currentDisplayName = local
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
                let data = snap.data() ?? [:]
                let name = (data["displayName"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (data["name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let name, !name.isEmpty {
                    await MainActor.run {
                        currentDisplayName = name
                    }
                }
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional: ignore fetch error
            }
        }
    }

    private func createSchoolYear() async {
        guard !isCreatingSchoolYearLocal else { return }
        isCreatingSchoolYearLocal = true
        defer { isCreatingSchoolYearLocal = false }
        let created = await store.createSchoolYear(name: newSchoolYearName)
        if let id = created {
            schoolYearMessage = "Neues Schuljahr \(id) aktiviert."
            schoolYearError = nil
            newSchoolYearName = ""
            schoolYearInputIsValid = false
        } else {
            schoolYearError = "Schuljahr konnte nicht angelegt werden."
            schoolYearMessage = nil
        }
    }

    private func confirmResetAccount() {
        Task {
            guard !isResettingAccount else { return }
            resetAccountError = nil
            isResettingAccount = true
            defer { isResettingAccount = false }
            do {
                try await store.resetEntireAccount(password: resetAccountPassword)
                showResetAccountSheet = false
                resetAccountPassword = ""
                resetAccountSlideDone = false
                resetAccountError = nil
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                resetAccountError = error.localizedDescription
            }
        }
    }

    private func confirmDeleteAccount() {
        Task {
            guard !isDeletingAccount else { return }
            deleteError = nil
            isDeletingAccount = true
            defer { isDeletingAccount = false }
            do {
                try await store.deleteAccountCompletely(password: deleteAccountPassword)
                showDeleteAccountSheet = false
                deleteAccountPassword = ""
                deleteAccountSlideDone = false
                deleteError = nil
                store.stopListening()
                authManager.signOut()
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                deleteError = error.localizedDescription
            }
        }
    }

    private func updateEmail() async {
        let trimmedEmail = changeEmailNewEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = changeEmailConfirmEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = changeEmailCurrentPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPassword.isEmpty else {
            changeEmailError = "Bitte aktuelles Passwort eingeben."
            changeEmailMessage = nil
            return
        }
        guard !trimmedEmail.isEmpty, !trimmedConfirm.isEmpty else {
            changeEmailError = "Bitte neue E-Mail eingeben."
            changeEmailMessage = nil
            return
        }
        guard trimmedEmail == trimmedConfirm else {
            changeEmailError = "E-Mail und Bestätigung stimmen nicht überein."
            changeEmailMessage = nil
            return
        }
        guard isValidEmail(trimmedEmail) else {
            changeEmailError = "Bitte eine gültige E-Mail-Adresse eingeben."
            changeEmailMessage = nil
            return
        }
        guard let user = Auth.auth().currentUser, let currentEmail = user.email else {
            changeEmailError = "Kein angemeldeter Nutzer gefunden."
            changeEmailMessage = nil
            return
        }

        await MainActor.run {
            isUpdatingEmail = true
            changeEmailError = nil
            changeEmailMessage = nil
        }

        do {
            let credential = EmailAuthProvider.credential(withEmail: currentEmail, password: trimmedPassword)
            try await user.reauthenticate(with: credential)
            try await user.sendEmailVerification(beforeUpdatingEmail: trimmedEmail)
            try await Firestore.firestore()
                .collection("users")
                .document(user.uid)
                .setData(["email": trimmedEmail], merge: true)
            await refreshEmailVerification()
            await MainActor.run {
                isUpdatingEmail = false
                changeEmailMessage = "Bestätigungslink gesendet. Bitte bestätige die neue E-Mail-Adresse."
                changeEmailCurrentPassword = ""
                changeEmailNewEmail = ""
                changeEmailConfirmEmail = ""
                changeEmailError = nil
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            await MainActor.run {
                isUpdatingEmail = false
                changeEmailError = mapAuthErrorMessage(error)
            }
        }
    }

    private func updatePassword() async {
        let current = changePasswordCurrent.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPass = changePasswordNew.trimmingCharacters(in: .whitespacesAndNewlines)
        let confirm = changePasswordConfirm.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !current.isEmpty else {
            changePasswordError = "Bitte aktuelles Passwort eingeben."
            changePasswordMessage = nil
            return
        }
        guard !newPass.isEmpty, !confirm.isEmpty else {
            changePasswordError = "Bitte neues Passwort eingeben."
            changePasswordMessage = nil
            return
        }
        guard newPass == confirm else {
            changePasswordError = "Neues Passwort und Bestätigung stimmen nicht überein."
            changePasswordMessage = nil
            return
        }
        guard newPass.count >= 6 else {
            changePasswordError = "Neues Passwort muss mindestens 6 Zeichen lang sein."
            changePasswordMessage = nil
            return
        }
        guard let user = Auth.auth().currentUser, let email = user.email else {
            changePasswordError = "Kein angemeldeter Nutzer gefunden."
            changePasswordMessage = nil
            return
        }

        await MainActor.run {
            isUpdatingPassword = true
            changePasswordError = nil
            changePasswordMessage = nil
        }

        do {
            let credential = EmailAuthProvider.credential(withEmail: email, password: current)
            try await user.reauthenticate(with: credential)
            try await user.updatePassword(to: newPass)
            await MainActor.run {
                isUpdatingPassword = false
                changePasswordMessage = "Passwort erfolgreich aktualisiert."
                changePasswordCurrent = ""
                changePasswordNew = ""
                changePasswordConfirm = ""
                changePasswordError = nil
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            await MainActor.run {
                isUpdatingPassword = false
                changePasswordError = mapAuthErrorMessage(error)
            }
        }
    }

    private func handleAppSettingsPrivacyToggle() {
        if store.isPrivacyModeActive {
            if biometricManager.isEnabledForActiveUser {
                Task {
                    let success = await biometricManager.authenticate(reason: "Noten anzeigen")
                    if success {
                        store.updatePrivacyMode(active: false)
                    }
                }
            } else {
                store.updatePrivacyMode(active: false)
            }
        } else {
            store.updatePrivacyMode(active: true)
        }
    }
}


private struct ChangeEmailSheet: View {
    let currentEmail: String
    @Binding var currentPassword: String
    @Binding var newEmail: String
    @Binding var confirmEmail: String
    @Binding var message: String?
    @Binding var errorMessage: String?
    let isProcessing: Bool
    let submit: () -> Void
    let cancel: () -> Void

    @EnvironmentObject private var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        !currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && newEmail.trimmingCharacters(in: .whitespacesAndNewlines) == confirmEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "E-Mail ändern",
                        subtitle: "Aktuell: \(currentEmail)",
                        systemImage: "envelope.fill",
                        accent: .blue
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Zur Sicherheit musst du dein aktuelles Passwort eingeben.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    IconField(
                                        icon: "lock.fill",
                                        placeholder: "Aktuelles Passwort",
                                        text: $currentPassword,
                                        isSecure: true,
                                        contentType: .password
                                    )

                                    IconField(
                                        icon: "envelope.badge",
                                        placeholder: "Neue E-Mail",
                                        text: $newEmail,
                                        keyboard: .emailAddress,
                                        contentType: .emailAddress
                                    )

                                    IconField(
                                        icon: "envelope.open.fill",
                                        placeholder: "Neue E-Mail bestätigen",
                                        text: $confirmEmail,
                                        keyboard: .emailAddress,
                                        contentType: .emailAddress
                                    )
                                }
                            }

                            if let msg = message {
                                StatusBubble(text: msg, icon: "checkmark.circle.fill", color: .green)
                            }

                            if let err = errorMessage {
                                StatusBubble(text: err, icon: "exclamationmark.triangle.fill", color: .red)
                            }

                            Button {
                                submit()
                            } label: {
                                HStack {
                                    if isProcessing {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                        Text("E-Mail speichern")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .blue))
                            .disabled(!canSubmit || isProcessing)
                        }
                    }

                    Button {
                        cancel()
                        dismiss()
                    } label: {
                        Label("Abbrechen", systemImage: "xmark")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(18)
            }
            .background(
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
            )
            .navigationTitle("E-Mail ändern")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("E-Mail ändern")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Abbrechen")
                }
            }
            .interactiveDismissDisabled(isProcessing)
        }
    }
}

private struct ChangePasswordSheet: View {
    @Binding var currentPassword: String
    @Binding var newPassword: String
    @Binding var confirmPassword: String
    @Binding var message: String?
    @Binding var errorMessage: String?
    let isProcessing: Bool
    let submit: () -> Void
    let cancel: () -> Void

    @EnvironmentObject private var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    private var canSubmit: Bool {
        !currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !newPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Passwort ändern",
                        subtitle: "Mit aktuellem Passwort bestätigen",
                        systemImage: "key.fill",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Gib dein aktuelles Passwort ein und bestätige das neue zweimal.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    IconField(
                                        icon: "lock.fill",
                                        placeholder: "Aktuelles Passwort",
                                        text: $currentPassword,
                                        isSecure: true,
                                        contentType: .password
                                    )

                                    IconField(
                                        icon: "key.horizontal.fill",
                                        placeholder: "Neues Passwort (min. 6 Zeichen)",
                                        text: $newPassword,
                                        isSecure: true,
                                        contentType: .newPassword
                                    )

                                    IconField(
                                        icon: "checkmark.seal.fill",
                                        placeholder: "Neues Passwort bestätigen",
                                        text: $confirmPassword,
                                        isSecure: true,
                                        contentType: .newPassword
                                    )
                                }
                            }

                            if let msg = message {
                                StatusBubble(text: msg, icon: "checkmark.circle.fill", color: .green)
                            }

                            if let err = errorMessage {
                                StatusBubble(text: err, icon: "exclamationmark.triangle.fill", color: .red)
                            }

                            Button {
                                submit()
                            } label: {
                                HStack {
                                    if isProcessing {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "key.fill")
                                        Text("Passwort speichern")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                            .disabled(!canSubmit || isProcessing)
                        }
                    }

                    Button {
                        cancel()
                        dismiss()
                    } label: {
                        Label("Abbrechen", systemImage: "xmark")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(18)
            }
            .background(
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
            )
            .navigationTitle("Passwort ändern")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Passwort ändern")
                        .font(.headline.weight(.semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        cancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Abbrechen")
                }
            }
            .interactiveDismissDisabled(isProcessing)
        }
    }
}

private struct SheetHeaderCard: View {
    let icon: String
    let accent: Color
    let title: String
    let subtitle: String
    let helper: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    .frame(width: 54, height: 54)
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let helper, !helper.isEmpty {
                    Text(helper)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(colorScheme == .dark ? 0.18 : 0.12),
                            Color.formSectionBackground
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct IconField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(contentType)
        }
        .padding(12)
        .background(Color.formInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StatusBubble: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
            Text(text)
                .font(.footnote)
                .lineLimit(nil)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .foregroundStyle(color)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PillActionButtonStyle: ButtonStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .foregroundStyle(accent)
            .background(accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.22), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CompactMetric: View {
    let title: String
    let value: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
        )
    }
}

struct SchoolYearEditView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    @State private var nameInput: String = ""
    @State private var isSavingName: Bool = false
    @State private var nameMessage: String?
    @State private var nameError: String?

    @State private var showResetSheet: Bool = false
    @State private var showDeleteSheet: Bool = false
    @State private var resetPassword: String = ""
    @State private var deletePassword: String = ""
    @State private var resetSlideDone: Bool = false
    @State private var deleteSlideDone: Bool = false
    @State private var isResetting: Bool = false
    @State private var isDeleting: Bool = false
    @State private var resetError: String?
    @State private var deleteError: String?

    private var accent: Color {
        store.theme == "feminine" ? Color(hex: "#ec4899") : .mint
    }

    private let sectionHeaderFont: Font = .headline.weight(.semibold)
    private let helperFont: Font = .footnote
    private let maxExamSubjects: Int = 4

    private var gradeOptions: [Int] {
        store.schoolType == .fos ? [11, 12, 13] : [12, 13]
    }

    private var examEligibleSubjects: [Subject] {
        store
            .sortedSubjectsForDisplay()
            .filter { $0.type == 1 && !$0.isElective }
    }

    private var currentExamSubjectsCount: Int {
        examEligibleSubjects.filter { ($0.examSubject ?? false) }.count
    }

    private var hasActiveYear: Bool { store.activeSchoolYearId != nil }

    private var displayName: String {
        guard let id = store.activeSchoolYearId else { return "" }
        let name = store.schoolYearNames[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return id
    }

    private var nameHasChanges: Bool {
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != displayName
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if !hasActiveYear {
                        Text("Kein aktives Schuljahr vorhanden. Starte den Schuljahrs-Setup aus den Einstellungen.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SettingsCard(
                            title: "Schuljahr \(store.activeSchoolYearId ?? "—")",
                            subtitle: "Bezeichnung und Überblick",
                            systemImage: "calendar.badge.clock",
                            accent: accent
                        ) {
                            chips
                            nameSection
                        }

                        SettingsCard(
                            title: "Schulart & Jahrgang",
                            subtitle: "Aktuelles Schuljahr konfigurieren",
                            systemImage: "graduationcap.fill",
                            accent: .indigo
                        ) {
                            schoolTypeSection
                        }

                        SettingsCard(
                            title: "Prüfungsfächer",
                            subtitle: "Bis zu 4 Hauptfächer markieren",
                            systemImage: "checkmark.seal.fill",
                            accent: .orange
                        ) {
                            examSection
                        }

                        SettingsCard(
                            title: "Aktionen",
                            subtitle: "Schuljahr zurücksetzen oder löschen",
                            systemImage: "exclamationmark.triangle.fill",
                            accent: .red
                        ) {
                            dangerZone
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Schuljahr bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
            .background(
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
                .ignoresSafeArea()
            )
            .sheetNavigationTitle("Schuljahr bearbeiten")
            .sheet(isPresented: $showResetSheet) {
                ResetConfirmSheet(
                    title: "Aktives Schuljahr zurücksetzen",
                    message: "Alle Daten des aktiven Schuljahres werden gelöscht. Danach startest du den Schuljahrs-Setup erneut.",
                    password: $resetPassword,
                    isPresented: $showResetSheet,
                    slideDone: $resetSlideDone,
                    isProcessing: isResetting,
                    errorMessage: resetError,
                    confirmAction: confirmResetYear
                )
            }
            .sheet(isPresented: $showDeleteSheet) {
                ResetConfirmSheet(
                    title: "Aktives Schuljahr löschen",
                    message: "Das aktuelle Schuljahr wird komplett entfernt. Falls ein weiteres Schuljahr existiert, wird es automatisch aktiviert, sonst startet der Schuljahrs-Setup erneut.",
                    password: $deletePassword,
                    isPresented: $showDeleteSheet,
                    slideDone: $deleteSlideDone,
                    isProcessing: isDeleting,
                    errorMessage: deleteError,
                    confirmAction: confirmDeleteYear
                )
            }
            .onAppear { bootstrap() }
            .onChange(of: store.activeSchoolYearId) { _, _ in bootstrap() }
        }
    }

    @ViewBuilder
    private var chips: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CompactStatusChip(
                    text: store.schoolType == .fos ? "FOS" : "BOS",
                    icon: "graduationcap.fill",
                    color: accent
                )
                if let grade = store.gradeYear {
                    CompactStatusChip(
                        text: "\(grade). Jgst.",
                        icon: "bookmark.fill",
                        color: .indigo
                    )
                }
                CompactStatusChip(
                    text: "\(currentExamSubjectsCount)/\(maxExamSubjects) Prüfungsfächer",
                    icon: "checkmark.seal.fill",
                    color: .orange
                )
            }
        }
    }

    @ViewBuilder
    private var nameSection: some View {
        SettingsSectionBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bezeichnung")
                    .font(sectionHeaderFont)
                Text("Passe die Anzeige deines aktuellen Schuljahres an.")
                    .font(helperFont)
                    .foregroundStyle(.secondary)

                TextField(displayName.isEmpty ? "Schuljahr" : displayName, text: $nameInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.formInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    Task { await saveName() }
                } label: {
                    HStack(spacing: 8) {
                        if isSavingName {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Bezeichnung speichern")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftTintButtonStyle(accent: accent))
                .disabled(!nameHasChanges || isSavingName)

                if let msg = nameMessage {
                    Text(msg)
                        .font(helperFont)
                        .foregroundStyle(.green)
                }
                if let err = nameError {
                    Text(err)
                        .font(helperFont)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var schoolTypeSection: some View {
        SettingsSectionBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Schulart & Jahrgang")
                    .font(sectionHeaderFont)
                Text("Lege Schulart und Jahrgangsstufe für das aktuelle Schuljahr fest.")
                    .font(helperFont)
                    .foregroundStyle(.secondary)

                Picker(
                    "",
                    selection: Binding(
                        get: { store.schoolType },
                        set: { val in
                            Task {
                                await store.updateSchoolType(val)
                                if val == .bos, store.gradeYear == 11 {
                                    await store.updateGradeYear(12)
                                }
                            }
                        }
                    )
                ) {
                    Text("FOS").tag(SchoolType.fos)
                    Text("BOS").tag(SchoolType.bos)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 10) {
                    ForEach(gradeOptions, id: \.self) { grade in
                        let selected = store.gradeYear == grade
                        Button {
                            Task { await store.updateGradeYear(grade) }
                        } label: {
                            HStack {
                                Text("\(grade). Jahrgang")
                                    .font(.body)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var examSection: some View {
        SettingsSectionBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Prüfungsfächer")
                    .font(sectionHeaderFont)
                Text("Markiere bis zu 4 Prüfungsfächer für das aktuelle Schuljahr.")
                    .font(helperFont)
                    .foregroundStyle(.secondary)

                let eligible = examEligibleSubjects

                if eligible.isEmpty {
                    Text("Lege zuerst Hauptfächer an, um Prüfungsfächer zu wählen.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(eligible, id: \.name) { subject in
                            ExamSubjectRow(
                                subject: subject,
                                isDisabled: !(subject.examSubject ?? false) && currentExamSubjectsCount >= maxExamSubjects,
                                onToggle: { isOn in
                                    let nextExamType = subject.examType ?? .written
                                    Task {
                                        await store.updateSubjectExamFlags(
                                            subjectName: subject.name,
                                            examSubject: isOn,
                                            examType: nextExamType
                                        )
                                    }
                                }
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                        }
                    }
                    if currentExamSubjectsCount >= maxExamSubjects {
                        Text("Du hast bereits 4 Prüfungsfächer ausgewählt. Entferne eines, um ein anderes Fach als Prüfungsfach zu markieren.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(role: .destructive) {
                resetPassword = ""
                resetSlideDone = false
                resetError = nil
                showResetSheet = true
            } label: {
                Label("Schuljahr zurücksetzen", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftTintButtonStyle(accent: .orange))

            Button(role: .destructive) {
                deletePassword = ""
                deleteSlideDone = false
                deleteError = nil
                showDeleteSheet = true
            } label: {
                Label("Schuljahr löschen", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftTintButtonStyle(accent: .red))
        }
    }

    private func bootstrap() {
        nameInput = displayName
        nameMessage = nil
        nameError = nil
    }

    private func saveName() async {
        guard nameHasChanges else { return }
        isSavingName = true
        nameMessage = nil
        nameError = nil
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { isSavingName = false }
        guard !trimmed.isEmpty else {
            nameError = "Bitte eine Bezeichnung eingeben."
            return
        }
        await store.updateSchoolYearName(trimmed)
        nameMessage = "Bezeichnung aktualisiert."
        nameInput = trimmed
    }

    private func confirmResetYear() {
        Task {
            guard !isResetting else { return }
            resetError = nil
            isResetting = true
            defer { isResetting = false }
            do {
                try await store.resetActiveSchoolYear(password: resetPassword)
                resetPassword = ""
                resetSlideDone = false
                resetError = nil
                showResetSheet = false
                dismiss()
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                resetError = error.localizedDescription
            }
        }
    }

    private func confirmDeleteYear() {
        Task {
            guard !isDeleting else { return }
            deleteError = nil
            isDeleting = true
            defer { isDeleting = false }
            do {
                try await store.deleteActiveSchoolYearCompletely(password: deletePassword)
                deletePassword = ""
                deleteSlideDone = false
                deleteError = nil
                showDeleteSheet = false
                dismiss()
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                deleteError = error.localizedDescription
            }
        }
    }
}

private struct CompactStatusChip: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .foregroundStyle(color)
        .background(color.opacity(0.14))
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .lineLimit(1)
    }
}

private struct ExamSubjectRow: View {
    let subject: Subject
    let isDisabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name).font(.body)
                if subject.isElective {
                    Tag(text: "Wahlfach", style: .elective)
                } else {
                    Tag(
                        text: (subject.gradingMode ?? (subject.type == 1 ? .withSchulaufgaben : .withoutSchulaufgaben)) == .withSchulaufgaben ? "Schulaufgaben" : "Ohne Schulaufgabe",
                        style: (subject.gradingMode ?? (subject.type == 1 ? .withSchulaufgaben : .withoutSchulaufgaben)) == .withSchulaufgaben ? .main : .minor
                    )
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { subject.examSubject ?? false },
                set: { val in onToggle(val) }
            ))
            .labelsHidden()
            .disabled(isDisabled)
        }
    }
}

private struct ResetConfirmSheet: View {
    let title: String
    let message: String
    @Binding var password: String
    @Binding var isPresented: Bool
    @Binding var slideDone: Bool
    let isProcessing: Bool
    let errorMessage: String?
    let confirmAction: () -> Void

    @EnvironmentObject private var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.red.opacity(colorScheme == .dark ? 0.28 : 0.18),
                                                Color.orange.opacity(colorScheme == .dark ? 0.20 : 0.12)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.red)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.title3.weight(.semibold))
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.red.opacity(colorScheme == .dark ? 0.22 : 0.16),
                                        Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )

                    SlideToConfirmView(isConfirmed: $slideDone)
                        .frame(height: 68)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mit Passwort bestätigen")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                            SecureField("Passwort eingeben", text: $password)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(12)
                        .background(Color.formInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        if let err = errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color.red.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    Button {
                        confirmAction()
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                                Text("Bestätigen")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .red))
                    .disabled(!(slideDone && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || isProcessing)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .background(
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Abbrechen")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
        }
    }
}

private struct SlideToConfirmView: View {
    @Binding var isConfirmed: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var hintPhase: Bool = false
    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 64
            let knobSize = height - 12
            let maxOffset = max(0, width - knobSize - 8)
            let progress: CGFloat = maxOffset == 0
                ? 1
                : max(0, min(dragOffset / maxOffset, 1))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: height / 2)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(isDragging ? 0.55 : 0.35),
                                Color.orange.opacity(isDragging ? 0.50 : 0.30)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(knobSize + 6, (knobSize + 6) + maxOffset * progress))
                    .opacity(0.35)
                    .overlay(
                        RoundedRectangle(cornerRadius: height / 2)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.0),
                                        Color.white.opacity(isDragging ? 0.30 : 0.16),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: isDragging ? 2 : 1
                            )
                            .opacity(isDragging ? 0.7 : 0.25)
                    )

                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text(isConfirmed ? "Bestätigt – jetzt Passwort eingeben" : "Zum Bestätigen nach rechts schieben")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary.opacity(isConfirmed ? 0.9 : 0.7))
                        Text("Sicherheits-Swipe verhindert versehentliches Löschen.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, knobSize * 0.35)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: isConfirmed
                                ? [Color.green, Color.green.opacity(0.8)]
                                : [Color.red, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: (isConfirmed ? Color.green : Color.orange).opacity(0.25), radius: 8, x: 0, y: 4)
                    .overlay(
                        ZStack {
                            if isDragging {
                                TimelineView(.animation) { timeline in
                                    let t = timeline.date.timeIntervalSinceReferenceDate
                                    let pulse = 1 + 0.08 * sin(t * 6)
                                    Circle()
                                        .stroke(Color.white.opacity(0.35), lineWidth: 3)
                                        .scaleEffect(pulse)
                                        .opacity(0.6 - 0.3 * abs(sin(t * 3)))
                                }
                            }

                            HStack(spacing: 2) {
                                Image(systemName: isConfirmed ? "checkmark" : "chevron.forward")
                                    .font(.headline.weight(.bold))
                                if !isConfirmed {
                                    Image(systemName: "chevron.forward")
                                        .font(.headline.weight(.bold))
                                        .opacity(hintPhase ? 1 : 0.4)
                                        .offset(x: hintPhase ? 2 : -2)
                                }
                            }
                            .foregroundStyle(.white)
                        }
                    )
                    .scaleEffect(isDragging ? 1.05 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isDragging)
                    .offset(x: max(4, min(dragOffset + 4, maxOffset + 4)))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !isConfirmed else { return }
                                if !isDragging {
                                    isDragging = true
                                }
                                dragOffset = max(0, min(value.translation.width, maxOffset))
                            }
                            .onEnded { _ in
                                guard !isConfirmed else { return }
                                if dragOffset > maxOffset * 0.82 {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        isConfirmed = true
                                        dragOffset = maxOffset
                                    }
                                } else {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isConfirmed = false
                                        dragOffset = 0
                                    }
                                }
                                isDragging = false
                            }
                    )
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: hintPhase)
            }
            .frame(height: height)
            .onAppear {
                hintPhase = true
            }
            .onChange(of: isConfirmed) { _, newValue in
                if !newValue {
                    dragOffset = 0
                    isDragging = false
                } else {
                    dragOffset = maxOffset
                }
            }
        }
    }
}
