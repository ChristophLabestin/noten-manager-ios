import SwiftUI

struct BottomNavView: View {
    @EnvironmentObject var store: GradesStore

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

    @State private var isOpen: Bool = false
    @State private var showAddSubject: Bool = false
    @State private var showAddGrade: Bool = false
    @State private var showAddFachreferat: Bool = false
    @State private var showAddHomework: Bool = false
    @State private var showAddExam: Bool = false
    @State private var showPractical: Bool = false
    @State private var fabPressed: Bool = false

    private var isFirstSubject: Bool { store.subjects.isEmpty }
    private var disableAddGrade: Bool { store.encryptionKey == nil || store.subjects.isEmpty }

    private var addGradeTitle: String {
        if store.encryptionKey == nil { return "Lade Schlüssel..." }
        if store.subjects.isEmpty { return "Lege zuerst ein Fach an" }
        return ""
    }

    private var hasFachreferat: Bool { store.fachreferat != nil }

    private var showPracticalTab: Bool {
        store.schoolType == .fos && (store.gradeYear == 11 || store.gradeYear == 12)
    }

    private let fabSize: CGFloat = 56
    private let barHeight: CGFloat = 72

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }

    private var colorPrimary: Color { Color(hex: "#1e3a8a") }
    private var colorPrimaryHover: Color { Color(hex: "#2563eb") }
    private var colorPrimaryDark: Color { Color(hex: "#3b82f6") }
    private var colorPrimaryHoverDark: Color { Color(hex: "#60a5fa") }
    private var colorPrimaryFem: Color { Color(hex: "#ec4899") }
    private var colorPrimaryFemHover: Color { Color(hex: "#f472b6") }

    private var colorTextDark: Color { Color(hex: "#111827") }
    private var colorTextDarkDark: Color { Color(hex: "#f9fafb") }
    private var colorTextMedium: Color { Color(hex: "#6b7280") }
    private var colorTextMediumDark: Color { Color(hex: "#d1d5db") }

    private var accentPrimary: Color {
        if isFeminine { return isDark ? colorPrimaryFemHover : colorPrimaryFem }
        return isDark ? colorPrimaryDark : colorPrimary
    }

    private var accentSecondary: Color {
        if isFeminine { return colorPrimaryFemHover }
        return isDark ? colorPrimaryHoverDark : colorPrimaryHover
    }

    private var labelPrimary: Color { isDark ? colorTextDarkDark : colorTextDark }
    private var labelSecondary: Color { isDark ? colorTextMediumDark : colorTextMedium }

    private var surface: Color {
        isDark ? Color(red: 0.07, green: 0.09, blue: 0.14) : Color.white
    }

    private var navStroke: Color {
        isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.06)
    }

    private var navShadow: Color {
        isDark ? Color.black.opacity(0.65) : Color.black.opacity(0.18)
    }

    private var activeIconGlow: Color {
        accentPrimary.opacity(isDark ? 0.45 : 0.18)
    }

    private var navBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        surface.opacity(isDark ? 0.86 : 0.96),
                        accentPrimary.opacity(isDark ? 0.24 : 0.2),
                        surface.opacity(isDark ? 0.78 : 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.16 : 0.3),
                                accentPrimary.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: navShadow.opacity(0.9), radius: 14, x: 0, y: 10)
    }

    private var activeIconBackground: LinearGradient {
        LinearGradient(
            colors: [
                accentPrimary,
                accentSecondary.opacity(isDark ? 0.9 : 0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var inactiveIconBackground: LinearGradient {
        LinearGradient(
            colors: [
                surface.opacity(isDark ? 0.8 : 0.94),
                surface.opacity(isDark ? 0.68 : 0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { geo in
            let bottomInset = geo.safeAreaInsets.bottom
            let barWidth = min(geo.size.width - 32, 500)
            let bottomPadding = bottomInset == 0 ? 2 : max(0, bottomInset - 8)

            ZStack(alignment: .bottom) {
                HStack(spacing: 14) {
                    navItem(icon: "house.fill", label: "Home", tab: .home, disabled: false) { onOpenHome?() }
                    navItem(icon: "chart.bar.fill", label: "Insights", tab: .insights, disabled: isFirstSubject) { onOpenInsights?() }

                    fabButton

                    navItem(icon: "book.fill", label: "Abschluss", tab: .final, disabled: isFirstSubject) { onOpenFinalGrade?() }
                    navItem(icon: "gearshape.fill", label: "Einstellungen", tab: .settings, disabled: false) { onOpenSettings?() }
                }
                .padding(.horizontal, 18)
                .frame(width: barWidth, height: barHeight)
                .background(navBackground)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: navShadow, radius: 14, x: 0, y: 10)
                .padding(.bottom, bottomPadding)
                .overlay(alignment: .top) {
                    if isFirstSubject && !isOpen {
                        hintBubble
                            .offset(y: -72)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay(
                Group {
                    if isOpen {
                        actionsOverlay(bottomInset: bottomInset)
                    }
                }
            )
            .ignoresSafeArea(edges: .bottom)
            .sheet(isPresented: $showAddSubject) {
                AddSubjectView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAddGrade) {
                AddGradeView(preselectedSubjectName: quickAddPreselectedSubjectName)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAddFachreferat) {
                AddFachreferatView(preselectedSubjectName: quickAddPreselectedSubjectName)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAddHomework) {
                AddHomeworkView(preselectedSubjectName: quickAddPreselectedSubjectName)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAddExam) {
                AddExamView(preselectedSubjectName: quickAddPreselectedSubjectName)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showPractical) {
                PracticalTrainingView()
                    .environmentObject(store)
            }
        }
    }

    // MARK: - Subviews

    private func navItem(icon: String, label: String, tab: Tab, disabled: Bool, action: @escaping () -> Void) -> some View {
        let active = (currentTab == tab)
        return Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            active
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        accentPrimary.opacity(isDark ? 0.42 : 0.32),
                                        accentSecondary.opacity(isDark ? 0.38 : 0.26)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        surface.opacity(isDark ? 0.9 : 0.98),
                                        surface.opacity(isDark ? 0.78 : 0.9)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(active ? accentPrimary.opacity(isDark ? 0.9 : 0.7) : navStroke, lineWidth: 1)
                        )
                        .shadow(color: active ? accentPrimary.opacity(isDark ? 0.4 : 0.2) : Color.black.opacity(isDark ? 0.18 : 0.05),
                                radius: active ? 10 : 4,
                                x: 0,
                                y: active ? 7 : 3)
                        .frame(width: 48, height: 42)

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            active
                            ? Color.white
                            : accentPrimary.opacity(disabled ? 0.35 : 0.8)
                        )
                        .padding(.horizontal, 4)
                }

                Capsule()
                    .fill(active ? accentPrimary : labelSecondary.opacity(0.25))
                    .frame(width: active ? 28 : 10, height: 3)
                    .opacity(disabled ? 0.2 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .opacity(disabled ? 0.55 : 1)
            .scaleEffect(active ? 1.03 : 1.0)
            .animation(.easeOut(duration: 0.16), value: active)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private var fabButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isOpen.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(accentPrimary.opacity(0.08))
                    .frame(width: fabSize + 16, height: fabSize + 16)
                    .blur(radius: 3)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accentPrimary,
                                accentSecondary.opacity(isDark ? 0.92 : 0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isDark ? 0.22 : 0.4), lineWidth: 1.1)
                    )
                    .frame(width: fabSize, height: fabSize)
                    .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.12),
                            radius: fabPressed ? 8 : 10,
                            x: 0,
                            y: fabPressed ? 6 : 9)

                Image(systemName: isOpen ? "xmark" : "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .scaleEffect(isOpen ? 0.96 : 1.05)
            }
        }
        .frame(width: max(fabSize, 56), height: barHeight)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.08)) { fabPressed = true } }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.12)) { fabPressed = false } }
        )
        .scaleEffect(fabPressed ? 0.96 : 1.0)
        .accessibilityLabel("Schnelle Aktionen öffnen")
    }

    private var hintBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Noch kein Fach?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(labelPrimary)
            Text("Lege dein erstes Fach an, dann kannst du sofort Noten hinzufügen.")
                .font(.system(size: 13))
                .foregroundStyle(labelSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            surface.opacity(isDark ? 0.92 : 0.98),
                            accentPrimary.opacity(isDark ? 0.18 : 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(navStroke, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(isDark ? 0.55 : 0.16), radius: 12, x: 0, y: 6)
        .frame(maxWidth: 260, alignment: .leading)
    }

    private func actionsOverlay(bottomInset: CGFloat) -> some View {
        GeometryReader { _ in
            ZStack {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.3)) { isOpen = false }
                    }

                VStack(spacing: 0) {
                    Spacer()
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(activeIconBackground)
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Schnelle Aktionen")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(labelPrimary)
                                Text("Leg sofort los, ohne die Seite zu verlassen.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(labelSecondary)
                            }
                            Spacer()
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { isOpen = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(labelSecondary)
                                    .padding(10)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(isDark ? 0.08 : 0.92))
                                            .overlay(
                                                Circle()
                                                    .stroke(navStroke, lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(spacing: 10) {
                            ActionButton(
                                iconContent: AnyView(Image(systemName: "checklist").font(.system(size: 17, weight: .semibold))),
                                label: "Hausaufgabe",
                                description: "Aufgabe mit Fach & Termin",
                                disabled: store.subjects.isEmpty,
                                title: store.subjects.isEmpty ? "Lege zuerst ein Fach an" : ""
                            ) {
                                isOpen = false
                                showAddHomework = true
                            }

                            ActionButton(
                                iconContent: AnyView(Image(systemName: "list.bullet.rectangle.portrait.fill").font(.system(size: 17, weight: .semibold))),
                                label: "Note",
                                description: "Einzelne Leistung eintragen",
                                disabled: disableAddGrade,
                                title: addGradeTitle
                            ) {
                                isOpen = false
                                showAddGrade = true
                            }

                            ActionButton(
                                iconContent: AnyView(Image(systemName: "calendar.badge.clock").font(.system(size: 17, weight: .semibold))),
                                label: "Klausurtermin",
                                description: "Termin & Fach wählen",
                                disabled: store.subjects.isEmpty,
                                title: store.subjects.isEmpty ? "Lege zuerst ein Fach an" : ""
                            ) {
                                isOpen = false
                                showAddExam = true
                            }

                            ActionButton(
                                iconContent: AnyView(Image(systemName: "folder.badge.plus").font(.system(size: 17, weight: .semibold))),
                                label: "Fach",
                                description: "Neues Fach anlegen",
                                disabled: false,
                                title: ""
                            ) {
                                isOpen = false
                                showAddSubject = true
                            }

                            if showPracticalTab {
                                ActionButton(
                                    iconContent: AnyView(Image(systemName: "briefcase.fill").font(.system(size: 17, weight: .semibold))),
                                    label: "Praktikum",
                                    description: "Fachpraktische Ausbildung",
                                    disabled: false,
                                    title: ""
                                ) {
                                    isOpen = false
                                    showPractical = true
                                    onOpenPractical?()
                                }
                            }

                            ActionButton(
                                iconContent: AnyView(
                                    Group {
                                        if hasFachreferat {
                                            Image(systemName: "slider.horizontal.3")
                                                .font(.system(size: 17, weight: .semibold))
                                        } else {
                                            Image(systemName: "doc.text.fill")
                                                .font(.system(size: 17, weight: .semibold))
                                        }
                                    }
                                ),
                                label: hasFachreferat ? "Fachreferat bearbeiten" : "Fachreferat",
                                description: hasFachreferat ? "Bestehendes Fachreferat" : "Fachreferatsnote anlegen",
                                disabled: store.encryptionKey == nil || isFirstSubject,
                                title: store.encryptionKey == nil ? "Lade Schlüssel..." : (isFirstSubject ? "Lege zuerst ein Fach an" : "")
                            ) {
                                isOpen = false
                                showAddFachreferat = true
                            }

                            ActionButton(
                                iconContent: AnyView(Image(systemName: "graduationcap.fill").font(.system(size: 17, weight: .semibold))),
                                label: "Abitur",
                                description: "Abschlussprüfung eintragen",
                                disabled: isFirstSubject,
                                title: isFirstSubject ? "Lege zuerst ein Fach an" : ""
                            ) {
                                isOpen = false
                                onOpenAbitur?()
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        surface,
                                        surface
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(navStroke.opacity(isDark ? 0.9 : 1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(isDark ? 0.8 : 0.2), radius: isDark ? 28 : 16, x: 0, y: isDark ? 18 : 10)
                    .padding(.horizontal, 16)
                    .padding(.bottom, bottomInset + fabSize + 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.3), value: isOpen)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct ActionButton: View {
    let iconContent: AnyView
    let label: String
    let description: String
    let disabled: Bool
    let title: String
    let onTap: () -> Void

    @EnvironmentObject var store: GradesStore

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }

    private var colorPrimary: Color { Color(hex: "#1e3a8a") }
    private var colorPrimaryDark: Color { Color(hex: "#3b82f6") }
    private var colorPrimaryFem: Color { Color(hex: "#ec4899") }
    private var colorPrimaryFemHover: Color { Color(hex: "#f472b6") }

    private var colorTextDark: Color { Color(hex: "#111827") }
    private var colorTextDarkDark: Color { Color(hex: "#f9fafb") }
    private var colorTextMedium: Color { Color(hex: "#6b7280") }
    private var colorTextMediumDark: Color { Color(hex: "#d1d5db") }

    private var accentPrimary: Color {
        if isFeminine { return isDark ? colorPrimaryFemHover : colorPrimaryFem }
        return isDark ? colorPrimaryDark : colorPrimary
    }

    private var accentSecondary: Color {
        if isFeminine { return colorPrimaryFemHover }
        return isDark ? Color(hex: "#60a5fa") : Color(hex: "#2563eb")
    }

    private var labelColor: Color { isDark ? colorTextDarkDark : colorTextDark }
    private var descriptionColor: Color { isDark ? colorTextMediumDark : colorTextMedium }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconGradient)
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(isDark ? 0.22 : 0.4), lineWidth: 1)
                        )
                    iconContent
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(labelColor)
                    Text(title.isEmpty ? description : title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(descriptionColor)
                        .lineLimit(2)
                }
                Spacer()
                Circle()
                    .fill(descriptionColor.opacity(0.15))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(descriptionColor.opacity(0.9))
                    )
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(buttonBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(buttonBorder, lineWidth: 1)
                    )
                    .overlay(
                        LinearGradient(
                            colors: [
                                accentPrimary.opacity(isDark ? 0.25 : 0.18),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 6)
                        .mask(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        ),
                        alignment: .leading
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.42 : 0.12), radius: 10, x: 0, y: 6)
        }
        .disabled(disabled)
        .buttonStyle(.plain)
        .opacity(disabled ? 0.55 : 1.0)
    }

    private var buttonBackground: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [
                    Color(red: 0.12, green: 0.15, blue: 0.22).opacity(0.96),
                    Color(red: 0.07, green: 0.08, blue: 0.12).opacity(0.94)
                ]
                : [
                    Color.white.opacity(0.96),
                    Color.white.opacity(0.90)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var buttonBorder: LinearGradient {
        LinearGradient(
            colors: [
                accentSecondary.opacity(isDark ? 0.55 : 0.35),
                Color.white.opacity(isDark ? 0.16 : 0.24)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: [
                accentPrimary,
                accentSecondary.opacity(isDark ? 0.85 : 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
