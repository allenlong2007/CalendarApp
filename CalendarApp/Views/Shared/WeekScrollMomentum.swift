import SwiftUI
import UIKit
import os

/// A small amount of remaining travel, rather than an absolute content offset:
/// lazy stacks can adjust their offset as they discover row sizes.
struct WheelScrollMotion {
    private(set) var remaining: Double = 0
    var isActive: Bool { remaining != 0 }

    mutating func enqueue(_ delta: Double, limit: Double) {
        guard delta.isFinite, limit.isFinite, limit > 0 else { return }
        if delta * remaining < 0 { remaining = 0 }
        remaining = min(limit, max(-limit, remaining + delta))
    }

    mutating func advance(by elapsed: Double) -> Double {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        if abs(remaining) < 0.25 {
            let final = remaining
            remaining = 0
            return final
        }
        let movement = remaining * (1 - exp(-elapsed / 0.075))
        remaining -= movement
        return movement
    }

    mutating func cancel() { remaining = 0 }
}

/// Preserve native trackpad input; blend only the discrete steps from a wheel.
struct WeekScrollMomentum: UIViewRepresentable {
    var interruptionToken: Int = 0
    var onWheelActivity: (Bool) -> Void = { _ in }
    var onWheelFinished: (Date?) -> Void = { _ in }

    func makeUIView(context: Context) -> ConfigurationView {
        let view = ConfigurationView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ConfigurationView, context: Context) {
        uiView.interrupt(ifChanged: interruptionToken)
        uiView.onWheelActivity = onWheelActivity
        uiView.onWheelFinished = onWheelFinished
        uiView.configure()
    }

    static func dismantleUIView(_ uiView: ConfigurationView, coordinator: ()) { uiView.detach() }

    final class ConfigurationView: UIView, UIGestureRecognizerDelegate {
        var onWheelActivity: (Bool) -> Void = { _ in }
        var onWheelFinished: (Date?) -> Void = { _ in }
        private weak var scrollView: UIScrollView?
        private var originalScrollTypes: UIScrollTypeMask = []
        private var originalDeceleration: UIScrollView.DecelerationRate = .normal
        private var motion = WheelScrollMotion()
        private var wheelIsActive = false
        private var displayLink: CADisplayLink?
        private var lastFrame: CFTimeInterval?
        private var idleTask: Task<Void, Never>?
        private var interruptionToken: Int?
        private static let logger = Logger(subsystem: "com.footsoregnu3115.calendarapp", category: "WheelScroll")

        func interrupt(ifChanged token: Int) {
            if let interruptionToken, interruptionToken != token { stop() }
            interruptionToken = token
        }
        private lazy var wheelPan: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(wheelMoved(_:)))
            gesture.allowedScrollTypesMask = .discrete
            gesture.allowedTouchTypes = []
            gesture.cancelsTouchesInView = false
            gesture.delegate = self
            return gesture
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { configure() }
        }

        func configure() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    install(on: scrollView)
                    return
                }
                ancestor = view.superview
            }
        }

        func install(on view: UIScrollView) {
            guard scrollView !== view else { return }
            detach()
            scrollView = view
            originalScrollTypes = view.panGestureRecognizer.allowedScrollTypesMask
            originalDeceleration = view.decelerationRate
            view.decelerationRate = UIScrollView.DecelerationRate(rawValue: 0.995)
            view.panGestureRecognizer.allowedScrollTypesMask.remove(.discrete)
            view.panGestureRecognizer.addTarget(self, action: #selector(nativePanMoved(_:)))
            view.addGestureRecognizer(wheelPan)
        }

        func detach() {
            stop()
            if let scrollView {
                scrollView.removeGestureRecognizer(wheelPan)
                scrollView.panGestureRecognizer.removeTarget(self, action: #selector(nativePanMoved(_:)))
                scrollView.panGestureRecognizer.allowedScrollTypesMask = originalScrollTypes
                scrollView.decelerationRate = originalDeceleration
            }
            scrollView = nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView, gestureRecognizer === wheelPan else { return true }
            let movement = wheelPan.translation(in: scrollView)
            return abs(movement.y) > abs(movement.x)
        }

        @objc private func nativePanMoved(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { stop() }
        }

        @objc private func wheelMoved(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView else { return }
            let delta = -gesture.translation(in: scrollView).y
            gesture.setTranslation(.zero, in: scrollView)
            guard delta != 0 else { return }
            idleTask?.cancel()
            if !wheelIsActive {
                wheelIsActive = true
                Self.logger.debug("Discrete mouse-wheel smoothing began")
                onWheelActivity(true)
            }
            // Keep the device's direction and step size, and cap queued travel
            // so rapid wheel ticks can't leave a long animation behind them.
            motion.enqueue(Double(delta), limit: Double(max(1, scrollView.bounds.height)))
            if Motion.reduced {
                apply(motion.advance(by: 10))
                motion.cancel()
                scheduleFinish()
            } else if displayLink == nil {
                lastFrame = nil
                let link = CADisplayLink(target: FrameTarget(self), selector: #selector(FrameTarget.tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
        }

        fileprivate func tick(_ link: CADisplayLink) {
            guard let scrollView, window != nil else { stop(); return }
            if scrollView.isTracking || scrollView.isDragging { stop(); return }
            let elapsed = lastFrame.map { link.timestamp - $0 } ?? (link.targetTimestamp - link.timestamp)
            lastFrame = link.timestamp
            apply(motion.advance(by: min(max(elapsed, 0), 1.0 / 15)))
            if !motion.isActive {
                displayLink?.invalidate()
                displayLink = nil
                lastFrame = nil
                scheduleFinish()
            }
        }

        private func apply(_ movement: Double) {
            guard let scrollView else { return }
            let minimum = -scrollView.adjustedContentInset.top
            let maximum = max(minimum, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            let offset = scrollView.contentOffset
            let y = min(maximum, max(minimum, offset.y + CGFloat(movement)))
            scrollView.setContentOffset(CGPoint(x: offset.x, y: y), animated: false)
            if abs(y - offset.y) < 0.001 { motion.cancel() }
        }

        /// Manual contentOffset changes need not update SwiftUI's bound row
        /// identity during a wheel gesture. Resolve the actual nearest row.
        static func nearestWeek(in scrollView: UIScrollView) -> Date? {
            let top = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            var candidates = scrollView.subviews
            var nearest: (distance: CGFloat, week: Date)?
            while let view = candidates.popLast() {
                if let anchor = view as? WeekScrollRowAnchor.AnchorView, let week = anchor.week {
                    let distance = abs(anchor.convert(.zero, to: scrollView).y - top)
                    if nearest == nil || distance < nearest!.distance { nearest = (distance, week) }
                } else {
                    candidates.append(contentsOf: view.subviews)
                }
            }
            return nearest?.week
        }

        private func scheduleFinish() {
            idleTask?.cancel()
            idleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, !motion.isActive else { return }
                wheelIsActive = false
                onWheelActivity(false)
                onWheelFinished(scrollView.flatMap { Self.nearestWeek(in: $0) })
            }
        }

        private func stop() {
            idleTask?.cancel()
            idleTask = nil
            displayLink?.invalidate()
            displayLink = nil
            lastFrame = nil
            motion.cancel()
            if wheelIsActive { wheelIsActive = false; onWheelActivity(false) }
        }
    }

    /// CADisplayLink retains its target; keep the owning view weak.
    @MainActor private final class FrameTarget: NSObject {
        weak var owner: ConfigurationView?
        init(_ owner: ConfigurationView) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.tick(link)
        }
    }
}


/// A lightweight native marker for row identity and geometry. Only the lazy
/// stack's instantiated rows have markers; no per-frame preference collection.
struct WeekScrollRowAnchor: UIViewRepresentable {
    let week: Date
    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ uiView: AnchorView, context: Context) { uiView.week = week }
    final class AnchorView: UIView { var week: Date? }
}
