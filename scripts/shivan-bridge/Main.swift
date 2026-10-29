import AppKit
import EventKit
import Foundation
import Darwin

/// Run only through Grok's approved local execution. No HTTP listener, OAuth
/// tokens or cloud credentials. macOS owns permission to the calendar store.
@main
struct ShivanCalendarBridge {
    @MainActor
    static func main() async {
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(CalendarBridgeRequest.self,
                from: data.isEmpty ? Data(#"{"action":"calendars"}"#.utf8) : data)
            try request.validate()
            let store = EKEventStore()
            guard try await store.requestFullAccessToEvents() else {
                throw CalendarBridgeRequest.Failure.invalid("Calendar access denied. Allow Shivan Calendar Bridge in macOS Privacy & Security > Calendars.")
            }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ShivanCalendarBridge", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let lock = open(directory.appendingPathComponent("requests.lock").path, O_CREAT | O_RDWR, 0o600)
            guard lock >= 0, lockf(lock, F_LOCK, 0) == 0 else {
                throw CalendarBridgeRequest.Failure.invalid("Could not lock the calendar request queue. Try again later.")
            }
            defer { _ = lockf(lock, F_ULOCK, 0); close(lock) }
            store.refreshSourcesIfNecessary()
            let calendars = store.calendars(for: .event).filter { $0.title != "CalendarApp Sync" && $0.title != "CalendarApp App Data" }
            if request.action == .calendars {
                try output(["calendars": calendars.map { ["id": $0.calendarIdentifier, "title": $0.title, "writable": $0.allowsContentModifications] }])
                return
            }
            if request.action == .events {
                let predicate = store.predicateForEvents(withStart: request.startDate!, end: request.endDate!, calendars: calendars)
                try output(["events": store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.map(record)])
                return
            }
            if request.action == .delete || request.action == .update {
                guard let event = store.event(withIdentifier: request.eventID!), event.calendar.allowsContentModifications else {
                    throw CalendarBridgeRequest.Failure.invalid("The event was not found or is read-only.")
                }
                guard !event.hasRecurrenceRules, event.attendees?.isEmpty != false else {
                    throw CalendarBridgeRequest.Failure.invalid("Recurring events and events with attendees must be edited in CalendarApp by Allen.")
                }
                if request.action == .delete {
                    let old = record(event)
                    try store.remove(event, span: .thisEvent)
                    if store.event(withIdentifier: request.eventID!) != nil {
                        throw CalendarBridgeRequest.Failure.invalid("Deletion could not be verified.")
                    }
                    wakeCalendarApp()
                    try output(["deleted": old])
                    return
                }
                let wasImportant = EventImportance.isImportant(notes: event.notes)
                if let calendarID = request.calendarID {
                    guard let destination = calendars.first(where: { $0.calendarIdentifier == calendarID && $0.allowsContentModifications }) else {
                        throw CalendarBridgeRequest.Failure.invalid("Destination calendar is missing or read-only.")
                    }
                    event.calendar = destination
                }
                event.title = request.title!
                event.startDate = request.startDate!
                event.endDate = request.endDate!
                if let allDay = request.allDay { event.isAllDay = allDay }
                if let location = request.location { event.location = location }
                let requestMarkers = (event.notes ?? "").split(separator: "\n")
                    .filter { $0.hasPrefix("[Shivan:request=") && $0.hasSuffix("]") }
                    .map(String.init)
                var updatedNotes = request.notes ?? event.notes ?? ""
                for marker in requestMarkers where !updatedNotes.contains(marker) {
                    updatedNotes += (updatedNotes.isEmpty ? "" : "\n") + marker
                }
                event.notes = EventImportance.notes(updatedNotes,
                    settingImportant: request.important ?? wasImportant)
                try store.save(event, span: .thisEvent)
                wakeCalendarApp()
                try output(["updated": record(event)])
                return
            }
            guard let calendarID = request.calendarID,
                  let calendar = calendars.first(where: { $0.calendarIdentifier == calendarID && $0.allowsContentModifications }) else {
                throw CalendarBridgeRequest.Failure.invalid("Choose an exact writable calendarID from the calendars response.")
            }
            let marker = "[Shivan:request=\(request.requestID!.uuidString)]"
            let receiptFile = directory.appendingPathComponent(request.requestID!.uuidString + ".json")
            if let receiptData = try? Data(contentsOf: receiptFile),
               let eventID = try? JSONDecoder().decode(String.self, from: receiptData) {
                guard let existing = store.event(withIdentifier: eventID) else {
                    throw CalendarBridgeRequest.Failure.invalid("This handoff was already processed, but its saved event ID changed or was deleted. Check the calendar before creating a new handoff.")
                }
                try output(["alreadyExists": record(existing)])
                return
            }
            let predicate = store.predicateForEvents(withStart: request.startDate!.addingTimeInterval(-366 * 86400),
                end: request.endDate!.addingTimeInterval(366 * 86400), calendars: calendars)
            if let existing = store.events(matching: predicate).first(where: { ($0.notes ?? "").contains(marker) }) {
                try JSONEncoder().encode(existing.eventIdentifier ?? "").write(to: receiptFile, options: .atomic)
                try output(["alreadyExists": record(existing)])
                return
            }
            let event = EKEvent(eventStore: store)
            event.title = request.title!
            event.startDate = request.startDate!
            event.endDate = request.endDate!
            event.isAllDay = request.allDay ?? false
            event.calendar = calendar
            event.location = request.location
            let notes = (request.notes.map { $0 + "\n" } ?? "") + marker
            event.notes = EventImportance.notes(notes, settingImportant: request.important ?? false)
            try store.save(event, span: .thisEvent)
            guard let saved = store.event(withIdentifier: event.eventIdentifier) else {
                throw CalendarBridgeRequest.Failure.invalid("Save returned but read-back failed. Check before retrying with the same requestID.")
            }
            try JSONEncoder().encode(saved.eventIdentifier ?? "").write(to: receiptFile, options: .atomic)
            wakeCalendarApp()
            try output(["created": record(saved)])
        } catch {
            let data = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data()
            FileHandle.standardOutput.write(data + Data("\n".utf8))
            exit(1)
        }
    }

    static func record(_ event: EKEvent) -> [String: Any] {
        ["id": event.eventIdentifier ?? "", "title": event.title ?? "",
         "start": ISO8601DateFormatter().string(from: event.startDate),
         "end": ISO8601DateFormatter().string(from: event.endDate),
         "calendarID": event.calendar.calendarIdentifier, "calendar": event.calendar.title,
         "location": event.location ?? "", "notes": event.notes ?? "",
         "important": EventImportance.isImportant(notes: event.notes), "allDay": event.isAllDay]
    }

    static func output(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    @MainActor
    static func wakeCalendarApp() {
        // Opening the app refreshes the app-owned notification queue. The
        // bridge never claims a notification was delivered merely after save.
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/CalendarApp.app"),
            configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}
