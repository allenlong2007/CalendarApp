import Foundation

enum PhoneCalendarLayout {
    /// Blank slots keep weekday alignment without displaying neighboring months.
    static func monthSlots(containing date: Date, weekStartDay: Int) -> [Date?] {
        let calendar = DateMath.calendar
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let days = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let leading = (DateMath.weekdayIndex(of: first) - weekStartDay + 7) % 7
        let count = ((leading + days.count + 6) / 7) * 7
        return (0..<count).map { slot in
            let offset = slot - leading
            return (0..<days.count).contains(offset) ? DateMath.addingDays(offset, to: first) : nil
        }
    }

    static func weekStarts(around date: Date, weekStartDay: Int) -> [Date] {
        let current = DateMath.startOfWeek(containing: date, weekStartDay: weekStartDay)
        return [0, 1].map { DateMath.addingWeeks($0, to: current) }
    }
}

enum CalendarPagePeriod {
    case month, week, day

    func date(at index: Int, from anchor: Date) -> Date {
        switch self {
        case .month: DateMath.addingMonths(index, to: anchor)
        case .week: DateMath.addingWeeks(index, to: anchor)
        case .day: DateMath.addingDays(index, to: anchor)
        }
    }

    func index(of date: Date, from anchor: Date, weekStartDay: Int) -> Int {
        let calendar = DateMath.calendar
        switch self {
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
            let end = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            return calendar.dateComponents([.month], from: start, to: end).month ?? 0
        case .week:
            let start = DateMath.startOfWeek(containing: anchor, weekStartDay: weekStartDay)
            let end = DateMath.startOfWeek(containing: date, weekStartDay: weekStartDay)
            return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) / 7
        case .day:
            return calendar.dateComponents([.day], from: DateMath.startOfDay(anchor), to: DateMath.startOfDay(date)).day ?? 0
        }
    }
}
