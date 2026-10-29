import AppIntents
import EventKit
import SwiftData
import WidgetKit

/// Lets Siri/Shortcuts create a real calendar event without opening the app.
/// Uses its own EKEventStore rather than EventStoreManager's, since App
/// Intents can run without the app's UI/state ever loading -- EventKit
/// notifies every live store instance of a change regardless of which
/// instance made it, so the app's own views still refresh live afterward.
struct CreateEventIntent: AppIntent {
    static var title: LocalizedStringResource { "Create Calendar Event" }
    static var description: IntentDescription { IntentDescription("Adds a new event to your calendar.") }

    @Parameter(title: "Title")
    var eventTitle: String

    @Parameter(title: "Start Time")
    var startDate: Date

    @Parameter(title: "Duration (minutes)", default: 60)
    var durationMinutes: Int

    @Parameter(title: "Important", default: false)
    var isImportant: Bool

    @Parameter(title: "Category")
    var calendarTitle: String?

    @Parameter(title: "Location")
    var location: String?

    @Parameter(title: "Notes")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$eventTitle) at \(\.$startDate)") {
            \.$durationMinutes
            \.$isImportant
            \.$calendarTitle
            \.$location
            \.$notes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else {
            return .result(dialog: "Calendar access is needed -- open CalendarApp and grant it first.")
        }
        let calendar: EKCalendar?
        if let calendarTitle, !calendarTitle.isEmpty {
            let matches = store.calendars(for: .event).filter {
                $0.title.caseInsensitiveCompare(calendarTitle) == .orderedSame && $0.allowsContentModifications
            }
            guard matches.count == 1 else {
                return .result(dialog: "Choose one unique writable category in CalendarApp first.")
            }
            calendar = matches.first
        } else {
            calendar = store.defaultCalendarForNewEvents
        }
        guard let calendar, calendar.allowsContentModifications else {
            return .result(dialog: "No writable calendar was found.")
        }

        let event = EKEvent(eventStore: store)
        event.title = eventTitle
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(Double(max(1, durationMinutes) * 60))
        event.calendar = calendar
        event.location = location
        event.notes = EventImportance.notes(notes, settingImportant: isImportant)
        try store.save(event, span: .thisEvent)
        // App Intents may run without the calendar view ever appearing.
        // Schedule the same app-owned reminder queue immediately.
        let container = ModelContainerFactory.make()
        let preferences = (try? container.mainContext.fetch(FetchDescriptor<EventReminderPreference>())) ?? []
        let predicate = store.predicateForEvents(withStart: Date.now.addingTimeInterval(-86400),
            end: Date.now.addingTimeInterval(180 * 86400), calendars: nil)
        await ReminderScheduler.refresh(events: store.events(matching: predicate).filter {
            $0.calendar?.title != EventStoreManager.syncCalendarTitle
        }, reminderRows: preferences)
        WidgetCenter.shared.reloadAllTimelines()

        let timeText = startDate.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "Added \"\(eventTitle)\" at \(timeText).")
    }
}
