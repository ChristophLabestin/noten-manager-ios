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
            navButton(tab: .insights, icon: "chart.bar.fill", action: onOpenInsights)
            Spacer()
            addButton
            Spacer()
            navButton(tab: .final, icon: "graduationcap.fill", action: onOpenFinalGrade)
            Spacer()
            navButton(tab: .settings, icon: "gearshape.fill", action: onOpenSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(isDark ? 0.4 : 0.1), radius: 16, x: 0, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(isDark ? 0.1 : 0.5), lineWidth: 1)
        }
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
        .sheet(isPresented: $showFachreferatDetail) { NavigationStack { FachreferatDetailView(subject: Subject(name: "Fachreferat", type: 0, date: Date())).environmentObject(store) } }
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
                        .fill(activeColor.opacity(0.15))
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
                    .fill(activeColor)
                    .shadow(color: activeColor.opacity(0.3), radius: 6, x: 0, y: 3)
                
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 44)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func handleCreationAction(_ action: CreationAction) {
        showCreationMenu = false
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
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    
    private var accentColor: Color {
        if isFeminine {
            return isDark ? Color(hex: "#f472b6") : Color(hex: "#ec4899")
        }
        return isDark ? Color(hex: "#60a5fa") : Color(hex: "#2563eb")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Quick Actions Grid
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
                    
                    // More Options List
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Weitere Optionen")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        
                        VStack(spacing: 0) {
                            if showPractical {
                                listActionRow(title: "Praktikum", icon: "briefcase.fill", color: .mint, action: .practical)
                                Divider().padding(.leading, 52)
                            }
                            if showFachreferat {
                                listActionRow(title: hasFachreferat ? "Fachreferat anzeigen" : "Fachreferat", icon: hasFachreferat ? "slider.horizontal.3" : "doc.text.fill", color: .pink, disabled: !encryptionKeyLoaded || isFirstSubject, action: .fachreferat)
                                Divider().padding(.leading, 52)
                            }
                            if showSeminar {
                                listActionRow(title: "Seminarfach", icon: "doc.text.magnifyingglass", color: .purple, disabled: !encryptionKeyLoaded, action: .seminar)
                                Divider().padding(.leading, 52)
                            }
                            listActionRow(title: "Abitur", icon: "graduationcap.fill", color: .red, disabled: isFirstSubject, action: .abitur)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: Color.black.opacity(store.darkMode ? 0.2 : 0.05), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(20)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .navigationTitle("Erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
    
    private func quickActionCard(title: String, icon: String, color: Color, disabled: Bool = false, action: CreationAction) -> some View {
        Button {
            onAction(action)
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                color.opacity(store.darkMode ? 0.12 : 0.08),
                                Color(uiColor: .secondarySystemGroupedBackground)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(store.darkMode ? 0.2 : 0.05), radius: 8, x: 0, y: 4)
            .opacity(disabled ? 0.5 : 1)
        }
        .disabled(disabled)
        .buttonStyle(ScaleButtonStyle())
    }
    
    private func listActionRow(title: String, icon: String, color: Color, disabled: Bool = false, action: CreationAction) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .disabled(disabled)
        .buttonStyle(.plain)
        .opacity(disabled ? 0.5 : 1)
    }

    private var primaryText: Color {
        store.darkMode ? .white : .primary
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
