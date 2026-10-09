import Foundation
import Testing
@testable import CalendarApp

struct CompletionOutboxTests {
    private func item(external: String?, id: String = "local", start: Int64, completed: Bool, at: Int64) -> PendingCompletion {
        PendingCompletion(eventIdentifier: id, external: external, startMs: start, title: "Gym", completed: completed, atMs: at)
    }

    @Test func newestQueuedChangeWins() {
        let items = [
            item(external: "ext", start: 1_000_000, completed: true, at: 1),
            item(external: "ext", start: 1_000_000, completed: false, at: 3),
            item(external: "ext", start: 1_000_000, completed: true, at: 2),
        ]
        #expect(CompletionOutbox.latestValue(eventIdentifier: "local", external: "ext", startMs: 1_000_000, in: items) == false)
    }

    @Test func onlyTheTappedOccurrenceOfARepeatingEventIsAffected() {
        // Every occurrence of a series shares its ids; the start time is what tells them apart.
        let items = [item(external: "series", start: 1_000_000, completed: true, at: 1)]
        let sameDay: Int64 = 1_000_000 + 30_000                       // within a minute: same occurrence
        let nextWeek: Int64 = 1_000_000 + 7 * 86_400_000
        #expect(CompletionOutbox.latestValue(eventIdentifier: "x", external: "series", startMs: sameDay, in: items) == true)
        #expect(CompletionOutbox.latestValue(eventIdentifier: "x", external: "series", startMs: nextWeek, in: items) == nil)
    }

    @Test func differentEventsDontCollide() {
        let items = [item(external: "gym", start: 1_000_000, completed: true, at: 1)]
        #expect(CompletionOutbox.latestValue(eventIdentifier: "x", external: "lecture", startMs: 1_000_000, in: items) == nil)
    }

    @Test func fallsBackToTheLocalIdWhenThereIsNoCrossDeviceId() {
        let items = [item(external: nil, id: "abc", start: 1_000_000, completed: true, at: 1)]
        #expect(CompletionOutbox.latestValue(eventIdentifier: "abc", external: nil, startMs: 1_000_000, in: items) == true)
        #expect(CompletionOutbox.latestValue(eventIdentifier: "zzz", external: nil, startMs: 1_000_000, in: items) == nil)
    }

    @Test func nothingQueuedMeansNoOverride() {
        #expect(CompletionOutbox.latestValue(eventIdentifier: "a", external: "e", startMs: 1, in: []) == nil)
    }
}
