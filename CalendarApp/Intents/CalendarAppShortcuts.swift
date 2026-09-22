import AppIntents

/// Registers the app's intents with Siri/Shortcuts -- no donation plumbing
/// needed, these phrases make the intents discoverable automatically.
struct CalendarAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateEventIntent(),
            phrases: [
                "Add an event in \(.applicationName)",
                "Create an event in \(.applicationName)",
                "New event in \(.applicationName)",
            ],
            shortTitle: "New Event",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: NextEventQueryIntent(),
            phrases: [
                "What's my next event in \(.applicationName)",
                "When's my next event in \(.applicationName)",
                "What's next on \(.applicationName)",
            ],
            shortTitle: "Next Event",
            systemImageName: "calendar"
        )
    }
}
