import EventKit
import Foundation
import Observation
import SwiftData
import WidgetKit

/// Keeps this device's app-only data (checkmarks, templates, reminders,
/// locations, planner, addresses, hidden calendars) in step with the user's
/// other devices. Events themselves already sync through iCloud Calendar --
/// this covers everything EventKit has no place for, which would normally
/// need CloudKit (unavailable on a free developer account).
///
/// Runs every ~20s while the app is open, and immediately on launch, when the
/// app returns to the foreground, and whenever the calendar store changes.
/// Each pass is cheap when nothing changed: diff, compare a digest, done.
@Observable
@MainActor
final class SyncCoordinator {
    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var status: Status = .idle

    private let deviceID: String
    private let ledgerFileName: String
    private var container: ModelContainer?
    private var eventStore: EventStoreManager?
    private var loop: Task<Void, Never>?
    private var isSyncing = false

    /// For tests: a second, independent "device" sharing this process.
    init(deviceID: String, ledgerFileName: String) {
        self.deviceID = deviceID
        self.ledgerFileName = ledgerFileName
    }

    init() {
        ledgerFileName = "CalendarAppSyncLedger.json"
        let key = "calendarapp.sync.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            deviceID = existing
        } else {
            let created = UUID().uuidString
            UserDefaults.standard.set(created, forKey: key)
            deviceID = created
        }
    }

    func attach(container: ModelContainer, eventStore: EventStoreManager) {
        self.container = container
        self.eventStore = eventStore
    }

    func start(container: ModelContainer, eventStore: EventStoreManager) {
        guard loop == nil else { return }
        attach(container: container, eventStore: eventStore)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func syncNow() async {
        guard !isSyncing, let container, let eventStore, eventStore.accessStatus == .fullAccess else { return }
        isSyncing = true
        status = .syncing
        defer { isSyncing = false }

        let transport = SyncTransport(store: eventStore.store, deviceID: deviceID)
        do {
            _ = try transport.ensureCalendar()

            var file = loadLedger()
            let context = container.mainContext
            // An earlier bug could leave several AppPreferences rows; keep the
            // first (the one the UI reads) so sync and the UI agree on which.
            let prefRows = (try? context.fetch(FetchDescriptor<AppPreferences>())) ?? []
            for extra in prefRows.dropFirst() { context.delete(extra) }
            let adapters = SyncAdapters(context: context, calendars: eventStore.calendars)
            var ledger = file.records

            let toApply = SyncReconciler.reconcile(
                ledger: &ledger,
                local: adapters.collect(),
                remote: transport.readRemoteSnapshots(),
                deviceID: deviceID,
                now: .now,
                isFirstSync: !file.existed
            )

            if !toApply.isEmpty {
                for id in toApply { if let record = ledger[id] { adapters.apply(record) } }
                try context.save()
                // Re-read what actually landed so the ledger holds this
                // device's canonical form -- otherwise any lossy round trip
                // would look like a fresh local edit next pass and ping-pong.
                let after = adapters.collect()
                for id in toApply {
                    guard var record = ledger[id], !record.deleted else { continue }
                    if let payload = after[id] {
                        record.payload = payload
                        ledger[id] = record
                    } else {
                        ledger.removeValue(forKey: id)
                    }
                }
            }

            let snapshot = SyncReconciler.snapshotRecords(from: ledger, now: .now)
            let digest = SyncTransport.digest(of: snapshot)
            if digest != file.pushedDigest || !transport.hasOwnSnapshot() {
                try transport.writeSnapshot(snapshot)
                file.pushedDigest = digest
            }

            file.records = ledger
            file.existed = true
            saveLedger(file)

            if !toApply.isEmpty {
                WidgetCenter.shared.reloadAllTimelines()
                eventStore.notifyStoreMutated()
            }
            status = .synced(.now)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Ledger persistence (this device only -- never synced)

    private struct LedgerFile: Codable {
        var records: [String: SyncRecord] = [:]
        var pushedDigest: String?
        var existed = false
    }

    private struct LoadedLedger {
        var records: [String: SyncRecord]
        var pushedDigest: String?
        var existed: Bool
    }

    var ledgerURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: ledgerFileName)
    }

    private func loadLedger() -> LoadedLedger {
        guard let data = try? Data(contentsOf: ledgerURL) else { return LoadedLedger(records: [:], pushedDigest: nil, existed: false) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let file = try? decoder.decode(LedgerFile.self, from: data) else { return LoadedLedger(records: [:], pushedDigest: nil, existed: false) }
        return LoadedLedger(records: file.records, pushedDigest: file.pushedDigest, existed: file.existed)
    }

    private func saveLedger(_ loaded: LoadedLedger) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let file = LedgerFile(records: loaded.records, pushedDigest: loaded.pushedDigest, existed: loaded.existed)
        if let data = try? encoder.encode(file) { try? data.write(to: ledgerURL, options: .atomic) }
    }
}
