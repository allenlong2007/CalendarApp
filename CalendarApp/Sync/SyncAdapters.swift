import EventKit
import Foundation
import SwiftData

// Wire formats. Calendar references are carried as calendar *titles*, never
// identifiers -- EKCalendar.calendarIdentifier is local to each device.
private struct ReminderPayload: Codable { var external: String; var minutes: Int?; var startMs: Int64?; var title: String? }
private struct LocationPayload: Codable { var text: String; var lat: Double?; var lon: Double? }
private struct TemplatePayload: Codable {
    var title: String; var isAllDay: Bool; var durationMinutes: Int; var preferredStartMinutes: Int?
    var categoryTitle: String?; var savedAddressID: String?; var notes: String?; var reminderMinutesBefore: Int?
}
private struct PlannerPayload: Codable {
    var weekday: Int; var title: String; var isAllDay: Bool; var startMinutes: Int?; var endMinutes: Int?
    var categoryTitle: String?; var notes: String?; var createdMs: Int64
}
private struct AddressPayload: Codable { var label: String; var addressLine: String; var lat: Double; var lon: Double; var createdMs: Int64 }
private struct PrefsPayload: Codable { var weekStartDay: Int; var hiddenTitles: [String] }

/// Translates between this device's SwiftData rows and sync records.
/// `collect()` is the canonical read: equal data always produces
/// byte-identical payload strings, which is what lets the reconciler tell a
/// real edit from a no-op.
@MainActor
struct SyncAdapters {
    let context: ModelContext
    let calendars: [EKCalendar]

    private func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
    private func minute(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / 60).rounded(.down)) }

    private func title(forCalendarID id: String?) -> String? {
        guard let id else { return nil }
        return calendars.first { $0.calendarIdentifier == id }?.title
    }

    private func calendarID(forTitle title: String?) -> String? {
        guard let title else { return nil }
        return calendars.first { $0.title == title }?.calendarIdentifier
    }

    /// Templates are identified by what they *are*, not by a random id: a
    /// device that already has its own "Gym 9:30" template must merge with
    /// another device's identical one instead of both being kept as
    /// duplicates. Changing a template's title, time, duration or category
    /// therefore reads as replace-with-a-new-one; notes and reminder edit in
    /// place.
    private func templateKey(for row: EventTemplate) -> String {
        [
            row.title.trimmingCharacters(in: .whitespaces).lowercased(),
            row.isAllDay ? "allday" : "timed",
            String(row.durationMinutes),
            row.preferredStartMinutes.map(String.init) ?? "-",
            title(forCalendarID: row.categoryIdentifier) ?? "-",
        ].joined(separator: "|")
    }

    private func templateKey(for p: TemplatePayload) -> String {
        [
            p.title.trimmingCharacters(in: .whitespaces).lowercased(),
            p.isAllDay ? "allday" : "timed",
            String(p.durationMinutes),
            p.preferredStartMinutes.map(String.init) ?? "-",
            p.categoryTitle ?? "-",
        ].joined(separator: "|")
    }

    private func all<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: - Read

    func collect() -> [String: String] {
        var result: [String: String] = [:]

        for row in all(EventCompletionStatus.self) {
            guard let external = row.calendarItemExternalIdentifier, !external.isEmpty,
                  let start = row.lastKnownStartDate,
                  let payload = CompletionMirror.payload(external: external, start: start, completed: row.completed, title: row.lastKnownTitle)
            else { continue }
            result[CompletionMirror.recordID(external: external, start: start)] = payload
        }
        for row in all(EventReminderPreference.self) {
            guard let external = row.calendarItemExternalIdentifier, !external.isEmpty,
                  let payload = SyncCodec.canonical(ReminderPayload(external: external, minutes: row.reminderMinutesBefore, startMs: row.lastKnownStartDate.map(ms), title: row.lastKnownTitle))
            else { continue }
            result["reminder/\(external)"] = payload
        }
        for row in all(EventLocationOverride.self) where !row.titleKey.isEmpty {
            if let payload = SyncCodec.canonical(LocationPayload(text: row.locationText, lat: row.latitude, lon: row.longitude)) {
                result["location/\(row.titleKey)"] = payload
            }
        }
        for row in all(EventTemplate.self) {
            if let payload = SyncCodec.canonical(TemplatePayload(
                title: row.title, isAllDay: row.isAllDay, durationMinutes: row.durationMinutes,
                preferredStartMinutes: row.preferredStartMinutes, categoryTitle: title(forCalendarID: row.categoryIdentifier),
                savedAddressID: row.savedAddressID?.uuidString, notes: row.notes, reminderMinutesBefore: row.reminderMinutesBefore
            )) { result["template/\(templateKey(for: row))"] = payload }
        }
        for row in all(PlannerEvent.self) {
            if let payload = SyncCodec.canonical(PlannerPayload(
                weekday: row.weekday, title: row.title, isAllDay: row.isAllDay, startMinutes: row.startMinutes,
                endMinutes: row.endMinutes, categoryTitle: title(forCalendarID: row.categoryIdentifier),
                notes: row.notes, createdMs: ms(row.createdAt)
            )) { result["planner/\(row.id.uuidString)"] = payload }
        }
        for row in all(SavedAddress.self) {
            if let payload = SyncCodec.canonical(AddressPayload(label: row.label, addressLine: row.addressLine, lat: row.latitude, lon: row.longitude, createdMs: ms(row.createdAt))) {
                result["address/\(row.id.uuidString)"] = payload
            }
        }
        // Default preferences are "no data": a fresh device's blank row must
        // never overwrite the settings another device already published.
        if let prefs = all(AppPreferences.self).first {
            let hidden = prefs.hiddenCalendarIdentifiers.compactMap { title(forCalendarID: $0) }.sorted()
            if prefs.weekStartDay != 0 || !hidden.isEmpty,
               let payload = SyncCodec.canonical(PrefsPayload(weekStartDay: prefs.weekStartDay, hiddenTitles: hidden)) {
                result["prefs/main"] = payload
            }
        }
        return result
    }

    // MARK: - Write

    func apply(_ record: SyncRecord) {
        guard let slash = record.id.firstIndex(of: "/") else { return }
        let kind = String(record.id[..<slash])
        let key = String(record.id[record.id.index(after: slash)...])
        switch kind {
        case "completion": applyCompletion(key: key, record: record)
        case "reminder": applyReminder(key: key, record: record)
        case "location": applyLocation(key: key, record: record)
        case "template": applyTemplate(key: key, record: record)
        case "planner": applyPlanner(key: key, record: record)
        case "address": applyAddress(key: key, record: record)
        case "prefs": applyPrefs(record: record)
        default: break
        }
    }

    private func applyCompletion(key: String, record: SyncRecord) {
        let rows = all(EventCompletionStatus.self)
        if record.deleted {
            guard let bar = key.lastIndex(of: "|"), let m = Int(key[key.index(after: bar)...]) else { return }
            let external = String(key[..<bar])
            for row in rows where row.calendarItemExternalIdentifier == external && row.lastKnownStartDate.map({ minute($0) == m }) == true {
                context.delete(row)
            }
            return
        }
        guard let p = SyncCodec.decodePayload(CompletionPayload.self, from: record.payload) else { return }
        let start = date(p.startMs)
        if let row = rows.first(where: { $0.calendarItemExternalIdentifier == p.external && abs(($0.lastKnownStartDate ?? .distantPast).timeIntervalSince(start)) < 60 }) {
            row.completed = p.completed
            row.lastKnownTitle = p.title
            row.lastKnownStartDate = start
        } else {
            context.insert(EventCompletionStatus(eventIdentifier: "", calendarItemExternalIdentifier: p.external, completed: p.completed, lastKnownStartDate: start, lastKnownTitle: p.title))
        }
    }

    private func applyReminder(key: String, record: SyncRecord) {
        let rows = all(EventReminderPreference.self).filter { $0.calendarItemExternalIdentifier == key }
        if record.deleted { rows.forEach { context.delete($0) }; return }
        guard let p = SyncCodec.decodePayload(ReminderPayload.self, from: record.payload) else { return }
        if let row = rows.first {
            row.reminderMinutesBefore = p.minutes
            row.lastKnownStartDate = p.startMs.map(date)
            row.lastKnownTitle = p.title
        } else {
            context.insert(EventReminderPreference(eventIdentifier: "", calendarItemExternalIdentifier: p.external, reminderMinutesBefore: p.minutes, lastKnownStartDate: p.startMs.map(date), lastKnownTitle: p.title))
        }
    }

    private func applyLocation(key: String, record: SyncRecord) {
        let rows = all(EventLocationOverride.self).filter { $0.titleKey == key }
        if record.deleted { rows.forEach { context.delete($0) }; return }
        guard let p = SyncCodec.decodePayload(LocationPayload.self, from: record.payload) else { return }
        if let row = rows.first {
            row.locationText = p.text; row.latitude = p.lat; row.longitude = p.lon
        } else {
            context.insert(EventLocationOverride(titleKey: key, locationText: p.text, latitude: p.lat, longitude: p.lon))
        }
    }

    private func applyTemplate(key: String, record: SyncRecord) {
        // Every local template with this identity (a device can hold several
        // identical ones) -- a deletion removes them all.
        let rows = all(EventTemplate.self).filter { templateKey(for: $0) == key }
        if record.deleted { rows.forEach { context.delete($0) }; return }
        guard let p = SyncCodec.decodePayload(TemplatePayload.self, from: record.payload) else { return }
        let row = rows.first ?? {
            let created = EventTemplate(title: p.title)
            context.insert(created)
            return created
        }()
        row.title = p.title
        row.isAllDay = p.isAllDay
        row.durationMinutes = p.durationMinutes
        row.preferredStartMinutes = p.preferredStartMinutes
        row.categoryIdentifier = calendarID(forTitle: p.categoryTitle)
        row.savedAddressID = p.savedAddressID.flatMap(UUID.init(uuidString:))
        row.notes = p.notes
        row.reminderMinutesBefore = p.reminderMinutesBefore
    }

    private func applyPlanner(key: String, record: SyncRecord) {
        guard let uuid = UUID(uuidString: key) else { return }
        let rows = all(PlannerEvent.self).filter { $0.id == uuid }
        if record.deleted { rows.forEach { context.delete($0) }; return }
        guard let p = SyncCodec.decodePayload(PlannerPayload.self, from: record.payload) else { return }
        let row = rows.first ?? {
            let created = PlannerEvent(weekday: p.weekday, title: p.title)
            created.id = uuid
            context.insert(created)
            return created
        }()
        row.weekday = p.weekday
        row.title = p.title
        row.isAllDay = p.isAllDay
        row.startMinutes = p.startMinutes
        row.endMinutes = p.endMinutes
        row.categoryIdentifier = calendarID(forTitle: p.categoryTitle)
        row.notes = p.notes
        row.createdAt = date(p.createdMs)
    }

    private func applyAddress(key: String, record: SyncRecord) {
        guard let uuid = UUID(uuidString: key) else { return }
        let rows = all(SavedAddress.self).filter { $0.id == uuid }
        if record.deleted { rows.forEach { context.delete($0) }; return }
        guard let p = SyncCodec.decodePayload(AddressPayload.self, from: record.payload) else { return }
        let row = rows.first ?? {
            let created = SavedAddress(label: p.label, addressLine: p.addressLine, latitude: p.lat, longitude: p.lon)
            created.id = uuid
            context.insert(created)
            return created
        }()
        row.label = p.label
        row.addressLine = p.addressLine
        row.latitude = p.lat
        row.longitude = p.lon
        row.createdAt = date(p.createdMs)
    }

    private func applyPrefs(record: SyncRecord) {
        let prefs = all(AppPreferences.self).first ?? {
            let created = AppPreferences()
            context.insert(created)
            return created
        }()
        if record.deleted {
            prefs.weekStartDay = 0
            prefs.hiddenCalendarIdentifiers = []
            return
        }
        guard let p = SyncCodec.decodePayload(PrefsPayload.self, from: record.payload) else { return }
        prefs.weekStartDay = p.weekStartDay
        prefs.hiddenCalendarIdentifiers = p.hiddenTitles.compactMap { calendarID(forTitle: $0) }
    }
}
