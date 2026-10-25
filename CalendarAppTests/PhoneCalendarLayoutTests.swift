import Foundation
import Testing
@testable import CalendarApp

struct PhoneCalendarLayoutTests {
    @Test func desktopRowsFitExactlyAtEveryHeight() {
        for height in [180.0, 260, 329, 330, 600, 1000] {
            let count = CalendarViewportLayout.desktopWeekCount(height: height)
            #expect(count == (height < 330 ? 2 : 3))
            let row = CalendarViewportLayout.rowHeight(height: height, count: count)
            #expect(abs(row * Double(count) + Double(count - 1) - height) < 0.001)
        }
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateMath.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test(arguments: 0...6)
    func monthContainsOnlyItsOwnDays(weekStart: Int) {
        let slots = PhoneCalendarLayout.monthSlots(containing: date(2026, 10, 24), weekStartDay: weekStart)
        let days = slots.compactMap { $0 }
        #expect(slots.count % 7 == 0)
        #expect(days.count == 31)
        #expect(days.first == date(2026, 10, 1))
        #expect(days.last == date(2026, 10, 31))
        let first = slots.firstIndex(where: { $0 != nil })!
        #expect((weekStart + first) % 7 == DateMath.weekdayIndex(of: days[0]))
    }

    @Test func monthUsesOnlyTheRowsItNeedsIncludingLeapYear() {
        #expect(PhoneCalendarLayout.monthSlots(containing: date(2026, 2, 14), weekStartDay: 0).count == 28)
        #expect(PhoneCalendarLayout.monthSlots(containing: date(2028, 2, 14), weekStartDay: 0).compactMap { $0 }.count == 29)
        #expect(PhoneCalendarLayout.monthSlots(containing: date(2026, 8, 14), weekStartDay: 0).count == 42)
    }

    @Test(arguments: 0...6)
    func landscapeShowsFocusedWeekAndNextWeek(weekStart: Int) {
        let focus = date(2026, 10, 24)
        let current = DateMath.startOfWeek(containing: focus, weekStartDay: weekStart)
        let weeks = PhoneCalendarLayout.weekStarts(around: focus, weekStartDay: weekStart)
        #expect(weeks == [0, 1].map { DateMath.addingWeeks($0, to: current) })
    }

    @Test func pagingCrossesYearBoundariesAndHandlesShortMonths() {
        let anchor = date(2026, 12, 31)
        #expect(CalendarPagePeriod.month.date(at: 2, from: anchor) == date(2027, 2, 28))
        #expect(CalendarPagePeriod.month.index(of: date(2027, 2, 3), from: anchor, weekStartDay: 0) == 2)
        #expect(CalendarPagePeriod.month.index(of: date(2025, 12, 1), from: anchor, weekStartDay: 0) == -12)
        #expect(CalendarPagePeriod.week.index(of: date(2027, 1, 4), from: anchor, weekStartDay: 1) == 1)
    }

    @Test func weekPagingUsesCalendarDaysAcrossDaylightSaving() {
        let anchor = date(2026, 3, 4)
        let next = CalendarPagePeriod.week.date(at: 1, from: anchor)
        #expect(next == date(2026, 3, 11))
        #expect(CalendarPagePeriod.week.index(of: next, from: anchor, weekStartDay: 0) == 1)
    }

    @Test func dayPagingCrossesMonthYearAndDaylightSavingBoundaries() {
        #expect(CalendarPagePeriod.day.date(at: 1, from: date(2026, 12, 31)) == date(2027, 1, 1))
        #expect(CalendarPagePeriod.day.date(at: -1, from: date(2028, 3, 1)) == date(2028, 2, 29))
        let start = date(2026, 3, 7)
        let end = date(2026, 3, 10)
        #expect(CalendarPagePeriod.day.index(of: end, from: start, weekStartDay: 0) == 3)
        #expect(CalendarPagePeriod.day.index(of: start, from: end, weekStartDay: 0) == -3)
    }
}
