import Foundation
import Testing
@testable import CalendarApp

struct VoiceEventParserTests {
    private let parser = VoiceEventParser(calendarTitles: ["Exercise", "Church", "Work", "Game"])
    private let cal = Calendar.current

    @Test func fullSentenceFillsEveryField() {
        let d = parser.parse("Add pickleball practice tomorrow at 6 pm to 8 pm at the Warren tennis courts category exercise")
        #expect(d.title == "Pickleball Practice")
        #expect(d.calendarTitle == "Exercise")
        #expect(d.location == "Warren Tennis Courts")
        #expect(d.timeKnown)
        #expect(d.durationMinutes == 120)
        if let start = d.start {
            #expect(cal.component(.hour, from: start) == 18)
            #expect(cal.isDateInTomorrow(start))
        } else { Issue.record("no start") }
        #expect(d.isComplete)
    }

    @Test func dayWithoutTimeAsksForTheTime() {
        let d = parser.parse("lunch with Sam tomorrow")
        #expect(d.title == "Lunch With Sam")
        #expect(d.gaps == [.time])
        #expect(!d.isComplete)
    }

    @Test func reminderAndDurationAreRecognised() {
        let d = parser.parse("Gym Friday at 9:30 am for an hour remind me 30 minutes before")
        #expect(d.reminderMinutes == 30)
        #expect(d.durationMinutes == 60)
        #expect(d.title == "Gym")
    }

    @Test func allDayEvent() {
        let d = parser.parse("Hackathon all day on Saturday location UCSD")
        #expect(d.isAllDay)
        #expect(d.location == "UCSD")
        #expect(d.isComplete)
    }

    @Test func correctionChangesOnlyWhatWasSaid() {
        var d = parser.parse("Pickleball practice tomorrow at 6 pm at the Warren tennis courts")
        let day = d.start.map { cal.startOfDay(for: $0) }
        d = parser.parse("change the time to 7pm", applying: d)
        #expect(d.title == "Pickleball Practice")
        #expect(d.location == "Warren Tennis Courts")
        #expect(d.start.map { cal.startOfDay(for: $0) } == day)
        #expect(d.start.map { cal.component(.hour, from: $0) } == 19)
        #expect(d.durationMinutes == 60)
    }

    @Test func movingToAnotherDayKeepsTheTime() {
        var d = parser.parse("Dentist tomorrow at 2:30 pm")
        d = parser.parse("move it to Friday", applying: d)
        #expect(d.start.map { cal.component(.hour, from: $0) } == 14)
        #expect(d.start.map { cal.component(.minute, from: $0) } == 30)
        #expect(d.start.map { cal.component(.weekday, from: $0) } == 6)
    }

    @Test func correctionCanSetCategoryTitleAndLength() {
        var d = parser.parse("Pickleball tomorrow at 5 pm")
        d = parser.parse("category exercise", applying: d)
        d = parser.parse("call it Pickleball Club", applying: d)
        d = parser.parse("make it two hours", applying: d)
        #expect(d.calendarTitle == "Exercise")
        #expect(d.title == "Pickleball Club")
        #expect(d.durationMinutes == 120)
    }

    @Test func chatterInACorrectionDoesNotRenameTheEvent() {
        var d = parser.parse("Pickleball tomorrow at 5 pm")
        d = parser.parse("actually location the gym", applying: d)
        #expect(d.title == "Pickleball")
        #expect(d.location == "Gym")
    }
}
