import SwiftUI
import CryptoKit

struct BottomNavView: View {
    @EnvironmentObject var store: GradesStore

    enum Tab {
        case home
        case insights
        case final
        case settings
    }

    // Aktueller Tab (für Active-Dot)
    let currentTab: Tab

    // Callbacks für Navigation (echte Seiten)
    var onOpenHome: (() -> Void)?
    var onOpenFinalGrade: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenInsights: (() -> Void)?
    var onOpenAbitur: (() -> Void)?

    // Optional: Vorauswahl für "Note hinzufügen" (z. B. auf SubjectDetail)
    var quickAddPreselectedSubjectName: String? = nil

    @State private var isOpen: Bool = false
    @State private var showAddSubject: Bool = false
    @State private var showAddGrade: Bool = false
    @State private var showAddFachreferat: Bool = false
    @State private var showAddHomework: Bool = false
    @State private var showAddExam: Bool = false

    // Press-Feedback für FAB
    @State private var fabPressed: Bool = false

    private var isFirstSubject: Bool {
        store.subjects.isEmpty
    }

    private var disableAddGrade: Bool {
        store.encryptionKey == nil || store.subjects.isEmpty
    }

    private var addGradeTitle: String {
        if store.encryptionKey == nil { return "Lade Schlüssel..." }
        if store.subjects.isEmpty { return "Lege zuerst ein Fach an" }
        return ""
    }

    private var hasFachreferat: Bool {
        store.fachreferat != nil
    }

    // Theme/Colors aus variables.scss
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }

    // variables.scss Farben (hex) als SwiftUI Colors
    private var colorPrimary: Color { Color(hex: "#1e3a8a") } // $color-primary
    private var colorPrimaryHover: Color { Color(hex: "#2563eb") } // $color-primary-hover
    private var colorPrimaryDark: Color { Color(hex: "#3b82f6") } // $color-primary-dark
    private var colorPrimaryHoverDark: Color { Color(hex: "#60a5fa") } // $color-primary-hover-dark
    private var colorPrimaryFem: Color { Color(hex: "#ec4899") } // $color-primary-feminine
    private var colorPrimaryFemHover: Color { Color(hex: "#f472b6") } // $color-primary-feminine-hover

    private var colorTextDark: Color { Color(hex: "#111827") } // $color-text-dark
    private var colorTextDarkDark: Color { Color(hex: "#f9fafb") } // $color-text-dark-dark
    private var colorTextMedium: Color { Color(hex: "#6b7280") } // $color-text-medium
    private var colorTextMediumDark: Color { Color(hex: "#d1d5db") } // $color-text-medium-dark

    private var colorBgLightDark: Color { Color(hex: "#1f2937") } // $color-bg-light-dark
    private var colorBgDarkDark: Color { Color(hex: "#1b478e") } // $color-bg-dark-dark

    private var barBackground: some View {
        Group {
            if isDark {
                // body.dark-mode .bottom-nav-bar – unabhängig vom Theme
                Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.96)
            } else if isFeminine {
                // body.theme-feminine .bottom-nav-bar
                LinearGradient(
                    gradient: Gradient(colors: [colorPrimaryFem, colorPrimaryFemHover]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                // Standard-Theme im Light Mode
                colorBgDarkDark
            }
        }
        .clipShape(RoundedBarShape())
        .shadow(color: (isDark ? Color.black.opacity(0.8) : Color.black.opacity(0.45)),
                radius: isDark ? 18 : 12, x: 0, y: isDark ? 10 : 6)
    }

    var body: some View {
        GeometryReader { geo in
            let bottomInset = geo.safeAreaInsets.bottom
            let barWidth = min(geo.size.width - 32, 420) // 16pt Rand pro Seite, max 420pt Breite
            ZStack(alignment: .bottom) {
                // Bottom Bar – volle Breite mit symmetrischem Abstand
                HStack {
                    navItem(icon: "house.fill", active: currentTab == .home, disabled: false) {
                        onOpenHome?()
                    }
                    navItem(icon: "chart.bar.fill", active: currentTab == .insights, disabled: isFirstSubject) {
                        onOpenInsights?()
                    }

                    // Spacer für FAB (56px)
                    Color.clear.frame(width: 56, height: 1)

                    navItem(icon: "book.fill", active: currentTab == .final, disabled: isFirstSubject) {
                        onOpenFinalGrade?()
                    }
                    navItem(icon: "gearshape.fill", active: currentTab == .settings, disabled: false) {
                        onOpenSettings?()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .background(barBackground)
                .frame(width: barWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                // unten Safe-Area ignorieren: nur 16pt Außenabstand wie links/rechts
                .padding(.bottom, 16)
                .overlay(fabOverlay, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // Overlay für das Actions-Panel, beeinflusst nicht die Layout-Höhe der Bar
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
                // Wichtig: Vorauswahl des Fachnamens weitergeben
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
        }
    }

    // MARK: - Subviews

    private func navItem(icon: String, active: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    let dotBackground: Color = {
                        guard active else { return .clear }
                        if isFeminine {
                            // body.theme-feminine(.dark-mode) .bottom-nav-dot--active
                            return colorPrimaryFem.opacity(isDark ? 0.55 : 0.30)
                        }
                        // rgba(37, 99, 235, 0.22) / 0.5
                        let base = Color(red: 37/255, green: 99/255, blue: 235/255)
                        return base.opacity(isDark ? 0.5 : 0.22)
                    }()

                    let dotBorder: Color = {
                        guard active else { return .clear }
                        return isFeminine ? colorPrimaryFemHover : colorPrimaryDark
                    }()

                    let dotShadowColor: Color = {
                        guard active else { return .clear }
                        if isFeminine {
                            return colorPrimaryFemHover.opacity(isDark ? 0.9 : 0.6)
                        }
                        return Color(red: 37/255, green: 99/255, blue: 235/255)
                            .opacity(isDark ? 0.85 : 0.45)
                    }()

                    let iconColor: Color = {
                        if disabled { return Color.gray.opacity(0.5) }
                        if active { return colorTextDarkDark }
                        return colorTextMediumDark
                    }()

                    Circle()
                        .fill(dotBackground)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle().stroke(dotBorder, lineWidth: active ? 2 : 0)
                        )
                        .shadow(color: dotShadowColor,
                                radius: active ? 4 : 0,
                                x: 0,
                                y: active ? 0 : 0)
                        .offset(y: active ? -1 : 0)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(minWidth: 64)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
        .accessibilityLabel(iconAccessibilityLabel(icon))
    }

    private var fabOverlay: some View {
        ZStack {
            if isFirstSubject && !isOpen {
                hintBubble
                    .offset(y: -108) // SCSS: bottom: 72px (über FAB)
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isOpen.toggle()
                }
            } label: {
                Circle()
                    .fill(fabBackgroundColor)
                    .frame(width: 56, height: 56)
                    .shadow(color: fabShadowColor, radius: fabPressed ? 12 : 24, x: 0, y: fabPressed ? 6 : 10)
                    .overlay(
                        Image(systemName: isOpen ? "xmark" : "plus")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(colorTextDarkDark) // $color-text-dark-dark
                    )
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in withAnimation(.easeOut(duration: 0.1)) { fabPressed = true } }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.12)) { fabPressed = false } }
            )
            .scaleEffect(fabPressed ? 0.96 : 1.0)
            // passt weiterhin; Bar steht nur 16pt vom Rand entfernt
            .offset(y: -26)
            .accessibilityLabel("Schnelle Aktionen öffnen")
        }
    }

    private var hintBubble: some View {
        VStack(spacing: 0) {
            Text("Du hast noch kein Fach angelegt.\nTippe hier, um dein erstes Fach zu erstellen.")
                .multilineTextAlignment(.center)
                .font(.system(size: 20))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(hintBubbleBackground)
                .foregroundStyle(hintBubbleTextColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(hintBubbleBorderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.25), radius: 26, x: 0, y: 10)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(hintBubbleBackground)
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(45))
                        .offset(y: 7)
                        .shadow(color: Color.black.opacity(0.25), radius: 26, x: 0, y: 10)
                }
        }
        .frame(maxWidth: 260)
    }

    private func actionsOverlay(bottomInset: CGFloat) -> some View {
        GeometryReader { _ in
            ZStack {
                // Backdrop
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.28)) { isOpen = false } // SCSS: 0.28s
                    }

                // Panel, am unteren Bildschirmrand über der BottomNav ausgerichtet
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Schnelle Aktionen")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(panelTitleColor)
                            Text("Was möchtest du hinzufügen?")
                                .font(.system(size: 12))
                                .foregroundStyle(panelSubtitleColor)
                        }

                        VStack(spacing: 8) {
                            // Hausaufgabe
                            ActionButton(
                                iconContent: AnyView(Image(systemName: "checklist").font(.system(size: 18, weight: .semibold))),
                                label: "Hausaufgabe",
                                description: "Aufgabe mit Fach und Fälligkeit",
                                disabled: store.subjects.isEmpty,
                                title: store.subjects.isEmpty ? "Lege zuerst ein Fach an" : ""
                            ) {
                                isOpen = false
                                showAddHomework = true
                            }

                            // Note
                            ActionButton(
                                iconContent: AnyView(Image(systemName: "list.bullet.rectangle.portrait.fill").font(.system(size: 18, weight: .semibold))),
                                label: "Note",
                                description: "Einzelne Leistung eintragen",
                                disabled: disableAddGrade,
                                title: addGradeTitle
                            ) {
                                isOpen = false
                                showAddGrade = true
                            }

                            // Klausurtermin
                            ActionButton(
                                iconContent: AnyView(Image(systemName: "calendar.badge.clock").font(.system(size: 18, weight: .semibold))),
                                label: "Klausurtermin",
                                description: "Klausurtermin eintragen",
                                disabled: store.subjects.isEmpty,
                                title: store.subjects.isEmpty ? "Lege zuerst ein Fach an" : ""
                            ) {
                                isOpen = false
                                showAddExam = true
                            }

                            // Fach
                            ActionButton(
                                iconContent: AnyView(Image(systemName: "folder.badge.plus").font(.system(size: 18, weight: .semibold))),
                                label: "Fach",
                                description: "Neues Fach anlegen",
                                disabled: false,
                                title: ""
                            ) {
                                isOpen = false
                                showAddSubject = true
                            }

                            // Fachreferat
                            ActionButton(
                                iconContent: AnyView(
                                    Group {
                                        if hasFachreferat {
                                            Image(systemName: "square.and.pencil")
                                                .font(.system(size: 18, weight: .semibold))
                                        } else {
                                            Image(systemName: "doc.text.fill")
                                                .font(.system(size: 18, weight: .semibold))
                                        }
                                    }
                                ),
                                label: hasFachreferat ? "Fachreferat bearbeiten" : "Fachreferat",
                                description: hasFachreferat ? "Bestehendes Fachreferat bearbeiten" : "Fachreferatsnote eintragen",
                                disabled: store.encryptionKey == nil || isFirstSubject,
                                title: store.encryptionKey == nil ? "Lade Schlüssel..." : (isFirstSubject ? "Lege zuerst ein Fach an" : "")
                            ) {
                                isOpen = false
                                showAddFachreferat = true
                            }

                            // Abitur
                            ActionButton(
                                iconContent: AnyView(Image(systemName: "graduationcap.fill").font(.system(size: 18, weight: .semibold))),
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
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                    .shadow(color: Color.black.opacity(isDark ? 0.9 : 0.45),
                            radius: 40, x: 0, y: 18)
                    .padding(.horizontal, 16)
                    // Abstand zur BottomNav: Bar-Höhe (~94) + Außenabstand (16) + 12
                    .padding(.bottom, 94 + 16 + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.32), value: isOpen) // SCSS: 0.32s
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Helpers

    private func iconAccessibilityLabel(_ name: String) -> String {
        switch name {
        case "house.fill": return "Home"
        case "folder.fill": return "Fächer"
        case "book.fill": return "Abschlussnote"
        case "gearshape.fill": return "Einstellungen"
        default: return "Navigation"
        }
    }

    private var fabBackgroundColor: Color {
        if isFeminine {
            return isDark ? colorPrimaryFemHover : colorPrimaryFem
        }
        return colorPrimaryDark
    }

    private var fabShadowColor: Color {
        if isFeminine {
            return colorPrimaryFem.opacity(isDark ? 0.6 : 0.6)
        }
        return isDark ? Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.9)
                      : colorPrimaryDark.opacity(0.6)
    }

    private var hintBubbleBackground: Color {
        if isFeminine {
            return isDark ? Color(red: 30/255, green: 64/255, blue: 175/255).opacity(0.9) : Color(hex: "#fff1f8")
        }
        return isDark ? Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.98) : .white
    }

    private var hintBubbleTextColor: Color {
        if isFeminine {
            return isDark ? Color.white : colorPrimaryFem
        }
        return isDark ? colorTextDarkDark : colorTextDark
    }

    private var hintBubbleBorderColor: Color {
        if isFeminine { return colorPrimaryFemHover.opacity(isDark ? 0.95 : 0.6) }
        return Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.9)
    }

    private var panelBackground: Color {
        // SCSS: white, in dark-mode $color-bg-light-dark
        return isDark ? colorBgLightDark : .white
    }
    private var panelTitleColor: Color {
        return isDark ? colorTextDarkDark : colorTextDark
    }
    private var panelSubtitleColor: Color {
        return isDark ? colorTextMediumDark : colorTextMedium
    }
}

// Abgerundete Form: oben 16, unten ~20 % der Breite
private struct RoundedBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let topR: CGFloat = 16
        let bottomR: CGFloat = rect.width * 0.14

        let tl = CGSize(width: topR, height: topR)
        let tr = CGSize(width: topR, height: topR)
        let bl = CGSize(width: bottomR, height: bottomR)
        let br = CGSize(width: bottomR, height: bottomR)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl.width, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr.width, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr.height),
                          control: CGPoint(x: rect.maxX, y: rect.minY))

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br.height))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - br.width, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))

        path.addLine(to: CGPoint(x: rect.minX + bl.width, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl.height),
                          control: CGPoint(x: rect.minX, y: rect.maxY))

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl.height))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tl.width, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))

        path.closeSubpath()
        return path
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

    private var colorBgLightDark: Color { Color(hex: "#1f2937") }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(iconCircleBackground)
                    .overlay(
                        Circle()
                            .stroke(iconCircleBorder, lineWidth: 1)
                    )
                    .frame(width: 30, height: 30)
                    .overlay(
                        iconContent
                            .foregroundStyle(iconCircleForeground)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(labelColor)
                    Text(title.isEmpty ? description : title)
                        .font(.system(size: 12))
                        .foregroundStyle(descriptionColor)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .disabled(disabled)
        .buttonStyle(.plain)
        .opacity(disabled ? 0.55 : 1.0)
    }

    private var buttonBackground: Color {
        isDark ? Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.9)
               : Color(red: 249/255, green: 250/255, blue: 251/255).opacity(0.95)
    }

    private var iconCircleBackground: Color {
        if isFeminine {
            return colorPrimaryFem.opacity(0.1)
        }
        return colorPrimaryDark.opacity(0.1)
    }

    private var iconCircleBorder: Color {
        if isFeminine {
            return colorPrimaryFem.opacity(isDark ? 0.95 : 0.6)
        }
        return colorPrimaryDark.opacity(isDark ? 0.9 : 0.45)
    }

    private var iconCircleForeground: Color {
        if isFeminine {
            return colorPrimaryFem
        }
        return isDark ? colorTextDarkDark : colorPrimaryDark
    }

    private var labelColor: Color {
        return isDark ? colorTextDarkDark : colorTextDark
    }

    private var descriptionColor: Color {
        return isDark ? colorTextMediumDark : colorTextMedium
    }
}

private extension Path {
    mutating func addRoundedRect(in rect: CGRect,
                                 topLeftRadius: CGSize,
                                 topRightRadius: CGSize,
                                 bottomLeftRadius: CGSize,
                                 bottomRightRadius: CGSize) {
        let tl = topLeftRadius
        let tr = topRightRadius
        let bl = bottomLeftRadius
        let br = bottomRightRadius

        move(to: CGPoint(x: rect.minX + tl.width, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX - tr.width, y: rect.minY))
        addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr.height), control: CGPoint(x: rect.maxX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br.height))
        addQuadCurve(to: CGPoint(x: rect.maxX - br.width, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX + bl.width, y: rect.maxY))
        addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl.height), control: CGPoint(x: rect.minX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl.height))
        addQuadCurve(to: CGPoint(x: rect.minX + tl.width, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        closeSubpath()
    }
}
