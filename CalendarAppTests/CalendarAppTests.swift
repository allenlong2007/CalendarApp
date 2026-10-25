import Foundation
import EventKit
import UIKit
import Testing
@testable import CalendarApp

@MainActor
struct CalendarEventCacheTests {
    @Test func redrawsReuseEventsAndChangesInvalidateThem() {
        let cache = CalendarEventCache(capacity: 4)
        let key = CalendarEventCache.Key(start: .distantPast, end: .distantFuture, calendarIdentifiers: ["b", "a"])
        let reordered = CalendarEventCache.Key(start: .distantPast, end: .distantFuture, calendarIdentifiers: ["a", "b"])
        var fetches = 0
        for _ in 0..<50 {
            _ = cache.events(for: reordered, revision: 1) { fetches += 1; return [] }
        }
        _ = cache.events(for: key, revision: 1) { fetches += 1; return [] }
        #expect(fetches == 1)
        _ = cache.events(for: key, revision: 2) { fetches += 1; return [] }
        #expect(fetches == 2)
        let hiddenCalendar = CalendarEventCache.Key(start: .distantPast, end: .distantFuture, calendarIdentifiers: ["a"])
        _ = cache.events(for: hiddenCalendar, revision: 2) { fetches += 1; return [] }
        #expect(fetches == 3)
    }

    @Test func boundedCacheKeepsRecentlyViewedWeeks() {
        let cache = CalendarEventCache(capacity: 2)
        func key(_ day: Double) -> CalendarEventCache.Key {
            .init(start: Date(timeIntervalSince1970: day), end: .distantFuture, calendarIdentifiers: nil)
        }
        var fetches = 0
        for day in [1.0, 2, 1, 3, 1] {
            _ = cache.events(for: key(day), revision: 0) { fetches += 1; return [] }
        }
        #expect(fetches == 3)
        _ = cache.events(for: key(2), revision: 0) { fetches += 1; return [] }
        #expect(fetches == 4)
    }
}

@MainActor
struct CalendarColorOrderTests {
    @Test func groupsHuesAndKeepsNeutralTonesTogether() {
        let store = EKEventStore()
        func category(_ title: String, _ color: UIColor) -> EKCalendar {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = title
            calendar.cgColor = color.cgColor
            return calendar
        }
        let calendars = [category("Gray", .gray), category("Blue", .blue),
                         category("White", .white), category("Red", .red),
                         category("Green", .green), category("Yellow", .yellow)]
        #expect(CalendarColorOrder.sorted(calendars).map(\.title) == ["Red", "Yellow", "Green", "Blue", "White", "Gray"])
    }

    @Test func equalColorsHaveStableAlphabeticalOrder() {
        let store = EKEventStore()
        let calendars = ["Work", "Exercise", "Church"].map { title in
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = title
            calendar.cgColor = UIColor.systemTeal.cgColor
            return calendar
        }
        #expect(CalendarColorOrder.sorted(calendars).map(\.title) == ["Church", "Exercise", "Work"])
    }
}

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


@MainActor
struct CalendarRenderCacheTests {
    @Test func repeatedRedrawsReuseDayGroupingUntilStoreChanges() {
        let cache = CalendarEventCache(capacity: 2)
        let key = CalendarEventCache.Key(start: day(2026, 10, 18), end: day(2026, 10, 25), calendarIdentifiers: nil)
        var fetches = 0
        var groupings = 0
        for _ in 0..<50 {
            _ = cache.eventsByDay(for: key, revision: 0, load: {
                fetches += 1
                return []
            }, group: { _ in
                groupings += 1
                return [:]
            })
        }
        #expect(fetches == 1)
        #expect(groupings == 1)
        _ = cache.eventsByDay(for: key, revision: 1, load: { fetches += 1; return [] }, group: { _ in
            groupings += 1
            return [:]
        })
        #expect(fetches == 2)
        #expect(groupings == 2)
    }

    @Test func dayGroupingSharesFetchedEventsAndEvictsWithThem() {
        let cache = CalendarEventCache(capacity: 1)
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.startDate = day(2026, 10, 18)
        event.endDate = day(2026, 10, 20)
        let key = CalendarEventCache.Key(start: event.startDate, end: event.endDate, calendarIdentifiers: nil)
        _ = cache.events(for: key, revision: 0) { [event] }
        let grouped = cache.eventsByDay(for: key, revision: 0, load: { Issue.record("Fetched an already cached range"); return [] })
        #expect(grouped[day(2026, 10, 18)]?.first === event)
        #expect(grouped[day(2026, 10, 19)]?.first === event)
        let other = CalendarEventCache.Key(start: day(2026, 11, 1), end: day(2026, 11, 2), calendarIdentifiers: nil)
        _ = cache.events(for: other, revision: 0) { [] }
        let reloaded = cache.eventsByDay(for: key, revision: 0, load: { [] })
        #expect(reloaded.isEmpty)
    }
}

struct WheelScrollMotionTests {
    @Test func wheelStepsGlideAndAccumulateWithoutOvershooting() {
        var motion = WheelScrollMotion()
        motion.enqueue(60, limit: 300)
        let first = motion.advance(by: 1.0 / 60)
        #expect(first > 0 && first < 60)
        motion.enqueue(60, limit: 300)
        var travel = first
        for _ in 0..<120 { travel += motion.advance(by: 1.0 / 60) }
        #expect(abs(travel - 120) < 0.001)
        #expect(!motion.isActive)
    }

    @Test func reversingDirectionDropsOldMomentumAndLimitsSensitivity() {
        var motion = WheelScrollMotion()
        motion.enqueue(1000, limit: 200)
        #expect(motion.remaining == 200)
        motion.enqueue(-30, limit: 200)
        #expect(motion.remaining == -30)
        #expect(motion.advance(by: 1.0 / 60) < 0)
        motion.cancel()
        #expect(!motion.isActive)
    }

    @Test func movementIsIndependentOfDisplayRefreshRate() {
        func distance(hz: Double) -> Double {
            var motion = WheelScrollMotion()
            motion.enqueue(120, limit: 300)
            return (0..<Int(hz / 5)).reduce(0) { sum, _ in sum + motion.advance(by: 1 / hz) }
        }
        #expect(abs(distance(hz: 60) - distance(hz: 120)) < 0.001)
    }
}
