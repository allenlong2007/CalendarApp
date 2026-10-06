import Foundation
import Testing
@testable import CalendarApp

/// A simulated device: a local "store" plus the ledger/published snapshot the
/// real SyncCoordinator keeps, driven through the same reconciler and codec.
private final class FakeDevice {
    let id: String
    var store: [String: String] = [:]
    var ledger: [String: SyncRecord] = [:]
    var hasSynced = false
    var published: [SyncRecord] = []
    init(_ id: String) { self.id = id }

    @discardableResult
    func cycle(_ others: [FakeDevice], at now: Date) -> Int {
        let toApply = SyncReconciler.reconcile(
            ledger: &ledger, local: store, remote: others.map(\.published),
            deviceID: id, now: now, isFirstSync: !hasSynced
        )
        hasSynced = true
        for recordID in toApply {
            guard let record = ledger[recordID] else { continue }
            store[recordID] = record.deleted ? nil : record.payload
        }
        // Round-trip through the wire format, as the real transport does.
        published = SyncCodec.decode(SyncCodec.encode(SyncReconciler.snapshotRecords(from: ledger, now: now))!)!
        return toApply.count
    }
}

private struct Clock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    mutating func tick() -> Date { now = now.addingTimeInterval(7.3); return now }
}

/// Cycles every device until a full round changes nothing anywhere.
private func settle(_ devices: [FakeDevice], _ clock: inout Clock) -> Bool {
    for _ in 0..<12 {
        let published = devices.map(\.published), ledgers = devices.map(\.ledger)
        var applied = 0
        for d in devices { applied += d.cycle(devices.filter { $0 !== d }, at: clock.tick()) }
        if applied == 0, published == devices.map(\.published), ledgers == devices.map(\.ledger) { return true }
    }
    return false
}

struct SyncReconcilerTests {
    @Test func freshDeviceReceivesEverythingAndSettles() {
        var clock = Clock()
        let a = FakeDevice("A"), b = FakeDevice("B")
        a.store = ["template/gym": "{}", "reminder/x": "{}"]
        #expect(settle([a, b], &clock))
        #expect(b.store == a.store)
    }

    @Test func editsAndDeletionsPropagateBothWays() {
        var clock = Clock()
        let a = FakeDevice("A"), b = FakeDevice("B")
        a.store = ["template/1": "v1", "template/2": "v1"]
        _ = settle([a, b], &clock)

        b.store["template/1"] = "v2"
        _ = settle([a, b], &clock)
        #expect(a.store["template/1"] == "v2")

        a.store["template/2"] = nil
        _ = settle([a, b], &clock)
        #expect(b.store["template/2"] == nil)
    }

    @Test func conflictingEditsResolveToTheLaterOneEverywhere() {
        var clock = Clock()
        let a = FakeDevice("A"), b = FakeDevice("B")
        a.store = ["template/1": "v0"]
        _ = settle([a, b], &clock)

        a.store["template/1"] = "fromA"
        a.cycle([b], at: clock.tick())
        b.store["template/1"] = "fromB"   // later edit, before B has pulled A's
        #expect(settle([a, b], &clock))
        #expect(a.store["template/1"] == "fromB")
        #expect(b.store == a.store)
    }

    @Test func twoPrePopulatedDevicesMergeWithoutLosingAnything() {
        var clock = Clock()
        let a = FakeDevice("A"), b = FakeDevice("B")
        a.store = ["prefs/main": "A", "template/a": "ta"]
        b.store = ["prefs/main": "B", "template/b": "tb"]
        #expect(settle([a, b], &clock))
        #expect(a.store == b.store)
        #expect(a.store["template/a"] != nil && a.store["template/b"] != nil)
    }

    @Test func randomEditsAcrossThreeDevicesAlwaysConvergeWithoutPingPong() {
        struct XorShift: RandomNumberGenerator {
            var state: UInt64
            mutating func next() -> UInt64 { state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state }
        }
        var rng = XorShift(state: 88_172_645_463_325_252)
        var clock = Clock()
        for _ in 0..<150 {
            let devices = [FakeDevice("A"), FakeDevice("B"), FakeDevice("C")]
            let keys = (0..<6).map { "template/\($0)" }
            for _ in 0..<40 {
                let d = devices.randomElement(using: &rng)!
                switch Int.random(in: 0..<5, using: &rng) {
                case 0: d.store[keys.randomElement(using: &rng)!] = "v\(Int.random(in: 0..<1000, using: &rng))"
                case 1: d.store[keys.randomElement(using: &rng)!] = nil
                default: d.cycle(devices.filter { $0 !== d }, at: clock.tick())
                }
            }
            #expect(settle(devices, &clock))
            #expect(devices[1].store == devices[0].store && devices[2].store == devices[0].store)
        }
    }
}
