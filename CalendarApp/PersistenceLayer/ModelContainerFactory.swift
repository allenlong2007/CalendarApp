import Foundation
import SwiftData

enum ModelContainerFactory {
    /// Shared with the (future) widget extension. Must match the App Group
    /// capability added in Signing & Capabilities and the Apple Developer portal.
    static let appGroupIdentifier = "group.com.footsoregnu3115.calendarapp"

    static let schema = Schema([
        PlannerEvent.self,
        EventCompletionStatus.self,
        SavedAddress.self,
        EventTemplate.self,
        AppPreferences.self,
        CalendarIconMap.self,
    ])

    static func make() -> ModelContainer {
        let storeURL = appGroupContainerURL()?.appending(path: "CalendarAppData.store")

        // Prefer App Group storage + CloudKit sync. Both require capabilities
        // that must be enabled in Xcode's Signing & Capabilities (and, for a
        // real device/TestFlight build, in the Apple Developer portal) before
        // they'll actually work -- fall back gracefully so the app still runs
        // during early bring-up before that's wired up.
        if let storeURL {
            let cloudConfig = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
                return container
            }
            let localConfig = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [localConfig]) {
                return container
            }
        }

        // Last resort: default (sandbox-local, non-shared) storage.
        if let container = try? ModelContainer(for: schema) {
            return container
        }
        fatalError("Unable to create ModelContainer under any configuration.")
    }

    private static func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
}
