import SwiftUI

/// Lets the user pick one or more other days to duplicate an existing event
/// onto (same time-of-day and duration, shifted to each picked date).
///
/// Built on our own month grid rather than SwiftUI's MultiDatePicker --
/// MultiDatePicker has long-standing reliability issues (selections not
/// registering, especially under Mac Catalyst), which is the likely cause
/// of reports that "mass add just doesn't work."
struct DuplicateToDaysView: View {
    let onConfirm: (Set<Date>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var referenceDate = Date.now
    @State private var selectedDays: Set<Date> = []

    var body: some View {
        NavigationStack {
            VStack {
                MultiDayGridPicker(referenceDate: $referenceDate, selectedDays: $selectedDays)
                    .padding()
                Spacer(minLength: 0)
            }
            .navigationTitle("Duplicate to Other Days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedDays.isEmpty ? "Duplicate" : "Duplicate (\(selectedDays.count))") {
                        onConfirm(selectedDays)
                        dismiss()
                    }
                    .disabled(selectedDays.isEmpty)
                }
            }
        }
    }
}

private struct MultiDayGridPicker: View {
    @Binding var referenceDate: Date
    @Binding var selectedDays: Set<Date>

    private var gridDays: [Date] { DateMath.monthGridDays(containing: referenceDate, weekStartDay: 0) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    referenceDate = DateMath.addingMonths(-1, to: referenceDate)
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(DateMath.monthYearFormatter.string(from: referenceDate))
                    .font(.headline)
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
                ForEach(DateMath.weekdayHeaderSymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(gridDays, id: \.self) { day in
                    let normalized = DateMath.startOfDay(day)
                    let isCurrentMonth = DateMath.isSameMonth(day, referenceDate)
                    let isToday = DateMath.isSameDay(day, .now)
                    let isSelected = selectedDays.contains(normalized)
                    Text(DateMath.dayNumberFormatter.string(from: day))
                        .font(.subheadline.weight(isToday ? .bold : .regular))
                        .frame(width: 34, height: 34)
                        .background {
                            if isSelected {
                                Circle().fill(AppTheme.ultramarine)
                            } else if isToday {
                                Circle().stroke(AppTheme.ultramarine, lineWidth: 1.5)
                            }
                        }
                        .foregroundStyle(isSelected ? Color.white : (isCurrentMonth ? Color.primary : Color.secondary.opacity(0.4)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected {
                                selectedDays.remove(normalized)
                            } else {
                                selectedDays.insert(normalized)
                            }
                        }
                }
            }

            if !selectedDays.isEmpty {
                Text("\(selectedDays.count) day\(selectedDays.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
