import EventKit
import SwiftUI

/// A single-click "quick look" popover for an event -- mirrors Apple
/// Calendar's own read-only preview that appears before a double-click
/// opens the full editor.
struct EventQuickLookView: View {
    let event: EKEvent
    let completed: Bool

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
            }

            if let location = event.location, !location.isEmpty {
                Button {
                    openInMaps(location)
                } label: {
                    Label(location, systemImage: "mappin.circle.fill")
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

    private func openInMaps(_ location: String) {
        if let geoLocation = event.structuredLocation?.geoLocation {
            MapsLauncher.open(title: location, coordinate: geoLocation.coordinate)
        } else {
            MapsLauncher.search(query: location)
        }
    }
}
