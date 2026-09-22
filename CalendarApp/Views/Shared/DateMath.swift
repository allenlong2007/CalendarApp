import Foundation

/// Date-grid helpers shared by Month/Week/Day views. Mirrors the web app's
/// own calendar-grid math (weekStart-aware month grid, 42-cell layout).
enum DateMath {
    static var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = .current
        return cal
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    /// The Sunday-based weekday index (0 = Sunday ... 6 = Saturday) for `date`.
    static func weekdayIndex(of date: Date) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    /// Start of the week containing `date`, given a user weekStartDay (0-6).
    static func startOfWeek(containing date: Date, weekStartDay: Int) -> Date {
        let day = startOfDay(date)
        let offset = (weekdayIndex(of: day) - weekStartDay + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    /// 42 contiguous days (6 weeks) covering the month containing `date`,
    /// starting on the first `weekStartDay`-aligned day on/before the 1st.
    static func monthGridDays(containing date: Date, weekStartDay: Int) -> [Date] {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard let firstOfMonth = calendar.date(from: comps) else { return [] }
        let gridStart = startOfWeek(containing: firstOfMonth, weekStartDay: weekStartDay)
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    static func isSameMonth(_ a: Date, _ b: Date) -> Bool {
        let ca = calendar.dateComponents([.year, .month], from: a)
        let cb = calendar.dateComponents([.year, .month], from: b)
        return ca.year == cb.year && ca.month == cb.month
    }

    static func addingMonths(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: n, to: date) ?? date
    }

    static func addingWeeks(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .weekOfYear, value: n, to: date) ?? date
    }

    static func addingDays(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: date) ?? date
    }

    static func endOfDay(_ date: Date) -> Date {
        calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay(date)) ?? date
    }

    static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()

    static let weekdayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    static let monthDayYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    static let weekdayFullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    static let weekdayHeaderSymbols: [String] = {
        // Sunday-first raw symbols; callers rotate by weekStartDay themselves.
        DateFormatter().veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    }()
}
