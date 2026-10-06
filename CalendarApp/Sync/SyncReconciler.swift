import Foundation

/// One synced piece of app data (a completion checkmark, a template, ...) or
/// the tombstone for a deleted one. `id` is "<kind>/<key>" and is identical
/// on every device for the same logical record.
struct SyncRecord: Codable, Equatable {
    var id: String
    var modifiedAt: Date
    var deleted: Bool
    var payload: String?
    var writer: String
}

/// The device-independent merge brain. No EventKit, no SwiftData -- the
/// caller hands in what this device's store currently contains and what the
/// other devices last published, and gets back which records to apply
/// locally. Kept pure so it can be tested exhaustively on its own.
///
/// Model: every device keeps a "ledger" -- its view of the merged world --
/// and publishes it. Each cycle (1) diff the local store against the ledger
/// to find local edits/deletions and stamp them "now", (2) take any remote
/// record that is newer than the ledger's, (3) report which of those differ
/// from the local store so the caller can apply them. Newest edit wins; ties
/// break on writer id so every device converges on the same winner.
enum SyncReconciler {
    private static let tombstoneLifetime: TimeInterval = 365 * 86_400

    /// - Returns: ids whose ledger version came from a remote device and
    ///   differs from the local store, i.e. what the caller must now apply.
    static func reconcile(
        ledger: inout [String: SyncRecord],
        local: [String: String],
        remote: [[SyncRecord]],
        deviceID: String,
        now rawNow: Date,
        isFirstSync: Bool
    ) -> [String] {
        // Millisecond precision, matching what survives a trip through JSON,
        // so a record compares equal to its own published copy.
        let now = Date(timeIntervalSince1970: (rawNow.timeIntervalSince1970 * 1000).rounded(.down) / 1000)

        // A: local edits, creations, resurrections.
        for (id, payload) in local {
            if let known = ledger[id], !known.deleted, known.payload == payload { continue }
            // On a device's very first sync, pre-existing local data must not
            // beat data other devices already published -- stamp it as oldest.
            ledger[id] = SyncRecord(
                id: id,
                modifiedAt: isFirstSync ? .distantPast : now,
                deleted: false,
                payload: payload,
                writer: deviceID
            )
        }
        // A: local deletions.
        for (id, known) in ledger where !known.deleted && local[id] == nil {
            ledger[id] = SyncRecord(id: id, modifiedAt: now, deleted: true, payload: nil, writer: deviceID)
        }

        // B: take newer remote records.
        var taken: [String] = []
        for snapshot in remote {
            for record in snapshot {
                if let known = ledger[record.id] {
                    let newer = record.modifiedAt > known.modifiedAt
                        || (record.modifiedAt == known.modifiedAt && record.writer > known.writer)
                    guard newer else { continue }
                }
                ledger[record.id] = record
                if !taken.contains(record.id) { taken.append(record.id) }
            }
        }

        // C: of those, which actually change this device's store?
        let toApply = taken.filter { id in
            guard let record = ledger[id] else { return false }
            return record.deleted ? local[id] != nil : local[id] != record.payload
        }

        ledger = ledger.filter { _, record in
            !(record.deleted && now.timeIntervalSince(record.modifiedAt) > tombstoneLifetime && record.modifiedAt != .distantPast)
        }
        return toApply
    }

    /// What to publish. Completion checkmarks for events more than ~6 months
    /// old are left out to keep the snapshot small; they stay on the devices
    /// that already have them.
    static func snapshotRecords(from ledger: [String: SyncRecord], now: Date) -> [SyncRecord] {
        let cutoff = now.addingTimeInterval(-180 * 86_400)
        return ledger.values
            .filter { record in
                guard record.id.hasPrefix("completion/"),
                      let bar = record.id.lastIndex(of: "|"),
                      let minutes = Double(record.id[record.id.index(after: bar)...]) else { return true }
                return Date(timeIntervalSince1970: minutes * 60) >= cutoff
            }
            .sorted { $0.id < $1.id }
    }
}

enum SyncCodec {
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static func encode(_ records: [SyncRecord]) -> Data? {
        try? encoder().encode(records)
    }

    static func decode(_ data: Data) -> [SyncRecord]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode([SyncRecord].self, from: data)
    }

    /// Canonical JSON for one record's payload, so equal data always yields
    /// byte-identical strings on every device.
    static func canonical<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodePayload<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
