#if !targetEnvironment(macCatalyst)
import BackgroundTasks
import Foundation

/// Best-effort sync while the app isn't open on the phone. iOS decides when
/// (and whether) to run it -- typically a few times a day for an app that's
/// used regularly -- so it's a safety net on top of the sync that runs every
/// time the app opens, not a replacement for it.
enum BackgroundSync {
    static let taskID = "com.footsoregnu3115.calendarapp.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Runs on a background queue, handed the task by the system.
    static func run(_ task: BGTask) {
        schedule()   // keep the chain going for next time
        let box = TaskBox(task: task)
        let work = Task { @MainActor in
            await SyncCoordinator.current?.syncNow()
            box.task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}

private struct TaskBox: @unchecked Sendable { let task: BGTask }
#endif
