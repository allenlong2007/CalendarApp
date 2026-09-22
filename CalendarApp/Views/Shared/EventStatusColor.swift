import EventKit
import SwiftUI

/// Completed/overdue status is computed live (never stored beyond the
/// `completed` boolean in EventCompletionStatus) -- an event is overdue once
/// its own end passes without being marked done. Ports the web app's
/// is-completed/is-overdue logic directly.
enum EventStatus {
    case normal
    case completed
    case overdue

    var tintColor: Color? {
        switch self {
        case .normal: return nil
        case .completed: return AppTheme.completed
        case .overdue: return AppTheme.overdue
        }
    }
}

enum EventStatusEvaluator {
    static func status(for event: EKEvent, completed: Bool) -> EventStatus {
        if completed { return .completed }
        return event.endDate < .now ? .overdue : .normal
    }

    /// Background wash for a row/chip: category color when normal, status
    /// color (softened) when completed/overdue -- the category dot itself is
    /// drawn separately so it's always visible regardless of status.
    static func backgroundTint(for status: EventStatus, categoryColor: Color) -> Color {
        status.tintColor?.opacity(0.22) ?? categoryColor.opacity(0.16)
    }

    /// Solid display color for a chip/capsule/dot: status color (green/red)
    /// when completed/overdue, category color otherwise. Never strikes
    /// through or hides the title -- status is conveyed by color alone.
    static func displayColor(for status: EventStatus, categoryColor: Color) -> Color {
        status.tintColor ?? categoryColor
    }
}
