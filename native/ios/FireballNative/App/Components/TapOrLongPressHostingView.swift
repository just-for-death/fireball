import SwiftUI
import UIKit

/// UIKit linkage so tap is not delayed waiting for long-press to fail visually, yet a long press does not also invoke tap (`tap.requires(toFail: long)`).
struct TapOrLongPressHostingView: UIViewRepresentable {
    var minimumPressDuration: TimeInterval = 0.48
    var onTap: () -> Void = {}
    var onLongPress: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.backgroundColor = .clear
        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        long.minimumPressDuration = minimumPressDuration
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: long)
        v.addGestureRecognizer(long)
        v.addGestureRecognizer(tap)
        context.coordinator.longPress = long
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.longPress?.minimumPressDuration = minimumPressDuration
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onLongPress: () -> Void
        weak var longPress: UILongPressGestureRecognizer?

        init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended {
                onTap()
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.prepare()
            impact.impactOccurred()
            onLongPress()
        }
    }
}
