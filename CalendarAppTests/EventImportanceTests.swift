import EventKit
import Foundation
import Testing
@testable import CalendarApp

@MainActor
struct EventImportanceTests {
    @Test func ordinaryEventsRemainUnchanged() {
        #expect(!EventImportance.isImportant(notes: nil))
        #expect(!EventImportance.isImportant(notes: "Bring a notebook"))
        #expect(EventImportance.notes("Bring a notebook", settingImportant: false) == "Bring a notebook")
        #expect(EventImportance.notes(nil, settingImportant: false) == nil)
    }

    @Test func importanceRoundTripsWithoutLosingUserNotes() {
        let original = "Room 203\n\nBring a notebook"
        let marked = EventImportance.notes(original, settingImportant: true)
        #expect(EventImportance.isImportant(notes: marked))
        #expect(EventImportance.displayNotes(marked) == original)
        #expect(EventImportance.notes(marked, settingImportant: true) == marked)
        #expect(EventImportance.notes(marked, settingImportant: false) == original)
    }

    @Test func markerMustBeACompleteMetadataLine() {
        #expect(!EventImportance.isImportant(notes: "Discuss [CalendarApp:important=true] syntax"))
        #expect(EventImportance.isImportant(notes: "Agenda\r\n[CalendarApp:important=true]"))
        #expect(EventImportance.notes(nil, settingImportant: true) == "[CalendarApp:important=true]")
    }

    @Test func preservesBlankLinesAtEndOfUserNotes() {
        let original = "Agenda\n\n"
        #expect(EventImportance.displayNotes(EventImportance.notes(original, settingImportant: true)) == original)
    }

    @Test func hidesRoutingMetadataWhilePreservingItOnEdit() {
        let marker = "[Shivan:request=83F8A09C-7E59-40DF-AAB7-287B34C75B94]"
        let original = "Bring notes\n" + marker + "\n" + EventImportance.marker
        #expect(EventImportance.displayNotes(original) == "Bring notes")
        let edited = EventImportance.notes("New agenda", settingImportant: false, preservingRequestsFrom: original)
        #expect(edited == "New agenda\n" + marker)
        #expect(EventImportance.displayNotes(edited) == "New agenda")
        #expect(EventImportance.notes(original, settingImportant: true) == original)
        let crlf = "Bring notes\r\n" + marker + "\r\n"
        #expect(EventImportance.displayNotes(crlf) == "Bring notes\n")
        #expect(EventImportance.notes("New agenda", settingImportant: false, preservingRequestsFrom: crlf) == "New agenda\n" + marker)
    }

    @Test func importantOverridesReminderAndTurningOffRestoresIt() {
        let event = EKEvent(eventStore: EKEventStore())
        event.notes = EventImportance.notes("Call details", settingImportant: true)
        #expect(EventReminderAccess.effectiveMinutes(for: event, in: []) == 30)
        event.notes = EventImportance.notes(event.notes, settingImportant: false)
        // Without a writable calendar or explicit preference, there is no default.
        #expect(EventReminderAccess.effectiveMinutes(for: event, in: []) == nil)
    }

    @Test func importantAlertMovesWithEventAndDoesNotFireLate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = now.addingTimeInterval(3600)
        #expect(EventImportance.fireDate(start: start, now: now) == start.addingTimeInterval(-1800))
        #expect(EventImportance.fireDate(start: start.addingTimeInterval(600), now: now) == start.addingTimeInterval(-1200))
        #expect(EventImportance.fireDate(start: now.addingTimeInterval(1200), now: now) == nil)
    }
}
