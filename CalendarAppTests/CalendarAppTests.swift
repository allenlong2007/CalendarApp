import Foundation
import Testing
@testable import CalendarApp

/// Builds a local-midnight date in the same calendar DateMath uses, so these
/// tests hold in any time zone the simulator happens to be set to.
private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    DateMath.calendar.date(from: DateComponents(year: year, month: month, day: day))!
}

struct DateMathTests {
    @Test func weekStartsOnSunday() {
        // Wednesday, Oct 1 2025 -> Sunday, Sep 28 2025
        #expect(DateMath.startOfWeek(containing: day(2025, 10, 1), weekStartDay: 0) == day(2025, 9, 28))
    }

    @Test func weekStartsOnMonday() {
        #expect(DateMath.startOfWeek(containing: day(2025, 10, 1), weekStartDay: 1) == day(2025, 9, 29))
    }

    @Test func weekStartDayIsItsOwnWeekStart() {
        // Sunday already is the start of a Sunday-based week, even late in the day.
        let sundayEvening = DateMath.calendar.date(byAdding: .hour, value: 20, to: day(2025, 9, 28))!
        #expect(DateMath.startOfWeek(containing: sundayEvening, weekStartDay: 0) == day(2025, 9, 28))
    }

    @Test(arguments: 0...6)
    func monthGridIsSixAlignedWeeksCoveringTheMonth(weekStartDay: Int) {
        let grid = DateMath.monthGridDays(containing: day(2026, 2, 14), weekStartDay: weekStartDay)

        #expect(grid.count == 42)
        #expect(DateMath.weekdayIndex(of: grid[0]) == weekStartDay)
        #expect(grid[0] <= day(2026, 2, 1))
        #expect(grid.contains(day(2026, 2, 1)))
        #expect(grid.contains(day(2026, 2, 28)))
        for (a, b) in zip(grid, grid.dropFirst()) {
            #expect(DateMath.addingDays(1, to: a) == b)
        }
    }

    @Test func monthGridStartsOnTheFirstWhenItFallsOnWeekStart() {
        // Feb 1 2026 is a Sunday.
        #expect(DateMath.monthGridDays(containing: day(2026, 2, 20), weekStartDay: 0).first == day(2026, 2, 1))
    }

    @Test func addingAMonthClampsToShorterMonth() {
        #expect(DateMath.addingMonths(1, to: day(2026, 1, 31)) == day(2026, 2, 28))
    }

    @Test func endOfDayIsTheLastSecondOfTheSameDay() {
        let end = DateMath.endOfDay(day(2026, 3, 8))
        #expect(DateMath.isSameDay(end, day(2026, 3, 8)))
        #expect(DateMath.addingDays(1, to: day(2026, 3, 8)).timeIntervalSince(end) == 1)
    }

    @Test func sameMonthComparesYearToo() {
        #expect(DateMath.isSameMonth(day(2026, 5, 1), day(2026, 5, 31)))
        #expect(!DateMath.isSameMonth(day(2026, 5, 1), day(2027, 5, 1)))
    }
}

struct GmailDateDetectionTests {
    @Test func usesFallbackWhenTextHasNoDate() {
        let fallback = day(2026, 1, 1)
        #expect(GmailEventExtractor.detectDate(in: "Thanks for your order!", fallback: fallback) == fallback)
    }

    @Test func findsTheReservationDate() throws {
        let found = try #require(GmailEventExtractor.detectDate(
            in: "Your table is confirmed for January 15, 2030 at 7:00 PM.",
            fallback: nil
        ))
        let parts = DateMath.calendar.dateComponents([.year, .month, .day], from: found)
        #expect(parts.year == 2030 && parts.month == 1 && parts.day == 15)
    }

    @Test func prefersAFutureDateOverAnEarlierOne() throws {
        let found = try #require(GmailEventExtractor.detectDate(
            in: "Booked on March 3, 2020. Your appointment is December 5, 2030.",
            fallback: nil
        ))
        let parts = DateMath.calendar.dateComponents([.year, .month, .day], from: found)
        #expect(parts.year == 2030 && parts.month == 12 && parts.day == 5)
    }
}
