import AppIntents
import EventKit
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

    static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$eventTitle) at \(\.$startDate)") {
            \.$durationMinutes
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else {
            return .result(dialog: "Calendar access is needed -- open CalendarApp and grant it first.")
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            return .result(dialog: "No writable calendar was found.")
        }

        let event = EKEvent(eventStore: store)
        event.title = eventTitle
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(Double(max(1, durationMinutes) * 60))
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        WidgetCenter.shared.reloadAllTimelines()

        let timeText = startDate.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "Added \"\(eventTitle)\" at \(timeText).")
    }
}
