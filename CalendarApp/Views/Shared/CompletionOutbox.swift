import Foundation

/// One checkmark change made from a widget, waiting for the app to apply it.
struct PendingCompletion: Codable, Equatable {
    var id = UUID()
    var eventIdentifier: String
    var external: String?
    var startMs: Int64
    var title: String?
    var completed: Bool
    var atMs: Int64
}

/// How a widget hands a checkmark change to the app.
///
/// A widget used to write the SwiftData store itself. The store is shared (an
/// App Group), but two processes writing one database don't see each other's
/// changes live: the app kept showing the copy it had already loaded, so a
/// checkmark tapped on the widget never appeared in the app -- and since the
/// sync engine reads from the app, never reached the Mac either.
///
/// Now the app is the only writer. The widget leaves a small file here (one
/// per change, so two taps can never clobber each other) and shows the new
/// state straight away by layering these over what's stored; the app applies
/// them to its own database, syncs, and deletes the files.
enum CompletionOutbox {
    /// Darwin notification a widget posts so a running app drains right away.
    static let darwinName = "com.footsoregnu3115.calendarapp.completionOutbox"

    private static var directory: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ModelContainerFactory.appGroupIdentifier) else { return nil }
        let dir = base.appending(path: "CompletionOutbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func enqueue(_ item: PendingCompletion) {
        guard let dir = directory, let data = try? JSONEncoder().encode(item) else { return }
        try? data.write(to: dir.appending(path: "\(item.atMs)-\(item.id.uuidString).json"), options: .atomic)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinName as CFString), nil, nil, true
        )
    }

    /// Everything waiting, oldest first.
    static func pending() -> [(url: URL, item: PendingCompletion)] {
        guard let dir = directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (URL, PendingCompletion)? in
                guard let data = try? Data(contentsOf: url),
                      let item = try? JSONDecoder().decode(PendingCompletion.self, from: data) else { return nil }
                return (url, item)
            }
            .sorted { $0.1.atMs < $1.1.atMs }
            .map { (url: $0.0, item: $0.1) }
    }

    static func remove(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// The newest queued value for this occurrence, if any: matched by the
    /// event's cross-device id (or local id) and its start time, since every
    /// occurrence of a repeating event shares the same ids.
    static func latestValue(
        eventIdentifier: String,
        external: String?,
        startMs: Int64,
        in items: [PendingCompletion]
    ) -> Bool? {
        items
            .filter { item in
                let sameEvent: Bool
                if let external, let itemExternal = item.external { sameEvent = external == itemExternal }
                else { sameEvent = !eventIdentifier.isEmpty && item.eventIdentifier == eventIdentifier }
                return sameEvent && abs(item.startMs - startMs) < 60_000
            }
            .max { $0.atMs < $1.atMs }?
            .completed
    }
}
