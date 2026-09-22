import CoreLocation
import EventKit
import Foundation
import Observation
import WidgetKit

enum CalendarAccessStatus {
    case notDetermined
    case denied
    case fullAccess
}

/// Thin, long-lived wrapper around a single EKEventStore. Real events are
/// genuine iCloud Calendar events -- this class is the only place that talks
/// to EventKit directly, so authorization, CRUD, and live external-change
/// observation all live here.
@Observable
@MainActor
final class EventStoreManager {
    let store = EKEventStore()

    private(set) var accessStatus: CalendarAccessStatus = .notDetermined

    /// Bumped whenever EKEventStoreChanged fires (e.g. the user edited an
    /// event in Apple's own Calendar app). Views that read this via the
    /// Observation framework re-render/re-fetch when it changes.
    private(set) var externalChangeToken = 0

    private var debounceTask: Task<Void, Never>?

    init() {
        accessStatus = Self.currentStatus()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeChanged),
            name: .EKEventStoreChanged,
            object: store
        )
    }

    private static func currentStatus() -> CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .fullAccess
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    @objc private func storeChanged() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.externalChangeToken += 1
        }
    }

    /// Requests full read/write calendar access. EventKit only shows its
    /// permission dialog once; if the user has already denied, this returns
    /// false immediately without re-prompting -- callers should deep-link to
    /// Settings in that case (see CalendarAccessStatus.denied handling in UI).
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            accessStatus = granted ? .fullAccess : .denied
            return granted
        } catch {
            accessStatus = .denied
            return false
        }
    }

    // MARK: - Calendars

    var calendars: [EKCalendar] {
        _ = externalChangeToken // participate in Observation tracking -- see events(from:to:in:)
        return store.calendars(for: .event)
    }

    // MARK: - Events

    /// Reading `externalChangeToken` here (even though its value is unused) is
    /// what makes every view that calls this method re-render when the store
    /// changes -- including right after THIS app's own saves: EKEventStoreChanged
    /// fires for local writes too, not just external ones, so this is the single
    /// choke point that keeps Month/Week/Day/Agenda live without each view
    /// needing to know about the token itself.
    func events(from startDate: Date, to endDate: Date, in calendars: [EKCalendar]? = nil) -> [EKEvent] {
        _ = externalChangeToken
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    @discardableResult
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendar: EKCalendar,
        location: String? = nil,
        structuredLocation: EKStructuredLocation? = nil,
        notes: String? = nil,
        recurrenceRules: [EKRecurrenceRule]? = nil
    ) throws -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay
        event.calendar = calendar
        event.location = location
        event.structuredLocation = structuredLocation
        event.notes = notes
        event.recurrenceRules = recurrenceRules
        try store.save(event, span: .thisEvent)
        bumpChangeToken()
        return event
    }

    func update(_ event: EKEvent) throws {
        try store.save(event, span: .thisEvent)
        bumpChangeToken()
    }

    func delete(_ event: EKEvent) throws {
        try store.remove(event, span: .thisEvent)
        bumpChangeToken()
    }

    /// Deletes an event and registers an undo action that recreates an
    /// equivalent one (EventKit has no "undelete," so the recreated event
    /// gets a new identifier). Shared by every quick-delete affordance
    /// (event rows, Agenda, the editor's own Delete button) so they all get
    /// the same undo-toast safety net.
    func deleteWithUndo(_ event: EKEvent, undoManager: UndoManagerService) {
        let snapshot = EventSnapshot(event: event)
        guard (try? delete(event)) != nil else { return }
        undoManager.register(message: "Event Deleted") { [weak self] in
            guard let self else { return }
            snapshot.recreate(in: self)
        }
    }

    /// Called right after our own successful writes so every view relying on
    /// events(from:to:in:)/calendars re-renders immediately -- doesn't wait on
    /// the EKEventStoreChanged round-trip (debounced, and only meant to catch
    /// changes made outside this screen, e.g. in Apple's own Calendar app).
    private func bumpChangeToken() {
        externalChangeToken += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// For call sites that mutate the store through CalendarCategoryManager
    /// directly (calendar create/rename/delete) rather than through this
    /// class's own methods -- lets them still trigger an immediate refresh.
    func notifyStoreMutated() {
        bumpChangeToken()
    }

    func event(withIdentifier identifier: String) -> EKEvent? {
        store.event(withIdentifier: identifier)
    }

    func event(withExternalIdentifier externalIdentifier: String, in range: (Date, Date)) -> EKEvent? {
        // EventKit has no direct external-identifier lookup, so search the
        // (already-fetched) events matching that identifier over a range.
        events(from: range.0, to: range.1).first { $0.calendarItemExternalIdentifier == externalIdentifier }
    }
}

/// Captures an EKEvent's fields before deletion so a later undo can recreate
/// an equivalent event -- EventKit has no "undelete," so this is a fresh
/// event with a new identifier, not a true restore.
struct EventSnapshot {
    let title: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendar: EKCalendar?
    let location: String?
    let geoLocation: CLLocation?
    let notes: String?
    let alarmOffsets: [TimeInterval]

    init(event: EKEvent) {
        title = event.title
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        calendar = event.calendar
        location = event.location
        geoLocation = event.structuredLocation?.geoLocation
        notes = event.notes
        alarmOffsets = event.alarms?.map(\.relativeOffset) ?? []
    }

    @MainActor
    func recreate(in eventStore: EventStoreManager) {
        guard let calendar else { return }
        var structuredLocation: EKStructuredLocation?
        if let location, let geoLocation {
            let structured = EKStructuredLocation(title: location)
            structured.geoLocation = geoLocation
            structuredLocation = structured
        }
        guard let recreated = try? eventStore.createEvent(
            title: title ?? "",
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendar: calendar,
            location: location,
            structuredLocation: structuredLocation,
            notes: notes
        ) else { return }
        for offset in alarmOffsets { recreated.addAlarm(EKAlarm(relativeOffset: offset)) }
        try? eventStore.update(recreated)
    }
}
