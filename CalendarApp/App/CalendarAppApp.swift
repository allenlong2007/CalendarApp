import SwiftUI
import SwiftData

@main
struct CalendarAppApp: App {
    let modelContainer: ModelContainer = ModelContainerFactory.make()
    @State private var eventStore = EventStoreManager()
    @State private var undoManager = UndoManagerService()
    @State private var sync = SyncCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(eventStore)
                .environment(undoManager)
                .environment(sync)
                .preferredColorScheme(.dark)
                .tint(AppTheme.ultramarine)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        eventStore.refreshFromSources()
                        Task { await sync.syncNow() }
                    }
                }
                .task { sync.start(container: modelContainer, eventStore: eventStore) }
        }
        .modelContainer(modelContainer)
    }
}
