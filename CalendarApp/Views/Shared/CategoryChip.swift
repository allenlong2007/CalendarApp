import EventKit
import SwiftUI

/// A single selectable, color-coded category/calendar chip -- shows its
/// color directly inline instead of hiding it behind a drill-down picker.
struct CategoryChip: View {
    let calendar: EKCalendar
    let isSelected: Bool
    let action: () -> Void

    private var color: Color { Color(cgColor: calendar.cgColor) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(calendar.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(isSelected ? color.opacity(0.25) : Color.secondary.opacity(0.12)))
            .overlay(Capsule().stroke(isSelected ? color : .clear, lineWidth: 1.5))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}
