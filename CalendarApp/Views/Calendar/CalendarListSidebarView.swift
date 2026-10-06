import EventKit
import SwiftData
import SwiftUI

/// Apple Calendar's own "Calendars" picker -- lists every EKCalendar with its
/// color, toggling per-calendar visibility (a display preference local to
/// this app; EventKit has no cross-app visibility flag to persist to).
struct CalendarListSidebarView: View {
    @Environment(EventStoreManager.self) private var eventStore
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferencesRows: [AppPreferences]

    @State private var editorContext: CalendarEditorContext?
    @State private var showingImport = false
    @State private var showingGmailImport = false
    @State private var duplicateScan: DuplicateEventFinder.Duplicates?
    @State private var duplicateMessage: String?

    private var preferences: AppPreferences { AppPreferencesAccess.ensure(preferencesRows, in: modelContext) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(eventStore.calendars, id: \.calendarIdentifier) { calendar in
                    HStack {
                        // Visibility toggle and edit are sibling Buttons, not a
                        // row-wide tap gesture with a Button inside it -- there,
                        // tapping the pencil could also fire the row's toggle and
                        // silently hide the calendar being edited.
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // A dedicated button rather than swipeActions -- swipe
                        // gestures are unreliable on Mac Catalyst's
                        // trackpad/mouse input (same reasoning as the
                        // template list's edit/delete buttons).
                        if calendar.allowsContentModifications {
                            Button {
                                editorContext = .edit(calendar)
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    HStack {
                        Label(syncStatusText, systemImage: syncStatusIcon)
                            .foregroundStyle(syncStatusColor)
                        Spacer()
                        Button("Sync Now") { Task { await sync.syncNow() } }
                            .disabled(sync.status == .syncing)
                    }
                } header: {
                    Text("Device Sync")
                } footer: {
                    Text("Keeps checkmarks, templates, reminders, locations and hidden calendars in step between your devices, through a hidden \"CalendarApp Sync\" calendar in iCloud. You can hide that calendar in Apple's Calendar app, but don't delete it.")
                }

                Section {
                    Button {
                        let found = DuplicateEventFinder.scan(eventStore)
                        if found.extras.isEmpty {
                            duplicateMessage = "No duplicate events found."
                        } else {
                            duplicateScan = found
                        }
                    } label: {
                        Label("Find Duplicate Events", systemImage: "square.on.square.dashed")
                    }
                } footer: {
                    Text("Looks for events saved twice with the same calendar, title and time. Repeating events are never touched.")
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
                        editorContext = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .confirmationDialog(
                duplicateDialogTitle,
                isPresented: Binding(get: { duplicateScan != nil }, set: { if !$0 { duplicateScan = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove Duplicates", role: .destructive) { removeDuplicates() }
                Button("Cancel", role: .cancel) { duplicateScan = nil }
            } message: {
                if let scan = duplicateScan {
                    Text("One copy of each stays. Affects: \(scan.sampleTitles.joined(separator: ", "))\(scan.groupCount > scan.sampleTitles.count ? ", and more" : "").")
                }
            }
            .alert(duplicateMessage ?? "", isPresented: Binding(get: { duplicateMessage != nil }, set: { if !$0 { duplicateMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .sheet(item: $editorContext) { context in
                CalendarEditorView(context: context)
            }
            .sheet(isPresented: $showingImport) {
                ImportFromWebAppView()
            }
            .sheet(isPresented: $showingGmailImport) {
                GmailImportView()
            }
        }
    }

    private var duplicateDialogTitle: String {
        let count = duplicateScan?.extras.count ?? 0
        return "Remove \(count) duplicate event\(count == 1 ? "" : "s")?"
    }

    private func removeDuplicates() {
        guard let scan = duplicateScan else { return }
        var removed = 0
        for event in scan.extras where (try? eventStore.delete(event)) != nil { removed += 1 }
        duplicateScan = nil
        duplicateMessage = "Removed \(removed) duplicate event\(removed == 1 ? "" : "s")."
    }

    private var syncStatusText: String {
        switch sync.status {
        case .idle: return "Waiting to sync"
        case .syncing: return "Syncing..."
        case .synced(let date): return "Synced \(date.formatted(.relative(presentation: .named)))"
        case .failed(let message): return message
        }
    }

    private var syncStatusIcon: String {
        switch sync.status {
        case .failed: return "exclamationmark.icloud"
        case .synced: return "checkmark.icloud"
        default: return "icloud"
        }
    }

    private var syncStatusColor: Color {
        if case .failed = sync.status { return .red }
        return .secondary
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

enum CalendarEditorContext: Identifiable {
    case new
    case edit(EKCalendar)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let calendar): return "edit-\(calendar.calendarIdentifier)"
        }
    }
}

/// Create a new "category" (EKCalendar), or rename/recolor/delete an
/// existing one -- EKCalendar.title and .cgColor are both mutable in place,
/// no master/occurrence split to worry about like events have.
struct CalendarEditorView: View {
    let context: CalendarEditorContext

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedColor: Color = AppTheme.calendarColors[0]
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation = false

    private var isEditing: Bool {
        if case .edit = context { return true }
        return false
    }

    /// A subscribed calendar (e.g. Holidays) can't be renamed, recolored, or deleted here.
    private var isReadOnly: Bool {
        if case .edit(let calendar) = context { return !calendar.allowsContentModifications }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                if isReadOnly {
                    Section {
                        Label("This is a subscribed calendar, so it can't be edited here.", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
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
                                    if isSelected(color) {
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
                if isEditing && !isReadOnly {
                    Section {
                        Button("Delete Calendar", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .disabled(isReadOnly)
            .navigationTitle(isEditing ? "Edit Calendar" : "New Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isReadOnly {
                        Button(isEditing ? "Save" : "Add") { save() }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .confirmationDialog(
                "Delete this calendar? All of its events will be deleted too.",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear(perform: populateIfNeeded)
        }
    }

    private func populateIfNeeded() {
        guard case .edit(let calendar) = context else { return }
        title = calendar.title
        selectedColor = Color(cgColor: calendar.cgColor)
    }

    /// Exact Color equality can miss after a round-trip through
    /// EKCalendar.cgColor (color-space conversion can nudge components by a
    /// hair), so the highlight ring matches within a small tolerance instead.
    private func isSelected(_ color: Color) -> Bool {
        guard let a = PlatformColor(color).cgColor.components,
              let b = PlatformColor(selectedColor).cgColor.components,
              a.count >= 3, b.count >= 3 else { return false }
        return abs(a[0] - b[0]) < 0.02 && abs(a[1] - b[1]) < 0.02 && abs(a[2] - b[2]) < 0.02
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        do {
            switch context {
            case .new:
                try CalendarCategoryManager.createCalendar(
                    title: trimmed,
                    color: PlatformColor(selectedColor),
                    in: eventStore.store
                )
            case .edit(let calendar):
                try CalendarCategoryManager.update(
                    calendar,
                    title: trimmed,
                    color: PlatformColor(selectedColor),
                    in: eventStore.store
                )
            }
            eventStore.notifyStoreMutated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        guard case .edit(let calendar) = context else { return }
        do {
            try CalendarCategoryManager.delete(calendar, in: eventStore.store)
            eventStore.notifyStoreMutated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
