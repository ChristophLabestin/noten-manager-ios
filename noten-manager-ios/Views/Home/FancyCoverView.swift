import SwiftUI
import Combine

struct FancyCoverView: View {
    @EnvironmentObject var store: GradesStore
    @EnvironmentObject var biometricManager: BiometricAuthManager
    @Binding var isPresented: Bool
    @State private var animateSpeedometer: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var showSwipeHint: Bool = false
    
    // Get grade similar to HomeView logic
    private var averagePoints: Double {
        return GradeCalculationService.calculateOverallAverage(
            subjects: store.subjects,
            halfYearValueProvider: { subject, hy in
                store.bestAvailableHalfYearValue(subject: subject, halfYear: hy)
            },
            droppedHalfYearProvider: { $0.droppedHalfYear },
            halfYearFilter: nil,
            fachreferat: store.fachreferat,
            seminar: store.seminarPerformance,
            practical: store.practicalPerformance,
            examPoints: store.examPoints,
            schoolType: store.schoolType,
            gradeYear: store.gradeYear ?? 12
        ) ?? 0.0
    }
    
    private var grade1to6: String {
        let p = averagePoints
        let grade = (17.0 - p) / 3.0
        return p > 0 ? String(format: "Ø %.2f", grade) : "-"
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background: Static High-Quality Gradient (Performance Fix)
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#0f172a"),
                        Color(hex: "#1e293b")
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Subtle overlay
                Color.black.opacity(0.2).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Privacy Toggle
                    HStack {
                        Spacer()
                        Button {
                            // If currently hidden (active), require auth to show
                            if store.isPrivacyModeActive {
                                if biometricManager.isEnabledForActiveUser {
                                    Task {
                                        let success = await biometricManager.authenticate(reason: "Noten anzeigen")
                                        if success {
                                            await MainActor.run {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    store.updatePrivacyMode(active: false)
                                                }
                                                let feedback = UINotificationFeedbackGenerator()
                                                feedback.notificationOccurred(.success)
                                            }
                                        }
                                    }
                                } else {
                                    // No biometric set, just toggle
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        store.updatePrivacyMode(active: false)
                                    }
                                    let feedback = UISelectionFeedbackGenerator()
                                    feedback.selectionChanged()
                                }
                            } else {
                                // Hiding is always allowed
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    store.updatePrivacyMode(active: true)
                                }
                                let feedback = UISelectionFeedbackGenerator()
                                feedback.selectionChanged()
                            }
                        } label: {
                            Image(systemName: store.isPrivacyModeActive ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(12)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                        .padding(.top, 60) // Safe Area approximation or use safeAreaInset
                        Spacer()
                    }
                    .padding(.bottom, 20)
                    
                    Spacer()
                    
                    // Header
                    VStack(spacing: 12) {
                        Text("Dein aktueller Stand")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Text(store.isPrivacyModeActive ? "***" : grade1to6)
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(.ultraThinMaterial)
                            )
                    }
                    .offset(y: animateSpeedometer ? 0 : 20)
                    .opacity(animateSpeedometer ? 1 : 0)
                    
                    Spacer().frame(height: 50)
                    
                    // Speedometer
                    SpeedometerView(
                        score: averagePoints,
                        animate: $animateSpeedometer,
                        isPrivacyMode: store.isPrivacyModeActive
                    )
                    
                    Spacer()
                    
                    // Footer / Swipe Hint
                    VStack(spacing: 12) {
                        Image(systemName: "chevron.compact.up")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                            .offset(y: showSwipeHint ? -10 : 0)
                            .animation(
                                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                value: showSwipeHint
                            )
                        
                        Text("Hochwischen für Details")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.bottom, 60)
                    .opacity(animateSpeedometer ? 1 : 0)
                }
            }
            .offset(y: dragOffset)
            .opacity(1.0 - (abs(dragOffset) / (geo.size.height * 0.5)))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height < 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height < -100 {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                dragOffset = -geo.size.height
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                isPresented = false
                                dragOffset = 0
                            }
                        } else {
                            withAnimation(.spring()) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) {
                animateSpeedometer = true
            }
            showSwipeHint = true
        }
    }
}

