import SwiftUI

@available(iOS 26, *)
struct LiquidBottomNavView: View {
    let currentTab: BottomNavView.Tab
    let isSubscriptionGateActive: Bool
    let onOpenHome: (() -> Void)?
    let onOpenInsights: (() -> Void)?
    let onOpenFinalGrade: (() -> Void)?
    let onOpenSettings: (() -> Void)?
    let onOpenAdd: () -> Void
    
    @Namespace private var namespace
    @Environment(\.colorScheme) var colorScheme
    
    private let labels: [BottomNavView.Tab: String] = [
        .home: "Home",
        .insights: "Statistik",
        .final: "Abi",
        .settings: "Settings"
    ]
    
    var body: some View {
        HStack(spacing: 12) {
            // Navigation Capsule
            GeometryReader { geo in
                ZStack {
                    // Main Container Background (Dark Capsule)
                    Capsule()
                        .fill(Color.black.opacity(0.8)) // Dark background
                        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    // Active Lens Cursor
                    lensOverlay
                    
                    // Items Layer
                    HStack(spacing: 0) {
                        navItem(tab: .home, icon: "house.fill", label: "Home", action: onOpenHome)
                        Spacer()
                        
                        if !isSubscriptionGateActive {
                            navItem(tab: .insights, icon: "chart.bar.fill", label: "Noten", action: onOpenInsights)
                            Spacer()
                            navItem(tab: .final, icon: "graduationcap.fill", label: "Abi", action: onOpenFinalGrade)
                            Spacer()
                        }
                        
                        navItem(tab: .settings, icon: "gearshape.fill", label: "Optionen", action: onOpenSettings)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                // Gesture for Drag (Scoped to the capsule)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let width = geo.size.width
                            let x = value.location.x
                            let relativeX = x / width
                            
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
                                if !isSubscriptionGateActive {
                                    // 4 Items: 0-0.25, 0.25-0.5, 0.5-0.75, 0.75-1.0
                                    if relativeX < 0.25 {
                                        onOpenHome?()
                                    } else if relativeX < 0.5 {
                                        onOpenInsights?()
                                    } else if relativeX < 0.75 {
                                        onOpenFinalGrade?()
                                    } else {
                                        onOpenSettings?()
                                    }
                                } else {
                                    // 2 Items: 0-0.5, 0.5-1.0
                                    if relativeX < 0.5 {
                                        onOpenHome?()
                                    } else {
                                        onOpenSettings?()
                                    }
                                }
                            }
                        }
                )
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            
            // Separate Add Button with Liquid Glass effect (iOS 26 native style)
            if !isSubscriptionGateActive {
                Button(action: onOpenAdd) {
                    ZStack {
                        // Liquid Glass Circle Background
                        Circle()
                            .fill(Color.black.opacity(0.8))
                            .glassEffect(.regular)
                            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                        
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 80, height: 80) // Match tab bar height
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 0)
    }
    
    private func navItem(tab: BottomNavView.Tab, icon: String, label: String, action: (() -> Void)?) -> some View {
        let isSelected = currentTab == tab
        
        return Button {
            if !isSelected {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
            action?()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : .gray) // Active is white (under lens), inactive gray
                
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .gray)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            // Mark position for the lens
            .matchedGeometryEffect(id: tab, in: namespace)
        }
        .buttonStyle(.plain)
    }
    
    private var addButton: some View {
        Button(action: onOpenAdd) {
            VStack(spacing: 4) {
                ZStack {
                     Circle()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                // Spacer() or Text to align baseline?
                Text("Neu")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray)
                    .opacity(0) // Invisible but keeps alignment
            }
            .frame(maxWidth: .infinity)
            .offset(y: -15) // Pop out slightly?
        }
        .buttonStyle(.plain)
    }
    
    // The "Lens" that floats over
    private var lensOverlay: some View {
        ZStack {
           Capsule()
                .glassEffect(.regular) // The liquid glass effect
                .shadow(color: .white.opacity(0.1), radius: 5, x: 0, y: 0) // Glow?
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .matchedGeometryEffect(id: currentTab, in: namespace, isSource: false)
                .frame(height: 60) // Slightly taller/larger than the item text+icon?
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentTab)
    }
    
    private func tabIndex(for tab: BottomNavView.Tab) -> Int? {
        // ... helper if needed
        return 0
    }
}
