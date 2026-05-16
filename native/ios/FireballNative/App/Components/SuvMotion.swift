import SwiftUI
import UIKit

/// Fade + slide entrance — port of Flutter `SuvFadeSlideIn`.
struct SuvFadeSlideIn<Content: View>: View {
    let delayMs: Int
    let content: Content
    @State private var visible = false

    init(delayMs: Int = 0, @ViewBuilder content: () -> Content) {
        self.delayMs = delayMs
        self.content = content()
    }

    var body: some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
            .onAppear {
                guard !UIAccessibility.isReduceMotionEnabled else {
                    visible = true
                    return
                }
                visible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delayMs) / 1000.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        visible = true
                    }
                }
            }
    }

    static func staggered(index: Int, @ViewBuilder content: () -> Content) -> SuvFadeSlideIn<Content> {
        let delay = min(320, max(0, index) * 40)
        return SuvFadeSlideIn(delayMs: delay, content: content)
    }
}

struct SuvPressScale<Content: View>: View {
    let scaleDown: CGFloat
    let onTap: (() -> Void)?
    let content: Content
    @GestureState private var pressed = false

    init(
        scaleDown: CGFloat = 0.98,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.scaleDown = scaleDown
        self.onTap = onTap
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(pressed ? scaleDown : 1)
            .animation(.easeOut(duration: 0.14), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, state, _ in state = true }
                    .onEnded { _ in onTap?() }
            )
    }
}

struct PremiumBackground<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.10, blue: 0.10),
                    Color(red: 0.07, green: 0.07, blue: 0.07),
                    Color(red: 0.04, green: 0.04, blue: 0.04),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            content
        }
    }
}
