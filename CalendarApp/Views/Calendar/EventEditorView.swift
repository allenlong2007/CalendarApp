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
    @Query private var reminderRows: [EventReminderPreference]
    @Query private var locationOverrides: [EventLocationOverride]
    @Query private var preferencesRows: [AppPreferences]

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
    /// What the Repeat controls showed when the editor opened. The controls
    /// can only express "every N for X occurrences", so an existing series
    /// (a class repeating weekly until a date, an open-ended weekly reminder)
    /// would be silently rewritten as "8 occurrences" by any save -- even one
    /// that only changed the title. Recurrence is only written back when the
    /// user actually changed these controls.
    @State private var originalRepeatOption: RepeatOption = .never
    @State private var originalRepeatOccurrences: Int = 8
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false
    @State private var didSaveTemplate = false
    /// Whether the event being edited had a resolved location before this
    /// edit -- see save() for why that matters to EventLocationOverride.
    @State private var originalHadLocation = false
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
                    FlowLayout(spacing: 8) {
                        ForEach(writableCalendars, id: \.calendarIdentifier) { calendar in
                            CategoryChip(
                                calendar: calendar,
                                isSelected: selectedCalendarIdentifier == calendar.calendarIdentifier
                            ) {
                                selectedCalendarIdentifier = calendar.calendarIdentifier
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
                            Label(
                                didSaveTemplate ? "Template Saved" : "Save as Template",
                                systemImage: didSaveTemplate ? "checkmark.circle.fill" : "bolt.fill"
                            )
                            .symbolEffect(.bounce, value: didSaveTemplate)
                        }
                        // Guards against the same double-invocation bug fixed in
                        // QuickAddTemplatesView -- this button created several
                        // duplicate templates from what looked like one tap.
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || didSaveTemplate)
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
            // Month/Agenda pass a bare day (midnight) -- defaulting to 12 AM
            // makes a new event land in the dead of night, so a "morning"
            // event looked like it hadn't been created. Use 9 AM instead.
            let defaultStart = Self.sensibleDefaultStart(for: defaultDate)
            startDate = defaultStart
            endDate = defaultStart.addingTimeInterval(3600)
            location = ""
            locationLatitude = nil
            locationLongitude = nil
            notes = ""
            reminderMinutes = 15
            repeatOption = .never
            repeatOccurrences = 8
            selectedCalendarIdentifier = eventStore.store.defaultCalendarForNewEvents?.calendarIdentifier
                ?? writableCalendars.first?.calendarIdentifier
        case .edit(let event):
            title = event.title ?? ""
            isAllDay = event.isAllDay
            startDate = event.startDate
            endDate = event.endDate
            // EventKit's own .location reads back empty for most occurrences
            // of a recurring event (a confirmed read-side limitation, not
            // fixable by writing differently -- see EventLocationOverride),
            // so fall back to this app's own mirror of it when that happens.
            originalHadLocation = EventLocationAccess.displayLocation(for: event, in: locationOverrides) != nil
            if let resolved = EventLocationAccess.displayLocation(for: event, in: locationOverrides) {
                location = resolved.text
                locationLatitude = resolved.coordinate?.latitude
                locationLongitude = resolved.coordinate?.longitude
            } else {
                location = ""
                locationLatitude = nil
                locationLongitude = nil
            }
            notes = event.notes ?? ""
            selectedCalendarIdentifier = event.calendar?.calendarIdentifier
            reminderMinutes = EventReminderAccess.effectiveMinutes(for: event, in: reminderRows)
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
            originalRepeatOption = repeatOption
            originalRepeatOccurrences = repeatOccurrences
        }
    }

    private static func sensibleDefaultStart(for date: Date) -> Date {
        guard date == DateMath.startOfDay(date) else { return date }
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private func save() {
        guard let calendar = selectedCalendar else {
            errorMessage = "Pick a category for this event first."
            return
        }
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
            // No EKAlarm here on purpose -- reminders are this app's own
            // local notifications now (see ReminderScheduler), not EventKit
            // alarms, which fire as system Calendar notifications shared
            // with Apple's own Calendar app.
            if repeatOption != originalRepeatOption || repeatOccurrences != originalRepeatOccurrences {
                if let frequency = repeatOption.frequency {
                    event.recurrenceRules = [EKRecurrenceRule(
                        recurrenceWith: frequency,
                        interval: 1,
                        end: EKRecurrenceEnd(occurrenceCount: repeatOccurrences)
                    )]
                } else {
                    event.recurrenceRules = nil
                }
            }
            try eventStore.update(event)
            AppPreferencesAccess.reveal(calendar, rows: preferencesRows, in: modelContext)
            EventReminderAccess.setReminder(reminderMinutes, for: event, in: reminderRows, context: modelContext)
            // See EventLocationOverride -- EventKit won't reliably read this
            // back for most occurrences of a recurring event, so this app
            // keeps its own copy for display.
            let coordinate = (locationLatitude != nil && locationLongitude != nil)
                ? CLLocationCoordinate2D(latitude: locationLatitude!, longitude: locationLongitude!)
                : nil
            // Overrides are keyed by title, so only touch one when this save
            // actually set a location or cleared one that existed -- an
            // unrelated save of a same-titled event with no location (a new
            // one-off "MATH-018 Lecture", say) must not wipe the whole
            // series' location.
            if !location.isEmpty || originalHadLocation {
                EventLocationAccess.setLocation(
                    location.isEmpty ? nil : location,
                    coordinate: coordinate,
                    title: event.title ?? "",
                    rows: locationOverrides,
                    context: modelContext
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAsTemplate() {
        guard !didSaveTemplate else { return }
        didSaveTemplate = true

        let durationMinutes = isAllDay ? 0 : max(5, Int(endDate.timeIntervalSince(startDate) / 60))
        let startComponents = Calendar.current.dateComponents([.hour, .minute], from: startDate)
        let preferredStartMinutes = isAllDay ? nil : (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let template = EventTemplate(
            title: title.trimmingCharacters(in: .whitespaces),
            isAllDay: isAllDay,
            durationMinutes: durationMinutes,
            preferredStartMinutes: preferredStartMinutes,
            categoryIdentifier: selectedCalendarIdentifier,
            notes: notes.isEmpty ? nil : notes,
            reminderMinutesBefore: reminderMinutes
        )
        modelContext.insert(template)
        undoManager.register(message: "Template Saved") {
            modelContext.delete(template)
        }
    }

    private func duplicate(to days: Set<Date>) {
        guard case .edit(let event) = context, let calendar = event.calendar else { return }
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: event.startDate)
        var created: [EKEvent] = []
        var failureCount = 0
        for day in days {
            let newStart = event.isAllDay
                ? day
                : Calendar.current.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: day) ?? day
            let newEnd = event.isAllDay ? DateMath.addingDays(1, to: newStart) : newStart.addingTimeInterval(duration)
            do {
                let newEvent = try eventStore.createEvent(
                    title: event.title ?? "",
                    startDate: newStart,
                    endDate: newEnd,
                    isAllDay: event.isAllDay,
                    calendar: calendar,
                    location: event.location,
                    structuredLocation: event.structuredLocation,
                    notes: event.notes
                )
                created.append(newEvent)
            } catch {
                failureCount += 1
            }
        }

        if created.isEmpty && failureCount > 0 {
            errorMessage = "Couldn't duplicate to any of the selected days."
            return
        } else if failureCount > 0 {
            errorMessage = "Duplicated to \(created.count) day(s); \(failureCount) failed."
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
