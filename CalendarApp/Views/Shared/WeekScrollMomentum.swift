import SwiftUI
import UIKit

/// Limit momentum on Catalyst without changing the user's system-wide
/// trackpad settings or intercepting the scroll view's gestures/delegate.
struct WeekScrollMomentum: UIViewRepresentable {
    func makeUIView(context: Context) -> ConfigurationView {
        let view = ConfigurationView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ConfigurationView, context: Context) { uiView.configure() }

    final class ConfigurationView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configure()
        }

        func configure() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    scrollView.decelerationRate = .fast
                    return
                }
                ancestor = view.superview
            }
        }
    }
}
