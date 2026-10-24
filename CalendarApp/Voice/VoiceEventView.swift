import EventKit
import SwiftData
import SwiftUI

/// Add or delete events by talking: say it, check the summary, then confirm (by
/// tapping or saying "yes"), speak a correction, or fall back to the editor.
///
/// It's a compact bottom panel, not a full screen: the calendar above stays
/// visible and tappable, and jumps to the day being talked about.
private struct MoveItem: Identifiable {
    let event: EKEvent
    let request: VoiceMoveRequest
    var id: String { (event.eventIdentifier ?? "") + "\(event.startDate.timeIntervalSince1970)" }
}

struct VoiceEventView: View {
    /// Hands the draft to the full editor (the parent presents it once this closes).
    let onEditManually: (EventDraft) -> Void
    /// Closes the panel. (A panel shown inline, not as a sheet, can't use `dismiss`.)
    var onClose: (() -> Void)?
    /// Moves the calendar behind the panel to a day.
    let onFocusDate: (Date) -> Void
    /// The event open in the calendar, which "move this event ..." refers to.
    var selectedEvent: EKEvent?
    /// The day the calendar is showing: "the 21st" means that month's 21st.
    var focusDate: Date = .now

    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var reminderRows: [EventReminderPreference]
    @Query private var locationOverrides: [EventLocationOverride]
    @Query private var preferencesRows: [AppPreferences]

    @State private var speech = SpeechTranscriber()
    /// Usually one; several when a sentence described several events (swipe through them).
    @State private var drafts: [EventDraft] = []
    @State private var pageID: Int? = 0
    /// Events a "delete ..." request matched, waiting for a yes.
    @State private var deleteCandidates: [EKEvent] = []
    @State private var deleteQuery: String?
    /// "Delete all ...": many events, so it takes an explicit, counted confirmation.
    @State private var deleteIsMass = false
    /// Set when the draft is a copy of an existing event ("Copying ...").
    @State private var copyNote: String?
    /// A "move ..." request waiting for a yes, and the events it could mean.
    @State private var moveRequest: VoiceMoveRequest?
    /// What a move would do, per event. One request covers all the candidates when the
    /// name is ambiguous (tap one); with `moveMulti` each item is a separate event.
    @State private var moveItems: [MoveItem] = []
    @State private var moveMulti = false
    @State private var moveMissing: [String] = []
    /// "Delete A and B" matched by separate names, so the card says which names found nothing.
    @State private var deleteMulti = false
    @State private var deleteMissing: [String] = []
    @State private var contextEvent: EKEvent?
    @State private var confirmingMassDelete = false
    @State private var lastHeard = ""
    @State private var typed = ""
    @State private var errorMessage: String?
    @State private var emailRequest: VoiceEmailRequest?
    @State private var emailMatches: [GmailMessageDetail] = []
    @State private var emailDateChoices: [EventDraft] = []
    @State private var emailLoading = false
    @State private var pastedEmail = ""
    @State private var emailTask: Task<Void, Never>?
    @State private var gmailOAuth = GoogleOAuthService.shared
    @State private var showingGmailConnection = false
    @FocusState private var typing: Bool

    private static let panelHeight: CGFloat = 380
    /// Above this many, a spoken "delete them" isn't enough -- it has to be tapped.
    private static let voiceDeleteLimit = 30

    /// The calendar a draft belongs in: the exact one it was copied from if that
    /// still exists, otherwise the one matching the spoken category name.
    private var page: Int { min(max(pageID ?? 0, 0), max(drafts.count - 1, 0)) }

    /// The draft on the page being looked at -- spoken corrections apply to it.
    private var draft: EventDraft? {
        get { drafts.isEmpty ? nil : drafts[page] }
        nonmutating set {
            if let newValue {
                if drafts.isEmpty { drafts = [newValue] } else { drafts[page] = newValue }
            } else {
                drafts = []; pageID = 0
            }
        }
    }

    private func targetCalendar(for draft: EventDraft) -> EKCalendar? {
        if let id = draft.calendarIdentifier, let exact = writableCalendars.first(where: { $0.calendarIdentifier == id }) { return exact }
        return writableCalendars.first { $0.title.caseInsensitiveCompare(draft.calendarTitle ?? "") == .orderedSame }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var writableCalendars: [EKCalendar] { eventStore.calendars.filter(\.allowsContentModifications) }
    private var parser: VoiceEventParser { VoiceEventParser(calendarTitles: writableCalendars.map(\.title), quarterEnd: quarterEnd) }
    private var classifier: VoiceIntentClassifier { VoiceIntentClassifier(quarterEnd: quarterEnd) }

    /// "The rest of the quarter" ends when the class schedule does: the last day
    /// of the latest event in a calendar named like "FA26 Schedule". With no such
    /// calendar it isn't known, and the app asks for an end date instead of guessing.
    private var quarterEnd: Date? {
        let schedules = eventStore.calendars.filter { $0.title.localizedCaseInsensitiveContains("schedule") }
        guard !schedules.isEmpty else { return nil }
        let now = Date.now
        let horizon = Calendar.current.date(byAdding: .day, value: 250, to: now) ?? now
        let ends = eventStore.events(from: now, to: horizon, in: schedules).map { $0.endDate as Date }
        return ends.max().map { Calendar.current.startOfDay(for: $0.addingTimeInterval(-1)) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                ScrollView {
                    VStack(spacing: 16) {
                        if emailRequest != nil { emailCard }
                        else if moveRequest != nil { moveCard }
                        else if deleteQuery != nil { deleteCard }
                        else if drafts.count > 1 { draftPager }
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
                ToolbarItem(placement: .cancellationAction) { Button("Close") { speech.cancel(); close() } }
            }
        }
        #if !targetEnvironment(macCatalyst)
        // Phone: compact by default, with the calendar still usable behind it. Sheet-only
        // modifiers -- on the Mac this view is inside a popover, and applying them there
        // makes UIKit trap while presenting it (the app quit on pressing the mic).
        .presentationDetents([.height(Self.panelHeight), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(Self.panelHeight)))
        .presentationDragIndicator(.visible)
        #endif
        .task {
            contextEvent = selectedEvent
            speech.contextualStrings = writableCalendars.map(\.title) + locationOverrides.map(\.locationText)
            speech.onFinished = { heard in handle(heard) }
            await speech.requestAccess()
            if speech.access == .granted { speech.start() }
        }
        .onDisappear { speech.cancel(); emailTask?.cancel() }
        .sheet(isPresented: $showingGmailConnection, onDismiss: {
            gmailOAuth = GoogleOAuthService.shared
            if let request = emailRequest, gmailOAuth.isSignedIn { startEmailLookup(request) }
        }) { GmailImportView() }
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
                    Text(deleteIsMass ? "Say “delete them”, or tap Delete below." : "Say “delete it”, or tap Delete below.")
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
            Text("“Add study session every Friday at 4 pm for the rest of the quarter.”")
                .font(.footnote).foregroundStyle(.secondary)
            Text("“Add the event from the email from my dentist about my appointment.”")
                .font(.footnote).foregroundStyle(.secondary)
            Text("“Duplicate the Speak Up meeting every Thursday for the rest of the quarter.”")
                .font(.footnote).foregroundStyle(.secondary)
            Text("“Delete pickleball practice on Thursday” or “delete all pickleball practice.”")
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

    private var emailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event from email").font(.headline)
            if emailLoading {
                ProgressView("Looking for matching emails…")
            } else if !emailDateChoices.isEmpty {
                Text("Which date in this email? Say first, second, or tap a date.")
                    .font(.subheadline)
                ForEach(Array(emailDateChoices.enumerated()), id: \.offset) { index, choice in
                    Button {
                        acceptEmailDraft(choice)
                    } label: {
                        Text("\(index + 1). \(choice.start?.formatted(date: .abbreviated, time: choice.timeKnown ? .shortened : .omitted) ?? "Date missing")")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                if !emailMatches.isEmpty {
                    Text("Which email? Say first, second, or tap one.").font(.subheadline)
                    ForEach(Array(emailMatches.enumerated()), id: \.element.id) { index, message in
                        Button { chooseEmail(message) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(index + 1). \(message.subject)").font(.subheadline.weight(.medium))
                                Text(message.from).font(.caption).foregroundStyle(.secondary)
                                if let inbox = message.accountEmail {
                                    Text("Inbox: \(inbox)").font(.caption).foregroundStyle(.secondary)
                                }
                                if let date = message.internalDate {
                                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text(emailRequest?.searchQuery == nil
                         ? "Say who sent the email or words from its subject, or paste the email below."
                         : "Connect Gmail to search this email, or paste its text below.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Connect Gmail") { showingGmailConnection = true }
                        .buttonStyle(.bordered)
                }
                Text("Or paste an email").font(.subheadline.weight(.semibold))
                TextEditor(text: $pastedEmail)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                    .accessibilityLabel("Email text")
                Button("Use Email Text") {
                    let text = pastedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    let first = text.components(separatedBy: .newlines).first ?? "Event from email"
                    chooseEmail(GmailMessageDetail(id: "pasted", subject: String(first.prefix(160)), from: "Pasted email", snippet: "", bodyText: text, internalDate: nil))
                }
                .buttonStyle(.borderedProminent)
                .disabled(pastedEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button("Cancel") { reset() }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clearEmailLookup() {
        emailTask?.cancel()
        emailTask = nil
        emailRequest = nil
        emailMatches = []
        emailDateChoices = []
        emailLoading = false
        pastedEmail = ""
    }

    private func startEmailLookup(_ request: VoiceEmailRequest) {
        emailTask?.cancel()
        guard let query = request.searchQuery else { return }
        guard GoogleOAuthConfig.isConfigured, gmailOAuth.isSignedIn else { return }
        emailLoading = true
        emailTask = Task {
            defer { if !Task.isCancelled { emailLoading = false } }
            do {
                let result = try await VoiceEmailLookup.findAcrossInboxes(query: query, oauth: gmailOAuth)
                let messages = result.messages
                try Task.checkCancellation()
                guard emailRequest == request else { return }
                emailMatches = messages
                if messages.count == 1, let message = messages.first { chooseEmail(message) }
                else if messages.isEmpty { errorMessage = "No matching emails found. Try another sender or subject, or paste the email." }
                if !result.failedAccounts.isEmpty {
                    errorMessage = "Couldn't search: \(result.failedAccounts.joined(separator: ", ")). Reconnect those accounts in Gmail settings."
                }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
    }

    private func chooseEmail(_ message: GmailMessageDetail) {
        let choices = VoiceEmailDrafts.extract(from: message)
        copyNote = "From email: “\(message.subject)” · \(message.from)" + (message.accountEmail.map { " · \($0)" } ?? "")
        if choices.count == 1, let choice = choices.first { acceptEmailDraft(choice) }
        else { emailDateChoices = choices }
    }

    private func acceptEmailDraft(_ choice: EventDraft) {
        clearEmailLookup()
        draft = choice
        if let start = choice.start { onFocusDate(start) }
    }

    @ViewBuilder
    private func summary(for draft: EventDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !lastHeard.isEmpty && drafts.count <= 1 {
                Text("I heard: “\(lastHeard)”").font(.footnote).foregroundStyle(.secondary)
            }
            if let copyNote {
                Label(copyNote, systemImage: "doc.on.doc").font(.footnote.weight(.medium))
            }

            VStack(alignment: .leading, spacing: 10) {
                row("Event", draft.title.isEmpty ? nil : draft.title, missing: "Say a title")
                row("Day", draft.start.map { DateMath.fullDateFormatter.string(from: $0) }, missing: "Say a day")
                row("Time", timeText(for: draft), missing: "Say a time")
                categoryRow(for: draft)
                row("Location", draft.location, missing: "None", optional: true)
                row("Reminder", reminderText(for: draft), missing: "Default (15 min before)", optional: true)
                // Notes only appear when copied from another event -- shown so they aren't carried along unseen.
                if let notes = draft.notes, !notes.isEmpty { row("Notes", notes, missing: "") }
                if !draft.extraDays.isEmpty {
                    row("Also on", draft.extraDays.sorted().map { DateMath.monthDayFormatter.string(from: $0) }.joined(separator: " · "), missing: "")
                }
                if let rule = draft.repeatRule {
                    row("Repeats", repeatText(for: draft, rule: rule), missing: "Say how long")
                    let plan = datesToCreate(draft)
                    let dates = plan.dates
                    if plan.alreadyThere > 0 {
                        Text(dates.isEmpty ? "Every one of these dates already has this event."
                                           : "\(plan.alreadyThere) of these dates already have this event and will be skipped.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if !dates.isEmpty {
                        DisclosureGroup("See the \(dates.count) dates") {
                            Text(dates.map { DateMath.monthDayFormatter.string(from: $0) }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.subheadline)
                        if dates.count >= RepeatRule.maxEvents {
                            Text("Limited to \(RepeatRule.maxEvents) events at a time.").font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))

            if !draft.gaps.isEmpty {
                Label("Still needed: " + draft.gaps.map(\.rawValue).joined(separator: ", ") + ". Say it, or edit by hand.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button(action: { create(draft) }) {
                Label(addButtonTitle(for: draft), systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.ultramarine)
            .disabled(!draft.isComplete || (draft.repeatRule != nil && datesToCreate(draft).dates.isEmpty))

            HStack(spacing: 12) {
                Button {
                    speech.cancel()
                    onEditManually(draft)
                    close()
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

    // MARK: Swipeable pages

    /// Pages you swipe between, with dots underneath. Plain scroll-snapping (not the
    /// page-style TabView), so it behaves the same on the phone and the Mac.
    private func pager<Content: View>(count: Int, @ViewBuilder content: @escaping (Int) -> Content) -> some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(0..<count, id: \.self) { index in
                        content(index)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pageID)
            .scrollIndicators(.hidden)

            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { index in
                    Circle().fill(index == page ? Color.primary : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                }
                Text("\(page + 1) of \(count)").font(.caption).foregroundStyle(.secondary).padding(.leading, 6)
            }
        }
    }

    private var draftPager: some View {
        VStack(spacing: 12) {
            if !lastHeard.isEmpty {
                Text("I heard: “\(lastHeard)”").font(.footnote).foregroundStyle(.secondary)
            }
            Text("\(drafts.count) events — swipe to review each").font(.headline)
            pager(count: drafts.count) { index in
                if drafts.indices.contains(index) { summary(for: drafts[index]) }
            }
            let ready = drafts.filter { $0.isComplete }.count
            Button(action: { addAll() }) {
                Label("Add All \(drafts.count) Events", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.ultramarine)
            .disabled(ready != drafts.count)
            if ready != drafts.count {
                Text("\(drafts.count - ready) still need details — swipe to them, or say what's missing.").font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    private func addAll() {
        let all = drafts
        for item in all where item.isComplete { create(item) }
    }

    private func categoryRow(for draft: EventDraft) -> some View {
        let calendar = targetCalendar(for: draft)
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
                Label(errorMessage ?? "I couldn't find an event matching that. Try the event's name, and a day if there are several.", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else if deleteIsMass {
                let events = deleteCandidates
                Text("Delete \(events.count) events?").font(.headline)
                if deleteMulti {
                    Text("Matched by name. Nothing is deleted until you confirm.").font(.footnote).foregroundStyle(.secondary)
                } else if let first = events.first, let last = events.last {
                    Text("Upcoming, \(DateMath.monthDayFormatter.string(from: first.startDate)) – \(DateMath.monthDayFormatter.string(from: last.startDate)). Past events are never included.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if deleteMulti && events.count <= 8 {
                    pager(count: events.count) { index in
                        if events.indices.contains(index) {
                            let event = events[index]
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppTheme.calendarColor(for: event.calendar))
                                    .frame(width: 4, height: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title ?? "Untitled").font(.body.weight(.medium))
                                    Text(whenText(for: event)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button(role: .destructive) { delete(event) } label: { Label("Delete", systemImage: "trash") }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                            .onTapGesture { onFocusDate(event.startDate) }
                        }
                    }
                } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events.prefix(6), id: \.eventIdentifier) { event in
                        HStack(spacing: 8) {
                            Circle().fill(AppTheme.calendarColor(for: event.calendar)).frame(width: 8, height: 8)
                            Text("\(event.title ?? "Untitled") · \(whenText(for: event))").font(.footnote).lineLimit(1)
                        }
                    }
                    if events.count > 6 {
                        Text("…and \(events.count - 6) more").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                }
                Button(role: .destructive) { confirmingMassDelete = true } label: {
                    Label("Delete \(events.count) Events", systemImage: "trash").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .confirmationDialog("Delete \(events.count) events?", isPresented: $confirmingMassDelete, titleVisibility: .visible) {
                    Button("Delete \(events.count) Events", role: .destructive) { deleteAll() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You can undo this right after.")
                }
                if !deleteMissing.isEmpty {
                    Label("Couldn't find: " + deleteMissing.joined(separator: ", "), systemImage: "magnifyingglass").font(.footnote).foregroundStyle(.orange)
                }
                Text(events.count <= Self.voiceDeleteLimit ? "Or say “delete them”." : "That's a lot — confirm by tapping.")
                    .font(.footnote).foregroundStyle(.secondary)
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

    // MARK: Move card

    private var moveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !lastHeard.isEmpty {
                Text("I heard: “\(lastHeard)”").font(.footnote).foregroundStyle(.secondary)
            }
            if moveItems.isEmpty {
                Label(errorMessage ?? "I couldn't find that event. Say its name, like “move the dentist one day forward”, or open it first and say “move this event ...”.", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                Text(moveMulti ? "Move \(moveItems.count) events?" : (moveItems.count == 1 ? "Move this event?" : "Which one should I move?")).font(.headline)
                if moveMulti {
                    pager(count: moveItems.count) { index in
                        if moveItems.indices.contains(index) { moveItemCard(moveItems[index]) }
                    }
                } else {
                    ForEach(moveItems) { moveItemCard($0) }
                }
                if !moveMissing.isEmpty {
                    Label("Couldn't find: " + moveMissing.joined(separator: ", "), systemImage: "magnifyingglass").font(.footnote).foregroundStyle(.orange)
                }
                if moveMulti {
                    Button { moveAll() } label: { Label("Move \(moveItems.count) Events", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.borderedProminent)
                    Text("Or say “yes”. You can undo this right after.").font(.footnote).foregroundStyle(.secondary)
                } else if moveItems.count == 1 {
                    Text("Say “yes” to move it, or give another amount. You can undo this right after.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Or say the day, like “move it on Thursday ...”.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button("Not now") { reset() }.buttonStyle(.bordered)
        }
    }

    private func moveItemCard(_ item: MoveItem) -> some View {
        let new = newTimes(for: item.event, request: item.request)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppTheme.calendarColor(for: item.event.calendar))
                .frame(width: 4, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.event.title ?? "Untitled").font(.body.weight(.medium))
                Text(whenText(for: item.event)).font(.caption).foregroundStyle(.secondary).strikethrough()
                if let new { Text(whenText(start: new.start, end: new.end, allDay: item.event.isAllDay)).font(.caption.weight(.semibold)) }
            }
            Spacer(minLength: 0)
            Button { if let new { move([(item.event, new)]) } } label: { Label("Move", systemImage: "arrow.right") }
                .buttonStyle(.borderedProminent)
                .disabled(new == nil)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
        .onTapGesture { onFocusDate(item.event.startDate) }
    }

    private func whenText(start: Date, end: Date, allDay: Bool) -> String {
        let day = DateMath.fullDateFormatter.string(from: start)
        if allDay { return "→ \(day) · All-day" }
        return "→ \(day) · \(DateMath.timeFormatter.string(from: start)) – \(DateMath.timeFormatter.string(from: end))"
    }

    private func whenTimes(_ event: EKEvent) -> String {
        event.isAllDay ? "all-day" : "\(DateMath.timeFormatter.string(from: event.startDate)) – \(DateMath.timeFormatter.string(from: event.endDate))"
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

    /// The dates that will actually be created: a repeat never adds an event that
    /// is already there (same title, same start), so copying over a stretch that is
    /// partly filled in doesn't double anything up.
    private func datesToCreate(_ draft: EventDraft) -> (dates: [Date], alreadyThere: Int) {
        let all = draft.occurrences()
        guard draft.repeatRule != nil, let first = all.first, let last = all.last else { return (all, 0) }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? last
        let existing = eventStore.events(from: calendar.startOfDay(for: first), to: end, in: writableCalendars)
        let keys = Set(existing.map { "\(($0.title ?? "").lowercased())|\(Int($0.startDate.timeIntervalSince1970))" })
        let title = draft.title.lowercased()
        let fresh = all.filter { !keys.contains("\(title)|\(Int($0.timeIntervalSince1970))") }
        return (fresh, all.count - fresh.count)
    }

    private func addButtonTitle(for draft: EventDraft) -> String {
        guard draft.repeatRule != nil else {
            let n = draft.occurrences().count
            return n > 1 ? "Add \(n) Events" : "Add to Calendar"
        }
        let count = datesToCreate(draft).dates.count
        return count == 1 ? "Add 1 Event" : "Add \(count) Events"
    }

    private func repeatText(for draft: EventDraft, rule: RepeatRule) -> String? {
        guard rule.until != nil || rule.count != nil else { return nil }
        let symbols = Calendar.current.weekdaySymbols
        let days: String
        if rule.everyDay { days = "Every day" }
        else if rule.weekdays == [2, 3, 4, 5, 6] { days = "Every weekday" }
        else if rule.weekdays.isEmpty, let start = draft.start { days = "Every " + symbols[Calendar.current.component(.weekday, from: start) - 1] }
        else { days = "Every " + rule.weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ") }
        let skipped = draft.skipDates.isEmpty ? "" : " (skipping " + draft.skipDates.map { DateMath.monthDayFormatter.string(from: $0) }.joined(separator: ", ") + ")"
        if let until = rule.until { return "\(days), through \(DateMath.monthDayFormatter.string(from: until))\(skipped)" }
        return "\(days), \(rule.count ?? 0) times\(skipped)"
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
        clearEmailLookup()
        draft = nil
        deleteQuery = nil
        deleteCandidates = []
        deleteIsMass = false
        copyNote = nil
        moveRequest = nil
        moveItems = []; moveMulti = false; moveMissing = []
        deleteMulti = false; deleteMissing = []
        lastHeard = ""
        errorMessage = nil
    }

    /// One path for spoken and typed sentences alike.
    private func handle(_ heard: String) {
        lastHeard = heard
        errorMessage = nil
        let intent = classifier.classify(heard)
        if emailRequest != nil, let index = VoiceEmailRequest.selectionIndex(from: heard) {
            if !emailDateChoices.isEmpty {
                if emailDateChoices.indices.contains(index) { acceptEmailDraft(emailDateChoices[index]) }
                else { errorMessage = "Choose one of the dates shown." }
            } else if emailMatches.indices.contains(index) { chooseEmail(emailMatches[index]) }
            else { errorMessage = "Choose one of the emails shown." }
            return
        }
        if emailRequest != nil, intent == .confirm {
            errorMessage = "Choose the email or date first, then review its event before adding it."
            return
        }
        switch intent {
        case .email(let request):
            reset()
            lastHeard = heard
            emailRequest = request
            startEmailLookup(request)
        case .confirm:
            if moveRequest != nil {
                // Moving is undoable, so a plain "yes" is enough -- but only for a single match.
                if moveMulti { moveAll() }
                else if moveItems.count == 1, let item = moveItems.first, let new = newTimes(for: item.event, request: item.request) { move([(item.event, new)]) }
                else if moveItems.count > 1 { errorMessage = "More than one event matches — tap the one to move." }
            } else if deleteQuery != nil {
                // A generic "yes"/"ok" is not enough to delete something.
                errorMessage = "To delete it, say “delete it” or tap Delete."
            } else if drafts.count > 1 {
                if drafts.allSatisfy(\.isComplete) { addAll() } else { errorMessage = "Some events still need details." }
            } else if let draft, draft.isComplete { create(draft) }
        case .confirmDelete:
            if deleteQuery != nil, deleteIsMass {
                if deleteCandidates.count <= Self.voiceDeleteLimit { deleteAll() }
                else { errorMessage = "That's \(deleteCandidates.count) events — tap “Delete \(deleteCandidates.count) Events” to confirm." }
            } else if deleteQuery != nil, deleteCandidates.count == 1, let event = deleteCandidates.first { delete(event) }
            else if deleteQuery != nil, deleteCandidates.count > 1 { errorMessage = "More than one event matches — tap the one to delete." }
        case .cancel:
            if emailRequest != nil || draft != nil || deleteQuery != nil || moveRequest != nil { reset() } else { speech.cancel(); close() }
        case .move(let request):
            clearEmailLookup()
            // With a draft on screen, "move it to Friday" is a correction to the draft.
            if var current = draft, let start = current.start {
                if let shifted = request.shifted(start) {
                    let length = current.end.map { $0.timeIntervalSince(start) } ?? 3600
                    current.start = shifted
                    current.end = shifted.addingTimeInterval(length)
                    draft = current
                    onFocusDate(shifted)
                } else {
                    draft = parser.parse(heard, applying: draft)
                    if let start = draft?.start { onFocusDate(start) }
                }
                return
            }
            deleteQuery = nil; deleteCandidates = []; deleteIsMass = false; copyNote = nil
            moveRequest = request
            moveItems = []; moveMulti = false; moveMissing = []
            func events(for r: VoiceMoveRequest, fuzzy: Bool) -> [EKEvent] {
                if r.source != nil { return eventsOnSourceDay(for: r) }
                if r.useSelected { return contextEvent.map { [$0] } ?? eventsOnFocusDay() }
                return findEvents(for: r.target, fuzzy: fuzzy)
            }
            let single = events(for: request, fuzzy: request.parts.count < 2)
            if single.isEmpty, request.parts.count >= 2 {
                // Several events named in one sentence: the best match for each.
                moveMulti = true
                var seen = Set<String>()
                for part in request.parts {
                    if let event = events(for: part, fuzzy: true).first {
                        let key = (event.eventIdentifier ?? "") + "\(event.startDate.timeIntervalSince1970)"
                        if seen.insert(key).inserted { moveItems.append(MoveItem(event: event, request: part)) }
                    } else {
                        moveMissing.append(part.useSelected ? "this event" : part.target.titleWords.joined(separator: " "))
                    }
                }
                if moveItems.isEmpty { moveMulti = false }
            } else {
                moveItems = single.prefix(5).map { MoveItem(event: $0, request: request) }
                if request.useSelected && contextEvent == nil {
                    errorMessage = single.isEmpty ? "No event on that day — say the event's name." : nil
                }
            }
            if let first = moveItems.first { onFocusDate(first.event.startDate) }
        case .delete(let request):
            clearEmailLookup()
            draft = nil
            moveRequest = nil; moveItems = []
            deleteQuery = heard
            deleteIsMass = request.isAll
            deleteMulti = false; deleteMissing = []
            // With several names in the sentence the whole phrase must match exactly, or it's split.
            deleteCandidates = findEvents(for: request, fuzzy: request.splitParts.count < 2)
            if deleteCandidates.isEmpty, request.splitParts.count >= 2 {
                // "Delete A and B": the best match for each name, all shown before anything goes.
                var seen = Set<String>()
                var found: [EKEvent] = []
                for part in request.splitParts {
                    let hits = findEvents(for: part, fuzzy: true)
                    let chosen = part.isAll ? hits : Array(hits.prefix(1))
                    if chosen.isEmpty { deleteMissing.append(part.titleWords.joined(separator: " ")) }
                    for event in chosen where seen.insert((event.eventIdentifier ?? "") + "\(event.startDate.timeIntervalSince1970)").inserted { found.append(event) }
                }
                deleteCandidates = found.sorted { $0.startDate < $1.startDate }
                deleteIsMass = true
                deleteMulti = true
            }
            if request.rangeUnresolved { errorMessage = "I don't know when the quarter ends. Say an end date instead, like “until December 4th”." }
            else if request.titleWords.isEmpty { errorMessage = "Say which event to delete, by name." }
            if let first = deleteCandidates.first { onFocusDate(first.startDate) }
        case .duplicate(let rest):
            clearEmailLookup()
            deleteQuery = nil; deleteCandidates = []; deleteIsMass = false
            moveRequest = nil; moveItems = []
            let words = parser.duplicateTitleWords(from: rest)
            guard !words.isEmpty, let source = findEvents(for: VoiceDeleteRequest(titleWords: words), fuzzy: true).first else {
                draft = nil; copyNote = nil
                errorMessage = "I couldn't find an event to copy. Say its name, like “duplicate the Speak Up meeting every Thursday for the rest of the quarter”."
                return
            }
            let location = EventLocationAccess.displayLocation(for: source, in: locationOverrides)?.text ?? source.location
            let copy = DuplicateSource(
                title: source.title ?? "", start: source.startDate, end: source.endDate, isAllDay: source.isAllDay,
                calendarTitle: source.calendar?.title, calendarIdentifier: source.calendar?.calendarIdentifier,
                location: location, notes: source.notes
            )
            draft = parser.duplicate(copy, saying: rest)
            copyNote = "Copying “\(copy.title)” (\(DateMath.monthDayFormatter.string(from: copy.start)), \(whenTimes(source)))"
            if let start = draft?.start { onFocusDate(start) }
        case .describeEvent:
            clearEmailLookup()
            copyNote = nil
            moveRequest = nil; moveItems = []
            // A new description while a delete was pending abandons it.
            if deleteQuery != nil { deleteQuery = nil; deleteCandidates = []; deleteIsMass = false }
            if drafts.isEmpty, let many = parser.parseMany(heard) {
                drafts = many
                pageID = 0
                if let start = many.first?.start { onFocusDate(start) }
                return
            }
            draft = parser.parse(heard, applying: draft)
            if let start = draft?.start { onFocusDate(start) }
        }
    }

    private func findEvents(for request: VoiceDeleteRequest, fuzzy: Bool = true) -> [EKEvent] {
        let now = Date.now
        let from = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let to = Calendar.current.date(byAdding: .day, value: 365, to: now) ?? now
        let events = eventStore.events(from: from, to: to, in: writableCalendars)
        let refs = events.enumerated().map { EventRef(id: String($0.offset), title: $0.element.title ?? "", start: $0.element.startDate) }
        return VoiceDeleteMatcher.matches(request, in: refs, now: now, fuzzy: fuzzy).compactMap { Int($0.id).map { events[$0] } }
    }

    /// "This event" with nothing open: whatever is on the day the calendar is showing.
    private func eventsOnFocusDay() -> [EKEvent] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: focusDate)
        let end = cal.date(byAdding: .day, value: 1, to: day) ?? day
        return Array(eventStore.events(from: day, to: end, in: writableCalendars).prefix(5))
    }

    /// "Move the event from the 21st to the 20th": the events on the source day, in
    /// the month the calendar is showing, narrowed by any name that was said.
    private func eventsOnSourceDay(for request: VoiceMoveRequest) -> [EKEvent] {
        let cal = Calendar.current
        guard let source = request.source,
              let monthStart = cal.dateInterval(of: .month, for: focusDate)?.start,
              let day = SpokenDateResolver().day(in: source, now: monthStart) else { return [] }
        let end = cal.date(byAdding: .day, value: 1, to: day) ?? day
        let onDay = eventStore.events(from: day, to: end, in: writableCalendars)
        guard !request.target.titleWords.isEmpty else { return Array(onDay.prefix(5)) }
        let refs = onDay.enumerated().map { EventRef(id: String($0.offset), title: $0.element.title ?? "", start: $0.element.startDate) }
        let hits = VoiceDeleteMatcher.matches(VoiceDeleteRequest(titleWords: request.target.titleWords), in: refs, now: day, fuzzy: true)
        return hits.compactMap { Int($0.id).map { onDay[$0] } }
    }

    /// Where an event would land under a move request.
    private func newTimes(for event: EKEvent, request: VoiceMoveRequest) -> (start: Date, end: Date)? {
        let cal = Calendar.current
        if request.isRelative {
            guard let start = request.shifted(event.startDate), let end = request.shifted(event.endDate) else { return nil }
            return (start, end)
        }
        guard let destination = request.destination else { return nil }
        // "to the 20th": that day of the event's own month, same time.
        if let g = destination.range(of: #"^(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)$"#, options: .regularExpression),
           let number = Int(destination[g].filter(\.isNumber)) {
            var parts = cal.dateComponents([.year, .month, .hour, .minute], from: event.startDate)
            parts.day = number
            guard let start = cal.date(from: parts), cal.component(.day, from: start) == number else { return nil }
            return (start, start.addingTimeInterval(event.endDate.timeIntervalSince(event.startDate)))
        }
        var current = EventDraft()
        current.title = event.title ?? ""
        current.start = event.startDate
        current.end = event.endDate
        current.isAllDay = event.isAllDay
        current.timeKnown = true
        let moved = parser.parse(destination, applying: current)
        guard let start = moved.start, let end = moved.end else { return nil }
        if event.isAllDay { return (cal.startOfDay(for: start), cal.startOfDay(for: start).addingTimeInterval(event.endDate.timeIntervalSince(event.startDate))) }
        return (start, end)
    }

    private func moveAll() {
        let plan = moveItems.compactMap { item in newTimes(for: item.event, request: item.request).map { (item.event, $0) } }
        move(plan)
    }

    /// Applies moves as one undoable step.
    private func move(_ plan: [(EKEvent, (start: Date, end: Date))]) {
        guard !plan.isEmpty else { return }
        struct Old { let id: String?; let start: Date; let end: Date }
        var olds: [Old] = []
        var failed = 0
        for (event, new) in plan {
            let old = Old(id: event.eventIdentifier, start: event.startDate, end: event.endDate)
            event.startDate = new.start
            event.endDate = new.end
            do { try eventStore.update(event); olds.append(old) } catch {
                event.startDate = old.start; event.endDate = old.end
                failed += 1; errorMessage = error.localizedDescription
            }
        }
        guard !olds.isEmpty else { return }
        undoManager.register(message: olds.count == 1 ? "Event Moved" : "\(olds.count) Events Moved") {
            for old in olds {
                if let e = old.id.flatMap({ eventStore.event(withIdentifier: $0) }) {
                    e.startDate = old.start; e.endDate = old.end
                    try? eventStore.update(e)
                }
            }
        }
        if failed > 0 { return }
        if let first = plan.first { onFocusDate(first.1.start) }
        if moveMulti {
            let moved = Set(plan.map { $0.0.eventIdentifier })
            moveItems.removeAll { moved.contains($0.event.eventIdentifier) }
            pageID = min(page, max(moveItems.count - 1, 0))
            if !moveItems.isEmpty { return }
        }
        speech.cancel()
        close()
    }

    private func delete(_ event: EKEvent) {
        eventStore.deleteWithUndo(event, undoManager: undoManager)
        deleteCandidates.removeAll { $0.eventIdentifier == event.eventIdentifier }
        if deleteCandidates.isEmpty {
            speech.cancel()
            close()
        }
    }

    private func deleteAll() {
        let events = deleteCandidates
        guard !events.isEmpty else { return }
        let snapshots = events.map { EventSnapshot(event: $0) }
        var failed = 0
        for event in events { do { try eventStore.delete(event) } catch { failed += 1 } }
        undoManager.register(message: "\(events.count - failed) Events Deleted") {
            for snapshot in snapshots { snapshot.recreate(in: eventStore) }
        }
        if failed > 0 { errorMessage = "\(failed) couldn't be deleted." }
        speech.cancel()
        close()
    }

    private func create(_ draft: EventDraft) {
        guard let start = draft.start else { return }
        let calendar = targetCalendar(for: draft)
            ?? eventStore.store.defaultCalendarForNewEvents
            ?? writableCalendars.first
        guard let calendar else { errorMessage = "No calendar to add this to."; return }
        let length = draft.end.map { $0.timeIntervalSince(start) } ?? 3600
        let starts = draft.repeatRule != nil ? datesToCreate(draft).dates : draft.occurrences()
        guard !starts.isEmpty else { errorMessage = "No dates to add."; return }
        do {
            var created: [EKEvent] = []
            for occurrence in starts {
                let end = draft.isAllDay
                    ? (Calendar.current.date(byAdding: .day, value: 1, to: occurrence) ?? occurrence.addingTimeInterval(86_400))
                    : occurrence.addingTimeInterval(length)
                let event = try eventStore.createEvent(
                    title: draft.title,
                    startDate: occurrence,
                    endDate: end,
                    isAllDay: draft.isAllDay,
                    calendar: calendar,
                    location: draft.location,
                    notes: draft.notes
                )
                created.append(event)
                if let minutes = draft.reminderMinutes {
                    EventReminderAccess.setReminder(minutes == 0 ? nil : minutes, for: event, in: reminderRows, context: modelContext)
                }
            }
            AppPreferencesAccess.reveal(calendar, rows: preferencesRows, in: modelContext)
            if let location = draft.location, !location.isEmpty {
                EventLocationAccess.setLocation(location, coordinate: nil, title: draft.title, rows: locationOverrides, context: modelContext)
            }
            let identifiers = created.compactMap(\.eventIdentifier)
            undoManager.register(message: created.count == 1 ? "Event Added" : "\(created.count) Events Added") {
                for identifier in identifiers {
                    if let event = eventStore.event(withIdentifier: identifier) { try? eventStore.delete(event) }
                }
            }
            onFocusDate(start)
            if let index = drafts.firstIndex(of: draft) { drafts.remove(at: index) }
            pageID = min(page, max(drafts.count - 1, 0))
            if drafts.isEmpty {
                speech.cancel()
                close()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
