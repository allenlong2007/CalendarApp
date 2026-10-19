import EventKit
import SwiftData
import SwiftUI

/// Add or delete events by talking: say it, check the summary, then confirm (by
/// tapping or saying "yes"), speak a correction, or fall back to the editor.
///
/// It's a compact bottom panel, not a full screen: the calendar above stays
/// visible and tappable, and jumps to the day being talked about.
struct VoiceEventView: View {
    /// Hands the draft to the full editor (the parent presents it once this closes).
    let onEditManually: (EventDraft) -> Void
    /// Moves the calendar behind the panel to a day.
    let onFocusDate: (Date) -> Void

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var reminderRows: [EventReminderPreference]
    @Query private var locationOverrides: [EventLocationOverride]
    @Query private var preferencesRows: [AppPreferences]

    @State private var speech = SpeechTranscriber()
    @State private var draft: EventDraft?
    /// Events a "delete ..." request matched, waiting for a yes.
    @State private var deleteCandidates: [EKEvent] = []
    @State private var deleteQuery: String?
    @State private var lastHeard = ""
    @State private var typed = ""
    @State private var errorMessage: String?
    @FocusState private var typing: Bool

    private static let panelHeight: CGFloat = 380

    private var writableCalendars: [EKCalendar] { eventStore.calendars.filter(\.allowsContentModifications) }
    private var parser: VoiceEventParser { VoiceEventParser(calendarTitles: writableCalendars.map(\.title)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 16) {
                        if deleteQuery != nil { deleteCard }
                        else if let draft { summary(for: draft) }
                        else { prompt }
                        typeInstead
                        if let message = errorMessage ?? speech.errorMessage {
                            Text(message).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { speech.cancel(); dismiss() } }
            }
        }
        // Compact by default with the calendar still usable behind it.
        .presentationDetents([.height(Self.panelHeight), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(Self.panelHeight)))
        .presentationDragIndicator(.visible)
        .task {
            speech.contextualStrings = writableCalendars.map(\.title) + locationOverrides.map(\.locationText)
            speech.onFinished = { heard in handle(heard) }
            await speech.requestAccess()
            if speech.access == .granted { speech.start() }
        }
        .onDisappear { speech.cancel() }
    }

    // MARK: - Header (mic + what it's hearing)

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if speech.isListening { speech.stop() } else { typing = false; speech.start() }
            } label: {
                Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(speech.isListening ? Color.red : AppTheme.ultramarine))
                    .overlay(Circle().stroke(Color.red.opacity(0.35), lineWidth: speech.isListening ? 5 : 0))
                    .animation(Motion.easeOut(0.2), value: speech.isListening)
            }
            .buttonStyle(.plain)
            .disabled(speech.access == .denied)
            .accessibilityLabel(speech.isListening ? "Stop listening" : "Start listening")

            Group {
                if speech.access == .denied {
                    Text("Microphone or speech access is off. Allow it in Settings → CalendarApp, or type below.")
                } else if speech.isListening {
                    Text(speech.transcript.isEmpty ? "Listening…" : "“\(speech.transcript)”")
                } else if deleteQuery != nil {
                    Text("Say “yes” to delete, or tap one below.")
                } else if draft != nil {
                    Text("Say “yes” to add it, or a correction like “make it 7 pm”.")
                } else {
                    Text("Tap the mic and start talking.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Sections

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add or delete by voice").font(.headline)
            Text("“Pickleball practice Thursday at 6 pm at the Warren tennis courts, category exercise.”")
                .font(.footnote).foregroundStyle(.secondary)
            Text("“Delete pickleball practice on Thursday.”")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typeInstead: some View {
        HStack {
            TextField("Or type it here", text: $typed)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit(submitTyped)
            if !typed.isEmpty {
                Button("Send", action: submitTyped).buttonStyle(.borderedProminent).tint(AppTheme.ultramarine)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
    }

    // MARK: Add summary

    @ViewBuilder
    private func summary(for draft: EventDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !lastHeard.isEmpty {
                Text("I heard: “\(lastHeard)”").font(.footnote).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                row("Event", draft.title.isEmpty ? nil : draft.title, missing: "Say a title")
                row("Day", draft.start.map { DateMath.fullDateFormatter.string(from: $0) }, missing: "Say a day")
                row("Time", timeText(for: draft), missing: "Say a time")
                categoryRow(for: draft)
                row("Location", draft.location, missing: "None", optional: true)
                row("Reminder", reminderText(for: draft), missing: "Default (15 min before)", optional: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))

            if !draft.gaps.isEmpty {
                Label("Still needed: " + draft.gaps.map(\.rawValue).joined(separator: ", ") + ". Say it, or edit by hand.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button(action: { create(draft) }) {
                Label("Add to Calendar", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.ultramarine)
            .disabled(!draft.isComplete)

            HStack(spacing: 12) {
                Button {
                    speech.cancel()
                    onEditManually(draft)
                    dismiss()
                } label: { Label("Edit Details", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)

                Button(role: .destructive) { reset() } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func row(_ label: String, _ value: String?, missing: String, optional: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            if let value, !value.isEmpty {
                Text(value).font(.body.weight(.medium))
            } else {
                Text(missing).font(.body).foregroundStyle(optional ? Color.secondary : Color.orange)
            }
            Spacer(minLength: 0)
        }
    }

    private func categoryRow(for draft: EventDraft) -> some View {
        let calendar = writableCalendars.first { $0.title.caseInsensitiveCompare(draft.calendarTitle ?? "") == .orderedSame }
        return HStack(alignment: .firstTextBaseline) {
            Text("Category").font(.subheadline).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            if let calendar {
                HStack(spacing: 6) {
                    Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 10, height: 10)
                    Text(calendar.title).font(.body.weight(.medium))
                }
            } else {
                Text("Default (\(eventStore.store.defaultCalendarForNewEvents?.title ?? "—"))").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Delete card

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !lastHeard.isEmpty {
                Text("I heard: “\(lastHeard)”").font(.footnote).foregroundStyle(.secondary)
            }

            if deleteCandidates.isEmpty {
                Label("I couldn't find an event matching that. Try the event's name, and a day if there are several.", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                Text(deleteCandidates.count == 1 ? "Delete this event?" : "Which one should I delete?")
                    .font(.headline)
                ForEach(deleteCandidates, id: \.eventIdentifier) { event in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.calendarColor(for: event.calendar))
                            .frame(width: 4, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title ?? "Untitled").font(.body.weight(.medium))
                            Text(whenText(for: event)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button(role: .destructive) { delete(event) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                    .onTapGesture { onFocusDate(event.startDate) }
                }
                if deleteCandidates.count > 1 {
                    Text("Or say the day, like “delete it on Thursday”.").font(.footnote).foregroundStyle(.secondary)
                }
            }

            Button("Not now") { reset() }.buttonStyle(.bordered)
        }
    }

    private func whenText(for event: EKEvent) -> String {
        let day = DateMath.fullDateFormatter.string(from: event.startDate)
        if event.isAllDay { return "\(day) · All-day" }
        return "\(day) · \(DateMath.timeFormatter.string(from: event.startDate)) – \(DateMath.timeFormatter.string(from: event.endDate))"
    }

    // MARK: - Text

    private func timeText(for draft: EventDraft) -> String? {
        guard let start = draft.start else { return nil }
        if draft.isAllDay { return "All-day" }
        guard draft.timeKnown else { return nil }
        let end = draft.end.map { " – " + DateMath.timeFormatter.string(from: $0) } ?? ""
        return DateMath.timeFormatter.string(from: start) + end
    }

    private func reminderText(for draft: EventDraft) -> String? {
        guard let minutes = draft.reminderMinutes else { return nil }
        if minutes == 0 { return "None" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) day\(minutes == 1440 ? "" : "s") before" }
        if minutes % 60 == 0 { return "\(minutes / 60) hour\(minutes == 60 ? "" : "s") before" }
        return "\(minutes) minutes before"
    }

    // MARK: - Actions

    private func submitTyped() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typed = ""
        handle(text)
    }

    private func reset() {
        draft = nil
        deleteQuery = nil
        deleteCandidates = []
        lastHeard = ""
        errorMessage = nil
    }

    /// One path for spoken and typed sentences alike.
    private func handle(_ heard: String) {
        lastHeard = heard
        errorMessage = nil
        switch VoiceIntentClassifier().classify(heard) {
        case .confirm:
            if deleteQuery != nil, deleteCandidates.count == 1, let event = deleteCandidates.first { delete(event) }
            else if deleteQuery == nil, let draft, draft.isComplete { create(draft) }
        case .cancel:
            if draft != nil || deleteQuery != nil { reset() } else { speech.cancel(); dismiss() }
        case .delete(let request):
            draft = nil
            deleteQuery = heard
            deleteCandidates = findEvents(for: request)
            if let first = deleteCandidates.first { onFocusDate(first.startDate) }
        case .describeEvent:
            // A new description while a delete was pending abandons it.
            if deleteQuery != nil { deleteQuery = nil; deleteCandidates = [] }
            draft = parser.parse(heard, applying: draft)
            if let start = draft?.start { onFocusDate(start) }
        }
    }

    private func findEvents(for request: VoiceDeleteRequest) -> [EKEvent] {
        let now = Date.now
        let from = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let to = Calendar.current.date(byAdding: .day, value: 365, to: now) ?? now
        let events = eventStore.events(from: from, to: to, in: writableCalendars)
        let refs = events.enumerated().map { EventRef(id: String($0.offset), title: $0.element.title ?? "", start: $0.element.startDate) }
        return VoiceDeleteMatcher.matches(request, in: refs, now: now).compactMap { Int($0.id).map { events[$0] } }
    }

    private func delete(_ event: EKEvent) {
        eventStore.deleteWithUndo(event, undoManager: undoManager)
        deleteCandidates.removeAll { $0.eventIdentifier == event.eventIdentifier }
        if deleteCandidates.isEmpty {
            speech.cancel()
            dismiss()
        }
    }

    private func create(_ draft: EventDraft) {
        guard let start = draft.start else { return }
        let calendar = writableCalendars.first { $0.title.caseInsensitiveCompare(draft.calendarTitle ?? "") == .orderedSame }
            ?? eventStore.store.defaultCalendarForNewEvents
            ?? writableCalendars.first
        guard let calendar else { errorMessage = "No calendar to add this to."; return }
        let end = draft.end ?? start.addingTimeInterval(3600)
        do {
            let event = try eventStore.createEvent(
                title: draft.title,
                startDate: start,
                endDate: end,
                isAllDay: draft.isAllDay,
                calendar: calendar,
                location: draft.location,
                notes: draft.notes
            )
            AppPreferencesAccess.reveal(calendar, rows: preferencesRows, in: modelContext)
            if let minutes = draft.reminderMinutes {
                EventReminderAccess.setReminder(minutes == 0 ? nil : minutes, for: event, in: reminderRows, context: modelContext)
            }
            if let location = draft.location, !location.isEmpty {
                EventLocationAccess.setLocation(location, coordinate: nil, title: draft.title, rows: locationOverrides, context: modelContext)
            }
            if let identifier = event.eventIdentifier {
                undoManager.register(message: "Event Added") {
                    if let created = eventStore.event(withIdentifier: identifier) { try? eventStore.delete(created) }
                }
            }
            onFocusDate(start)
            speech.cancel()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
