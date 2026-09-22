import EventKit
import Foundation

/// "Categories" from the web app map to EKCalendars here -- each with its own
/// color, exactly like Apple Calendar's own calendar list. New calendars are
/// created on an iCloud source when available (so they sync like Apple
/// Calendar's own "iCloud" section), falling back to a local source so the
/// app still works fully offline / without an iCloud account.
enum CalendarCategoryManager {
    static func findCalendar(named title: String, in store: EKEventStore) -> EKCalendar? {
        store.calendars(for: .event).first { $0.title == title }
    }

    @discardableResult
    static func createCalendar(
        title: String,
        color: PlatformColor,
        in store: EKEventStore
    ) throws -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = title
        calendar.cgColor = color.cgColor
        calendar.source = preferredSource(in: store)
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    static func findOrCreateCalendar(
        named title: String,
        color: PlatformColor,
        in store: EKEventStore
    ) throws -> EKCalendar {
        if let existing = findCalendar(named: title, in: store) {
            return existing
        }
        return try createCalendar(title: title, color: color, in: store)
    }

    static func delete(_ calendar: EKCalendar, in store: EKEventStore) throws {
        try store.removeCalendar(calendar, commit: true)
    }

    /// Prefers an iCloud CalDAV source (so calendars sync across devices like
    /// Apple Calendar's own do); falls back to a local source, which still
    /// satisfies fully-offline use, just without cross-device sync until the
    /// user signs into iCloud.
    private static func preferredSource(in store: EKEventStore) -> EKSource {
        if let icloud = store.sources.first(where: { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }) {
            return icloud
        }
        if let local = store.sources.first(where: { $0.sourceType == .local }) {
            return local
        }
        // Extremely unlikely fallback: any source that supports events.
        return store.sources.first { $0.sourceType != .subscribed }!
    }
}

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif
