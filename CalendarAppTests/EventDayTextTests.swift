import EventKit
import Foundation
import Testing
@testable import CalendarApp

@MainActor
struct EventDayTextTests {
    private func overnightEvent() -> (EKEvent, Date, Date) {
        let cal = Calendar.current
        let day1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 24))!
        let day2 = cal.date(byAdding: .day, value: 1, to: day1)!
        let event = EKEvent(eventStore: EKEventStore())
        event.startDate = cal.date(bySettingHour: 23, minute: 30, second: 0, of: day1)!
        event.endDate = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day2)!
        return (event, day1, day2)
    }

    @Test func nextDayShowsOnlyThatDaysHours() {
        let (event, _, day2) = overnightEvent()
        let text = EventDayGrouping.timeRangeText(of: event, on: day2)
        #expect(text.hasPrefix(DateMath.timeFormatter.string(from: day2)))   // starts at midnight
        #expect(text.hasSuffix(DateMath.timeFormatter.string(from: event.endDate)))
        #expect(!text.contains(DateMath.timeFormatter.string(from: event.startDate)) || DateMath.timeFormatter.string(from: event.startDate) == DateMath.timeFormatter.string(from: day2))
    }

    @Test func firstDayRunsUntilMidnight() {
        let (event, day1, day2) = overnightEvent()
        let text = EventDayGrouping.timeRangeText(of: event, on: day1)
        #expect(text.hasPrefix(DateMath.timeFormatter.string(from: event.startDate)))
        #expect(text.hasSuffix(DateMath.timeFormatter.string(from: day2)))
    }

    @Test func singleDayEventIsUnchanged() {
        let cal = Calendar.current
        let day = cal.date(from: DateComponents(year: 2026, month: 10, day: 24))!
        let event = EKEvent(eventStore: EKEventStore())
        event.startDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        event.endDate = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
        #expect(EventDayGrouping.timeRangeText(of: event, on: day)
            == "\(DateMath.timeFormatter.string(from: event.startDate)) – \(DateMath.timeFormatter.string(from: event.endDate))")
    }
}

@MainActor
struct WeekdayLocationOverrideTests {
    @Test func thursdayFallbackDoesNotChangeOtherWeekdays() {
        let store = EKEventStore()
        let title = "Pickleball Team Practice"
        let rows = [EventLocationOverride(titleKey: title, locationText: "Warren Tennis Courts"),
                    EventLocationOverride(titleKey: EventLocationAccess.scopedTitle(title, weekday: 5), locationText: "Muir Tennis Courts")]
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 17))!
        event.endDate = event.startDate.addingTimeInterval(3600)
        #expect(EventLocationAccess.displayLocation(for: event, in: rows)?.text == "Muir Tennis Courts")
        event.startDate = Calendar.current.date(byAdding: .day, value: 1, to: event.startDate)!
        #expect(EventLocationAccess.displayLocation(for: event, in: rows)?.text == "Warren Tennis Courts")
        event.location = "Special Match Venue"
        #expect(EventLocationAccess.displayLocation(for: event, in: rows)?.text == "Special Match Venue")
    }
}
