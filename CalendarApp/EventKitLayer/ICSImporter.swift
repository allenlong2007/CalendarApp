import EventKit
import Foundation

/// One VEVENT block from an .ics file, already resolved to concrete dates --
/// RRULE is kept as an EKRecurrenceRule (EventKit's own representation)
/// rather than re-parsed at apply time.
struct ICSEvent {
    let summary: String
    let location: String?
    let notes: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let recurrenceRule: EKRecurrenceRule?
    /// EXDATE entries -- EventKit has no way to pre-seed these on a recurrence
    /// rule, so they're applied after creation by deleting the matching
    /// occurrence (see ICSImporter.apply).
    let exceptionDates: [Date]
}

struct ParsedICS {
    let calendarName: String
    let events: [ICSEvent]
}

enum ICSParseError: Error {
    case noEvents
}

/// Minimal iCalendar (RFC 5545) reader covering exactly what real-world
/// exports (class schedules, Google/Outlook calendars) actually use: DTSTART/
/// DTEND with TZID or UTC/floating time, SUMMARY/LOCATION/DESCRIPTION, RRULE
/// (FREQ/INTERVAL/BYDAY/UNTIL/COUNT), and EXDATE. Not a general-purpose ICS
/// parser -- BYMONTHDAY/BYSETPOS/VALARM/etc. are out of scope.
enum ICSImporter {
    static func parse(_ text: String) throws -> ParsedICS {
        let lines = unfold(text)
        var calendarName = "Imported Schedule"
        var events: [ICSEvent] = []

        var inEvent = false
        var props: [String: [(params: [String: String], value: String)]] = [:]

        for rawLine in lines {
            guard !rawLine.isEmpty else { continue }
            if rawLine == "BEGIN:VEVENT" {
                inEvent = true
                props = [:]
                continue
            }
            if rawLine == "END:VEVENT" {
                inEvent = false
                if let event = makeEvent(from: props) { events.append(event) }
                continue
            }
            guard let colonIndex = rawLine.firstIndex(of: ":") else { continue }
            let namePart = String(rawLine[rawLine.startIndex..<colonIndex])
            let value = String(rawLine[rawLine.index(after: colonIndex)...])
            let nameComponents = namePart.split(separator: ";").map(String.init)
            guard let name = nameComponents.first else { continue }

            if !inEvent {
                if name == "X-WR-CALNAME" { calendarName = unescape(value) }
                continue
            }

            var params: [String: String] = [:]
            for component in nameComponents.dropFirst() {
                let kv = component.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0]] = kv[1] }
            }
            props[name, default: []].append((params: params, value: value))
        }

        guard !events.isEmpty else { throw ICSParseError.noEvents }
        return ParsedICS(calendarName: calendarName, events: events)
    }

    /// Applies a parsed schedule to a target calendar: creates each master
    /// event (with its recurrence rule, if any), then deletes the specific
    /// occurrences named by EXDATE so they read as proper recurrence
    /// exceptions rather than being silently skipped. Skips events that
    /// already exist (same title, same start time) so re-importing the same
    /// file doesn't duplicate everything.
    @MainActor
    static func apply(_ parsed: ParsedICS, to calendar: EKCalendar, eventStore: EventStoreManager) -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0

        for icsEvent in parsed.events {
            if occurrence(matching: icsEvent.summary, near: icsEvent.startDate, in: calendar, eventStore: eventStore) != nil {
                skipped += 1
                continue
            }

            guard let created = try? eventStore.createEvent(
                title: icsEvent.summary,
                startDate: icsEvent.startDate,
                endDate: icsEvent.endDate,
                isAllDay: icsEvent.isAllDay,
                calendar: calendar,
                location: icsEvent.location,
                notes: icsEvent.notes,
                recurrenceRules: icsEvent.recurrenceRule.map { [$0] }
            ) else {
                skipped += 1
                continue
            }
            _ = created

            for exceptionDate in icsEvent.exceptionDates {
                if let toRemove = occurrence(matching: icsEvent.summary, near: exceptionDate, in: calendar, eventStore: eventStore) {
                    try? eventStore.delete(toRemove)
                }
            }

            imported += 1
        }

        return (imported, skipped)
    }

    @MainActor
    private static func occurrence(matching title: String, near date: Date, in calendar: EKCalendar, eventStore: EventStoreManager) -> EKEvent? {
        eventStore.events(
            from: date.addingTimeInterval(-60),
            to: date.addingTimeInterval(60),
            in: [calendar]
        ).first { $0.title == title }
    }

    // MARK: - Line unfolding (RFC 5545: continuation lines start with a space/tab)

    private static func unfold(_ text: String) -> [String] {
        let rawLines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [String] = []
        for line in rawLines {
            if let first = line.first, (first == " " || first == "\t"), !result.isEmpty {
                result[result.count - 1] += line.dropFirst()
            } else {
                result.append(line)
            }
        }
        return result
    }

    // MARK: - VEVENT -> ICSEvent

    private static func makeEvent(from props: [String: [(params: [String: String], value: String)]]) -> ICSEvent? {
        guard let dtstartProp = props["DTSTART"]?.first,
              let start = parseDate(dtstartProp)
        else { return nil }

        let summary = props["SUMMARY"]?.first.map { unescape($0.value) } ?? "Untitled"
        let location = props["LOCATION"]?.first.map { unescape($0.value) }
        let notes = props["DESCRIPTION"]?.first.map { unescape($0.value) }

        let endDate: Date
        if let dtendProp = props["DTEND"]?.first, let end = parseDate(dtendProp) {
            endDate = end.date
        } else if start.isAllDay {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: start.date) ?? start.date
        } else {
            endDate = start.date.addingTimeInterval(3600)
        }

        let recurrenceRule = props["RRULE"]?.first.flatMap { parseRRule($0.value, timeZone: start.timeZone) }

        var exceptionDates: [Date] = []
        for exdateProp in props["EXDATE"] ?? [] {
            for component in exdateProp.value.split(separator: ",") {
                if let parsed = parseDate((params: exdateProp.params, value: String(component))) {
                    exceptionDates.append(parsed.date)
                }
            }
        }

        return ICSEvent(
            summary: summary,
            location: location,
            notes: notes,
            startDate: start.date,
            endDate: endDate,
            isAllDay: start.isAllDay,
            recurrenceRule: recurrenceRule,
            exceptionDates: exceptionDates
        )
    }

    private static func parseDate(_ property: (params: [String: String], value: String)) -> (date: Date, isAllDay: Bool, timeZone: TimeZone)? {
        let value = property.value
        if property.params["VALUE"] == "DATE" || (value.count == 8 && !value.contains("T")) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            let utc = TimeZone(identifier: "UTC")!
            formatter.timeZone = utc
            guard let date = formatter.date(from: value) else { return nil }
            return (date, true, utc)
        }

        var dateString = value
        var timeZone = TimeZone.current
        if dateString.hasSuffix("Z") {
            timeZone = TimeZone(identifier: "UTC")!
            dateString = String(dateString.dropLast())
        } else if let tzid = property.params["TZID"], let named = TimeZone(identifier: tzid) {
            timeZone = named
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = timeZone
        guard let date = formatter.date(from: dateString) else { return nil }
        return (date, false, timeZone)
    }

    // MARK: - RRULE -> EKRecurrenceRule

    private static func parseRRule(_ rrule: String, timeZone: TimeZone) -> EKRecurrenceRule? {
        var parts: [String: String] = [:]
        for pair in rrule.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { parts[kv[0]] = kv[1] }
        }

        let frequency: EKRecurrenceFrequency
        switch parts["FREQ"] {
        case "DAILY": frequency = .daily
        case "WEEKLY": frequency = .weekly
        case "MONTHLY": frequency = .monthly
        case "YEARLY": frequency = .yearly
        default: return nil
        }

        let interval = Int(parts["INTERVAL"] ?? "1") ?? 1

        var daysOfWeek: [EKRecurrenceDayOfWeek]?
        if let byday = parts["BYDAY"] {
            let dayMap: [String: EKWeekday] = [
                "SU": .sunday, "MO": .monday, "TU": .tuesday, "WE": .wednesday,
                "TH": .thursday, "FR": .friday, "SA": .saturday,
            ]
            let parsed: [EKRecurrenceDayOfWeek] = byday.split(separator: ",").compactMap { token in
                let str = String(token)
                guard str.count >= 2, let weekday = dayMap[String(str.suffix(2))] else { return nil }
                let weekNumber = Int(str.dropLast(2)) ?? 0
                return EKRecurrenceDayOfWeek(weekday, weekNumber: weekNumber)
            }
            daysOfWeek = parsed.isEmpty ? nil : parsed
        }

        var end: EKRecurrenceEnd?
        if let until = parts["UNTIL"] {
            let formatter = DateFormatter()
            let untilString = until
            if untilString.hasSuffix("Z") {
                formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                formatter.timeZone = TimeZone(identifier: "UTC")
            } else {
                formatter.dateFormat = "yyyyMMdd'T'HHmmss"
                formatter.timeZone = timeZone
            }
            if let untilDate = formatter.date(from: untilString) {
                end = EKRecurrenceEnd(end: untilDate)
            }
        } else if let countString = parts["COUNT"], let count = Int(countString) {
            end = EKRecurrenceEnd(occurrenceCount: count)
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    // MARK: - Text unescaping (RFC 5545 4.3.11)

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
