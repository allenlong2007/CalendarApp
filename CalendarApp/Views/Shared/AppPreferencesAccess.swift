import SwiftData

/// Small helper so every view that needs the single AppPreferences row can
/// get-or-create it through its own @Query + @Environment(\.modelContext)
/// (all views share the same context via .modelContainer, so this never
/// creates a second competing context).
enum AppPreferencesAccess {
    static func ensure(_ rows: [AppPreferences], in context: ModelContext) -> AppPreferences {
        if let existing = rows.first { return existing }
        let created = AppPreferences()
        context.insert(created)
        return created
    }
}
