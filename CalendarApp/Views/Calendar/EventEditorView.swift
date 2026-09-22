import CoreLocation
import EventKit
import MapKit
import SwiftData
import SwiftUI

enum EventEditorContext: Identifiable {
    case new(defaultDate: Date)
    case edit(EKEvent)

    var id: String {
        switch self {
        case .new(let date): return "new-\(date.timeIntervalSince1970)"
        case .edit(let event): return "edit-\(event.eventIdentifier ?? event.calendarItemIdentifier)"
        }
    }
}

private enum RepeatOption: String, CaseIterable, Identifiable {
    case never = "Never"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    var id: String { rawValue }

    var unitName: String {
        switch self {
        case .never: return ""
        case .daily: return "days"
        case .weekly: return "weeks"
        case .monthly: return "months"
        }
    }

    var frequency: EKRecurrenceFrequency? {
        switch self {
        case .never: return nil
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        }
    }
}

private let reminderOptions: [(label: String, minutes: Int?)] = [
    ("None", nil),
    ("At time of event", 0),
    ("5 minutes before", 5),
    ("15 minutes before", 15),
    ("30 minutes before", 30),
    ("1 hour before", 60),
    ("1 day before", 1440),
]

struct EventEditorView: View {
    let context: EventEditorContext

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var completionRows: [EventCompletionStatus]

    @State private var title = ""
    @State private var isAllDay = false
    @State private var startDate = Date.now
    @State private var endDate = Date.now.addingTimeInterval(3600)
    @State private var selectedCalendarIdentifier: String?
    @State private var location = ""
    @State private var locationLatitude: Double?
    @State private var locationLongitude: Double?
    @State private var notes = ""
    @State private var reminderMinutes: Int?
    @State private var repeatOption: RepeatOption = .never
    @State private var repeatOccurrences: Int = 8
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var showingLocationPicker = false
    @State private var showingDuplicateToDays = false

    private var isEditing: Bool {
        if case .edit = context { return true }
        return false
    }

    /// True for e.g. a subscribed Holidays/Birthdays event -- shown for
    /// browsing, but EventKit will refuse any save/delete against it.
    private var isReadOnly: Bool {
        if case .edit(let event) = context, let calendar = event.calendar {
            return !calendar.allowsContentModifications
        }
        return false
    }

    /// Holiday/Birthdays-style subscribed calendars are read-only -- events can
    /// only ever be saved to a writable one, so those are the only ones offered.
    private var writableCalendars: [EKCalendar] {
        eventStore.calendars.filter(\.allowsContentModifications)
    }

    private var selectedCalendar: EKCalendar? {
        writableCalendars.first { $0.calendarIdentifier == selectedCalendarIdentifier }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isReadOnly {
                    Section {
                        Label("This calendar is read-only, so this event can't be edited here.", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Title", text: $title)
                }

                Section {
                    Toggle("All-day", isOn: $isAllDay.animation())
                    DatePicker(
                        "Starts",
                        selection: $startDate,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                    .onChange(of: startDate) { _, newValue in
                        if endDate < newValue { endDate = newValue.addingTimeInterval(3600) }
                    }
                    DatePicker(
                        "Ends",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                }

                Section("Repeat") {
                    Picker("Repeat", selection: $repeatOption) {
                        ForEach(RepeatOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    if repeatOption != .never {
                        Stepper(
                            "For the next \(repeatOccurrences) \(repeatOption.unitName)",
                            value: $repeatOccurrences,
                            in: 2...52
                        )
                    }
                }

                if isEditing, case .edit(let event) = context {
                    Section {
                        Toggle(isOn: Binding(
                            get: { EventCompletionAccess.isCompleted(event, in: completionRows) },
                            set: { _ in EventCompletionAccess.toggle(event, in: completionRows, context: modelContext) }
                        )) {
                            Label("Mark Complete", systemImage: "checkmark.circle")
                        }
                        .tint(AppTheme.completed)
                    }
                }

                Section("Category") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(writableCalendars, id: \.calendarIdentifier) { calendar in
                                CategoryChip(
                                    calendar: calendar,
                                    isSelected: selectedCalendarIdentifier == calendar.calendarIdentifier
                                ) {
                                    selectedCalendarIdentifier = calendar.calendarIdentifier
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
                }

                Section("Location") {
                    Button {
                        showingLocationPicker = true
                    } label: {
                        HStack {
                            Text(location.isEmpty ? "Add a location" : location)
                                .foregroundStyle(location.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let latitude = locationLatitude, let longitude = locationLongitude {
                        Button {
                            MapsLauncher.open(
                                title: location,
                                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                            )
                        } label: {
                            Label("Open in Maps", systemImage: "map")
                        }
                    }
                }

                Section("Remind me") {
                    Picker("Reminder", selection: $reminderMinutes) {
                        ForEach(reminderOptions, id: \.minutes) { option in
                            Text(option.label).tag(option.minutes)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                if !isReadOnly {
                    Section {
                        Button {
                            saveAsTemplate()
                        } label: {
                            Label("Save as Template", systemImage: "bolt.fill")
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                if isEditing && !isReadOnly {
                    Section {
                        Button {
                            showingDuplicateToDays = true
                        } label: {
                            Label("Duplicate to Other Days", systemImage: "plus.square.on.square")
                        }
                    }

                    Section {
                        Button("Delete Event", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .disabled(isReadOnly)
            .navigationTitle(isEditing ? "Edit Event" : "New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isReadOnly {
                        Button("Save") { save() }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selectedCalendarIdentifier == nil)
                    }
                }
            }
            .confirmationDialog(
                "Delete this event?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: populateIfNeeded)
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerView { title, picked in
                    location = title
                    locationLatitude = picked?.latitude
                    locationLongitude = picked?.longitude
                }
            }
            .sheet(isPresented: $showingDuplicateToDays) {
                DuplicateToDaysView { dates in
                    duplicate(to: dates)
                }
            }
        }
    }

    private func populateIfNeeded() {
        switch context {
        case .new(let defaultDate):
            title = ""
            isAllDay = false
            startDate = defaultDate
            endDate = defaultDate.addingTimeInterval(3600)
            location = ""
            locationLatitude = nil
            locationLongitude = nil
            notes = ""
            reminderMinutes = nil
            repeatOption = .never
            repeatOccurrences = 8
            selectedCalendarIdentifier = eventStore.store.defaultCalendarForNewEvents?.calendarIdentifier
                ?? writableCalendars.first?.calendarIdentifier
        case .edit(let event):
            title = event.title ?? ""
            isAllDay = event.isAllDay
            startDate = event.startDate
            endDate = event.endDate
            location = event.location ?? ""
            if let geoLocation = event.structuredLocation?.geoLocation {
                locationLatitude = geoLocation.coordinate.latitude
                locationLongitude = geoLocation.coordinate.longitude
            } else {
                locationLatitude = nil
                locationLongitude = nil
            }
            notes = event.notes ?? ""
            selectedCalendarIdentifier = event.calendar?.calendarIdentifier
            if let alarm = event.alarms?.first {
                reminderMinutes = Int(-alarm.relativeOffset / 60)
            } else {
                reminderMinutes = nil
            }
            if let rule = event.recurrenceRules?.first {
                switch rule.frequency {
                case .daily: repeatOption = .daily
                case .weekly: repeatOption = .weekly
                case .monthly: repeatOption = .monthly
                default: repeatOption = .never
                }
                let occurrenceCount = rule.recurrenceEnd?.occurrenceCount ?? 0
                repeatOccurrences = occurrenceCount > 0 ? occurrenceCount : 8
            } else {
                repeatOption = .never
                repeatOccurrences = 8
            }
        }
    }

    private func save() {
        guard let calendar = selectedCalendar else { return }
        do {
            let event: EKEvent
            if case .edit(let existing) = context {
                event = existing
            } else {
                event = EKEvent(eventStore: eventStore.store)
            }
            event.title = title.trimmingCharacters(in: .whitespaces)
            if isAllDay {
                let dayStart = DateMath.startOfDay(startDate)
                event.startDate = dayStart
                event.endDate = DateMath.addingDays(1, to: dayStart)
            } else {
                event.startDate = startDate
                event.endDate = endDate
            }
            event.isAllDay = isAllDay
            event.calendar = calendar
            event.location = location.isEmpty ? nil : location
            if let latitude = locationLatitude, let longitude = locationLongitude, !location.isEmpty {
                let structured = EKStructuredLocation(title: location)
                structured.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
                event.structuredLocation = structured
            } else {
                event.structuredLocation = nil
            }
            event.notes = notes.isEmpty ? nil : notes
            event.alarms = nil
            if let reminderMinutes {
                event.addAlarm(EKAlarm(relativeOffset: -Double(reminderMinutes * 60)))
            }
            if let frequency = repeatOption.frequency {
                event.recurrenceRules = [EKRecurrenceRule(
                    recurrenceWith: frequency,
                    interval: 1,
                    end: EKRecurrenceEnd(occurrenceCount: repeatOccurrences)
                )]
            } else {
                event.recurrenceRules = nil
            }
            try eventStore.update(event)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAsTemplate() {
        let durationMinutes = isAllDay ? 0 : max(5, Int(endDate.timeIntervalSince(startDate) / 60))
        let template = EventTemplate(
            title: title.trimmingCharacters(in: .whitespaces),
            isAllDay: isAllDay,
            durationMinutes: durationMinutes,
            categoryIdentifier: selectedCalendarIdentifier,
            notes: notes.isEmpty ? nil : notes,
            reminderMinutesBefore: reminderMinutes
        )
        modelContext.insert(template)
        undoManager.register(message: "Template Saved") {
            modelContext.delete(template)
        }
    }

    private func duplicate(to dates: Set<DateComponents>) {
        guard case .edit(let event) = context, let calendar = event.calendar else { return }
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
        var created: [EKEvent] = []
        for var components in dates {
            components.hour = event.isAllDay ? 0 : timeComponents.hour
            components.minute = event.isAllDay ? 0 : timeComponents.minute
            guard let newStart = Calendar.current.date(from: components) else { continue }
            let newEnd = event.isAllDay ? DateMath.addingDays(1, to: newStart) : newStart.addingTimeInterval(duration)
            if let newEvent = try? eventStore.createEvent(
                title: event.title ?? "",
                startDate: newStart,
                endDate: newEnd,
                isAllDay: event.isAllDay,
                calendar: calendar,
                location: event.location,
                structuredLocation: event.structuredLocation,
                notes: event.notes
            ) {
                created.append(newEvent)
            }
        }
        guard !created.isEmpty else { return }
        let identifiers = created.compactMap(\.eventIdentifier)
        undoManager.register(message: "Duplicated to \(created.count) Day\(created.count == 1 ? "" : "s")") {
            for identifier in identifiers {
                if let toDelete = eventStore.event(withIdentifier: identifier) {
                    try? eventStore.delete(toDelete)
                }
            }
        }
    }

    private func delete() {
        guard case .edit(let event) = context else { return }
        eventStore.deleteWithUndo(event, undoManager: undoManager)
        dismiss()
    }
}
