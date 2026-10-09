import EventKit
import Foundation

/// Lets a widget see checkmarks made on another device (the Mac) before the
/// phone app has had a chance to run its own sync.
///
/// The app is the only thing that merges data, and it only runs when it's
/// open or iOS wakes it. A widget can run on its own, and it can read the same
/// iCloud sync calendar the app does. So the app leaves a small file here
/// saying how fresh its copy of each checkmark is; the widget reads the other
/// devices' published snapshots and layers any checkmark that's newer than the
/// app's copy on top of what it shows. The app still does the real merge later.
/// The wire form of one synced checkmark.
struct CompletionPayload: Codable {
    var external: String
    var startMs: Int64
    var completed: Bool
    var title: String?
}

enum CompletionMirror {
    /// Record id and payload for one occurrence's checkmark. Shared by the app's
    /// own sync and the widget's direct publish so both produce identical records.
    static func recordID(external: String, start: Date) -> String {
        "completion/\(external)|\(Int((start.timeIntervalSince1970 / 60).rounded(.down)))"
    }

    static func payload(external: String, start: Date, completed: Bool, title: String?) -> String? {
        SyncCodec.canonical(CompletionPayload(
            external: external,
            startMs: Int64((start.timeIntervalSince1970 * 1000).rounded()),
            completed: completed,
            title: title
        ))
    }

    private struct File: Codable {
        var deviceID: String
        /// "completion/..." record id -> when the app's copy was last modified (ms).
        var records: [String: Int64]
    }

    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ModelContainerFactory.appGroupIdentifier)?
            .appending(path: "CompletionMirror.json")
    }

    /// App side: record what this device's merged view looks like.
    static func write(deviceID: String, ledger: [String: SyncRecord]) {
        guard let url else { return }
        var records: [String: Int64] = [:]
        for (id, record) in ledger where id.hasPrefix("completion/") {
            records[id] = Int64((record.modifiedAt.timeIntervalSince1970 * 1000).rounded())
        }
        guard let data = try? JSONEncoder().encode(File(deviceID: deviceID, records: records)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Widget side: checkmarks other devices have published that the app hasn't
    /// merged yet, shaped like queued widget taps so they layer the same way.
    /// Empty until the app has run once and written its file.
    static func unmergedRemoteChanges(store: EKEventStore) -> [PendingCompletion] {
        guard let url, let data = try? Data(contentsOf: url),
              let mirror = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        let snapshots = SyncTransport(store: store, deviceID: mirror.deviceID).readRemoteSnapshots()
        var result: [PendingCompletion] = []
        for snapshot in snapshots {
            for record in snapshot where record.id.hasPrefix("completion/") && !record.deleted {
                let modifiedMs = Int64((record.modifiedAt.timeIntervalSince1970 * 1000).rounded())
                if let known = mirror.records[record.id], known >= modifiedMs { continue }
                guard let json = record.payload?.data(using: .utf8),
                      let payload = try? JSONDecoder().decode(CompletionPayload.self, from: json) else { continue }
                result.append(PendingCompletion(
                    eventIdentifier: "",
                    external: payload.external,
                    startMs: payload.startMs,
                    title: nil,
                    completed: payload.completed,
                    atMs: modifiedMs
                ))
            }
        }
        return result
    }

    // MARK: - Widget publishes straight to the other devices

    private static var widgetRecordsURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ModelContainerFactory.appGroupIdentifier)?
            .appending(path: "WidgetSyncRecords.json")
    }

    /// Widget side: send a checkmark to the user's other devices (and this
    /// phone's own app) right now, through the sync calendar.
    ///
    /// The queued tap in CompletionOutbox only reaches the Mac once the phone
    /// app next runs, and iOS doesn't run it on demand. A widget can write
    /// calendar events itself, so it publishes under its own writer id
    /// ("widget-<device>") -- a snapshot of its own, which the phone app and the
    /// Mac merge like any other device's, newest change winning.
    /// Returns false when it couldn't (the app hasn't run yet, no cross-device
    /// id for the event, or no iCloud calendar), in which case the queued tap
    /// still gets there the slower way.
    /// Last few widget attempts and how each went, kept in the shared container's
    /// Library so a developer can pull it off the phone (`devicectl device copy from`).
    static func note(_ line: String) {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ModelContainerFactory.appGroupIdentifier) else { return }
        let dir = base.appending(path: "Library", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "WidgetPublishLog.txt")
        let old = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let lines = (old.split(separator: "\n").map(String.init) + ["\(Date.now.formatted(.iso8601)) \(line)"]).suffix(30)
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    @discardableResult
    static func publishFromWidget(external: String?, start: Date, completed: Bool, title: String?) -> Bool {
        guard let external, !external.isEmpty else { note("skip: event has no cross-device id"); return false }
        guard let url, let data = try? Data(contentsOf: url),
              let mirror = try? JSONDecoder().decode(File.self, from: data),
              let recordsURL = widgetRecordsURL else { note("skip: app hasn't written its mirror file yet"); return false }

        let writer = "widget-\(mirror.deviceID)"
        var records: [String: SyncRecord] = [:]
        if let stored = try? Data(contentsOf: recordsURL), let list = SyncCodec.decode(stored) {
            records = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        }
        let now = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
        let id = recordID(external: external, start: start)
        records[id] = SyncRecord(
            id: id, modifiedAt: now, deleted: false,
            payload: payload(external: external, start: start, completed: completed, title: title),
            writer: writer
        )
        // Only recent taps are kept so this snapshot stays tiny.
        records = records.filter { now.timeIntervalSince($0.value.modifiedAt) < 30 * 86_400 }
        let list = records.values.sorted { $0.id < $1.id }
        if let encoded = SyncCodec.encode(list) { try? encoded.write(to: recordsURL, options: .atomic) }

        let transport = SyncTransport(store: EKEventStore(), deviceID: writer)
        do {
            try transport.writeSnapshot(list)
            note("published \(completed ? "done" : "not done") for \(title ?? "?") (\(list.count) records)")
            return true
        } catch {
            note("publish failed: \(error.localizedDescription)")
            return false
        }
    }
}
