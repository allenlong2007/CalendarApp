import EventKit
import SwiftData
import SwiftUI

struct WeekView: View {
    let referenceDate: Date
    @Binding var selectedDate: Date
    let weekStartDay: Int
    let hiddenCalendarIdentifiers: Set<String>
    let onSelectEvent: (EKEvent) -> Void
    let onCreateEvent: (Date) -> Void

    @Environment(EventStoreManager.self) private var eventStore
    @Query private var completionRows: [EventCompletionStatus]

    private let hourHeight: CGFloat = 52
    private let gutterWidth: CGFloat = 40

    private var days: [Date] {
        let start = DateMath.startOfWeek(containing: referenceDate, weekStartDay: weekStartDay)
        return (0..<7).map { DateMath.addingDays($0, to: start) }
    }

    private var visibleCalendars: [EKCalendar] {
        eventStore.calendars.filter { !hiddenCalendarIdentifiers.contains($0.calendarIdentifier) }
    }

    private var eventsByDay: [Date: [EKEvent]] {
        guard let first = days.first, let last = days.last else { return [:] }
        let events = eventStore.events(from: DateMath.startOfDay(first), to: DateMath.endOfDay(last), in: visibleCalendars)
            .filter { !$0.isAllDay }
        return Dictionary(grouping: events) { DateMath.startOfDay($0.startDate) }
    }

    private var allDayEventsByDay: [Date: [EKEvent]] {
        guard let first = days.first, let last = days.last else { return [:] }
        let events = eventStore.events(from: DateMath.startOfDay(first), to: DateMath.endOfDay(last), in: visibleCalendars)
            .filter(\.isAllDay)
        return Dictionary(grouping: events) { DateMath.startOfDay($0.startDate) }
    }

    var body: some View {
        VStack(spacing: 0) {
            weekHeader
            Divider()
            allDayRow
            Divider()
            ScrollView(.vertical) {
                hourGrid
            }
            .defaultScrollAnchor(.init(x: 0, y: 7.0 / 24.0))
        }
    }

    private var weekHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(DateMath.weekdayShortFormatter.string(from: day).uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(DateMath.dayNumberFormatter.string(from: day))
                        .font(.subheadline.weight(DateMath.isSameDay(day, .now) ? .bold : .regular))
                        .frame(width: 24, height: 24)
                        .background {
                            if DateMath.isSameDay(day, .now) {
                                Circle().fill(AppTheme.ultramarine)
                            }
                        }
                        .foregroundStyle(DateMath.isSameDay(day, .now) ? .white : .primary)
                }
                .frame(maxWidth: .infinity)
                .onTapGesture { selectedDate = day }
            }
        }
        .padding(.vertical, 6)
        // Color.clear (the gutter-width spacer above) has no height
        // constraint of its own and defaults to greedily filling all
        // available vertical space, stretching this whole row -- fixedSize
        // forces the row back to its content's own ideal height.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var allDayRow: some View {
        let map = allDayEventsByDay
        if map.values.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("All-day").font(.caption2).foregroundStyle(.secondary).frame(width: gutterWidth, alignment: .leading)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 2) {
                        ForEach(map[DateMath.startOfDay(day)] ?? [], id: \.eventIdentifier) { event in
                            Text(event.title ?? "")
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 3)
                                .frame(maxWidth: .infinity)
                                .background(colorFor(event).opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
                                .onTapGesture { onSelectEvent(event) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var hourGrid: some View {
        let map = eventsByDay
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: gutterWidth, height: hourHeight, alignment: .top)
                        .offset(y: -6)
                }
            }
            ForEach(days, id: \.self) { day in
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { _ in
                                Divider().frame(height: hourHeight, alignment: .top)
                            }
                        }
                        ForEach(map[DateMath.startOfDay(day)] ?? [], id: \.eventIdentifier) { event in
                            let frame = layout(for: event, width: geo.size.width)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorFor(event))
                                .overlay(alignment: .topLeading) {
                                    Text(event.title ?? "")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .lineLimit(2)
                                }
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: frame.x, y: frame.y)
                                .onTapGesture { onSelectEvent(event) }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            onCreateEvent(dateFor(y: value.location.y, on: day))
                        }
                    )
                }
                .frame(height: hourHeight * 24)
                .frame(maxWidth: .infinity)
            }
        }
        // Matches the hour labels' own -6pt offset above (which visually
        // aligns each label with its divider line) so "12 AM" has room to
        // render fully instead of being clipped by the scroll content's own
        // top edge.
        .padding(.top, 6)
    }

    private func colorFor(_ event: EKEvent) -> Color {
        let completed = EventCompletionAccess.isCompleted(event, in: completionRows)
        let status = EventStatusEvaluator.status(for: event, completed: completed)
        return EventStatusEvaluator.displayColor(for: status, categoryColor: AppTheme.calendarColor(for: event.calendar))
    }

    private func hourLabel(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12) \(period)"
    }

    private func layout(for event: EKEvent, width: CGFloat) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let dayStart = DateMath.startOfDay(event.startDate)
        let startMinutes = event.startDate.timeIntervalSince(dayStart) / 60
        let endMinutes = max(startMinutes + 20, event.endDate.timeIntervalSince(dayStart) / 60)
        let top = CGFloat(startMinutes / 60) * hourHeight
        let height = CGFloat((endMinutes - startMinutes) / 60) * hourHeight
        return (x: 2, y: top, width: max(0, width - 4), height: height)
    }

    private func dateFor(y: CGFloat, on day: Date) -> Date {
        let minutes = Double(y / hourHeight) * 60
        return DateMath.startOfDay(day).addingTimeInterval(minutes * 60)
    }
}
