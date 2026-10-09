import SwiftUI

/// The tappable checkmark circle used on every event row and block.
///
/// A plain Button lost taps on the phone: it sits inside rows and blocks that
/// have their own tap handlers (open the event, preview it, create one), and
/// at icon size it was also a tiny target. This is a finger-sized area whose
/// tap takes priority over those handlers.
struct CompletionCheckButton: View {
    let completed: Bool
    var font: Font = .title3
    var hitSize: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
            .font(font)
            .foregroundStyle(completed ? AppTheme.completed : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .animation(Motion.easeOut(0.15), value: completed)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded(action))
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(completed ? "Mark incomplete" : "Mark complete")
            .accessibilityAction(.default, action)
    }
}
