import SwiftUI
import UIKit

/// The app's motion vocabulary. Everything animates through here so Reduce
/// Motion is honored in one place: a nil animation means "just change".
enum Motion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Strong ease-out, cubic-bezier(0.23, 1, 0.32, 1). Fast at the start, where
    /// the eye is waiting; the built-in .easeOut is too weak to feel responsive.
    static func easeOut(_ duration: Double) -> Animation? {
        reduced ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// withAnimation that degrades to an instant change under Reduce Motion.
    static func perform(_ animation: Animation?, _ body: () -> Void) {
        if let animation { withAnimation(animation, body) } else { body() }
    }
}
