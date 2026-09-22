import CoreLocation
import EventKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Matches the web app's exportData() payload exactly: `{events, prefs, exportedAt}`.
private struct ExportPayload: Decodable {
    let events: [ExportedEvent]
    let prefs: ExportedPrefs?
}

private struct ExportedEvent: Decodable {
    let id: String
    let title: String
    let date: String
    let allDay: Bool
    let start: String?
    let end: String?
    let category: String?
    let location: String?
    let locationLat: Double?
    let locationLon: Double?
    let notes: String?
    let reminder: Int?
    let completed: Bool?
}

private struct ExportedPrefs: Decodable {
    let weekStart: Int?
    let defaultReminder: String?
}

/// The web app's built-in category ids map to these friendly names; anything
/// else (custom categories) falls back to a title-cased version of the id.
private let knownCategoryNames: [String: String] = [
    "gym": "Gym", "food": "Food", "class": "Class", "sleep": "Sleep",
]

private enum ImportStage {
    case pickFile
    case reviewCategories(payload: [ExportedEvent], categoryIDs: [String])
    case importing
    case done(imported: Int, skipped: Int)
    case failed(String)
}

struct ImportFromWebAppView: View {
    @Environment(EventStoreManager.self) private var eventStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var stage: ImportStage = .pickFile
    @State private var showingFileImporter = false
    @State private var categoryNames: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .pickFile:
                    pickFileView
                case .reviewCategories(_, let categoryIDs):
                    reviewCategoriesView(categoryIDs: categoryIDs)
                case .importing:
                    ProgressView("Importing…")
                case .done(let imported, let skipped):
                    doneView(imported: imported, skipped: skipped)
                case .failed(let message):
                    failedView(message: message)
                }
            }
            .navigationTitle("Import from Web App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.json]) { result in
            handlePickedFile(result)
        }
    }

    private var pickFileView: some View {
        ContentUnavailableView {
            Label("Import Your Old Events", systemImage: "square.and.arrow.down")
        } description: {
            Text("Pick the backup JSON file exported from the web app's Settings screen.")
        } actions: {
            Button("Choose File") { showingFileImporter = true }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ultramarine)
        }
    }

    private func reviewCategoriesView(categoryIDs: [String]) -> some View {
        Form {
            Section {
                Text("Each old category becomes its own calendar. Rename them if you'd like before importing.")
                    .foregroundStyle(.secondary)
            }
            Section("Calendars") {
                ForEach(categoryIDs, id: \.self) { id in
                    TextField(
                        "Calendar name",
                        text: Binding(
                            get: { categoryNames[id] ?? friendlyName(for: id) },
                            set: { categoryNames[id] = $0 }
                        )
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Import") { runImport(categoryIDs: categoryIDs) }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ultramarine)
                .padding()
        }
    }

    private func doneView(imported: Int, skipped: Int) -> some View {
        ContentUnavailableView {
            Label("Import Complete", systemImage: "checkmark.circle.fill")
        } description: {
            Text(skipped > 0
                ? "Imported \(imported) event(s). Skipped \(skipped) that couldn't be read."
                : "Imported \(imported) event(s).")
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ultramarine)
        }
    }

    private func failedView(message: String) -> some View {
        ContentUnavailableView {
            Label("Import Failed", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { stage = .pickFile }
        }
    }

    private func friendlyName(for categoryID: String) -> String {
        if categoryID.isEmpty { return "Other" }
        return knownCategoryNames[categoryID] ?? categoryID.prefix(1).uppercased() + categoryID.dropFirst()
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(ExportPayload.self, from: data)
            let categoryIDs = Array(Set(payload.events.map { $0.category ?? "" })).sorted()
            stage = .reviewCategories(payload: payload.events, categoryIDs: categoryIDs)
            if let weekStart = payload.prefs?.weekStart {
                let rows = try? modelContext.fetch(FetchDescriptor<AppPreferences>())
                let preferences = AppPreferencesAccess.ensure(rows ?? [], in: modelContext)
                preferences.weekStartDay = weekStart
            }
        } catch {
            stage = .failed("Couldn't read that file. Make sure it's a calendar backup JSON exported from the web app.")
        }
    }

    private func runImport(categoryIDs: [String]) {
        guard case .reviewCategories(let events, _) = stage else { return }
        stage = .importing
        var calendarsByCategory: [String: EKCalendar] = [:]
        for (index, id) in categoryIDs.enumerated() {
            let name = categoryNames[id] ?? friendlyName(for: id)
            let color = AppTheme.calendarColors[index % AppTheme.calendarColors.count]
            if let calendar = try? CalendarCategoryManager.findOrCreateCalendar(
                named: name,
                color: PlatformColor(color),
                in: eventStore.store
            ) {
                calendarsByCategory[id] = calendar
            }
        }

        var imported = 0
        var skipped = 0
        let dateParser = DateFormatter()
        dateParser.dateFormat = "yyyy-MM-dd"
        dateParser.timeZone = .current
        let timeParser = DateFormatter()
        timeParser.dateFormat = "yyyy-MM-dd HH:mm"
        timeParser.timeZone = .current

        for event in events {
            guard let calendar = calendarsByCategory[event.category ?? ""],
                  let dayStart = dateParser.date(from: event.date)
            else {
                skipped += 1
                continue
            }

            let startDate: Date
            let endDate: Date
            if event.allDay {
                startDate = DateMath.startOfDay(dayStart)
                endDate = DateMath.addingDays(1, to: startDate)
            } else if let startTime = event.start,
                      let parsedStart = timeParser.date(from: "\(event.date) \(startTime)") {
                startDate = parsedStart
                if let endTime = event.end, let parsedEnd = timeParser.date(from: "\(event.date) \(endTime)") {
                    endDate = parsedEnd
                } else {
                    endDate = parsedStart.addingTimeInterval(3600)
                }
            } else {
                skipped += 1
                continue
            }

            var structuredLocation: EKStructuredLocation?
            if let location = event.location, !location.isEmpty,
               let lat = event.locationLat, let lon = event.locationLon {
                let structured = EKStructuredLocation(title: location)
                structured.geoLocation = CLLocation(latitude: lat, longitude: lon)
                structuredLocation = structured
            }

            guard let created = try? eventStore.createEvent(
                title: event.title,
                startDate: startDate,
                endDate: endDate,
                isAllDay: event.allDay,
                calendar: calendar,
                location: event.location?.isEmpty == false ? event.location : nil,
                structuredLocation: structuredLocation,
                notes: event.notes?.isEmpty == false ? event.notes : nil
            ) else {
                skipped += 1
                continue
            }

            if let reminder = event.reminder {
                created.addAlarm(EKAlarm(relativeOffset: -Double(reminder * 60)))
                try? eventStore.update(created)
            }

            if event.completed == true {
                let status = EventCompletionStatus(
                    eventIdentifier: created.eventIdentifier ?? "",
                    calendarItemExternalIdentifier: created.calendarItemExternalIdentifier,
                    completed: true,
                    lastKnownStartDate: created.startDate,
                    lastKnownTitle: created.title
                )
                modelContext.insert(status)
            }

            imported += 1
        }

        stage = .done(imported: imported, skipped: skipped)
    }
}
