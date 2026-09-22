import EventKit
import SwiftData
import SwiftUI

/// Persistent right-hand panel shown on wide (Mac/iPad) windows: a mini
/// month navigator up top, then either the selected day's event list or --
/// once a single-click preview comes in from Month/Day -- that one event's
/// quick-look with an Edit button. Mirrors Apple Calendar's own sidebar.
struct CalendarSidebarView: View {
    @Binding var referenceDate: Date
    let selectedDate: Date
    let weekStartDay: Int
    let hiddenCalendarIdentifiers: Set<String>
    let previewEvent: EKEvent?
    let onSelectDay: (Date) -> Void
    let onEditEvent: (EKEvent) -> Void
    let onAddEvent: (Date) -> Void
    let onToggleComplete: (EKEvent) -> Void
    let onDelete: (EKEvent) -> Void

    @Environment(EventStoreManager.self) private var eventStore
    @Query private var completionRows: [EventCompletionStatus]

    private var visibleCalendars: [EKCalendar] {
        eventStore.calendars.filter { !hiddenCalendarIdentifiers.contains($0.calendarIdentifier) }
    }

    private var dayEvents: [EKEvent] {
        eventStore.events(from: DateMath.startOfDay(selectedDate), to: DateMath.endOfDay(selectedDate), in: visibleCalendars)
            .sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            MiniMonthPicker(referenceDate: $referenceDate, selectedDate: selectedDate, weekStartDay: weekStartDay, onSelectDay: onSelectDay)
                .padding(16)

            Divider()

            if let previewEvent {
                ScrollView {
                    EventQuickLookView(
                        event: previewEvent,
                        completed: EventCompletionAccess.isCompleted(previewEvent, in: completionRows)
                    )
                    Button {
                        onEditEvent(previewEvent)
                    } label: {
                        Label("Edit Event", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.ultramarine)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            } else {
                List {
                    Section(DateMath.fullDateFormatter.string(from: selectedDate)) {
                        if dayEvents.isEmpty {
                            Text("No events")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(dayEvents, id: \.eventIdentifier) { event in
                                EventRow(
                                    event: event,
                                    completed: EventCompletionAccess.isCompleted(event, in: completionRows),
                                    onToggleComplete: { onToggleComplete(event) },
                                    onDelete: { onDelete(event) }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { onEditEvent(event) }
                            }
                        }
                    }
                }
                .listStyle(.plain)

                Button {
                    onAddEvent(selectedDate)
                } label: {
                    Label("Add Event", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ultramarine)
                .padding(16)
            }
        }
        .frame(minWidth: 300, idealWidth: 320, maxWidth: 360)
    }
}
