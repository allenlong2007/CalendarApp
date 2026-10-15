import EventKit
import SwiftUI

/// The quick-delete button that sits next to an event's checkmark.
///
/// Like CompletionCheckButton it's a finger-sized target that wins taps over
/// the row or panel around it. An event that runs across several days is ONE
/// event -- deleting it from any day removes it from all of them -- so that
/// case asks first instead of looking like it only deleted the day you were on.
struct EventTrashButton: View {
    let event: EKEvent
    var font: Font = .title3
    var hitSize: CGFloat = 44
    let onDelete: () -> Void

    @State private var confirming = false

    static func spansMultipleDays(_ event: EKEvent) -> Bool {
        guard let start = event.startDate, let end = event.endDate else { return false }
        let last = end > start ? end.addingTimeInterval(-1) : end
        return !Calendar.current.isDate(start, inSameDayAs: last)
    }

    var body: some View {
        Image(systemName: "trash.circle.fill")
            .font(font)
            .foregroundStyle(.secondary)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded {
                if Self.spansMultipleDays(event) { confirming = true } else { onDelete() }
            })
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Delete event")
            .accessibilityAction(.default) {
                if Self.spansMultipleDays(event) { confirming = true } else { onDelete() }
            }
            .confirmationDialog("Delete this multi-day event?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete from all days", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\"\(event.title ?? "This event")\" runs from \(DateMath.monthDayYearFormatter.string(from: event.startDate)) to \(DateMath.monthDayYearFormatter.string(from: event.endDate)), so deleting it removes it from every day it covers.")
            }
    }
}
