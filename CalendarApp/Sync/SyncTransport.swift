import CryptoKit
import EventKit
import Foundation

/// Carries each device's snapshot through iCloud inside a dedicated calendar:
/// a free Apple ID can't use CloudKit, but it *can* write calendar events, and
/// those sync between a user's devices on their own. A device only ever
/// writes its own events and only reads everyone else's, so two devices can
/// never overwrite each other -- merging happens afterward in SyncReconciler.
///
/// A snapshot is compressed JSON, base64-encoded into event notes, split into
/// parts so no single event gets large. Each part's first line is a header:
///   CALAPP-SYNC1|<device>|<pushID>|<part>|<total>|<pushedAtMs>
/// A reader only trusts a (device, pushID) group once every part is present,
/// so a half-synced write is ignored until the rest arrives.
@MainActor
struct SyncTransport {
    let store: EKEventStore
    let deviceID: String

    static let marker = "CALAPP-SYNC1"
    private static let chunkSize = 48_000
    /// Every snapshot event sits at this one fixed moment (2001-01-01 12:00
    /// UTC) -- decades away from anything the calendar views, agenda, or
    /// reminders ever fetch, so the events stay out of sight in the app.
    private static let anchor = Date(timeIntervalSince1970: 978_350_400)

    private var window: (Date, Date) { (Self.anchor.addingTimeInterval(-2 * 86_400), Self.anchor.addingTimeInterval(2 * 86_400)) }

    // MARK: - Calendar

    func syncCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.title == EventStoreManager.syncCalendarTitle }
    }

    /// Creates the sync calendar if neither device has yet. If both devices
    /// create one before iCloud connects them, both calendars are simply read
    /// from -- nothing breaks, there are just two.
    func ensureCalendar() throws -> EKCalendar {
        if let existing = syncCalendars().first(where: { $0.allowsContentModifications }) { return existing }
        guard let source = store.sources.first(where: { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }) else {
            throw SyncError.noICloudCalendar
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = EventStoreManager.syncCalendarTitle
        calendar.source = source
        calendar.cgColor = CGColor(gray: 0.5, alpha: 1)
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    // MARK: - Read

    private struct Part {
        var device: String
        var pushID: String
        var index: Int
        var total: Int
        var pushedAt: Int64
        var body: String
        var event: EKEvent
    }

    private func allParts() -> [Part] {
        let calendars = syncCalendars()
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: window.0, end: window.1, calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            guard let notes = event.notes, notes.hasPrefix(Self.marker),
                  let newline = notes.firstIndex(of: "\n") else { return nil }
            let header = notes[..<newline].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard header.count == 6, header[0] == Self.marker,
                  let index = Int(header[3]), let total = Int(header[4]), let pushedAt = Int64(header[5]) else { return nil }
            let body = notes[notes.index(after: newline)...].filter { !$0.isWhitespace }
            return Part(device: header[1], pushID: header[2], index: index, total: total, pushedAt: pushedAt, body: String(body), event: event)
        }
    }

    /// The newest *complete* snapshot from every other device.
    func readRemoteSnapshots() -> [[SyncRecord]] {
        let others = Dictionary(grouping: allParts().filter { $0.device != deviceID }, by: \.device)
        return others.values.compactMap { parts in
            let complete = Dictionary(grouping: parts, by: \.pushID).values
                .filter { group in
                    guard let total = group.first?.total else { return false }
                    return Set(group.map(\.index)) == Set(0..<total)
                }
                .max { ($0.first?.pushedAt ?? 0) < ($1.first?.pushedAt ?? 0) }
            guard let group = complete else { return nil }
            let joined = group.sorted { $0.index < $1.index }.map(\.body).joined()
            guard let compressed = Data(base64Encoded: joined),
                  let json = try? (compressed as NSData).decompressed(using: .zlib) as Data else { return nil }
            return SyncCodec.decode(json)
        }
    }

    func hasOwnSnapshot() -> Bool {
        allParts().contains { $0.device == deviceID }
    }

    // MARK: - Write

    func writeSnapshot(_ records: [SyncRecord]) throws {
        guard let json = SyncCodec.encode(records),
              let compressed = try? (json as NSData).compressed(using: .zlib) as Data else { throw SyncError.encodingFailed }
        let encoded = compressed.base64EncodedString()
        let chunks = stride(from: 0, to: encoded.count, by: Self.chunkSize).map { start -> String in
            let from = encoded.index(encoded.startIndex, offsetBy: start)
            let to = encoded.index(from, offsetBy: Self.chunkSize, limitedBy: encoded.endIndex) ?? encoded.endIndex
            return String(encoded[from..<to])
        }
        let parts = chunks.isEmpty ? [""] : chunks

        let calendar = try ensureCalendar()
        var mine = allParts().filter { $0.device == deviceID }.sorted { $0.index < $1.index }.map(\.event)
        let pushID = UUID().uuidString
        let pushedAt = Int64(Date.now.timeIntervalSince1970 * 1000)

        for (index, body) in parts.enumerated() {
            let event = index < mine.count ? mine[index] : EKEvent(eventStore: store)
            // Only brand-new parts pick a calendar; existing ones stay put so a
            // duplicate sync calendar can't make them hop back and forth.
            if index >= mine.count { event.calendar = calendar }
            event.title = "CalendarApp sync data (\(deviceID.prefix(8))) - do not edit"
            event.startDate = Self.anchor
            event.endDate = Self.anchor.addingTimeInterval(60)
            event.isAllDay = false
            event.notes = "\(Self.marker)|\(deviceID)|\(pushID)|\(index)|\(parts.count)|\(pushedAt)\n\(body)"
            try store.save(event, span: .thisEvent, commit: false)
        }
        if mine.count > parts.count {
            for stale in mine[parts.count...] { try store.remove(stale, span: .thisEvent, commit: false) }
            mine.removeSubrange(parts.count...)
        }
        try store.commit()
    }

    static func digest(of records: [SyncRecord]) -> String {
        let data = SyncCodec.encode(records) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum SyncError: LocalizedError {
    case noICloudCalendar
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noICloudCalendar: return "Sync needs an iCloud calendar account on this device."
        case .encodingFailed: return "Couldn't package data for sync."
        }
    }
}
