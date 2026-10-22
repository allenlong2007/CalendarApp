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

struct SpokenDateTests {
    private let parser = VoiceEventParser(calendarTitles: ["Exercise"])
    private let cal = Calendar.current

    private func startOfWeek(_ date: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: date)!.start }

    @Test func thursdayNextWeek() {
        let d = parser.parse("dentist Thursday next week at 2pm")
        #expect(d.title == "Dentist")
        let start = d.start!
        #expect(cal.component(.weekday, from: start) == 5)
        #expect(startOfWeek(start) == cal.date(byAdding: .day, value: 7, to: startOfWeek(.now)))
        #expect(cal.component(.hour, from: start) == 14)
    }

    @Test func thisWeekWithAWeekday() {
        let d = parser.parse("gym this week Wednesday at 9am")
        #expect(cal.component(.weekday, from: d.start!) == 4)
        #expect(startOfWeek(d.start!) == startOfWeek(.now))
    }

    @Test func bareNextWeekIsSevenDaysOut() {
        let d = parser.parse("lunch next week")
        #expect(cal.isDate(d.start!, inSameDayAs: cal.date(byAdding: .day, value: 7, to: .now)!))
        #expect(d.gaps == [.time])
    }

    @Test func inTwoWeeksAndTheDayAfterTomorrow() {
        let weeks = parser.parse("meeting in two weeks at 3 pm")
        #expect(cal.isDate(weeks.start!, inSameDayAs: cal.date(byAdding: .day, value: 14, to: .now)!))
        let after = parser.parse("call mom the day after tomorrow at noon")
        #expect(cal.isDate(after.start!, inSameDayAs: cal.date(byAdding: .day, value: 2, to: .now)!))
        #expect(cal.component(.hour, from: after.start!) == 12)
    }

    @Test func theTwentyFifthIsTheNextTwentyFifth() {
        let d = parser.parse("project due the 25th at 5 pm")
        let start = d.start!
        #expect(cal.component(.day, from: start) == 25)
        #expect(start >= cal.startOfDay(for: .now))
        #expect(d.title == "Project Due")
    }

    @Test func weekendsResolveToSaturday() {
        let d = parser.parse("hike next weekend at 8 am")
        #expect(cal.component(.weekday, from: d.start!) == 7)
        #expect(d.start! > cal.date(byAdding: .day, value: 6, to: .now)!)
    }

    @Test func wordsTheDetectorSwallowsStayInTheTitle() {
        #expect(parser.parse("team lunch 10/28 at 12:30 pm").title == "Team Lunch")
    }

    @Test func deleteUnderstandsTheSamePhrases() {
        guard case .delete(let request) = VoiceIntentClassifier().classify("delete the speak up meeting Thursday next week") else { Issue.record("not a delete"); return }
        #expect(request.titleWords == ["speak", "meeting"])
        #expect(request.day.map { cal.component(.weekday, from: $0) } == 5)
        #expect(request.day.map { startOfWeek($0) } == cal.date(byAdding: .day, value: 7, to: startOfWeek(.now)))
    }

    // MARK: - Reminders

    @Test func remindMeInSixMonthsIsAnAllDayItemSixMonthsOut() {
        let d = parser.parse("remind me in 6 months to renew my passport")
        #expect(d.title == "Renew My Passport")
        #expect(d.isAllDay)
        #expect(cal.isDate(d.start!, inSameDayAs: cal.date(byAdding: .month, value: 6, to: .now)!))
    }

    @Test func setAReminderForATimeKeepsTheTimeAndTitle() {
        let d = parser.parse("set a reminder for tomorrow at 3 pm to call mom")
        #expect(d.title == "Call Mom")
        #expect(cal.component(.hour, from: d.start!) == 15)
        #expect(d.durationMinutes == 15)
    }

    @Test func remindMeInTwentyMinutesIsRelativeToNow() {
        let now = Date()
        let d = parser.parse("set a reminder in 20 minutes to check the oven", now: now)
        #expect(d.title == "Check The Oven")
        #expect(abs(d.start!.timeIntervalSince(now) - 20 * 60) < 60)
    }

    @Test func minutesBeforeStillMeansAnAlert() {
        let d = parser.parse("dentist tomorrow remind me 30 minutes before")
        #expect(d.reminderMinutes == 30)
        #expect(d.title == "Dentist")
    }
}
