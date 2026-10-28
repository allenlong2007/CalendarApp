import Foundation
import Testing
@testable import CalendarApp

struct VoiceIntentTests {
    private let classifier = VoiceIntentClassifier()
    private let cal = Calendar.current

    @Test func recognisesDeleteWithNameAndDay() {
        guard case .delete(let request) = classifier.classify("Delete the speak up meeting on Thursday") else { Issue.record("not a delete"); return }
        #expect(request.titleWords == ["speak", "meeting"])
        #expect(request.day.map { cal.component(.weekday, from: $0) } == 5)
    }

    @Test func confirmAndCancelAreRecognised() {
        #expect(classifier.classify("yes") == .confirm)
        #expect(classifier.classify("ok") == .confirm)
        #expect(classifier.classify("delete it") == .confirmDelete)
        #expect(classifier.classify("yes delete it") == .confirmDelete)
        #expect(classifier.classify("never mind") == .cancel)
        #expect(classifier.classify("cancel") == .cancel)
    }

    @Test func cancelWithANameIsADelete() {
        guard case .delete(let request) = classifier.classify("cancel pickleball team practice Monday") else { Issue.record("not a delete"); return }
        #expect(request.titleWords == ["pickleball", "team", "practice"])
    }

    @Test func eventDescriptionsAreNotDeletes() {
        #expect(classifier.classify("Add lunch tomorrow at noon") == .describeEvent)
        #expect(classifier.classify("make it 7pm") == .describeEvent)
    }

    @Test func matcherNeedsATitleAndPrefersUpcoming() {
        let now = Date.now
        func day(_ offset: Int, _ hour: Int) -> Date {
            cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!)!
        }
        let events = [
            EventRef(id: "past", title: "Pickleball Team Practice", start: day(-5, 17)),
            EventRef(id: "soon", title: "Pickleball Team Practice", start: day(2, 17)),
            EventRef(id: "gym", title: "Gym", start: day(1, 9)),
        ]
        let byName = VoiceDeleteMatcher.matches(VoiceDeleteRequest(titleWords: ["pickleball", "practice"], day: nil, hour: nil), in: events, now: now)
        #expect(byName.map(\.id) == ["soon", "past"])
        let dayOnly = VoiceDeleteMatcher.matches(VoiceDeleteRequest(titleWords: [], day: day(1, 0), hour: nil), in: events, now: now)
        #expect(dayOnly.isEmpty)
        // Whole words only, and all of them.
        let practiceInsideAnotherWord = [EventRef(id: "x", title: "Malpractice review", start: day(1, 10))]
        #expect(VoiceDeleteMatcher.matches(VoiceDeleteRequest(titleWords: ["practice"], day: nil, hour: nil), in: practiceInsideAnotherWord, now: now).isEmpty)
        #expect(VoiceDeleteMatcher.matches(VoiceDeleteRequest(titleWords: ["pickleball", "tryouts", "finals"], day: nil, hour: nil), in: events, now: now).isEmpty)
    }
}

struct VoiceLocationChangeTests {
    @Test func targetsOnlyNamedThursdayPractices() {
        guard case .changeLocation(let request) = VoiceIntentClassifier().classify("change all Thursday pickleball team practice locations to mirror tennis courts") else {
            Issue.record("Not a location change"); return
        }
        #expect(request.location == "Muir Tennis Courts")
        #expect(request.target.isAll)
        #expect(request.target.weekdays == [5])
        #expect(Set(request.target.titleWords) == ["pickleball", "team", "practice"])
    }
}
