import SwiftUI
import SwiftData

@main
struct CalendarAppApp: App {
    let modelContainer: ModelContainer = ModelContainerFactory.make()
    @State private var eventStore = EventStoreManager()
    @State private var undoManager = UndoManagerService()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(eventStore)
                .environment(undoManager)
                .preferredColorScheme(.dark)
                .tint(AppTheme.ultramarine)
        }
        .modelContainer(modelContainer)
    }
}
