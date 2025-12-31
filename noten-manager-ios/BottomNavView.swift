import SwiftUI

struct BottomNavView: View {
    @EnvironmentObject var store: GradesStore
    @Namespace private var namespace

    enum Tab {
        case home
        case insights
        case final
        case settings
    }

    let currentTab: Tab
    var isSubscriptionGateActive: Bool = false

    var onOpenHome: (() -> Void)?
    var onOpenFinalGrade: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenInsights: (() -> Void)?
    var onOpenAbitur: (() -> Void)?
    var onOpenPractical: (() -> Void)?

    var quickAddPreselectedSubjectName: String? = nil

    // Sheet States
    @State private var showCreationMenu: Bool = false
    
    @State private var showAddSubject: Bool = false
    @State private var showAddGrade: Bool = false
    @State private var showAddFachreferat: Bool = false
    @State private var showFachreferatDetail: Bool = false
    @State private var showAddHomework: Bool = false
    @State private var showAddExam: Bool = false
    @State private var showPractical: Bool = false
    @State private var showSeminar: Bool = false

    private var isFirstSubject: Bool { store.subjects.isEmpty }
    private var disableAddGrade: Bool { store.encryptionKey == nil || store.subjects.isEmpty }
    private var gradeYear: Int { store.gradeYear ?? 12 }

    private var addGradeTitle: String {
        if store.encryptionKey == nil { return "Lade Schlüssel..." }
        if store.subjects.isEmpty { return "Lege zuerst ein Fach an" }
        return ""
    }

    private var hasFachreferat: Bool { store.fachreferat != nil }

    private var showPracticalTab: Bool {
        store.schoolType == .fos && (gradeYear == 11 || gradeYear == 12)
    }

    private var showFachreferatAction: Bool { gradeYear == 12 }
    private var showSeminarAction: Bool {
        gradeYear >= 12 || store.seminarPerformance != nil
    }

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    
    private var activeColor: Color {
        if isFeminine {
            return isDark ? Color(hex: "#f472b6") : Color(hex: "#ec4899")
        }
        return isDark ? Color(hex: "#60a5fa") : Color(hex: "#2563eb")
    }

    var body: some View {
        HStack(spacing: 0) {
            navButton(tab: .home, icon: "house.fill", action: onOpenHome)
            Spacer()
            if !isSubscriptionGateActive {
                navButton(tab: .insights, icon: "chart.bar.fill", action: onOpenInsights)
                Spacer()
                addButton
                Spacer()
                navButton(tab: .final, icon: "graduationcap.fill", action: onOpenFinalGrade)
                Spacer()
            }
            navButton(tab: .settings, icon: "gearshape.fill", action: onOpenSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(navSurface)
        .overlay(navBorder)
        .padding(.horizontal, 20)
        .padding(.bottom, -10)
        .sheet(isPresented: $showCreationMenu) {
            CreationMenuView(
                onAction: handleCreationAction,
                isFirstSubject: isFirstSubject,
                disableAddGrade: disableAddGrade,
                showPractical: showPracticalTab,
                showFachreferat: showFachreferatAction,
                hasFachreferat: hasFachreferat,
                showSeminar: showSeminarAction,
                encryptionKeyLoaded: store.encryptionKey != nil
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddSubject) { AddSubjectView().environmentObject(store) }
        .sheet(isPresented: $showAddGrade) { AddGradeView(preselectedSubjectName: quickAddPreselectedSubjectName).environmentObject(store) }
        .sheet(isPresented: $showAddFachreferat) { AddFachreferatView(preselectedSubjectName: quickAddPreselectedSubjectName).environmentObject(store) }
        .sheet(isPresented: $showFachreferatDetail) {
            NavigationStack {
                FachreferatDetailView(subject: Subject(name: "Fachreferat", type: 0, date: Date()))
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showFachreferatDetail = false
                            } label: {
                                Image(systemName: "chevron.down")
                                    .imageScale(.medium)
                            }
                            .accessibilityLabel("Schließen")
                        }
                    }
            }
        }
        .sheet(isPresented: $showAddHomework) { AddHomeworkView(preselectedSubjectName: quickAddPreselectedSubjectName).environmentObject(store) }
        .sheet(isPresented: $showAddExam) { AddExamView(preselectedSubjectName: quickAddPreselectedSubjectName).environmentObject(store) }
        .sheet(isPresented: $showPractical) { NavigationStack { PraktikumDetailView().environmentObject(store) } }
        .sheet(isPresented: $showSeminar) { SeminarPerformanceView().environmentObject(store) }
    }

    private func navButton(tab: Tab, icon: String, action: (() -> Void)?) -> some View {
        let isSelected = currentTab == tab
        return Button {
            if !isSelected {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            action?()
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    activeColor.opacity(isDark ? 0.28 : 0.18),
                                    activeColor.opacity(isDark ? 0.12 : 0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(activeColor.opacity(isDark ? 0.45 : 0.28), lineWidth: 1)
                        )
                        .shadow(color: activeColor.opacity(isDark ? 0.35 : 0.2), radius: 6, x: 0, y: 3)
                        .matchedGeometryEffect(id: "TAB_BG", in: namespace)
                }
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? activeColor : .secondary)
                    .scaleEffect(isSelected ? 1.05 : 1.0)
            }
            .frame(width: 56, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var addButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showCreationMenu = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(addButtonGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(isDark ? 0.24 : 0.55), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isDark ? 0.18 : 0.32),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .blendMode(.screen)
                    )
                    .shadow(color: activeColor.opacity(isDark ? 0.45 : 0.3), radius: 10, x: 0, y: 6)

                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 46)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var navCornerRadius: CGFloat { 26 }

    private var navBaseTop: Color {
        if isDark {
            return isFeminine ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
        }
        return isFeminine ? Color(hex: "#fff1f7") : Color(hex: "#eef2ff")
    }

    private var navBaseBottom: Color {
        if isDark {
            return isFeminine ? Color(hex: "#120a16") : Color(hex: "#111827")
        }
        return isFeminine ? Color(hex: "#fff7fb") : Color(hex: "#f8fafc")
    }

    private var navSurface: some View {
        RoundedRectangle(cornerRadius: navCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [navBaseTop, navBaseBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: navCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                activeColor.opacity(isDark ? 0.18 : 0.1),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.5 : 0.14), radius: 14, x: 0, y: 8)
    }

    private var navBorder: some View {
        RoundedRectangle(cornerRadius: navCornerRadius, style: .continuous)
            .stroke(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
    }

    private var addButtonGradient: LinearGradient {
        LinearGradient(
            colors: [
                activeColor.opacity(isDark ? 0.85 : 0.95),
                activeColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func handleCreationAction(_ action: CreationAction) {
        showCreationMenu = false
        if isSubscriptionGateActive {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            switch action {
            case .homework: showAddHomework = true
            case .grade: showAddGrade = true
            case .exam: showAddExam = true
            case .subject: showAddSubject = true
            case .practical: 
                showPractical = true
                onOpenPractical?()
            case .fachreferat:
                if hasFachreferat { showFachreferatDetail = true }
                else { showAddFachreferat = true }
            case .seminar: showSeminar = true
            case .abitur: onOpenAbitur?()
            }
        }
    }
}

enum CreationAction {
    case homework, grade, exam, subject, practical, fachreferat, seminar, abitur
}

struct CreationMenuView: View {
    let onAction: (CreationAction) -> Void
    let isFirstSubject: Bool
    let disableAddGrade: Bool
    let showPractical: Bool
    let showFachreferat: Bool
    let hasFachreferat: Bool
    let showSeminar: Bool
    let encryptionKeyLoaded: Bool
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    quickActionsSection
                    moreOptionsSection
                }
                .padding(20)
            }
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Schnellaktionen")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                    }
                    .accessibilityLabel("Abbrechen")
                }
            }
        }
    }

    private var quickActionsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            quickActionCard(
                title: "Hausaufgabe",
                icon: "checklist",
                color: .cyan,
                disabled: isFirstSubject,
                action: .homework
            )
            quickActionCard(
                title: "Note",
                icon: "list.bullet.rectangle.portrait.fill",
                color: .indigo,
                disabled: disableAddGrade,
                action: .grade
            )
            quickActionCard(
                title: "Klausur",
                icon: "calendar.badge.clock",
                color: .orange,
                disabled: isFirstSubject,
                action: .exam
            )
            quickActionCard(
                title: "Fach",
                icon: "folder.badge.plus",
                color: .blue,
                action: .subject
            )
        }
    }

    private var moreOptionsSection: some View {
        VStack(spacing: 12) {
            if showPractical {
                listActionRow(title: "Praktikum", icon: "briefcase.fill", color: .mint, action: .practical)
            }
            if showFachreferat {
                listActionRow(title: hasFachreferat ? "Fachreferat anzeigen" : "Fachreferat", icon: hasFachreferat ? "slider.horizontal.3" : "doc.text.fill", color: .pink, disabled: !encryptionKeyLoaded || isFirstSubject, action: .fachreferat)
            }
            if showSeminar {
                listActionRow(title: "Seminarfach", icon: "doc.text.magnifyingglass", color: .purple, disabled: !encryptionKeyLoaded, action: .seminar)
            }
            listActionRow(title: "Abitur", icon: "graduationcap.fill", color: .red, disabled: isFirstSubject, action: .abitur)
        }
    }
    
    private func quickActionCard(title: String, icon: String, color: Color, disabled: Bool = false, action: CreationAction) -> some View {
        Button {
            onAction(action)
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isDark ? 0.22 : 0.16))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                cardSurface(accent: color, cornerRadius: 20)
                    .shadow(color: cardShadow, radius: 8, x: 0, y: 4)
            )
            .overlay(
                cardBorder(accent: color, cornerRadius: 20)
            )
            .opacity(disabled ? 0.45 : 1)
        }
        .disabled(disabled)
        .buttonStyle(ScaleButtonStyle())
    }
    
    private func listActionRow(title: String, icon: String, color: Color, disabled: Bool = false, action: CreationAction) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isDark ? 0.2 : 0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryText)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                cardSurface(accent: color, cornerRadius: 18)
                    .shadow(color: rowShadow, radius: 10, x: 0, y: 6)
            )
            .overlay(
                cardBorder(accent: color, cornerRadius: 18)
            )
        }
        .disabled(disabled)
        .buttonStyle(.plain)
        .opacity(disabled ? 0.45 : 1)
    }

    private var primaryText: Color {
        isDark ? .white : Color(hex: "#0f172a")
    }

    private var secondaryText: Color {
        isDark ? Color.white.opacity(0.75) : Color.secondary
    }

    private var cardShadow: Color {
        Color.black.opacity(isDark ? 0.42 : 0.1)
    }

    private var rowShadow: Color {
        Color.black.opacity(isDark ? 0.36 : 0.08)
    }

    private var cardTop: Color {
        if isDark {
            return isFeminine ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
        }
        return isFeminine ? Color(hex: "#fff1f7") : Color(hex: "#eef2ff")
    }

    private var cardBottom: Color {
        if isDark {
            return isFeminine ? Color(hex: "#120a16") : Color(hex: "#111827")
        }
        return isFeminine ? Color(hex: "#fff7fb") : Color(hex: "#f8fafc")
    }

    private func cardSurface(accent: Color, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [cardTop, cardBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(isDark ? 0.14 : 0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private func cardBorder(accent: Color, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(accent.opacity(isDark ? 0.22 : 0.12), lineWidth: 1)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
