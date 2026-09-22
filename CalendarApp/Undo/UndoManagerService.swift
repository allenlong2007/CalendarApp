import Foundation
import Observation

/// A single-slot "toast with Undo" stack -- registering a new action replaces
/// whatever was pending (matching Apple's own Mail/Reminders undo-toast
/// behavior, where only the most recent destructive action stays undoable).
@Observable
@MainActor
final class UndoManagerService {
    struct PendingUndo {
        let message: String
        let action: () -> Void
    }

    private(set) var pending: PendingUndo?
    private var dismissTask: Task<Void, Never>?

    func register(message: String, action: @escaping () -> Void) {
        dismissTask?.cancel()
        pending = PendingUndo(message: message, action: action)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.pending = nil
        }
    }

    func performUndo() {
        dismissTask?.cancel()
        let action = pending?.action
        pending = nil
        action?()
    }

    func dismiss() {
        dismissTask?.cancel()
        pending = nil
    }
}
