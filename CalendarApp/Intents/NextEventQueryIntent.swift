import AppIntents
import EventKit

/// "What's my next event?" -- a spoken-answer Siri intent, no UI needed.
struct NextEventQueryIntent: AppIntent {
    static var title: LocalizedStringResource { "Next Event" }
    static var description: IntentDescription { IntentDescription("Tells you your next upcoming calendar event.") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return .result(dialog: "Open CalendarApp and grant calendar access first.")
        }
        let store = EKEventStore()
        let now = Date.now
        guard let end = Calendar.current.date(byAdding: .day, value: 14, to: now) else {
            return .result(dialog: "Something went wrong looking up your events.")
        }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let next = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first

        guard let next else {
            return .result(dialog: "You have no upcoming events.")
        }

        let title = next.title ?? "Untitled event"
        if next.isAllDay {
            return .result(dialog: "Your next event is \(title), all day today.")
        }
        let timeText = next.startDate.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(next.startDate) {
            return .result(dialog: "Your next event is \(title) at \(timeText).")
        }
        let dayText = next.startDate.formatted(.dateTime.weekday(.wide))
        return .result(dialog: "Your next event is \(title) on \(dayText) at \(timeText).")
    }
}
