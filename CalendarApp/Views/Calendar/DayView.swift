import EventKit
import SwiftData
import SwiftUI

/// Hour-by-hour Day view matching Apple Calendar's own: event blocks show
/// title + location inline. Single-click previews an event (in the sidebar
/// on wide layouts), double-click opens the full editor; single-click on
/// empty grid space creates a new event there.
struct DayView: View {
    let date: Date
    let hiddenCalendarIdentifiers: Set<String>
    let onSelectEvent: (EKEvent) -> Void
    let onCreateEvent: (Date) -> Void
    /// Wide (Mac/iPad) layout only -- see MonthView's onPreviewEvent.
    var onPreviewEvent: ((EKEvent) -> Void)?

    @Environment(EventStoreManager.self) private var eventStore
    @Query private var completionRows: [EventCompletionStatus]

    private let hourHeight: CGFloat = 64
    private let gutterWidth: CGFloat = 52

    private var visibleCalendars: [EKCalendar] {
        eventStore.calendars.filter { !hiddenCalendarIdentifiers.contains($0.calendarIdentifier) }
    }

    private var timedEvents: [EKEvent] {
        eventStore.events(from: DateMath.startOfDay(date), to: DateMath.endOfDay(date), in: visibleCalendars)
            .filter { !$0.isAllDay }
    }

    private var allDayEvents: [EKEvent] {
        eventStore.events(from: DateMath.startOfDay(date), to: DateMath.endOfDay(date), in: visibleCalendars)
            .filter(\.isAllDay)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateMath.monthDayYearFormatter.string(from: date))
                    .font(.title2.weight(.semibold))
                Text(DateMath.weekdayFullFormatter.string(from: date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            if !allDayEvents.isEmpty {
                HStack {
                    Text("all-day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: gutterWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(allDayEvents, id: \.eventIdentifier) { event in
                            Text(event.title ?? "")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colorFor(event).opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
                                .onTapGesture(count: 2) { onSelectEvent(event) }
                                .onTapGesture(count: 1) { onPreviewEvent?(event) ?? onSelectEvent(event) }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            Divider()

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(hourLabel(hour))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: gutterWidth, height: hourHeight, alignment: .top)
                                .offset(y: -7)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ForEach(0..<24, id: \.self) { _ in
                                    Divider().frame(height: hourHeight, alignment: .top)
                                }
                            }
                            ForEach(timedEvents, id: \.eventIdentifier) { event in
                                let frame = layout(for: event, width: geo.size.width)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(colorFor(event))
                                    .overlay(alignment: .topLeading) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.title ?? "")
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            if let location = event.location, !location.isEmpty {
                                                Label(location, systemImage: "mappin.circle.fill")
                                                    .font(.caption2)
                                                    .lineLimit(1)
                                            } else {
                                                Text(timeRangeText(for: event))
                                                    .font(.caption2)
                                            }
                                        }
                                        .foregroundStyle(.white)
                                        .padding(8)
                                    }
                                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                                    .offset(x: frame.x, y: frame.y)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { onSelectEvent(event) }
                                    .onTapGesture(count: 1) { onPreviewEvent?(event) ?? onSelectEvent(event) }
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                onCreateEvent(dateFor(y: value.location.y))
                            }
                        )
                    }
                    .frame(height: hourHeight * 24)
                }
                // Matches the hour labels' own -7pt offset above (which
                // visually aligns each label with its divider line) so
                // "12 AM" has room to render fully instead of being clipped
                // by the scroll content's own top edge.
                .padding(.top, 7)
            }
            .defaultScrollAnchor(UnitPoint(x: 0, y: 7.0 / 24.0))
        }
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

    private func timeRangeText(for event: EKEvent) -> String {
        "\(DateMath.timeFormatter.string(from: event.startDate)) – \(DateMath.timeFormatter.string(from: event.endDate))"
    }

    private func layout(for event: EKEvent, width: CGFloat) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let dayStart = DateMath.startOfDay(event.startDate)
        let startMinutes = event.startDate.timeIntervalSince(dayStart) / 60
        let endMinutes = max(startMinutes + 20, event.endDate.timeIntervalSince(dayStart) / 60)
        let top = CGFloat(startMinutes / 60) * hourHeight
        let height = CGFloat((endMinutes - startMinutes) / 60) * hourHeight
        return (x: 4, y: top, width: max(0, width - 8), height: height)
    }

    private func dateFor(y: CGFloat) -> Date {
        let minutes = Double(y / hourHeight) * 60
        return DateMath.startOfDay(date).addingTimeInterval(minutes * 60)
    }
}
