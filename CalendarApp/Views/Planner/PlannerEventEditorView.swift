import EventKit
import SwiftData
import SwiftUI

private let weekdayFullNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

struct PlannerEventEditorView: View {
    let context: PlannerEditorContext

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var weekday = 0
    @State private var isAllDay = false
    @State private var startTime = Date.now
    @State private var endTime = Date.now.addingTimeInterval(3600)
    @State private var categoryIdentifier: String?
    @State private var notes = ""

    private var isEditing: Bool {
        if case .edit = context { return true }
        return false
    }

    private var writableCalendars: [EKCalendar] {
        eventStore.calendars.filter(\.allowsContentModifications)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                }

                Section {
                    Picker("Day", selection: $weekday) {
                        ForEach(0..<7, id: \.self) { day in
                            Text(weekdayFullNames[day]).tag(day)
                        }
                    }
                }

                Section {
                    Toggle("All-day", isOn: $isAllDay.animation())
                    if !isAllDay {
                        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                            .onChange(of: startTime) { _, newValue in
                                if endTime < newValue { endTime = newValue.addingTimeInterval(3600) }
                            }
                        DatePicker("Ends", selection: $endTime, in: startTime..., displayedComponents: .hourAndMinute)
                    }
                }

                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            Button {
                                categoryIdentifier = nil
                            } label: {
                                Text("None")
                                    .font(.subheadline.weight(categoryIdentifier == nil ? .semibold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.secondary.opacity(categoryIdentifier == nil ? 0.25 : 0.12)))
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            ForEach(writableCalendars, id: \.calendarIdentifier) { calendar in
                                CategoryChip(
                                    calendar: calendar,
                                    isSelected: categoryIdentifier == calendar.calendarIdentifier
                                ) {
                                    categoryIdentifier = calendar.calendarIdentifier
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                if isEditing {
                    Section {
                        Button("Delete", role: .destructive) { delete() }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Planner Event" : "New Planner Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: populateIfNeeded)
        }
    }

    private func populateIfNeeded() {
        switch context {
        case .new(let day, let startMinutes):
            title = ""
            weekday = day
            isAllDay = false
            startTime = timeFromMinutes(startMinutes)
            endTime = timeFromMinutes(startMinutes + 60)
            categoryIdentifier = nil
            notes = ""
        case .edit(let event):
            title = event.title
            weekday = event.weekday
            isAllDay = event.isAllDay
            startTime = timeFromMinutes(event.startMinutes ?? 0)
            endTime = timeFromMinutes(event.endMinutes ?? 60)
            categoryIdentifier = event.categoryIdentifier
            notes = event.notes ?? ""
        }
    }

    private func timeFromMinutes(_ minutes: Int) -> Date {
        let normalized = ((minutes % 1440) + 1440) % 1440
        return Calendar.current.date(bySettingHour: normalized / 60, minute: normalized % 60, second: 0, of: .now) ?? .now
    }

    private func minutesFromTime(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func save() {
        let event: PlannerEvent
        if case .edit(let existing) = context {
            event = existing
        } else {
            event = PlannerEvent(weekday: weekday, title: title)
            modelContext.insert(event)
        }
        event.title = title.trimmingCharacters(in: .whitespaces)
        event.weekday = weekday
        event.isAllDay = isAllDay
        if isAllDay {
            event.startMinutes = nil
            event.endMinutes = nil
        } else {
            event.startMinutes = minutesFromTime(startTime)
            event.endMinutes = minutesFromTime(endTime)
        }
        event.categoryIdentifier = categoryIdentifier
        event.notes = notes.isEmpty ? nil : notes
        dismiss()
    }

    private func delete() {
        guard case .edit(let event) = context else { return }
        let weekday = event.weekday
        let title = event.title
        let isAllDay = event.isAllDay
        let startMinutes = event.startMinutes
        let endMinutes = event.endMinutes
        let categoryIdentifier = event.categoryIdentifier
        let notes = event.notes
        modelContext.delete(event)
        dismiss()
        undoManager.register(message: "Planner Event Deleted") {
            let restored = PlannerEvent(
                weekday: weekday,
                title: title,
                isAllDay: isAllDay,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                categoryIdentifier: categoryIdentifier,
                notes: notes
            )
            modelContext.insert(restored)
        }
    }
}
