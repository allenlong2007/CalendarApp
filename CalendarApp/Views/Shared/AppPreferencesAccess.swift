import EventKit
import SwiftData

/// Small helper so every view that needs the single AppPreferences row can
/// get-or-create it through its own @Query + @Environment(\.modelContext)
/// (all views share the same context via .modelContainer, so this never
/// creates a second competing context).
enum AppPreferencesAccess {
    static func ensure(_ rows: [AppPreferences], in context: ModelContext) -> AppPreferences {
        if let existing = rows.first { return existing }
        // Several views can call this in the same pass, each holding an
        // @Query snapshot that doesn't yet show a row another one just
        // inserted -- check the context itself so only one is ever created.
        if let existing = (try? context.fetch(FetchDescriptor<AppPreferences>()))?.first { return existing }
        let created = AppPreferences()
        context.insert(created)
        return created
    }

    /// Anything that creates or edits an event into a calendar the user has
    /// hidden would otherwise make it vanish the instant it's saved, with no
    /// feedback (saving into a hidden "Home" calendar looked exactly like the
    /// save having failed). Saving into a calendar is an explicit choice to
    /// see it, so reveal that calendar.
    static func reveal(_ calendar: EKCalendar, rows: [AppPreferences], in context: ModelContext) {
        let preferences = ensure(rows, in: context)
        guard preferences.hiddenCalendarIdentifiers.contains(calendar.calendarIdentifier) else { return }
        preferences.hiddenCalendarIdentifiers.removeAll { $0 == calendar.calendarIdentifier }
    }
}
