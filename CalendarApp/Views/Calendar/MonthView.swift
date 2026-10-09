import CoreLocation
import EventKit
import SwiftData
import SwiftUI

struct MonthView: View {
    let referenceDate: Date
    let selectedDate: Date
    let weekStartDay: Int
    let hiddenCalendarIdentifiers: Set<String>
    /// Wide layout only. The parent bumps this whenever it wants the week list
    /// to jump to the current reference (Today, month arrows, a day picked in
    /// the sidebar, a new week starting); ordinary scrolling never changes it.
    var jumpToken: Int = 0
    let onSelectDay: (Date) -> Void
    let onSelectEvent: (EKEvent) -> Void
    let onAddEvent: (Date) -> Void
    /// Wide (Mac/iPad) layout only: single-click on an event reports it here
    /// instead of opening a local popover, so a persistent sidebar (see
    /// CalendarRootView) can show its details -- double-click still opens
    /// the full editor via onSelectEvent.
    var onPreviewEvent: ((EKEvent) -> Void)?
    /// Wide layout only: the date in the middle of the weeks now on screen,
    /// reported as the user scrolls so the title and mini calendar follow.
    var onVisibleDateChange: ((Date) -> Void)?

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var completionRows: [EventCompletionStatus]

    /// Wide layout: the id (week start) of the row at the top of the window.
    @State private var topWeek: Date?
    @State private var rangeStart: Date?
    @State private var rangeEnd: Date?

    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    /// How many week rows fit in the window at once on wide layouts.
    private static let visibleWeeks: CGFloat = 3

    private var gridDays: [Date] { DateMath.monthGridDays(containing: referenceDate, weekStartDay: weekStartDay) }

    private var weekdaySymbols: [String] {
        let all = DateMath.weekdayHeaderSymbols
        return (0..<7).map { all[(weekStartDay + $0) % 7] }
    }

    private var eventsByDay: [Date: [EKEvent]] {
        guard let first = gridDays.first, let last = gridDays.last else { return [:] }
        let events = eventStore.events(
            from: DateMath.startOfDay(first),
            to: DateMath.endOfDay(last),
            in: visibleCalendars
        )
        return EventDayGrouping.group(events, within: DateMath.startOfDay(first)...DateMath.startOfDay(last))
    }

    private var visibleCalendars: [EKCalendar] {
        eventStore.calendars.filter { !hiddenCalendarIdentifiers.contains($0.calendarIdentifier) }
    }

    // MARK: - Wide layout: one continuous run of weeks

    private func weekStart(containing date: Date) -> Date {
        DateMath.startOfWeek(containing: date, weekStartDay: weekStartDay)
    }

    private var effectiveRangeStart: Date {
        rangeStart ?? weekStart(containing: DateMath.addingWeeks(-52, to: .now))
    }

    private var effectiveRangeEnd: Date {
        rangeEnd ?? weekStart(containing: DateMath.addingWeeks(104, to: .now))
    }

    private var weekStarts: [Date] {
        var result: [Date] = []
        var week = effectiveRangeStart
        while week <= effectiveRangeEnd {
            result.append(week)
            week = DateMath.addingWeeks(1, to: week)
        }
        return result
    }

    /// The week to put at the top: the one holding the selected day when it's
    /// in the month being shown (Today, a new week rolling over), else the
    /// week holding the 1st of the month (the month arrows).
    private var jumpTarget: Date {
        if DateMath.isSameMonth(selectedDate, referenceDate) { return weekStart(containing: selectedDate) }
        let first = DateMath.calendar.date(from: DateMath.calendar.dateComponents([.year, .month], from: referenceDate)) ?? referenceDate
        return weekStart(containing: first)
    }

    private func jump() {
        let target = jumpTarget
        // Grow the range if the target is near or past an edge.
        if target < DateMath.addingWeeks(4, to: effectiveRangeStart) { rangeStart = weekStart(containing: DateMath.addingWeeks(-26, to: target)) }
        if target > DateMath.addingWeeks(-8, to: effectiveRangeEnd) { rangeEnd = weekStart(containing: DateMath.addingWeeks(52, to: target)) }
        // Deferred a beat so the rows exist before the scroll is requested. A
        // short hop glides (it tells you where you went); a long one -- Today
        // from months away -- jumps, since gliding through 100 rows just stutters.
        let distanceInWeeks = topWeek.map { abs(Calendar.current.dateComponents([.day], from: $0, to: target).day ?? 0) / 7 }
        DispatchQueue.main.async {
            if let distanceInWeeks, distanceInWeeks <= 8 {
                Motion.perform(Motion.easeOut(0.3)) { topWeek = target }
            } else {
                topWeek = target
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)

            if isWideLayout {
                // About three weeks fill the window at a time, in one unbroken
                // scroll of weeks -- not a month-shaped grid, which near the end
                // of a month has nothing left to show below the current week. Each
                // day cell is roughly twice the height of a whole-month grid's, so
                // far more events fit before a "+N more" is needed.
                //
                // The ScrollView isn't just for the overflow -- without any
                // UIScrollView in the tree at all, Mac Catalyst's navigation bar
                // reserves space for a large title instead of honoring
                // .navigationBarTitleDisplayMode(.inline), which caused a large
                // empty gap under the "September 2026" title.
                GeometryReader { geo in
                    let cellHeight = max(110, geo.size.height / Self.visibleWeeks)
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 1) {
                            ForEach(weekStarts, id: \.self) { week in
                                MonthWeekRow(
                                    weekStart: week,
                                    visibleCalendars: visibleCalendars,
                                    selectedDate: selectedDate,
                                    completionRows: completionRows,
                                    cellHeight: cellHeight,
                                    onSelectDay: onSelectDay,
                                    onAddEvent: onAddEvent,
                                    onQuickLook: { onPreviewEvent?($0) },
                                    onEditEvent: onSelectEvent
                                )
                                .frame(height: cellHeight)
                                .id(week)
                            }
                        }
                        .scrollTargetLayout()
                        .background(Color.secondary.opacity(0.15))
                    }
                    .scrollPosition(id: $topWeek, anchor: .top)
                    .onAppear { jump() }
                    .onChange(of: jumpToken) { jump() }
                    .onChange(of: topWeek) { _, week in
                        guard let week else { return }
                        // The middle of the three visible weeks.
                        onVisibleDateChange?(DateMath.addingDays(10, to: week))
                    }
                }
            } else {
                let dayMap = eventsByDay
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(gridDays, id: \.self) { day in
                        MonthDayCell(
                            day: day,
                            isCurrentMonth: DateMath.isSameMonth(day, referenceDate),
                            isToday: DateMath.isSameDay(day, .now),
                            isSelected: DateMath.isSameDay(day, selectedDate),
                            events: dayMap[DateMath.startOfDay(day)] ?? [],
                            completionRows: completionRows
                        )
                        .onTapGesture { onSelectDay(day) }
                    }
                }

                Divider().padding(.top, 6)

                SelectedDayEventList(
                    date: selectedDate,
                    events: (dayMap[DateMath.startOfDay(selectedDate)] ?? []).sorted { $0.startDate < $1.startDate },
                    completionRows: completionRows,
                    onSelectEvent: onSelectEvent,
                    onAddEvent: { onAddEvent(selectedDate) },
                    onToggleComplete: { EventCompletionAccess.toggle($0, in: completionRows, context: modelContext) },
                    onDelete: { eventStore.deleteWithUndo($0, undoManager: undoManager) }
                )
            }
        }
    }
}

/// One week of day cells. Fetches only its own seven days, so the lazy list
/// above only ever loads events for the weeks actually on screen.
private struct MonthWeekRow: View {
    let weekStart: Date
    let visibleCalendars: [EKCalendar]
    let selectedDate: Date
    let completionRows: [EventCompletionStatus]
    let cellHeight: CGFloat
    let onSelectDay: (Date) -> Void
    let onAddEvent: (Date) -> Void
    let onQuickLook: (EKEvent) -> Void
    let onEditEvent: (EKEvent) -> Void

    @Environment(EventStoreManager.self) private var eventStore

    var body: some View {
        let days = (0..<7).map { DateMath.addingDays($0, to: weekStart) }
        let events = eventStore.events(
            from: DateMath.startOfDay(days[0]),
            to: DateMath.endOfDay(days[6]),
            in: visibleCalendars
        )
        let dayMap = EventDayGrouping.group(events, within: DateMath.startOfDay(days[0])...DateMath.startOfDay(days[6]))
        HStack(spacing: 1) {
            ForEach(days, id: \.self) { day in
                MonthDayCellWide(
                    day: day,
                    isAlternateMonth: DateMath.calendar.component(.month, from: day) % 2 == 1,
                    showsMonthLabel: DateMath.calendar.component(.day, from: day) == 1,
                    isToday: DateMath.isSameDay(day, .now),
                    isSelected: DateMath.isSameDay(day, selectedDate),
                    events: (dayMap[DateMath.startOfDay(day)] ?? []).sorted { $0.startDate < $1.startDate },
                    completionRows: completionRows,
                    cellHeight: cellHeight,
                    onSelectDay: { onSelectDay(day) },
                    onAddEvent: { onAddEvent(day) },
                    onQuickLook: onQuickLook,
                    onEditEvent: onEditEvent
                )
            }
        }
    }
}

/// Apple Calendar-style day cell for wide (Mac/iPad) windows: events render
/// directly in the grid as colored chips instead of behind a separate list.
/// Single-click a chip for a quick-look popover, double-click to edit;
/// single-click empty cell space selects the day, double-click creates a
/// new event there -- the same click/double-click split Apple Calendar uses.
private struct MonthDayCellWide: View {
    let day: Date
    /// Alternate months get a faint tint, since weeks run on unbroken across
    /// month boundaries and nothing else would mark where one month ends.
    let isAlternateMonth: Bool
    let showsMonthLabel: Bool
    let isToday: Bool
    let isSelected: Bool
    let events: [EKEvent]
    let completionRows: [EventCompletionStatus]
    let cellHeight: CGFloat
    let onSelectDay: () -> Void
    let onAddEvent: () -> Void
    let onQuickLook: (EKEvent) -> Void
    let onEditEvent: (EKEvent) -> Void

    private var maxVisibleChips: Int {
        max(1, Int((cellHeight - 34) / 20))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                if showsMonthLabel {
                    Text(day.formatted(.dateTime.month(.abbreviated)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.ultramarine)
                }
                Text(DateMath.dayNumberFormatter.string(from: day))
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .frame(width: 22, height: 22)
                    .background {
                        ZStack {
                            if isToday {
                                Circle().fill(AppTheme.ultramarine)
                            } else if isSelected {
                                Circle().stroke(AppTheme.ultramarine, lineWidth: 1.5)
                                    .transition(.opacity)
                            }
                        }
                        .animation(Motion.easeOut(0.12), value: isSelected)
                    }
                    .foregroundStyle(isToday ? Color.white : Color.primary)
            }
            .padding(.top, 4)
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(events.prefix(maxVisibleChips), id: \.eventIdentifier) { event in
                    EventChip(
                        event: event,
                        completed: EventCompletionAccess.isCompleted(event, in: completionRows)
                    )
                    .onTapGesture(count: 2) { onEditEvent(event) }
                    .onTapGesture(count: 1) { onQuickLook(event) }
                }
                if events.count > maxVisibleChips {
                    Text("+\(events.count - maxVisibleChips) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: cellHeight, maxHeight: cellHeight, alignment: .topLeading)
        .background(isAlternateMonth ? Color.secondary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onAddEvent() }
        .onTapGesture(count: 1) { onSelectDay() }
    }
}

private struct EventChip: View {
    let event: EKEvent
    let completed: Bool

    private var status: EventStatus {
        EventStatusEvaluator.status(for: event, completed: completed)
    }

    var body: some View {
        // A solid bar plus a stronger tint (it was a 6pt dot on an 18% wash,
        // which read as one grey-teal blur): the category color is what the eye
        // scans a dense month for, so it gets the most contrast.
        let color = EventStatusEvaluator.displayColor(for: status, categoryColor: AppTheme.calendarColor(for: event.calendar))
        // The bar is an overlay, not a sibling view: a bare Rectangle in the
        // stack is infinitely tall and stretches every chip to fill its cell.
        HStack(spacing: 4) {
            if !event.isAllDay {
                Text(DateMath.timeFormatter.string(from: event.startDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(event.title ?? "Untitled")
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.30))
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .animation(Motion.easeOut(0.2), value: completed)
        .contentShape(Rectangle())
    }
}

private struct MonthDayCell: View {
    let day: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let events: [EKEvent]
    let completionRows: [EventCompletionStatus]

    var body: some View {
        VStack(spacing: 3) {
            Text(DateMath.dayNumberFormatter.string(from: day))
                .font(.system(size: 15, weight: isToday ? .bold : .regular))
                .frame(width: 26, height: 26)
                .background {
                    if isToday {
                        Circle().fill(AppTheme.ultramarine)
                    } else if isSelected {
                        Circle().stroke(AppTheme.ultramarine, lineWidth: 1.5)
                    }
                }
                .foregroundStyle(isToday ? Color.white : (isCurrentMonth ? Color.primary : Color.secondary.opacity(0.5)))

            HStack(spacing: 3) {
                ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, event in
                    Circle()
                        .fill(dotColor(for: event))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }

    private func dotColor(for event: EKEvent) -> Color {
        let completed = EventCompletionAccess.isCompleted(event, in: completionRows)
        let status = EventStatusEvaluator.status(for: event, completed: completed)
        return EventStatusEvaluator.displayColor(for: status, categoryColor: AppTheme.calendarColor(for: event.calendar))
    }
}

private struct SelectedDayEventList: View {
    let date: Date
    let events: [EKEvent]
    let completionRows: [EventCompletionStatus]
    let onSelectEvent: (EKEvent) -> Void
    let onAddEvent: () -> Void
    let onToggleComplete: (EKEvent) -> Void
    let onDelete: (EKEvent) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    if events.isEmpty {
                        Text("No events")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events, id: \.eventIdentifier) { event in
                            EventRow(
                                event: event,
                                completed: EventCompletionAccess.isCompleted(event, in: completionRows),
                                onToggleComplete: { onToggleComplete(event) },
                                onDelete: { onDelete(event) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectEvent(event) }
                        }
                    }
                } header: {
                    Text(DateMath.fullDateFormatter.string(from: date))
                }
            }
            .listStyle(.plain)

            Button(action: onAddEvent) {
                Label("Add Event", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.ultramarine)
            .padding(.horizontal)
            // iOS 26's floating tab bar doesn't reduce the safe area reported to
            // plain (non-List/ScrollView) content nested this deeply under a
            // TabView, so a fixed clearance is used instead of safeAreaPadding.
            .padding(.bottom, 90)
        }
    }
}

struct EventRow: View {
    let event: EKEvent
    var completed: Bool = false
    var onToggleComplete: (() -> Void)?
    var onDelete: (() -> Void)?

    @Query private var locationOverrides: [EventLocationOverride]

    private var status: EventStatus {
        EventStatusEvaluator.status(for: event, completed: completed)
    }

    private var resolvedLocation: (text: String, coordinate: CLLocationCoordinate2D?)? {
        EventLocationAccess.displayLocation(for: event, in: locationOverrides)
    }

    private var trimmedNotes: String? {
        guard let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
              notes.contains(where: \.isLetter) || notes.contains(where: \.isNumber) else { return nil }
        return notes
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(EventStatusEvaluator.displayColor(for: status, categoryColor: AppTheme.calendarColor(for: event.calendar)))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Untitled")
                    .font(.body.weight(.medium))
                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let resolvedLocation {
                    Button {
                        openInMaps(resolvedLocation)
                    } label: {
                        Label(resolvedLocation.text, systemImage: "mappin.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.ultramarine)
                }
                // Notes were only ever visible in the Mac's side panel or at the
                // bottom of the edit form, so on the phone they looked like they
                // hadn't synced -- even though Apple Calendar showed them.
                if let notes = trimmedNotes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let onToggleComplete {
                CompletionCheckButton(completed: completed, action: onToggleComplete)
            }
            if let onDelete, event.calendar?.allowsContentModifications == true {
                Image(systemName: "trash.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded(onDelete))
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Delete event")
                    .accessibilityAction(.default, onDelete)
            }
        }
        .padding(.vertical, 2)
    }

    private var timeLabel: String {
        if event.isAllDay { return "All-day" }
        return "\(DateMath.timeFormatter.string(from: event.startDate)) – \(DateMath.timeFormatter.string(from: event.endDate))"
    }

    private func openInMaps(_ resolved: (text: String, coordinate: CLLocationCoordinate2D?)) {
        if let coordinate = resolved.coordinate {
            MapsLauncher.open(title: resolved.text, coordinate: coordinate)
        } else {
            MapsLauncher.search(query: resolved.text)
        }
    }
}
