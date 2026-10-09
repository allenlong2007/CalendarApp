import Foundation
import SwiftData
import Testing
@testable import CalendarApp

@MainActor
struct CompletionMirrorTests {
    /// The widget publishes with CompletionMirror's own builder; the app's sync
    /// reads rows with SyncAdapters. If these ever disagree on id or payload, a
    /// widget tap would show up as a second, conflicting record.
    @Test func widgetRecordMatchesWhatTheAppWouldPublishForTheSameCheckmark() throws {
        let container = try ModelContainer(for: EventCompletionStatus.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_800_000_123.456)
        context.insert(EventCompletionStatus(eventIdentifier: "", calendarItemExternalIdentifier: "ext-1", completed: true, lastKnownStartDate: start, lastKnownTitle: "Gym"))
        try context.save()

        let collected = SyncAdapters(context: context, calendars: []).collect()
        let id = CompletionMirror.recordID(external: "ext-1", start: start)
        #expect(collected[id] == CompletionMirror.payload(external: "ext-1", start: start, completed: true, title: "Gym"))
    }
}
