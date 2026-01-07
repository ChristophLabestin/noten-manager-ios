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

struct MainView: View {
    let onLogout: () -> Void
    @Binding var incomingHomeworkShare: HomeworkShareLinkPayload?
    @Binding var incomingExamId: String?
    @Binding var deeplinkDestination: DeeplinkDestination?
    @StateObject private var gradesStore = GradesStore()
    @StateObject private var notificationInbox = NotificationInboxStore.shared
    @State private var currentTab: BottomNavView.Tab = .home
    @EnvironmentObject private var offlineManager: OfflineModeManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var biometricManager: BiometricAuthManager
    @EnvironmentObject private var storeKit: StoreKitManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("launchMessageSeen_2026_paid") private var launchMessageSeen = false
    @AppStorage("launchOfferPurchased") private var launchOfferPurchased = false
#if DEBUG
    @AppStorage(LaunchOfferNotificationManager.debugForceFebruaryKey) private var debugForceFebruary = false
#endif
    @State private var navPath = NavigationPath()
    @State private var showOnboardingFunnel: Bool = false
    @State private var offlineBannerVisible: Bool = false
    @State private var offlineBannerDismissTask: Task<Void, Never>?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var showPfingstferienPrompt: Bool = false
    @State private var nextSchoolYearSuggestion: String?
    @State private var spinnerAnimating: Bool = false
    @State private var emailBannerVisible: Bool = false
    @State private var emailBannerDismissTask: Task<Void, Never>?
    @State private var needsEmailVerification: Bool = false
    @State private var scrollToAccountOnOpen: Bool = false
    @State private var showNotificationsSheet: Bool = false
    @State private var pendingNotificationAction: NotificationInboxItem?
    @State private var pendingOpenLaunchMessageFromInbox: Bool = false
    @State private var showLaunchMessage: Bool = false
    @State private var showLaunchLaterReminder: Bool = false
    @State private var pendingLaunchLaterReminder: Bool = false
    @State private var showSubscriptionOffer: Bool = false
    @State private var showSubscriptionPurchaseSuccess: Bool = false
    @State private var pendingSubscriptionPurchaseSuccess: Bool = false
    @State private var subscriptionOfferShownThisSession: Bool = false
    @State private var showLaunchPurchaseSuccess: Bool = false
    @State private var pendingLaunchPurchaseSuccess: Bool = false

    // Von SubjectDetail per Preference gemeldetes Fach für „Note hinzufügen“
    @State private var quickAddSubjectName: String? = nil
    @State private var navigateToAbiturExam: Bool = false
    @State private var deeplinkExamId: String? = nil
    @State private var deeplinkExam: Exam? = nil
    @State private var deeplinkHomework: Homework? = nil
    @State private var showExamListSheet: Bool = false
    @State private var showHomeworkListSheet: Bool = false

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
                showLaunchMessageIfNeeded()
                Task { await showSubscriptionOfferIfNeeded() }
                notificationInbox.refreshFromDelivered()
                scheduleLaunchOfferNotifications(purchased: launchOfferPurchased)
                if LaunchOfferNotificationManager.consumePendingOpen() {
                    handleOpenLaunchOfferNotification()
                }
                enforceSubscriptionGateIfNeeded()
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
#if DEBUG
            .onChange(of: debugForceFebruary) { _, _ in
                enforceSubscriptionGateIfNeeded()
            }
#endif
            .preferredColorScheme(gradesStore.preferredColorScheme)

        let onboardingTracking = base
            .onChange(of: gradesStore.onboardingRequired) { _, required in
                showOnboardingFunnel = required
            }
            .onChange(of: gradesStore.gradeYear) {
                Task { await evaluatePfingstferienPrompt() }
            }
            .onChange(of: gradesStore.activeSchoolYearId) {
                Task { await evaluatePfingstferienPrompt() }
            }
            .onChange(of: gradesStore.isLoading) { _, loading in
                spinnerAnimating = loading
                if !loading {
                    showOnboardingFunnel = gradesStore.onboardingRequired
                } else if gradesStore.onboardingRequired {
                    showOnboardingFunnel = true
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
            .onChange(of: gradesStore.allExams) {
                self.handleDeeplinkExam()
                Task {
                    await ExamLiveActivityManager.syncLiveActivities(for: gradesStore.allExams)
                    BackgroundRefreshManager.schedule(for: gradesStore.allExams)
                }
            }

        let lifecycle = deeplinkTracking
            .sheet(isPresented: $showOnboardingFunnel) {
                OnboardingFunnelView {
                    showOnboardingFunnel = false
                }
                .environmentObject(gradesStore)
                .environmentObject(authManager)
            }
            .task {
                await handleDataLoading()
                await refreshEmailVerification()
            }
            .onChange(of: offlineManager.isOfflineModeActive) { _, active in
                Task {
                    await handleOfflineToggle(active: active)
                }
            }
            .onChange(of: authManager.isAuthenticated) {
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
                    showLaunchMessageIfNeeded()
                    Task { await showSubscriptionOfferIfNeeded() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLaunchOffer)) { _ in
                handleOpenLaunchOfferNotification()
            }
            .onChange(of: gradesStore.legacyMigrationSummary) { _, summary in
                if summary != nil {
                    showOnboardingFunnel = true
                }
            }

        let overlays = lifecycle
            .overlay(alignment: .center) {
                if gradesStore.isLoading {
                    loadingOverlay
                }
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

        overlays
            .sheet(isPresented: $showExamListSheet, onDismiss: {
                deeplinkDestination = nil
            }) {
                ExamListView()
                    .environmentObject(gradesStore)
            }
            .sheet(isPresented: $showHomeworkListSheet, onDismiss: {
                deeplinkDestination = nil
            }) {
                HomeworkListView()
                    .environmentObject(gradesStore)
            }
            .sheet(isPresented: $showNotificationsSheet, onDismiss: handleNotificationsSheetDismiss) {
                NotificationsInboxView(
                    inbox: notificationInbox,
                    onSelectNotification: { item in
                        pendingNotificationAction = item
                    },
                    onOpenImportant: {
                        pendingOpenLaunchMessageFromInbox = true
                    }
                )
                .environmentObject(gradesStore)
            }
            .sheet(isPresented: $showLaunchMessage, onDismiss: {
                launchMessageSeen = true
                if pendingLaunchLaterReminder {
                    showLaunchLaterReminder = true
                    pendingLaunchLaterReminder = false
                }
                if pendingLaunchPurchaseSuccess {
                    showLaunchPurchaseSuccess = true
                    pendingLaunchPurchaseSuccess = false
                }
            }) {
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
            }
            .sheet(isPresented: $showSubscriptionOffer, onDismiss: {
                if pendingSubscriptionPurchaseSuccess {
                    showSubscriptionPurchaseSuccess = true
                    pendingSubscriptionPurchaseSuccess = false
                }
            }) {
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
            }
            .sheet(item: $deeplinkExam) { exam in
                ExamDetailSheet(exam: exam, onEdit: { _ in })
                    .environmentObject(gradesStore)
            }
            .sheet(item: $deeplinkHomework) { homework in
                HomeworkDetailSheet(homework: homework, onEdit: { _ in })
                    .environmentObject(gradesStore)
            }
            .toolbar {
                if navPath.isEmpty {
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        notificationsToolbarButton
                        if offlineManager.isOfflineModeActive {
                            offlineToolbarButton
                        }
                        if needsEmailVerification {
                            emailVerificationToolbarButton
                        }
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
            .sheet(isPresented: $showLaunchLaterReminder) {
                ReminderConfirmationView()
                    .environmentObject(gradesStore)
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
    }

    @MainActor
    private func handleDataLoading() async {
        if offlineManager.isOfflineModeActive {
            if let snapshot = offlineManager.cachedSnapshot ?? offlineManager.availableSnapshot() {
                gradesStore.loadOfflineSnapshot(snapshot)
            }
            showOfflineBannerTemporarily()
            await refreshEmailVerification()
            await evaluatePfingstferienPrompt()
            if gradesStore.onboardingRequired {
                showOnboardingFunnel = true
            }
            return
        }

        // Fallback: wenn kein Internet, aber ein Snapshot existiert und innerhalb 3 Tage ist, direkt offline laden
        if !offlineManager.isOnline {
            if let snapshot = offlineManager.availableSnapshot(),
               offlineManager.isOfflineLoginAllowed(for: snapshot.userId) {
                gradesStore.loadOfflineSnapshot(snapshot)
                showOfflineBannerTemporarily()
                await refreshEmailVerification()
                await evaluatePfingstferienPrompt()
                if gradesStore.onboardingRequired {
                    showOnboardingFunnel = true
                }
                return
            }
        }

        OfflineModeManager.shared.enableFirestoreNetworkIfNeeded()
        await gradesStore.syncOfflinePendingChanges(forceLocalOverride: true)

        gradesStore.leaveOfflineModePreservingState()
        await gradesStore.startListening()
        hideOfflineBanner()
        await evaluatePfingstferienPrompt()
        if gradesStore.onboardingRequired {
            showOnboardingFunnel = true
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
                if gradesStore.onboardingRequired {
                    showOnboardingFunnel = true
                }
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
        let created = await gradesStore.createSchoolYear(name: id)
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

    private var notificationsToolbarButton: some View {
        Button {
            showNotificationsSheet = true
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
            Image(systemName: "wifi.slash")
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
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
        VStack(spacing: 10) {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("E-Mail noch nicht bestätigt")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.white)
                Text("Bitte bestätige deine Adresse über die E-Mail, die wir gesendet haben.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(1))
            }
            Spacer()

            Button {
                hideEmailBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(1))
            }
            .buttonStyle(.plain)
        }
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(1))
        )
        .padding(.horizontal, 16)
    }

    private var emailVerificationToolbarButton: some View {
        Button {
            showEmailBannerTemporarily()
        } label: {
            Image(systemName: "info.circle.fill")
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.orange.opacity(0.85))
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
        guard !launchMessageSeen else { return }
        guard !launchOfferPurchased else { return }
        guard LaunchOfferNotificationManager.isOfferActive() else { return }
        guard !showLaunchMessage else { return }
        showLaunchMessage = true
    }

    @MainActor
    private func showSubscriptionOfferIfNeeded() async {
        guard authManager.isAuthenticated else { return }
        guard currentTab == .home else { return }
        guard !LaunchOfferNotificationManager.isOfferActive() else { return }
        guard !launchOfferPurchased else { return }
        guard !showSubscriptionOffer else { return }
        guard !subscriptionOfferShownThisSession else { return }
        let isActive = await storeKit.refreshSubscriptionStatus()
        guard !isActive else { return }
        showSubscriptionOffer = true
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
        currentTab = .home
        showNotificationsSheet = false
        pendingOpenLaunchMessageFromInbox = false
        showLaunchMessage = true
    }

    private func handleNotificationsSheetDismiss() {
        if pendingOpenLaunchMessageFromInbox {
            pendingOpenLaunchMessageFromInbox = false
            showLaunchMessage = true
            return
        }
        guard let item = pendingNotificationAction else { return }
        pendingNotificationAction = nil
        openInboxNotification(item)
    }

    private func openInboxNotification(_ item: NotificationInboxItem) {
        currentTab = .home
        switch item.kind {
        case .exam:
            if let examId = item.examId,
               let exam = gradesStore.allExams.first(where: { $0.id == examId }) {
                deeplinkExam = exam
            } else {
                showExamListSheet = true
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
                    showHomeworkListSheet = true
                }
            } else {
                showHomeworkListSheet = true
            }
        case .daily:
            let examIds = item.examIds ?? (item.examId.map { [$0] } ?? [])
            if examIds.count > 1 {
                showExamListSheet = true
                return
            }
            if let examId = examIds.first,
               let exam = gradesStore.allExams.first(where: { $0.id == examId }) {
                deeplinkExam = exam
                return
            }
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
                    showHomeworkListSheet = true
                }
            } else {
                showExamListSheet = true
            }
        default:
            break
        }
    }

    @MainActor
    private func refreshEmailVerification() async {
        guard let user = Auth.auth().currentUser else {
            needsEmailVerification = false
            emailBannerVisible = false
            return
        }
        do {
            try await user.reload()
            needsEmailVerification = !user.isEmailVerified
            if !needsEmailVerification {
                hideEmailBanner()
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            needsEmailVerification = false
            hideEmailBanner()
        }
    }

    @ViewBuilder
    private var navigationContainer: some View {
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
                    AppSettingsView(scrollToAccount: scrollToAccountOnOpen)
                        .environmentObject(gradesStore)
                        .environmentObject(authManager)
                        .environmentObject(offlineManager)
                        .environmentObject(biometricManager)
                }
            }
        }
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
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 100)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .bottom) {
            BottomNavView(
                currentTab: currentTab,
                isSubscriptionGateActive: isSubscriptionGateActive,
                onOpenHome: { openTab(.home) },
                onOpenFinalGrade: { openTab(.final) },
                onOpenSettings: { openTab(.settings) },
                onOpenInsights: { openTab(.insights) },
                onOpenAbitur: {
                    if isSubscriptionGateActive {
                        presentSubscriptionGate()
                        return
                    }
                    navigateToAbiturExam = true
                },
                quickAddPreselectedSubjectName: quickAddSubjectName
            )
            .environmentObject(gradesStore)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private var isSubscriptionGateActive: Bool {
#if DEBUG
        _ = debugForceFebruary
#endif
        guard LaunchOfferNotificationManager.isSubscriptionGateActive() else { return false }
        if launchOfferPurchased { return false }
        if storeKit.isSubscriptionActive { return false }
        return true
    }

    private func isTabAllowed(_ tab: BottomNavView.Tab) -> Bool {
        if !isSubscriptionGateActive {
            return true
        }
        return tab == .home || tab == .settings
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
        guard isSubscriptionGateActive else { return }
        guard !showSubscriptionOffer else { return }
        showSubscriptionOffer = true
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
                        showOnboardingFunnel = true
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
        guard let destination else { return }
        currentTab = .home
        switch destination {
        case .examList:
            showExamListSheet = true
        case .homeworkList:
            showHomeworkListSheet = true
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
