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
            // A normal app launch must not wait forever for an stdin EOF.
            // Mutating commands explicitly opt into the JSON stdin contract.
            let data: Data
            if let file = argument("--request-file") {
                let url = try exchangeURL(file)
                data = try readRequestFile(url)
                guard data.count <= 262144 else { throw CalendarBridgeRequest.Failure.invalid("Request is too large.") }
            } else {
                data = CommandLine.arguments.contains("--stdin")
                    ? FileHandle.standardInput.readDataToEndOfFile() : Data()
            }
            let request = try JSONDecoder().decode(CalendarBridgeRequest.self,
                from: data.isEmpty ? Data(#"{"action":"calendars"}"#.utf8) : data)
            try request.validate()
            _ = NSApplication.shared
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
                event.notes = EventImportance.notes(request.notes ?? event.notes,
                    settingImportant: request.important ?? wasImportant, preservingRequestsFrom: event.notes)
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
            try? output(["error": error.localizedDescription])
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
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) + Data("\n".utf8)
        if let file = argument("--response-file") {
            let url = try exchangeURL(file)
            try data.write(to: url, options: .atomic)
            try Data((value["error"] == nil ? "0\n" : "1\n").utf8)
                .write(to: url.appendingPathExtension("status"), options: .atomic)
        } else {
            FileHandle.standardOutput.write(data)
        }
    }

    static func argument(_ name: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    /// Only a private regular file owned by this user is honoured. O_NONBLOCK and
    /// O_NOFOLLOW stop a FIFO or symlink dropped in the exchange folder from hanging
    /// the bridge or redirecting it.
    static func readRequestFile(_ url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else { throw CalendarBridgeRequest.Failure.invalid("Could not open the request file.") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              info.st_mode & 0o077 == 0 else {
            throw CalendarBridgeRequest.Failure.invalid("The request file must be a private regular file owned by this user.")
        }
        guard info.st_size <= 262144 else { throw CalendarBridgeRequest.Failure.invalid("Request is too large.") }
        return try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
    }

    static func exchangeURL(_ path: String) throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShivanCalendarBridge/exchange", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        var dirInfo = stat()
        guard stat(directory.path, &dirInfo) == 0, dirInfo.st_uid == getuid(), dirInfo.st_mode & 0o077 == 0 else {
            throw CalendarBridgeRequest.Failure.invalid("The exchange folder must be private to this user.")
        }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.deletingLastPathComponent() == directory else {
            throw CalendarBridgeRequest.Failure.invalid("Request and response files must be in ShivanCalendarBridge/exchange.")
        }
        return url
    }

    @MainActor
    static func wakeCalendarApp() {
        // Opening the app refreshes the app-owned notification queue. The
        // bridge never claims a notification was delivered merely after save.
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/CalendarApp.app"),
            configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}
