import AppIntents
import SwiftData
import WidgetKit

/// Lets a widget mark an event complete with one tap, without opening the
/// app. AppIntent parameters must be Codable primitives (no EKEvent), so
/// this carries the same identifying fields EventCompletionAccess matches
/// on, and writes through the same App Group-shared SwiftData container the
/// main app uses.
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
        let container = ModelContainerFactory.make()
        let context = ModelContext(container)
        let rows = (try? context.fetch(FetchDescriptor<EventCompletionStatus>())) ?? []
        EventCompletionAccess.toggle(
            eventIdentifier: eventIdentifier,
            calendarItemExternalIdentifier: calendarItemExternalIdentifier,
            occurrenceStartDate: occurrenceStartDate,
            title: eventTitle,
            in: rows,
            context: context
        )
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
