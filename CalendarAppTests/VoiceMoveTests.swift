import Foundation
import Testing
@testable import CalendarApp

struct VoiceMoveTests {
    private let classifier = VoiceIntentClassifier()

    private func move(_ s: String) -> VoiceMoveRequest? {
        if case .move(let m) = classifier.classify(s) { return m }
        return nil
    }

    @Test func thisEventOneDayForward() {
        let m = move("move this event one day forward")
        #expect(m?.useSelected == true)
        #expect(m?.amount == 1 && m?.unit == .day && m?.direction == 1)
    }

    @Test func pushBackMeansLater() {
        let m = move("push this event 2 months back")
        #expect(m?.amount == 2 && m?.unit == .month && m?.direction == 1)
    }

    @Test func moveBackMeansEarlier() {
        #expect(move("move it back a day")?.direction == -1)
    }

    @Test func namedEventAndAbsoluteDestination() {
        let m = move("move the pickleball practice to Friday at 3 pm")
        #expect(m?.target.titleWords == ["pickleball", "practice"])
        #expect(m?.destination == "friday at 3 pm")
    }

    @Test func shiftAddsToTheDate() {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        let m = move("push this event 2 months back")!
        #expect(m.shifted(start, calendar: cal) == cal.date(from: DateComponents(year: 2026, month: 12, day: 31)))
    }

    @Test func deleteIsNotAMove() {
        #expect(move("delete the dentist") == nil)
    }
}

struct VoiceMultiTests {
    private let classifier = VoiceIntentClassifier()
    private let parser = VoiceEventParser(calendarTitles: ["Exercise"])

    @Test func oneShiftCoversSeveralEvents() {
        guard case .move(let m) = classifier.classify("move the dentist and the haircut back one day") else { Issue.record("not a move"); return }
        #expect(m.parts.count == 2)
        #expect(m.parts.map(\.target.titleWords) == [["dentist"], ["haircut"]])
        #expect(m.parts.allSatisfy { $0.amount == 1 && $0.direction == -1 })
    }

    @Test func eachEventCanHaveItsOwnShift() {
        guard case .move(let m) = classifier.classify("move the dentist one day forward and push the haircut 2 days back") else { Issue.record("not a move"); return }
        #expect(m.parts.map(\.amount) == [1, 2])
        #expect(m.parts.map(\.direction) == [1, 1])
    }

    @Test func deleteSplitsIntoNamesAndSharesTheDay() {
        guard case .delete(let r) = classifier.classify("delete the dentist and the haircut on Friday") else { Issue.record("not a delete"); return }
        #expect(r.splitParts.map(\.titleWords) == [["dentist"], ["haircut"]])
        #expect(r.splitParts.allSatisfy { $0.day != nil })
    }

    @Test func addOnSeveralDays() {
        let d = parser.parse("add study group on tuesday and next friday at 3 pm")
        #expect(d.title == "Study Group")
        #expect(d.occurrences().count == 2)
        #expect(d.occurrences().allSatisfy { Calendar.current.component(.hour, from: $0) == 15 })
    }

    @Test func namesWithAndStayOneEvent() {
        let d = parser.parse("dinner with sam and alex tomorrow at 7 pm")
        #expect(d.occurrences().count == 1)
    }
}
