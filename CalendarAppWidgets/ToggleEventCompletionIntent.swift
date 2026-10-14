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

    /// Same-title, same-time copies shown as this one row (see EventSummary).
    @Parameter(title: "Duplicate Event Identifiers", default: [])
    var peerEventIdentifiers: [String]

    @Parameter(title: "Duplicate External Identifiers", default: [])
    var peerExternalIdentifiers: [String]

    init() {}

    init(
        eventIdentifier: String,
        calendarItemExternalIdentifier: String?,
        occurrenceStartDate: Date,
        eventTitle: String?,
        peerEventIdentifiers: [String] = [],
        peerExternalIdentifiers: [String] = []
    ) {
        self.peerEventIdentifiers = peerEventIdentifiers
        self.peerExternalIdentifiers = peerExternalIdentifiers
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
        let queued = CompletionOutbox.pending().map(\.item)

        // Every copy of this row: the tapped event plus same-time duplicates.
        var members: [(eventIdentifier: String, external: String?)] = [(eventIdentifier, calendarItemExternalIdentifier)]
        for (index, id) in peerEventIdentifiers.enumerated() {
            let external = index < peerExternalIdentifiers.count ? peerExternalIdentifiers[index] : ""
            members.append((id, external.isEmpty ? nil : external))
        }

        // What this widget is showing right now: done if any copy is done,
        // counting taps the app hasn't applied yet -- so two quick taps flip twice.
        let current = members.contains { member in
            let stored = EventCompletionAccess.isCompleted(
                eventIdentifier: member.eventIdentifier,
                calendarItemExternalIdentifier: member.external,
                occurrenceStartDate: occurrenceStartDate,
                in: rows
            )
            return CompletionOutbox.latestValue(eventIdentifier: member.eventIdentifier, external: member.external, startMs: startMs, in: queued) ?? stored
        }

        for member in members {
            CompletionOutbox.enqueue(PendingCompletion(
                eventIdentifier: member.eventIdentifier,
                external: member.external,
                startMs: startMs,
                title: eventTitle,
                completed: !current,
                atMs: Int64(Date.now.timeIntervalSince1970 * 1000)
            ))
            // Also publish straight to the sync calendar, so the Mac and the phone app
            // get it without waiting for the phone app to run (see CompletionMirror).
            CompletionMirror.publishFromWidget(external: member.external, start: occurrenceStartDate, completed: !current, title: eventTitle)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
