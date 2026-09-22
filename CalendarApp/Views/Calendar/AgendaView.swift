import EventKit
import SwiftData
import SwiftUI

/// Upcoming events across many days, grouped by date -- mirrors the web
/// app's Agenda tab.
struct AgendaView: View {
    let hiddenCalendarIdentifiers: Set<String>
    let onSelectEvent: (EKEvent) -> Void

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Query private var completionRows: [EventCompletionStatus]

    private var visibleCalendars: [EKCalendar] {
        eventStore.calendars.filter { !hiddenCalendarIdentifiers.contains($0.calendarIdentifier) }
    }

    private var upcoming: [EKEvent] {
        let start = DateMath.startOfDay(.now)
        let end = DateMath.addingDays(180, to: start)
        return eventStore.events(from: start, to: end, in: visibleCalendars)
    }

    private var groups: [(day: Date, events: [EKEvent])] {
        let grouped = Dictionary(grouping: upcoming) { DateMath.startOfDay($0.startDate) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.startDate < $1.startDate }) }
    }

    var body: some View {
        List {
            if groups.isEmpty {
                ContentUnavailableView(
                    "No Upcoming Events",
                    systemImage: "calendar",
                    description: Text("Tap + to add your first one.")
                )
            } else {
                ForEach(groups, id: \.day) { group in
                    Section(DateMath.fullDateFormatter.string(from: group.day)) {
                        ForEach(group.events, id: \.eventIdentifier) { event in
                            EventRow(
                                event: event,
                                completed: EventCompletionAccess.isCompleted(event, in: completionRows),
                                onToggleComplete: { EventCompletionAccess.toggle(event, in: completionRows, context: modelContext) },
                                onDelete: { eventStore.deleteWithUndo(event, undoManager: undoManager) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectEvent(event) }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
