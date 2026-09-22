import EventKit
import SwiftData
import SwiftUI

private let durationOptions = [15, 30, 45, 60, 90, 120, 180, 240]

struct EventTemplateEditorView: View {
    let existing: EventTemplate?

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var isAllDay = false
    @State private var durationMinutes = 60
    @State private var categoryIdentifier: String?
    @State private var notes = ""
    @State private var reminderMinutesBefore: Int?

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
                    Toggle("All-day", isOn: $isAllDay.animation())
                    if !isAllDay {
                        Picker("Duration", selection: $durationMinutes) {
                            ForEach(durationOptions, id: \.self) { minutes in
                                Text(durationLabel(minutes)).tag(minutes)
                            }
                        }
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
            }
            .navigationTitle(existing == nil ? "New Template" : "Edit Template")
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

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    private func populateIfNeeded() {
        guard let existing else { return }
        title = existing.title
        isAllDay = existing.isAllDay
        durationMinutes = existing.durationMinutes
        categoryIdentifier = existing.categoryIdentifier
        notes = existing.notes ?? ""
        reminderMinutesBefore = existing.reminderMinutesBefore
    }

    private func save() {
        let template = existing ?? EventTemplate(title: title)
        if existing == nil { modelContext.insert(template) }
        template.title = title.trimmingCharacters(in: .whitespaces)
        template.isAllDay = isAllDay
        template.durationMinutes = durationMinutes
        template.categoryIdentifier = categoryIdentifier
        template.notes = notes.isEmpty ? nil : notes
        template.reminderMinutesBefore = reminderMinutesBefore
        dismiss()
    }
}
