import SwiftUI

/// Small month navigator for the sidebar (see CalendarSidebarView) --
/// mirrors the compact calendar Apple's own Calendar app shows above its
/// day-detail panel.
struct MiniMonthPicker: View {
    @Binding var referenceDate: Date
    let selectedDate: Date
    let weekStartDay: Int
    let onSelectDay: (Date) -> Void

    private var gridDays: [Date] { DateMath.monthGridDays(containing: referenceDate, weekStartDay: weekStartDay) }

    private var weekdayInitials: [String] {
        let all = DateMath.weekdayHeaderSymbols
        return (0..<7).map { String(all[(weekStartDay + $0) % 7].prefix(1)) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    referenceDate = DateMath.addingMonths(-1, to: referenceDate)
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(DateMath.monthYearFormatter.string(from: referenceDate))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    referenceDate = DateMath.addingMonths(1, to: referenceDate)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(gridDays, id: \.self) { day in
                    let isCurrentMonth = DateMath.isSameMonth(day, referenceDate)
                    let isToday = DateMath.isSameDay(day, .now)
                    let isSelected = DateMath.isSameDay(day, selectedDate)
                    Text(DateMath.dayNumberFormatter.string(from: day))
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .background {
                            if isToday {
                                Circle().fill(AppTheme.ultramarine)
                            } else if isSelected {
                                Circle().stroke(AppTheme.ultramarine, lineWidth: 1.2)
                            }
                        }
                        .foregroundStyle(isToday ? Color.white : (isCurrentMonth ? Color.primary : Color.secondary.opacity(0.4)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectDay(day)
                            referenceDate = day
                        }
                }
            }
        }
    }
}
