import SwiftUI
import FirebaseAuth

struct GroupsListView: View {
    @EnvironmentObject var store: GradesStore
    
    @ObservedObject private var notificationStore = NotificationInboxStore.shared
    var onOpenCreationMenu: () -> Void = {}
    
    // Toolbar Sheets State
    @State private var showNotifications = false
    @State private var showExamSheet = false
    @State private var showHomeworkSheet = false
    
    // Red Dot Logic
    private var hasOverdueExams: Bool {
        let now = Date()
        return store.allExams.contains { exam in
            !exam.isCompleted && exam.date < now
        }
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

    var body: some View {
        ClassesListView()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showNotifications = true
                } label: {
                    ToolbarIcon(
                        symbol: "bell",
                        showDot: notificationStore.hasUnread || (LaunchOfferNotificationManager.isOfferActive() && !UserDefaults.standard.bool(forKey: "launchOfferPurchased"))
                    )
                }
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
        .sheet(isPresented: $showNotifications) {
           NotificationsInboxView(
               inbox: notificationStore,
               onSelectNotification: { _ in },
               onOpenImportant: { NotificationCenter.default.post(name: .openLaunchOffer, object: nil) }
           )
           .environmentObject(store)
        }
    }
}


