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

    @State private var editingTemplate: EventTemplate?
    @State private var showingNewTemplate = false

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
                                    Text(template.isAllDay ? "All-day" : "\(template.durationMinutes) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(AppTheme.ultramarine)
                            }
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

    private func colorFor(_ template: EventTemplate) -> Color {
        guard let identifier = template.categoryIdentifier,
              let calendar = eventStore.calendars.first(where: { $0.calendarIdentifier == identifier })
        else { return AppTheme.ultramarine }
        return AppTheme.calendarColor(for: calendar)
    }

    private func quickAdd(_ template: EventTemplate) {
        let writableCalendars = eventStore.calendars.filter(\.allowsContentModifications)
        guard let calendar = writableCalendars.first(where: { $0.calendarIdentifier == template.categoryIdentifier })
            ?? eventStore.store.defaultCalendarForNewEvents
            ?? writableCalendars.first
        else { return }

        let startDate = targetDate
        let endDate = template.isAllDay
            ? DateMath.addingDays(1, to: DateMath.startOfDay(startDate))
            : startDate.addingTimeInterval(TimeInterval(template.durationMinutes * 60))

        guard let created = try? eventStore.createEvent(
            title: template.title,
            startDate: template.isAllDay ? DateMath.startOfDay(startDate) : startDate,
            endDate: endDate,
            isAllDay: template.isAllDay,
            calendar: calendar,
            notes: template.notes
        ) else { return }

        if let reminderMinutesBefore = template.reminderMinutesBefore {
            created.addAlarm(EKAlarm(relativeOffset: -Double(reminderMinutesBefore * 60)))
            try? eventStore.update(created)
        }

        dismiss()
        if let identifier = created.eventIdentifier {
            undoManager.register(message: "\"\(template.title)\" Added") {
                if let toDelete = eventStore.event(withIdentifier: identifier) {
                    try? eventStore.delete(toDelete)
                }
            }
        }
    }
}
