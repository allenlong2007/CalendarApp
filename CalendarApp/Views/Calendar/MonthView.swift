import EventKit
import SwiftData
import SwiftUI

struct MonthView: View {
    let referenceDate: Date
    let selectedDate: Date
    let weekStartDay: Int
    let hiddenCalendarIdentifiers: Set<String>
    let onSelectDay: (Date) -> Void
    let onSelectEvent: (EKEvent) -> Void
    let onAddEvent: (Date) -> Void
    /// Wide (Mac/iPad) layout only: single-click on an event reports it here
    /// instead of opening a local popover, so a persistent sidebar (see
    /// CalendarRootView) can show its details -- double-click still opens
    /// the full editor via onSelectEvent.
    var onPreviewEvent: ((EKEvent) -> Void)?

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var completionRows: [EventCompletionStatus]

    private var isWideLayout: Bool { horizontalSizeClass == .regular }

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
        return Dictionary(grouping: events) { DateMath.startOfDay($0.startDate) }
    }

    private var visibleCalendars: [EKCalendar] {
        eventStore.calendars.filter { !hiddenCalendarIdentifiers.contains($0.calendarIdentifier) }
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

            let dayMap = eventsByDay
            if isWideLayout {
                // A ScrollView wrapper isn't just for overflow on short
                // windows -- without any UIScrollView present in the tree at
                // all, Mac Catalyst's navigation bar falls back to reserving
                // space for a large title instead of honoring
                // .navigationBarTitleDisplayMode(.inline), which is what
                // caused a large empty gap under the "September 2026" title.
                // The GeometryReader also lets rows stretch to fill the full
                // window height instead of leaving blank space under a
                // 5-row month.
                GeometryReader { geo in
                    let rowCount = max(1, gridDays.count / 7)
                    let cellHeight = max(110, geo.size.height / CGFloat(rowCount))
                    ScrollView(.vertical) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                            ForEach(gridDays, id: \.self) { day in
                                MonthDayCellWide(
                                    day: day,
                                    isCurrentMonth: DateMath.isSameMonth(day, referenceDate),
                                    isToday: DateMath.isSameDay(day, .now),
                                    isSelected: DateMath.isSameDay(day, selectedDate),
                                    events: (dayMap[DateMath.startOfDay(day)] ?? []).sorted { $0.startDate < $1.startDate },
                                    completionRows: completionRows,
                                    cellHeight: cellHeight,
                                    onSelectDay: { onSelectDay(day) },
                                    onAddEvent: { onAddEvent(day) },
                                    onQuickLook: { onPreviewEvent?($0) },
                                    onEditEvent: onSelectEvent
                                )
                            }
                        }
                        .background(Color.secondary.opacity(0.15))
                    }
                }
            } else {
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

/// Apple Calendar-style day cell for wide (Mac/iPad) windows: events render
/// directly in the grid as colored chips instead of behind a separate list.
/// Single-click a chip for a quick-look popover, double-click to edit;
/// single-click empty cell space selects the day, double-click creates a
/// new event there -- the same click/double-click split Apple Calendar uses.
private struct MonthDayCellWide: View {
    let day: Date
    let isCurrentMonth: Bool
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
            Text(DateMath.dayNumberFormatter.string(from: day))
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .frame(width: 22, height: 22)
                .background {
                    if isToday {
                        Circle().fill(AppTheme.ultramarine)
                    } else if isSelected {
                        Circle().stroke(AppTheme.ultramarine, lineWidth: 1.5)
                    }
                }
                .foregroundStyle(isToday ? Color.white : (isCurrentMonth ? Color.primary : Color.secondary.opacity(0.5)))
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
        .background(isCurrentMonth ? Color.clear : Color.secondary.opacity(0.04))
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
        HStack(spacing: 4) {
            Circle()
                .fill(EventStatusEvaluator.displayColor(for: status, categoryColor: AppTheme.calendarColor(for: event.calendar)))
                .frame(width: 6, height: 6)
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
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EventStatusEvaluator.displayColor(for: status, categoryColor: AppTheme.calendarColor(for: event.calendar)).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
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

    private var status: EventStatus {
        EventStatusEvaluator.status(for: event, completed: completed)
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
                if let location = event.location, !location.isEmpty {
                    Button {
                        openInMaps(location)
                    } label: {
                        Label(location, systemImage: "mappin.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.ultramarine)
                }
            }
            Spacer()
            if let onToggleComplete {
                Button(action: onToggleComplete) {
                    Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(completed ? AppTheme.completed : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            if let onDelete, event.calendar?.allowsContentModifications == true {
                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private var timeLabel: String {
        if event.isAllDay { return "All-day" }
        return "\(DateMath.timeFormatter.string(from: event.startDate)) – \(DateMath.timeFormatter.string(from: event.endDate))"
    }

    private func openInMaps(_ location: String) {
        if let geoLocation = event.structuredLocation?.geoLocation {
            MapsLauncher.open(title: location, coordinate: geoLocation.coordinate)
        } else {
            MapsLauncher.search(query: location)
        }
    }
}
