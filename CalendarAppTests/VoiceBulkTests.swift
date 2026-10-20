import Foundation
import Testing
@testable import CalendarApp

struct VoiceBulkTests {
    private let cal = Calendar.current
    private var quarterEnd: Date { cal.date(byAdding: .day, value: 49, to: cal.startOfDay(for: .now))! }   // seven weeks out
    private var parser: VoiceEventParser { VoiceEventParser(calendarTitles: ["Exercise"], quarterEnd: quarterEnd) }

    @Test func everyFridayForTheRestOfTheQuarter() {
        let d = parser.parse("add pickleball every Friday at 5 pm for the rest of the quarter")
        let dates = d.occurrences()
        #expect(d.title == "Pickleball")
        #expect(!dates.isEmpty)
        #expect(dates.allSatisfy { cal.component(.weekday, from: $0) == 6 && cal.component(.hour, from: $0) == 17 })
        #expect(dates.allSatisfy { cal.startOfDay(for: $0) <= quarterEnd })
        #expect(dates.count >= 6 && dates.count <= 8)
        #expect(d.isComplete)
    }

    @Test func nextFewWeeksMeansThree() {
        let d = parser.parse("study session every Thursday at 6 pm the next few weeks")
        #expect(d.occurrences().count == 3)
    }

    @Test func nextNWeeksAndTimes() {
        #expect(parser.parse("tutoring every Monday at 4 pm for 4 weeks").occurrences().count == 4)
        #expect(parser.parse("call mom every Sunday at noon for 4 times").occurrences().count == 4)
    }

    @Test func weekdaysAndEveryDay() {
        let weekdays = parser.parse("gym every weekday at 9:30 am for the next 2 weeks").occurrences()
        #expect(weekdays.count == 10 || weekdays.count == 9 || weekdays.count == 8)   // today may already be past
        #expect(weekdays.allSatisfy { (2...6).contains(cal.component(.weekday, from: $0)) })
        let everyDay = parser.parse("standup every day this week at 10 am").occurrences()
        #expect(!everyDay.isEmpty && everyDay.count <= 7)
    }

    @Test func manyDaysNeedAnEndBeforeTheyCanBeAdded() {
        let d = parser.parse("lab every Friday at 1 pm")
        #expect(d.gaps == [.repeatEnd])
        #expect(!d.isComplete)
    }

    @Test func skippingAHolidayAndLaterCorrections() {
        var d = parser.parse("pickleball every Thursday at 6 pm for the rest of the quarter")
        let before = d.occurrences().count
        let thursday = d.occurrences().first!
        d = parser.parse("skip \(DateMath.monthDayFormatter.string(from: thursday).dropFirst(5))", applying: d)   // "Oct 22"
        #expect(d.occurrences().count == before - 1)
        d = parser.parse("make it 7 pm", applying: d)
        #expect(d.occurrences().allSatisfy { cal.component(.hour, from: $0) == 19 })
    }

    @Test func thanksgivingIsUnderstood() {
        let day = SpokenDateResolver().day(in: "Thanksgiving", now: .now)!
        #expect(cal.component(.weekday, from: day) == 5)
        #expect(cal.component(.month, from: day) == 11)
        #expect((22...28).contains(cal.component(.day, from: day)))
    }

    // MARK: delete

    private func refs() -> [EventRef] {
        let today = cal.startOfDay(for: .now)
        func at(_ offset: Int, _ hour: Int) -> Date { cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: offset, to: today)!)! }
        var list: [EventRef] = []
        for week in 0..<6 { list.append(EventRef(id: "tp\(week)", title: "Pickleball Team Practice", start: at(3 + 7 * week, 17))) }
        list.append(EventRef(id: "past", title: "Pickleball Team Practice", start: at(-8, 17)))
        list.append(EventRef(id: "gym", title: "Gym", start: at(1, 9)))
        return list
    }

    @Test func deleteAllMatchesEveryUpcomingEventButNeverThePast() {
        guard case .delete(let request) = VoiceIntentClassifier(quarterEnd: quarterEnd).classify("delete all pickleball team practice") else { Issue.record("not a delete"); return }
        #expect(request.isAll)
        let ids = VoiceDeleteMatcher.matches(request, in: refs()).map(\.id)
        #expect(ids == ["tp0", "tp1", "tp2", "tp3", "tp4", "tp5"])
    }

    @Test func deleteAllHonoursARange() {
        guard case .delete(let request) = VoiceIntentClassifier(quarterEnd: quarterEnd).classify("delete all pickleball team practice for the next 2 weeks") else { Issue.record("not a delete"); return }
        let ids = VoiceDeleteMatcher.matches(request, in: refs()).map(\.id)
        #expect(ids == ["tp0", "tp1"])
    }

    @Test func deleteAllNeedsAnEventNameAndAKnownRange() {
        guard case .delete(let everything) = VoiceIntentClassifier().classify("delete all events") else { Issue.record("not a delete"); return }
        #expect(VoiceDeleteMatcher.matches(everything, in: refs()).isEmpty)
        guard case .delete(let unknownQuarter) = VoiceIntentClassifier(quarterEnd: nil).classify("delete all pickleball for the rest of the quarter") else { Issue.record("not a delete"); return }
        #expect(unknownQuarter.rangeUnresolved)
        #expect(VoiceDeleteMatcher.matches(unknownQuarter, in: refs()).isEmpty)
    }

    @Test func massConfirmationIsExplicit() {
        #expect(VoiceIntentClassifier().classify("delete them") == .confirmDelete)
        #expect(VoiceIntentClassifier().classify("delete all") == .confirmDelete)
        #expect(VoiceIntentClassifier().classify("ok") == .confirm)
    }
}

struct VoiceDuplicateTests {
    private let cal = Calendar.current
    private var quarterEnd: Date { cal.date(byAdding: .day, value: 49, to: cal.startOfDay(for: .now))! }
    private var parser: VoiceEventParser { VoiceEventParser(calendarTitles: ["Tech"], quarterEnd: quarterEnd) }

    private func source() -> DuplicateSource {
        var day = cal.startOfDay(for: .now)
        while cal.component(.weekday, from: day) != 5 { day = cal.date(byAdding: .day, value: 1, to: day)! }   // a Thursday
        return DuplicateSource(
            title: "Speak Up meeting",
            start: cal.date(bySettingHour: 14, minute: 0, second: 0, of: day)!,
            end: cal.date(bySettingHour: 15, minute: 0, second: 0, of: day)!,
            isAllDay: false, calendarTitle: "Tech", location: "Center Hall", notes: nil)
    }

    @Test func duplicateIsAnIntentNotATitle() {
        guard case .duplicate(let rest) = VoiceIntentClassifier(quarterEnd: quarterEnd).classify("Duplicate the Speak Up meeting to every Thursday same time same everything else for the rest of the quarter") else {
            Issue.record("not a duplicate"); return
        }
        #expect(parser.duplicateTitleWords(from: rest) == ["speak", "up", "meeting"])
    }

    @Test func copyKeepsEverythingAndStartsAfterTheOriginal() {
        let original = source()
        let rest = "the Speak Up meeting to every Thursday same time same everything else for the rest of the quarter"
        let draft = parser.duplicate(original, saying: rest)
        #expect(draft.title == "Speak Up meeting")           // never "Duplicate ..."
        #expect(draft.calendarTitle == "Tech")
        #expect(draft.location == "Center Hall")
        let dates = draft.occurrences()
        #expect(!dates.isEmpty)
        #expect(dates.allSatisfy { cal.component(.weekday, from: $0) == 5 && cal.component(.hour, from: $0) == 14 })
        #expect(dates.first! > original.start)
        #expect(draft.durationMinutes == 60)
        #expect(draft.isComplete)
    }

    @Test func weekdayIsOptionalAndSpansCountFromTheFirstCopy() {
        let original = source()
        let weekly = parser.duplicate(original, saying: "speak up meeting for the rest of the quarter")
        #expect(weekly.isComplete)
        #expect(weekly.occurrences().allSatisfy { cal.component(.weekday, from: $0) == 5 })
        let three = parser.duplicate(original, saying: "speak up meeting every Thursday for the next 3 weeks")
        #expect(three.occurrences().count == 3)
    }

    @Test func plainCopyOfItOrThatIsNotADuplicateRequest() {
        #expect(VoiceIntentClassifier().classify("duplicate it") == .describeEvent)
    }
}
