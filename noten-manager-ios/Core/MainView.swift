// MainView.swift
import SwiftUI
import StoreKit
import FirebaseAuth

// PreferenceKey, mit dem Detailseiten (SubjectDetail) den aktuellen Fachnamen
// an den Container melden, damit die global überlagerte BottomNav die Vorauswahl kennt.
struct QuickAddSubjectPreferenceKey: PreferenceKey {
    static var defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

enum SheetDestination: Identifiable {
    case launchMessage
    case subscriptionOffer
    case examList
    case homeworkList
    case notifications
    case groupJoin
    case launchLaterReminder
    case creationMenu
    case addSubject
    case addGrade
    case addFachreferat
    case fachreferatDetail
    case addHomework
    case addExam
    case practical
    case seminar
    case groupCreation
    case onboardingFunnel
    
    var id: String {
        switch self {
        case .launchMessage: return "launchMessage"
        case .subscriptionOffer: return "subscriptionOffer"
        case .examList: return "examList"
        case .homeworkList: return "homeworkList"
        case .notifications: return "notifications"
        case .groupJoin: return "groupJoin"
        case .launchLaterReminder: return "launchLaterReminder"
        case .creationMenu: return "creationMenu"
        case .addSubject: return "addSubject"
        case .addGrade: return "addGrade"
        case .addFachreferat: return "addFachreferat"
        case .fachreferatDetail: return "fachreferatDetail"
        case .addHomework: return "addHomework"
        case .addExam: return "addExam"
        case .practical: return "practical"
        case .seminar: return "seminar"
        case .groupCreation: return "groupCreation"
        case .onboardingFunnel: return "onboardingFunnel"
        }
    }
}

struct MainView: View {
    let onLogout: () -> Void
    @Binding var incomingHomeworkShare: HomeworkShareLinkPayload?
    @Binding var incomingExamId: String?
    @Binding var deeplinkDestination: DeeplinkDestination?
    @EnvironmentObject private var gradesStore: GradesStore
    @StateObject private var notificationInbox = NotificationInboxStore.shared
    @State private var currentTab: BottomNavView.Tab = .home
    @EnvironmentObject private var offlineManager: OfflineModeManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var biometricManager: BiometricAuthManager
    @EnvironmentObject private var storeKit: StoreKitManager

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview
    @AppStorage("app_first_launch_timestamp") private var firstLaunchTimestamp: Double = 0
    @AppStorage("launchMessageSeen_2026_paid") private var launchMessageSeen = false
    @AppStorage("launchOfferPurchased") private var launchOfferPurchased = false
    @State private var navPath = NavigationPath()
    @State private var offlineBannerVisible: Bool = false
    @State private var offlineBannerDismissTask: Task<Void, Never>?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var showPfingstferienPrompt: Bool = false
    @State private var nextSchoolYearSuggestion: String?
    @State private var spinnerAnimating: Bool = false
    @State private var emailBannerVisible: Bool = false
    @State private var emailVerificationError: Bool = false
    @State private var isVerifyingEmail: Bool = false
    @State private var emailBannerDismissTask: Task<Void, Never>?
    @State private var needsEmailVerification: Bool = false
    @State private var scrollToAccountOnOpen: Bool = false
    @State private var pendingNotificationAction: NotificationInboxItem?
    @State private var pendingOpenLaunchMessageFromInbox: Bool = false
    @State private var showLaunchLaterReminder: Bool = false
    @State private var pendingLaunchLaterReminder: Bool = false
    @State private var showSubscriptionPurchaseSuccess: Bool = false
    @State private var pendingSubscriptionPurchaseSuccess: Bool = false
    @State private var subscriptionOfferShownThisSession: Bool = false
    @State private var showLaunchPurchaseSuccess: Bool = false
    @State private var pendingLaunchPurchaseSuccess: Bool = false
    @State private var showGroupJoinSheet: Bool = false
    @State private var pendingGroupJoinCode: String = ""
    @State private var activeSheet: SheetDestination?

    // Von SubjectDetail per Preference gemeldetes Fach für „Note hinzufügen“
    @State private var quickAddSubjectName: String? = nil
    @State private var navigateToAbiturExam: Bool = false
    @State private var deeplinkExamId: String? = nil
    @State private var deeplinkExam: Exam? = nil
    @State private var deeplinkHomework: Homework? = nil
    
    @AppStorage("showSpeedometerOnLaunch") private var showSpeedometerOnLaunch: Bool = false
    @State private var isInitialLaunch: Bool = true // Force loading screen on start
    
    // Fancy Speedometer Cover State
    @State private var showSpeedometerCover: Bool = false
    @State private var dailySummaryData: DailySummaryData?
    
    @Namespace private var namespace

    // Compute props for sheets
    private var isFirstSubject: Bool { gradesStore.subjects.isEmpty }
    private var disableAddGrade: Bool { gradesStore.encryptionKey == nil || gradesStore.subjects.isEmpty }
    private var gradeYear: Int { gradesStore.gradeYear ?? 12 }
    private var hasFachreferat: Bool { gradesStore.fachreferat != nil }
    private var showPracticalTab: Bool {
        gradesStore.schoolType == .fos && (gradeYear == 11 || gradeYear == 12)
    }
    private var showFachreferatAction: Bool { gradeYear == 12 }
    private var showSeminarAction: Bool {
        gradeYear >= 12 || gradesStore.seminarPerformance != nil
    }

    private var isFeminine: Bool { gradesStore.theme == "feminine" }
    private var isDark: Bool { gradesStore.darkMode }
    private var activeColor: Color {
        if isFeminine {
            return isDark ? Color(hex: "#f472b6") : Color(hex: "#ec4899")
        }
        return isDark ? Color(hex: "#60a5fa") : Color(hex: "#2563eb")
    }

    var body: some View {
        let base = ZStack {
            themedBackground
            navigationContainer
        }
        applyGlobalModifiers(to: base)
    }

    @ViewBuilder
    private func applyGlobalModifiers<Content: View>(to view: Content) -> some View {
        let base = view
            .onPreferenceChange(QuickAddSubjectPreferenceKey.self) { value in
                quickAddSubjectName = value
            }
            .onAppear {
                gradesStore.syncDarkModeWithSystem(colorScheme: colorScheme)
                notificationInbox.refreshFromDelivered()
                scheduleLaunchOfferNotifications(purchased: launchOfferPurchased)

                if showSpeedometerOnLaunch {
                    showSpeedometerCover = true
                }
                
                // Native TabBar Appearance (Liquid Glass)
                let appearance = UITabBarAppearance()
                appearance.configureWithDefaultBackground()
                appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
                UITabBar.appearance().standardAppearance = appearance
                if #available(iOS 15.0, *) {
                    UITabBar.appearance().scrollEdgeAppearance = appearance
                }
            }
            .onChange(of: colorScheme) { _, newScheme in
                gradesStore.syncDarkModeWithSystem(colorScheme: newScheme)
            }
            .onChange(of: launchOfferPurchased) { _, purchased in
                scheduleLaunchOfferNotifications(purchased: purchased)
                enforceSubscriptionGateIfNeeded()
            }
            .onChange(of: storeKit.product?.displayPrice) { _, _ in
                scheduleLaunchOfferNotifications(purchased: launchOfferPurchased)
            }
            .onChange(of: storeKit.isSubscriptionActive) { _, _ in
                enforceSubscriptionGateIfNeeded()
            }
            .preferredColorScheme(gradesStore.preferredColorScheme)
            .environmentObject(gradesStore) // Inject explicitly for overlay if needed

        let onboardingTracking = base
            .onChange(of: gradesStore.gradeYear) { _, _ in
                Task { await evaluatePfingstferienPrompt() }
            }
            .onChange(of: gradesStore.activeSchoolYearId) { _, _ in
                Task { await evaluatePfingstferienPrompt() }
            }
            .onChange(of: gradesStore.isLoading) { _, loading in
                spinnerAnimating = loading
            }
            .onChange(of: gradesStore.initialSyncSettled) { _, settled in
                if settled {
                    // First settlement: Decide between onboarding or other launch modals
                    if gradesStore.onboardingRequired {
                        // Handled by ContentView or separate flow if needed
                    } else {
                        // Priority 1: Mandatory subscription gate (if active)
                        enforceSubscriptionGateIfNeeded()
                        
                        // Priority 2: Deferred Notification triggers (Launch Offer)
                        if LaunchOfferNotificationManager.consumePendingOpen() {
                            handleOpenLaunchOfferNotification()
                        }
                        
                        // Priority 3: Non-destructive automated informational modals
                        showLaunchMessageIfNeeded()
                        Task { await showSubscriptionOfferIfNeeded() }
                        attemptRequestReview()
                    }
                }
            }

        let deeplinkTracking = onboardingTracking
            .onChange(of: incomingExamId) { _, newId in
                self.deeplinkExamId = newId
                if newId != nil {
                    self.currentTab = .home
                }
                self.handleDeeplinkExam()
            }
            .onChange(of: deeplinkDestination) { _, destination in
                handleDeeplinkDestination(destination)
            }
            .onChange(of: gradesStore.allExams) { _, _ in
                self.handleDeeplinkExam()
                Task {
                    await ExamLiveActivityManager.syncLiveActivities(for: gradesStore.allExams)
                    BackgroundRefreshManager.schedule(for: gradesStore.allExams)
                }
            }

        let lifecycle = deeplinkTracking
            .task {
                await handleDataLoading()
                await refreshEmailVerification()
            }
            .onChange(of: offlineManager.isOfflineModeActive) { _, active in
                Task {
                    await handleOfflineToggle(active: active)
                }
            }
            .onChange(of: authManager.isAuthenticated) { _, _ in
                Task {
                    await refreshEmailVerification()
                    await showSubscriptionOfferIfNeeded()
                }
            }
            .onChange(of: currentTab) { _, newTab in
                if isSubscriptionGateActive && !isTabAllowed(newTab) {
                    currentTab = .home
                    presentSubscriptionGate()
                    return
                }
                if newTab != .settings {
                    scrollToAccountOnOpen = false
                }
                if newTab == .home {
                    Task { await showSubscriptionOfferIfNeeded() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLaunchOffer)) { _ in
                handleOpenLaunchOfferNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openGroupJoin)) { notification in
                if let code = notification.object as? String {
                    self.currentTab = .home
                    self.pendingGroupJoinCode = code
                    self.activeSheet = .groupJoin
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSheet)) { notification in
                if let type = notification.object as? String {
                    handleOpenSheet(type)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNotificationItem)) { notification in
                if let item = notification.object as? NotificationInboxItem {
                    openInboxNotification(item)
                }
            }
            .onChange(of: gradesStore.legacyMigrationSummary) { _, summary in
                // Legacy migration handled via ContentView or Alert in future
            }

        let overlays = lifecycle
            // Minimal Loading Indicator (Non-Blocking)
            // Minimal Loading Indicator (Removed in favor of SyncStatusView in Home)
            .overlay(alignment: .bottom) {
                // Empty
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
            // Fancy Speedometer Cover Layer
            .overlay {
                if showSpeedometerCover && currentTab == .home {
                    FancyCoverView(isPresented: $showSpeedometerCover)
                        .transition(.move(edge: .bottom))
                        .zIndex(100)
                        .environmentObject(gradesStore)
                }
            }
            // Enhanced Loading Screen (Full Screen Cover)
            .overlay {
                if gradesStore.isLoading || isInitialLaunch {
                    EnhancedLoadingScreen()
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                        .zIndex(200) // Ensure it sits above everything else, including Speedometer
                        .environmentObject(gradesStore)
                }
            }

        overlays
            .sheet(item: $deeplinkExam) { exam in
                ExamDetailSheet(exam: exam, onEdit: { _ in })
                    .environmentObject(gradesStore)
            }
            .sheet(item: $deeplinkHomework) { homework in
                HomeworkDetailSheet(homework: homework, onEdit: { _ in })
                    .environmentObject(gradesStore)
            }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        notificationsToolbarButton()
                        if offlineManager.isOfflineModeActive {
                            offlineToolbarButton
                        }
                        if needsEmailVerification {
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
            .alert("Kauf erfolgreich", isPresented: $showLaunchPurchaseSuccess) {
                Button("Alles klar", role: .cancel) {}
            } message: {
                Text("Danke! Die Vollversion ist jetzt freigeschaltet.")
            }
            .alert("Abo aktiviert", isPresented: $showSubscriptionPurchaseSuccess) {
                Button("Alles klar", role: .cancel) {}
            } message: {
                Text("Danke! Dein Jahresabo ist jetzt aktiv.")
            }
            .sheet(item: $incomingHomeworkShare, onDismiss: {
                incomingHomeworkShare = nil
            }) { payload in
                AddHomeworkView(
                    preselectedSubjectName: payload.subjectName,
                    prefill: AddHomeworkPrefill(
                        subjectName: payload.subjectName,
                        title: payload.title,
                        dueDate: payload.dueDate
                    )
                )
                .environmentObject(gradesStore)
            }
            .sheet(item: $dailySummaryData) { data in
                DailySummarySheet(data: data)
                    .environmentObject(gradesStore)
            }
            .sheet(isPresented: $gradesStore.showSupportHistory) {
                SupportHistoryView()
                    .environmentObject(gradesStore)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSupportTicket)) { notification in
                if let ticketId = notification.object as? String {
                    gradesStore.pendingTicketId = ticketId
                    gradesStore.showSupportHistory = true
                }
            }
    }

    private func handleNotificationsSheetDismiss() {
        // Small delay to ensure sheet is fully dismissed before presenting next one
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.pendingOpenLaunchMessageFromInbox {
                self.pendingOpenLaunchMessageFromInbox = false
                if !self.gradesStore.onboardingRequired && !self.gradesStore.schoolYears.isEmpty {
                    self.activeSheet = .launchMessage
                }
                return
            }
            guard let item = self.pendingNotificationAction else { return }
            self.pendingNotificationAction = nil
            self.openInboxNotification(item)
        }
    }

    @MainActor
    private func handleDataLoading() async {
        // We do NOT set gradesStore.isLoading = true here anymore to avoid full blocking.
        // Instead, the GradesStore handles isLoading internally, and we rely on the minimal indicator.
        // We only trigger the actual fetch/sync here.
        gradesStore.isLoading = true // Trigger the minimal indicator
        
        // 1. Always attempt to load cached content immediately for instant UI
        // Use async loading to prevent UI freeze on startup (decoding JSON on main thread causes stutter)
        let snapshot = await offlineManager.loadSnapshotAsync()
        
        if let snapshot {
            gradesStore.loadOfflineSnapshot(snapshot)
            // Fix: Force loading state to true again, because loadOfflineSnapshot sets it to false.
            // We want the loading screen to remain visible while we check for online updates.
            gradesStore.isLoading = true
             
            // Now that we have something to show (even if we are still loading online data),
            // we can carefully disable the initial launch flag if we wanted to show data immediately.
            // BUT user wants loading screen to persist. So we keep isLoading = true.
            // We'll flip isInitialLaunch to false now so standard isLoading logic takes over.
            withAnimation {
                isInitialLaunch = false
            }
        } else {
             // No snapshot, so we are definitely loading from scratch
             // Keep isInitialLaunch = true until we are done
        }
        
        // 2. Determine if we should stay in Offline Mode
        //    Either explicitly manual, or no internet + allowed offline login
        //    IMPORTANT: We check isManualOfflinePinned instead of isOfflineModeActive,
        //    because step 1 (loadOfflineSnapshot) sets isOfflineModeActive = true as a side effect.
        var shouldStayOffline = offlineManager.isManualOfflinePinned
        
        if !shouldStayOffline && !offlineManager.isOnline {
            if let snapshot, offlineManager.isOfflineLoginAllowed(for: snapshot.userId) {
                shouldStayOffline = true
            }
        }
        
        if shouldStayOffline {
            // Fix: Explicitly activate offline mode state so UI indicators (badge/toolbar) update.
            // We previously assumed loadOfflineSnapshot did this, but it implies local usage, not mode activation.
            offlineManager.activateOfflineMode(manual: offlineManager.isManualOfflinePinned)
            
            showOfflineBannerTemporarily()
            await refreshEmailVerification()
            await evaluatePfingstferienPrompt()
            gradesStore.isLoading = false
            gradesStore.initialSyncSettled = true
            withAnimation { isInitialLaunch = false }
            return
        }

        // 3. Proceed to Online Sync
        OfflineModeManager.shared.enableFirestoreNetworkIfNeeded()
        await gradesStore.syncOfflinePendingChanges(forceLocalOverride: true)

        gradesStore.leaveOfflineModePreservingState()
        await gradesStore.startListening()
        hideOfflineBanner()
        await evaluatePfingstferienPrompt()
        
        // Final cleanup
        withAnimation {
             isInitialLaunch = false
        }
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
        let created = await gradesStore.createSchoolYear(name: id, gradeYear: nil, schoolType: nil)
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

    private func notificationsToolbarButton() -> some View {
        Button {
            activeSheet = .notifications
        } label: {
            ToolbarIcon(
                symbol: "bell.fill",
                showDot: notificationInbox.hasUnread || hasImportantNotifications,
                dotOffset: CGSize(width: 0, height: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Benachrichtigungen")
    }

    private var hasImportantNotifications: Bool {
        LaunchOfferNotificationManager.isOfferActive() && !launchOfferPurchased
    }

    private var offlineToolbarButton: some View {
        Button {
            showOfflineBannerTemporarily()
        } label: {
            ToolbarIcon(symbol: "wifi.slash", showDot: false)
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if isVerifyingEmail {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: emailVerificationError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    if emailVerificationError {
                        Text("Verbindung fehlgeschlagen")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text("Bitte überprüfe deine Internetverbindung.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    } else {
                        Text("E-Mail noch nicht bestätigt")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text("Bitte bestätige deine Adresse über die E-Mail, die wir gesendet haben.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                
                Spacer()

                Button {
                    hideEmailBanner()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 10) {
                if emailVerificationError {
                    Button {
                        Task { await refreshEmailVerification() }
                    } label: {
                        Label("Erneut versuchen", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
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
                
                if !emailVerificationError {
                    Button {
                        Task { await refreshEmailVerification() }
                    } label: {
                        Text("Aktualisieren")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(emailVerificationError ? Color.orange : Color.red)
        )
        .padding(.horizontal, 16)
        .animation(.snappy, value: emailVerificationError)
    }

    private var emailVerificationToolbarButton: some View {
        Button {
            showEmailBannerTemporarily()
        } label: {
            ToolbarIcon(symbol: "info.circle.fill", showDot: false)
        }
        .buttonStyle(.plain)
    }

    private func showEmailBannerTemporarily() {
        emailBannerDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            emailBannerVisible = true
        }
        emailBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            hideEmailBanner()
        }
    }

    private func hideEmailBanner() {
        emailBannerDismissTask?.cancel()
        emailBannerDismissTask = nil
        withAnimation(.easeInOut(duration: 0.15)) {
            emailBannerVisible = false
        }
    }

    private func showLaunchMessageIfNeeded() {
        guard authManager.isAuthenticated else { return }
        guard currentTab == .home else { return }
        guard !gradesStore.isLoading else { return }
        guard !gradesStore.onboardingRequired else { return }
        // New user safety guard: strictly no launch message if no years or no active year
        guard !gradesStore.schoolYears.isEmpty else { return }
        guard gradesStore.activeSchoolYearId != nil else { return }
        
        guard !launchMessageSeen else { return }
        
        // Version-based guard: only show if user registered on an older version
        if let regVersion = gradesStore.registeredInVersion {
            // Very simple comparison for now (legacy or older strings)
            guard regVersion != "1.3" else { return }
        }
        
        guard !launchOfferPurchased else { return }
        guard LaunchOfferNotificationManager.isOfferActive() else { return }
        guard activeSheet == nil else { return }
        activeSheet = .launchMessage
    }

    @MainActor
    private func showSubscriptionOfferIfNeeded() async {
        guard authManager.isAuthenticated else { return }
        guard currentTab == .home else { return }
        guard !gradesStore.isLoading else { return }
        guard !gradesStore.onboardingRequired else { return }
        guard !LaunchOfferNotificationManager.isOfferActive() else { return }
        guard !launchOfferPurchased else { return }
        guard activeSheet == nil else { return }
        guard !subscriptionOfferShownThisSession else { return }
        let isActive = await storeKit.refreshSubscriptionStatus()
        guard !isActive else { return }
        activeSheet = .subscriptionOffer
        subscriptionOfferShownThisSession = true
    }

    private func scheduleLaunchOfferNotifications(purchased: Bool) {
        LaunchOfferNotificationManager.scheduleIfNeeded(
            purchased: purchased,
            displayPrice: storeKit.product?.displayPrice
        )
    }

    private func handleOpenLaunchOfferNotification() {
        guard authManager.isAuthenticated else { return }
        guard !launchOfferPurchased else { return }
        guard LaunchOfferNotificationManager.isOfferActive() else { return }
        guard !gradesStore.onboardingRequired && !gradesStore.schoolYears.isEmpty else { return }
        currentTab = .home
        
        if activeSheet == .notifications {
            pendingOpenLaunchMessageFromInbox = true
            activeSheet = nil
        } else {
            activeSheet = .launchMessage
        }
    }

    private func handleOpenSheet(_ type: String) {
        switch type {
        case "settings":
            currentTab = .settings
        case "notifications":
            activeSheet = .notifications
        case "launch_offer":
            handleOpenLaunchOfferNotification()
        case "add_homework":
            activeSheet = .addHomework
        case "add_exam":
            activeSheet = .addExam
        default:
            break
        }
        // Ensure we are on a tab where sheets can be presented visibly if needed
        if type != "settings" && currentTab == .settings {
            currentTab = .home
        }
    }


    private func openInboxNotification(_ item: NotificationInboxItem) {
        currentTab = .home
        switch item.kind {
        case .exam:
            if let examId = item.examId,
               let exam = gradesStore.allExams.first(where: { $0.id == examId }) {
                deeplinkExam = exam
            } else {
                activeSheet = .examList
            }
        case .homework:
            if let homeworkId = item.homeworkId {
                let homework = gradesStore.allHomeworks.first { hw in
                    guard hw.id == homeworkId else { return false }
                    if let gid = item.groupId {
                        return hw.groupId == gid
                    }
                    return true
                }
                if let homework {
                    deeplinkHomework = homework
                } else {
                    activeSheet = .homeworkList
                }
            } else {
                activeSheet = .homeworkList
            }
        case .daily:
            let examIds = item.examIds ?? (item.examId.map { [$0] } ?? [])
            let homeworkIds = item.homeworkIds ?? (item.homeworkId.map { [$0] } ?? [])
            
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let tomorrowExams = gradesStore.allExams.filter { examIds.contains($0.id) }
            let tomorrowHomeworks = gradesStore.allHomeworks.filter { homeworkIds.contains($0.id) }
            
            self.dailySummaryData = DailySummaryData(exams: tomorrowExams, homeworks: tomorrowHomeworks, date: tomorrow)
            return
        default:
            break
        }
    }

    @MainActor
    private func refreshEmailVerification() async {
        guard !offlineManager.isOfflineModeActive else { return }
        guard let user = Auth.auth().currentUser else {
            needsEmailVerification = false
            emailBannerVisible = false
            return
        }
        
        isVerifyingEmail = true
        emailVerificationError = false
        
        // Retry Loop Configuration
        let maxRetries = 3
        var currentAttempt = 0
        var success = false
        
        while currentAttempt < maxRetries && !success {
            do {
                if currentAttempt > 0 {
                    // Exponential backoff: 0.5s, 1s, 2s
                    let delaySeconds = 0.5 * pow(2.0, Double(currentAttempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                }
                
                try await user.reload()
                success = true
                
                needsEmailVerification = !user.isEmailVerified
                if !needsEmailVerification {
                    hideEmailBanner()
                }
                
            } catch let error as NSError {
                currentAttempt += 1
                
                // Handle Network Errors specifically
                let domain = error.domain
                let code = error.code
                
                let isNetworkError = domain == NSURLErrorDomain && (
                    code == NSURLErrorNotConnectedToInternet ||
                    code == NSURLErrorTimedOut ||
                    code == NSURLErrorNetworkConnectionLost
                )
                
                if currentAttempt >= maxRetries {
                    ErrorLoggingService.logErrorIfEnabled(error)
                    if isNetworkError {
                        emailVerificationError = true
                        // Ensure banner is visible so user can see error and retry
                        if !emailBannerVisible {
                            showEmailBannerTemporarily()
                        }
                    } else {
                        // For non-network errors, we might fail silently or hide banner
                        hideEmailBanner() // Fallback to safe state
                    }
                }
            } catch {
                currentAttempt += 1
                if currentAttempt >= maxRetries {
                   ErrorLoggingService.logErrorIfEnabled(error)
                   hideEmailBanner()
                }
            }
        }
        
        isVerifyingEmail = false
    }

    private func attemptRequestReview() {
        let now = Date.now.timeIntervalSince1970
        if firstLaunchTimestamp == 0 {
            firstLaunchTimestamp = now
            return
        }
        
        // 3 Days = 3 * 24 * 60 * 60 = 259200 seconds
        let threeDaysCoords: TimeInterval = 259200
        
        if now > (firstLaunchTimestamp + threeDaysCoords) {
            Task { @MainActor in
                // Delay to ensure UI has settled
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                
                // Double check guards after sleep
                guard !gradesStore.isLoading else { return }
                guard !gradesStore.onboardingRequired else { return }
                guard activeSheet == nil else { return }
                
                requestReview()
            }
        }
    }

    @ViewBuilder
    private var navigationContainer: some View {
        Group {
            // Native TabView for all iOS versions with Liquid Glass System Style
            TabView(selection: $currentTab) {
                NavigationStack {
                    HomeView(
                        onOpenCreationMenu: { activeSheet = .creationMenu },
                        onToggleOfflineBanner: { showOfflineBannerTemporarily() }
                    )
                        .environmentObject(gradesStore)
                        .navigationDestination(for: Subject.self) { subject in
                            if subject.name == "Fachreferat" {
                                FachreferatDetailView(subject: subject)
                                    .environmentObject(gradesStore)
                            } else {
                                SubjectDetailView(subject: subject)
                                    .environmentObject(gradesStore)
                            }
                        }
                        .navigationDestination(isPresented: $navigateToAbiturExam) {
                            AbiturExamView().environmentObject(gradesStore)
                        }

                }
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(BottomNavView.Tab.home)

                NavigationStack {
                    GroupsListView(onOpenCreationMenu: { activeSheet = .creationMenu })
                        .environmentObject(gradesStore)

                }
                .tabItem {
                    Label("Gruppen", systemImage: "person.3.fill")
                }
                .tag(BottomNavView.Tab.groups)

                if !isSubscriptionGateActive {
                    NavigationStack {
                        InsightsView(onOpenCreationMenu: { activeSheet = .creationMenu })
                            .environmentObject(gradesStore)
                            .navigationDestination(for: Subject.self) { subject in
                                if subject.name == "Fachreferat" {
                                    FachreferatDetailView(subject: subject)
                                        .environmentObject(gradesStore)
                                } else {
                                    SubjectDetailView(subject: subject)
                                        .environmentObject(gradesStore)
                                }
                            }
                            .navigationDestination(isPresented: $navigateToAbiturExam) {
                                AbiturExamView().environmentObject(gradesStore)
                            }
                    }
                    .tabItem {
                        Label("Noten", systemImage: "chart.bar.fill")
                    }
                    .tag(BottomNavView.Tab.insights)
                    
                    NavigationStack {
                        FinalGradeView(onOpenCreationMenu: { activeSheet = .creationMenu })
                            .environmentObject(gradesStore)
                            .navigationDestination(isPresented: $navigateToAbiturExam) {
                                AbiturExamView().environmentObject(gradesStore)
                            }
                    }
                    .tabItem {
                        Label("Abi", systemImage: "graduationcap.fill")
                    }
                    .tag(BottomNavView.Tab.final)
                }

                NavigationStack {
                    AppSettingsView(
                        scrollToAccount: scrollToAccountOnOpen,
                        onOpenCreationMenu: { activeSheet = .creationMenu }
                    )
                        .environmentObject(gradesStore)
                        .environmentObject(authManager)
                        .environmentObject(offlineManager)
                        .environmentObject(biometricManager)
                        .navigationDestination(isPresented: $navigateToAbiturExam) {
                            AbiturExamView().environmentObject(gradesStore)
                        }
                }
                .tabItem {
                    Label("Optionen", systemImage: "gearshape.fill")
                }
                .tag(BottomNavView.Tab.settings)
            }
            .tint(activeColor)

        }
        // Attach Sheet Modifiers to the Group
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .creationMenu:
                CreationMenuView(
                    onAction: handleCreationAction,
                    isFirstSubject: isFirstSubject,
                    disableAddGrade: disableAddGrade,
                    showPractical: showPracticalTab,
                    showFachreferat: showFachreferatAction,
                    hasFachreferat: hasFachreferat,
                    showSeminar: showSeminarAction,
                    encryptionKeyLoaded: gradesStore.encryptionKey != nil
                )
                .environmentObject(gradesStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .addSubject: AddSubjectView().environmentObject(gradesStore)
            case .addGrade: AddGradeView(preselectedSubjectName: quickAddSubjectName).environmentObject(gradesStore)
            case .addFachreferat: AddFachreferatView(preselectedSubjectName: quickAddSubjectName).environmentObject(gradesStore)
            case .fachreferatDetail:
                NavigationStack {
                    FachreferatDetailView(subject: Subject(name: "Fachreferat", type: 0, date: Date()))
                        .environmentObject(gradesStore)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    activeSheet = nil
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .imageScale(.medium)
                                }
                            }
                        }
                }
            case .addHomework: AddHomeworkView(preselectedSubjectName: quickAddSubjectName).environmentObject(gradesStore)
            case .addExam: AddExamView(preselectedSubjectName: quickAddSubjectName).environmentObject(gradesStore)
            case .practical: NavigationStack { PraktikumDetailView().environmentObject(gradesStore) }
            case .seminar: SeminarPerformanceView().environmentObject(gradesStore)
            case .groupCreation: GroupCreationView().environmentObject(gradesStore)
            case .examList: 
                ExamListView()
                    .environmentObject(gradesStore)
                    .onDisappear { deeplinkDestination = nil }
            case .homeworkList:
                HomeworkListView()
                    .environmentObject(gradesStore)
                    .onDisappear { deeplinkDestination = nil }
            case .notifications:
                NotificationsInboxView(
                    inbox: notificationInbox,
                    onSelectNotification: { item in
                        if item.kind == .support, let tId = item.ticketId {
                            gradesStore.pendingTicketId = tId
                            gradesStore.showSupportHistory = true
                        } else {
                            pendingNotificationAction = item
                        }
                    },
                    onOpenImportant: {
                        pendingOpenLaunchMessageFromInbox = true
                    }
                )
                .environmentObject(gradesStore)
                .onDisappear { handleNotificationsSheetDismiss() }
            case .launchMessage:
                LaunchMessageSheetView(
                    onLater: { pendingLaunchLaterReminder = true },
                    onPurchaseSuccess: {
                        launchOfferPurchased = true
                        pendingLaunchPurchaseSuccess = true
                    }
                )
                .environmentObject(gradesStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(true)
                .onDisappear {
                    launchMessageSeen = true
                    if pendingLaunchLaterReminder {
                        activeSheet = .launchLaterReminder
                        pendingLaunchLaterReminder = false
                    } else if pendingLaunchPurchaseSuccess {
                        showLaunchPurchaseSuccess = true
                        pendingLaunchPurchaseSuccess = false
                    }
                }
            case .subscriptionOffer:
                SubscriptionOfferSheetView(
                    onLater: {},
                    onPurchaseSuccess: {
                        pendingSubscriptionPurchaseSuccess = true
                    }
                )
                .environmentObject(gradesStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(true)
                .onDisappear {
                    if pendingSubscriptionPurchaseSuccess {
                        showSubscriptionPurchaseSuccess = true
                        pendingSubscriptionPurchaseSuccess = false
                    }
                }
            case .groupJoin:
                GroupJoinView(initialCode: pendingGroupJoinCode)
                    .environmentObject(gradesStore)
            case .launchLaterReminder:
                ReminderConfirmationView()
                    .environmentObject(gradesStore)
            case .onboardingFunnel:
                EmptyView() // Structural placement to satisfy exhaustiveness
            }
        }
        // Retain NavigationDestinations logic by wrapping tabs as above.
    }

    private var isSubscriptionGateActive: Bool {
        guard LaunchOfferNotificationManager.isSubscriptionGateActive() else { return false }
        if launchOfferPurchased { return false }
        if storeKit.isSubscriptionActive { return false }
        return true
    }

    private func isTabAllowed(_ tab: BottomNavView.Tab) -> Bool {
        if !isSubscriptionGateActive {
            return true
        }
        return tab == .home || tab == .settings || tab == .groups
    }

    @MainActor
    private func openTab(_ tab: BottomNavView.Tab) {
        if isTabAllowed(tab) {
            currentTab = tab
            return
        }
        currentTab = .home
        presentSubscriptionGate()
    }

    @MainActor
    private func enforceSubscriptionGateIfNeeded() {
        guard isSubscriptionGateActive else { return }
        if !isTabAllowed(currentTab) {
            currentTab = .home
        }
        presentSubscriptionGate()
    }

    @MainActor
    private func presentSubscriptionGate() {
        guard activeSheet == nil else { return }
        activeSheet = .subscriptionOffer
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
                    if gradesStore.onboardingRequired || gradesStore.activeSchoolYearId == nil {
                        // Onboarding logic is now handled in ContentView or via specific alerts. 
                        // For now we just log or ignore, ensuring we don't crash.
                    }
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

            VStack(spacing: 18) {
                // Style matching CreationMenuView quickActionCard icon
                ZStack {
                    Circle()
                        .fill(loadingAccent.opacity(gradesStore.darkMode ? 0.22 : 0.16))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(loadingAccent)
                        .rotationEffect(.degrees(spinnerAnimating ? 360 : 0))
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spinnerAnimating)
                }

                VStack(spacing: 6) {
                    Text("Synchronisiere deine Daten")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(gradesStore.darkMode ? .white : Color(hex: "#0f172a"))
                    
                    Text(loadingOverlayLabel)
                        .font(.subheadline)
                        .foregroundStyle(gradesStore.darkMode ? Color.white.opacity(0.7) : .secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)

                if gradesStore.progress > 0 {
                    VStack(spacing: 8) {
                        ProgressView(value: gradesStore.progress, total: 100)
                            .tint(loadingAccent)
                        Text("\(Int(gradesStore.progress.rounded()))% abgeschlossen")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(gradesStore.darkMode ? Color.white.opacity(0.6) : .secondary)
                    }
                    .frame(maxWidth: 220)
                } else {
                    ProgressView()
                        .tint(loadingAccent)
                        .scaleEffect(1.1)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(
                loadingCardSurface
                    .shadow(color: Color.black.opacity(gradesStore.darkMode ? 0.45 : 0.12), radius: 12, x: 0, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(loadingAccent.opacity(gradesStore.darkMode ? 0.22 : 0.12), lineWidth: 1)
            )
            .padding(.horizontal, 32)
        }
        .onAppear { spinnerAnimating = true }
        .onDisappear { spinnerAnimating = false }
        .zIndex(50)
    }

    private var loadingCardSurface: some View {
        let isDark = gradesStore.darkMode
        let isFeminine = gradesStore.theme == "feminine"
        
        let cardTop: Color = {
            if isDark {
                return isFeminine ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
            }
            return isFeminine ? Color(hex: "#fff1f7") : Color(hex: "#eef2ff")
        }()

        let cardBottom: Color = {
            if isDark {
                return isFeminine ? Color(hex: "#120a16") : Color(hex: "#111827")
            }
            return isFeminine ? Color(hex: "#fff7fb") : Color(hex: "#f8fafc")
        }()

        return RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [cardTop, cardBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                loadingAccent.opacity(isDark ? 0.12 : 0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private func handleDeeplinkExam() {
        guard let id = self.deeplinkExamId else { return }
        if let exam = self.gradesStore.allExams.first(where: { $0.id == id }) {
            self.deeplinkExam = exam
            self.deeplinkExamId = nil
        }
    }

    private func handleDeeplinkDestination(_ destination: DeeplinkDestination?) {
        guard let dest = destination else { return }
        switch dest {
        case .notifications:
            activeSheet = .notifications
        case .support:
            gradesStore.showSupportHistory = true
        case .launchMessage:
            if !gradesStore.onboardingRequired && !gradesStore.schoolYears.isEmpty {
                activeSheet = .launchMessage
            }
        case .examList:
            activeSheet = .examList
        case .homeworkList:
            activeSheet = .homeworkList
        }
        deeplinkDestination = nil
    }

    private var themedBackground: some View {
        ThemedBackground(
            isDark: gradesStore.darkMode,
            isFeminine: gradesStore.theme == "feminine",
            intensity: gradesStore.themeBackgroundIntensity
        )
    }
    private func handleCreationAction(_ action: CreationAction) {
        activeSheet = nil
        if isSubscriptionGateActive {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch action {
            case .homework: activeSheet = .addHomework
            case .grade: activeSheet = .addGrade
            case .exam: activeSheet = .addExam
            case .subject: activeSheet = .addSubject
            case .practical: activeSheet = .practical
            case .fachreferat:
                if hasFachreferat { activeSheet = .fachreferatDetail }
                else { activeSheet = .addFachreferat }
            case .seminar: activeSheet = .seminar
            case .abitur: 
                if isSubscriptionGateActive {
                    presentSubscriptionGate()
                    return
                }
                navigateToAbiturExam = true
            case .group:
                activeSheet = .groupCreation
            }
        }
    }
}

struct LegacyMigrationPromptView: View {
    let summary: LegacyMigrationSummary
    let onImport: () -> Void
    let onStartFresh: () -> Void
    @EnvironmentObject private var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        statsCard

                        Text("Daten, die du in dieser App anlegst, sind nicht mit der Web-Version kompatibel.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)

                        VStack(spacing: 12) {
                            optionButton(
                                icon: "arrow.down.doc.fill",
                                title: "Daten übernehmen",
                                subtitle: "Importiert deine Web-Fächer und Noten in dieses Schuljahr.",
                                accent: accentPrimary,
                                action: onImport
                            )
                            optionButton(
                                icon: "sparkles",
                                title: "Neu anfangen ohne Web-Daten",
                                subtitle: "Beginnt frisch in der App. Deine Web-Daten bleiben dort erhalten.",
                                accent: Color.orange,
                                action: onStartFresh
                            )
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.fraction(0.75), .large])
        .interactiveDismissDisabled()
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentPrimary.opacity(store.darkMode ? 0.22 : 0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accentPrimary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Daten aus der Web-App erkannt")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(primaryText)
                    Text("Wir haben Inhalte aus der Web-Version gefunden. Wie möchtest du fortfahren?")
                        .font(.subheadline)
                        .foregroundStyle(secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(accentPrimary)
                Text("Gefundene Web-Daten")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(primaryText)
            }
            statRow(icon: "text.book.closed", title: formattedCount(summary.subjectCount, singular: "Fach", plural: "Fächer"), subtitle: "aus der Web-App")
            statRow(icon: "number.square", title: formattedCount(summary.gradeCount, singular: "Note", plural: "Noten"), subtitle: "bestehende Bewertungen")
            if let gradeYear = summary.gradeYear {
                statRow(icon: "graduationcap", title: "Klassenstufe \(gradeYear)", subtitle: "aus Web-Einstellungen")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tileBackground)
                .shadow(color: shadowColor, radius: 14, x: 0, y: 10)
        )
    }

    private func optionButton(icon: String, title: String, subtitle: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(store.darkMode ? 0.22 : 0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(optionGradient(accent: accent))
                    .shadow(color: shadowColor, radius: 16, x: 0, y: 10)
            )
        }
        .buttonStyle(.plain)
    }

    private func statRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentPrimary.opacity(store.darkMode ? 0.18 : 0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryText)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }
            Spacer()
        }
    }

    private func formattedCount(_ value: Int, singular: String, plural: String) -> String {
        if value == 1 { return "1 \(singular)" }
        return "\(value) \(plural)"
    }

    private var accentPrimary: Color {
        if store.theme == "feminine" {
            return Color(hex: store.darkMode ? "#f472b6" : "#ec4899")
        }
        return .indigo
    }

    private var primaryText: Color {
        store.darkMode ? Color.white : Color(hex: "#0f172a")
    }

    private var secondaryText: Color {
        store.darkMode ? Color.white.opacity(0.78) : Color.secondary
    }

    private var tileBackground: LinearGradient {
        let top = accentPrimary.opacity(store.darkMode ? 0.16 : 0.08)
        let bottom = Color(.secondarySystemBackground)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func optionGradient(accent: Color) -> LinearGradient {
        let top = accent.opacity(store.darkMode ? 0.22 : 0.15)
        let bottom = Color(.secondarySystemBackground)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.38 : 0.16)
    }
}

