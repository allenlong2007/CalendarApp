import EventKit
import SwiftData
import SwiftUI

/// Apple Calendar's own "Calendars" picker -- lists every EKCalendar with its
/// color, toggling per-calendar visibility (a display preference local to
/// this app; EventKit has no cross-app visibility flag to persist to).
struct CalendarListSidebarView: View {
    @Environment(EventStoreManager.self) private var eventStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferencesRows: [AppPreferences]

    @State private var showingNewCalendar = false
    @State private var showingImport = false
    @State private var showingGmailImport = false

    private var preferences: AppPreferences { AppPreferencesAccess.ensure(preferencesRows, in: modelContext) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(eventStore.calendars, id: \.calendarIdentifier) { calendar in
                    Button {
                        toggle(calendar)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(cgColor: calendar.cgColor))
                                .frame(width: 14, height: 14)
                            Text(calendar.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isVisible(calendar) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.ultramarine)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import from Web App", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showingGmailImport = true
                    } label: {
                        Label("Import from Gmail", systemImage: "envelope")
                    }
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingNewCalendar = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewCalendar) {
                NewCalendarView()
            }
            .sheet(isPresented: $showingImport) {
                ImportFromWebAppView()
            }
            .sheet(isPresented: $showingGmailImport) {
                GmailImportView()
            }
        }
    }

    private func isVisible(_ calendar: EKCalendar) -> Bool {
        !preferences.hiddenCalendarIdentifiers.contains(calendar.calendarIdentifier)
    }

    private func toggle(_ calendar: EKCalendar) {
        var hidden = Set(preferences.hiddenCalendarIdentifiers)
        if hidden.contains(calendar.calendarIdentifier) {
            hidden.remove(calendar.calendarIdentifier)
        } else {
            hidden.insert(calendar.calendarIdentifier)
        }
        preferences.hiddenCalendarIdentifiers = Array(hidden)
    }
}

/// Create a new "category" (EKCalendar).
struct NewCalendarView: View {
    @Environment(EventStoreManager.self) private var eventStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedColor: Color = AppTheme.calendarColors[0]
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Calendar name", text: $title)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Array(AppTheme.calendarColors.enumerated()), id: \.offset) { _, color in
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if color == selectedColor {
                                        Circle().stroke(Color.white, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { selectedColor = color }
                        }
                    }
                    .padding(.vertical, 6)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        do {
            try CalendarCategoryManager.createCalendar(
                title: title.trimmingCharacters(in: .whitespaces),
                color: PlatformColor(selectedColor),
                in: eventStore.store
            )
            eventStore.notifyStoreMutated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
