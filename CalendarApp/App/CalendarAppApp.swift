import SwiftUI
import SwiftData
#if !targetEnvironment(macCatalyst)
import BackgroundTasks
#endif

@main
struct CalendarAppApp: App {
    let modelContainer: ModelContainer
    @State private var eventStore: EventStoreManager
    @State private var undoManager = UndoManagerService()
    @State private var sync: SyncCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Built here, not lazily in the view tree, so a background launch (the
        // system waking the app to sync) has a working coordinator even though
        // no window -- and so none of the view code -- ever runs.
        let container = ModelContainerFactory.make()
        let store = EventStoreManager()
        let coordinator = SyncCoordinator()
        coordinator.attach(container: container, eventStore: store)
        modelContainer = container
        _eventStore = State(initialValue: store)
        _sync = State(initialValue: coordinator)
        #if !targetEnvironment(macCatalyst)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundSync.taskID, using: nil) { task in
            BackgroundSync.run(task)
        }
        #endif
    }

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
                    #if !targetEnvironment(macCatalyst)
                    if phase == .background { BackgroundSync.schedule() }
                    #endif
                }
                .task { sync.start(container: modelContainer, eventStore: eventStore) }
        }
        .modelContainer(modelContainer)
    }
}
