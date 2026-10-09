import AppIntents
import SwiftData
import WidgetKit

/// Lets a widget mark an event complete with one tap, without opening the
/// app. AppIntent parameters must be Codable primitives (no EKEvent), so
/// this carries the same identifying fields EventCompletionAccess matches
/// on. It queues the change in the shared CompletionOutbox for the app to
/// apply; it never writes the database itself.
struct ToggleEventCompletionIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Event Complete"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Event Identifier")
    var eventIdentifier: String

    @Parameter(title: "Calendar Item External Identifier")
    var calendarItemExternalIdentifier: String?

    @Parameter(title: "Occurrence Start Date")
    var occurrenceStartDate: Date

    @Parameter(title: "Event Title")
    var eventTitle: String?

    init() {}

    init(eventIdentifier: String, calendarItemExternalIdentifier: String?, occurrenceStartDate: Date, eventTitle: String?) {
        self.eventIdentifier = eventIdentifier
        self.calendarItemExternalIdentifier = calendarItemExternalIdentifier
        self.occurrenceStartDate = occurrenceStartDate
        self.eventTitle = eventTitle
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        CompletionMirror.note("tap on \(eventTitle ?? "?") (calendar access: \(WidgetEventStore.hasAccess))")
        // Read-only: the app is the one writer (see CompletionOutbox for why).
        let rows = (try? ModelContext(ModelContainerFactory.make()).fetch(FetchDescriptor<EventCompletionStatus>())) ?? []
        let startMs = Int64((occurrenceStartDate.timeIntervalSince1970 * 1000).rounded())
        let external = calendarItemExternalIdentifier

        // What this widget is showing right now: what's stored, overlaid with
        // any taps the app hasn't applied yet -- so two quick taps flip twice.
        let stored = EventCompletionAccess.isCompleted(
            eventIdentifier: eventIdentifier,
            calendarItemExternalIdentifier: external,
            occurrenceStartDate: occurrenceStartDate,
            in: rows
        )
        let queued = CompletionOutbox.pending().map(\.item)
        let current = CompletionOutbox.latestValue(eventIdentifier: eventIdentifier, external: external, startMs: startMs, in: queued) ?? stored

        CompletionOutbox.enqueue(PendingCompletion(
            eventIdentifier: eventIdentifier,
            external: external,
            startMs: startMs,
            title: eventTitle,
            completed: !current,
            atMs: Int64(Date.now.timeIntervalSince1970 * 1000)
        ))
        // Also publish straight to the sync calendar, so the Mac and the phone app
        // get it without waiting for the phone app to run (see CompletionMirror).
        CompletionMirror.publishFromWidget(external: external, start: occurrenceStartDate, completed: !current, title: eventTitle)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
