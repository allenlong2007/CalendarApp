import EventKit
import Foundation
import UserNotifications

/// This app's own local-notification reminders, replacing EventKit's
/// EKAlarm (which fires as a system Calendar notification, not something
/// this app controls or can brand as its own). Events still live in
/// EventKit/iCloud for cross-device sync and Apple Calendar/widget
/// visibility -- only the *reminder delivery* moved to this app.
///
/// iOS caps an app at 64 pending local notifications, so rather than
/// scheduling every future occurrence of every recurring class for the
/// whole semester, this keeps only the nearest `maxScheduled` upcoming
/// ones queued and fully rebuilds that queue on every refresh -- cheap,
/// and correct as long as the app gets opened occasionally (every launch
/// and every EventKit change triggers a refresh; see CalendarRootView).
@MainActor
enum ReminderScheduler {
    private static let maxScheduled = 60

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func refresh(events: [EKEvent], reminderRows: [EventReminderPreference]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let now = Date.now
        let candidates = events
            .compactMap { event -> (event: EKEvent, fireDate: Date)? in
                guard let minutes = EventReminderAccess.effectiveMinutes(for: event, in: reminderRows) else { return nil }
                let fireDate = event.startDate.addingTimeInterval(-Double(minutes * 60))
                guard fireDate > now else { return nil }
                return (event, fireDate)
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maxScheduled)

        for (event, fireDate) in candidates {
            let content = UNMutableNotificationContent()
            content.title = event.title ?? "Event"
            var body = event.isAllDay ? "All-day" : "Starts at \(DateMath.timeFormatter.string(from: event.startDate))"
            if let location = event.location, !location.isEmpty {
                body += " · \(location)"
            }
            content.body = body
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let key = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
            let identifier = "\(key)-\(Int(event.startDate.timeIntervalSince1970))"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
