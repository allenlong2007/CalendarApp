import CoreLocation
import EventKit
import SwiftData
import SwiftUI

/// A single-click "quick look" popover for an event -- mirrors Apple
/// Calendar's own read-only preview that appears before a double-click
/// opens the full editor.
struct EventQuickLookView: View {
    let event: EKEvent
    let completed: Bool
    var onToggleComplete: (() -> Void)?

    @Query private var locationOverrides: [EventLocationOverride]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Capsule()
                    .fill(EventStatusEvaluator.displayColor(
                        for: EventStatusEvaluator.status(for: event, completed: completed),
                        categoryColor: AppTheme.calendarColor(for: event.calendar)
                    ))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title ?? "Untitled")
                        .font(.headline)
                    Text(DateMath.fullDateFormatter.string(from: event.startDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(timeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let rule = event.recurrenceRules?.first {
                        Text(recurrenceText(for: rule))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let onToggleComplete {
                    Button(action: onToggleComplete) {
                        Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(completed ? AppTheme.completed : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .animation(Motion.easeOut(0.15), value: completed)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let resolved = EventLocationAccess.displayLocation(for: event, in: locationOverrides) {
                Button {
                    openInMaps(resolved)
                } label: {
                    Label(resolved.text, systemImage: "mappin.circle.fill")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.ultramarine)
            }

            if let notes = event.notes, !notes.isEmpty {
                Divider()
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(16)
        .frame(minWidth: 260, maxWidth: 340, alignment: .leading)
    }

    private var timeText: String {
        event.isAllDay ? "All-day" : "\(DateMath.timeFormatter.string(from: event.startDate)) – \(DateMath.timeFormatter.string(from: event.endDate))"
    }

    private func recurrenceText(for rule: EKRecurrenceRule) -> String {
        switch rule.frequency {
        case .daily: return "Repeats daily"
        case .weekly: return "Repeats weekly"
        case .monthly: return "Repeats monthly"
        case .yearly: return "Repeats yearly"
        @unknown default: return "Repeats"
        }
    }

    private func openInMaps(_ resolved: (text: String, coordinate: CLLocationCoordinate2D?)) {
        if let coordinate = resolved.coordinate {
            MapsLauncher.open(title: resolved.text, coordinate: coordinate)
        } else {
            MapsLauncher.search(query: resolved.text)
        }
    }
}
