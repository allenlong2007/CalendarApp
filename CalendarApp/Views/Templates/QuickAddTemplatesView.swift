import EventKit
import SwiftData
import SwiftUI

/// Lists saved quick-add templates; tapping one immediately creates a real
/// event at `targetDate` using the template's defaults.
struct QuickAddTemplatesView: View {
    let targetDate: Date

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EventTemplate.title) private var templates: [EventTemplate]
    @Query private var reminderRows: [EventReminderPreference]
    @Query private var preferencesRows: [AppPreferences]

    private enum RowFeedback: Equatable {
        case added
        case duplicate
        case failed
    }

    @State private var editingTemplate: EventTemplate?
    @State private var showingNewTemplate = false
    @State private var isAdding = false
    @State private var feedbackByID: [UUID: RowFeedback] = [:]

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates Yet",
                        systemImage: "bolt.fill",
                        description: Text("Tap + to save a quick-add template.")
                    )
                } else {
                    ForEach(templates, id: \.id) { template in
                        HStack {
                            // The add action is its own Button, a sibling of
                            // (not a parent tap gesture around) the edit/delete
                            // buttons, so tapping those can never also add.
                            Button {
                                quickAdd(template)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(colorFor(template))
                                        .frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.title)
                                            .foregroundStyle(.primary)
                                        Text(subtitle(for: template))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: iconName(for: template))
                                        .foregroundStyle(iconColor(for: template))
                                        .symbolEffect(.bounce, value: feedbackByID[template.id])
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                editingTemplate = template
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) {
                                modelContext.delete(template)
                            } label: {
                                Image(systemName: "trash.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(template)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingTemplate = template
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(AppTheme.ultramarine)
                        }
                    }
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingNewTemplate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewTemplate) {
                EventTemplateEditorView(existing: nil)
            }
            .sheet(item: $editingTemplate) { template in
                EventTemplateEditorView(existing: template)
            }
        }
    }

    private func iconName(for template: EventTemplate) -> String {
        switch feedbackByID[template.id] {
        case .added: return "checkmark.circle.fill"
        case .duplicate: return "exclamationmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case nil: return "plus.circle.fill"
        }
    }

    private func iconColor(for template: EventTemplate) -> Color {
        switch feedbackByID[template.id] {
        case .added: return AppTheme.completed
        case .duplicate: return .orange
        case .failed: return .red
        case nil: return AppTheme.ultramarine
        }
    }

    private func subtitle(for template: EventTemplate) -> String {
        if template.isAllDay { return "All-day" }
        guard let minutes = template.preferredStartMinutes else { return "\(template.durationMinutes) min" }
        let time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return "\(DateMath.timeFormatter.string(from: time)) · \(template.durationMinutes) min"
    }

    private func colorFor(_ template: EventTemplate) -> Color {
        guard let identifier = template.categoryIdentifier,
              let calendar = eventStore.calendars.first(where: { $0.calendarIdentifier == identifier })
        else { return AppTheme.ultramarine }
        return AppTheme.calendarColor(for: calendar)
    }

    private func quickAdd(_ template: EventTemplate) {
        // Guards against a double-invocation (reported on iOS: tapping a
        // template row sometimes fired its action twice, creating two
        // events). Once this row's tap has started creating an event,
        // ignore any repeat firing until this sheet dismisses.
        guard !isAdding else { return }
        isAdding = true

        let writableCalendars = eventStore.calendars.filter(\.allowsContentModifications)
        guard let calendar = writableCalendars.first(where: { $0.calendarIdentifier == template.categoryIdentifier })
            ?? eventStore.store.defaultCalendarForNewEvents
            ?? writableCalendars.first
        else {
            showFeedback(.failed, for: template, thenDismiss: false)
            isAdding = false
            return
        }

        // The template remembers its own time of day (e.g. 9:00 AM) --
        // targetDate is just the day the user tapped/selected, which for
        // Month/Agenda has no time component of its own (midnight). Combine
        // the target day with the template's stored time rather than using
        // targetDate's own (usually midnight) time directly.
        let dayStart = DateMath.startOfDay(targetDate)
        let startDate: Date
        if template.isAllDay {
            startDate = dayStart
        } else if let minutes = template.preferredStartMinutes {
            startDate = dayStart.addingTimeInterval(TimeInterval(minutes * 60))
        } else {
            startDate = targetDate
        }
        let endDate = template.isAllDay
            ? DateMath.addingDays(1, to: dayStart)
            : startDate.addingTimeInterval(TimeInterval(template.durationMinutes * 60))

        // Don't add the same template to the same slot twice -- check for
        // an existing event with this title at (almost) this exact time in
        // the target calendar first.
        let alreadyExists = eventStore.events(
            from: startDate.addingTimeInterval(-60),
            to: startDate.addingTimeInterval(60),
            in: [calendar]
        ).contains { $0.title == template.title }

        guard !alreadyExists else {
            showFeedback(.duplicate, for: template, thenDismiss: false)
            isAdding = false
            return
        }

        guard let created = try? eventStore.createEvent(
            title: template.title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: template.isAllDay,
            calendar: calendar,
            notes: template.notes
        ) else {
            showFeedback(.failed, for: template, thenDismiss: false)
            isAdding = false
            return
        }

        AppPreferencesAccess.reveal(calendar, rows: preferencesRows, in: modelContext)

        // No EKAlarm here on purpose -- see EventEditorView.save() for why.
        EventReminderAccess.setReminder(template.reminderMinutesBefore, for: created, in: reminderRows, context: modelContext)

        if let identifier = created.eventIdentifier {
            undoManager.register(message: "\"\(template.title)\" Added") {
                if let toDelete = eventStore.event(withIdentifier: identifier) {
                    try? eventStore.delete(toDelete)
                }
            }
        }

        showFeedback(.added, for: template, thenDismiss: true)
    }

    private func showFeedback(_ feedback: RowFeedback, for template: EventTemplate, thenDismiss: Bool) {
        withAnimation {
            feedbackByID[template.id] = feedback
        }
        Task {
            try? await Task.sleep(for: .milliseconds(thenDismiss ? 550 : 1100))
            if thenDismiss {
                dismiss()
            } else {
                withAnimation { feedbackByID[template.id] = nil }
                isAdding = false
            }
        }
    }
}
