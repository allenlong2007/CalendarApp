import EventKit
import SwiftData
import SwiftUI

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case month = "Month"
    case week = "Week"
    case day = "Day"
    case agenda = "Agenda"
    var id: String { rawValue }
}

struct CalendarRootView: View {
    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferencesRows: [AppPreferences]
    @Query private var completionRows: [EventCompletionStatus]
    @Query private var reminderRows: [EventReminderPreference]

    @State private var viewMode: CalendarViewMode = .month
    @State private var referenceDate = Date.now
    @State private var selectedDate = Date.now
    @State private var showingCalendarList = false
    @State private var eventEditorContext: EventEditorContext?
    @State private var showingQuickAdd = false
    /// Wide (Mac/iPad) layout only: the event a single-click on Month/Day
    /// most recently previewed, shown in the sidebar until the user picks a
    /// different day or event.
    @State private var previewEvent: EKEvent?
    /// Bumped to make the wide Month view jump to the current reference.
    @State private var monthJump = 0
    /// The reference date last set by scrolling, so a change to it that did NOT
    /// come from scrolling (the mini calendar's arrows) can be told apart.
    @State private var scrollReportedReference: Date?
    /// What "today" was last time we looked, to notice a new day (and week) starting.
    @State private var lastKnownToday = DateMath.startOfDay(.now)

    private var preferences: AppPreferences { AppPreferencesAccess.ensure(preferencesRows, in: modelContext) }
    private var hiddenCalendarIdentifiers: Set<String> { Set(preferences.hiddenCalendarIdentifiers) }
    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            Group {
                if eventStore.accessStatus != .fullAccess {
                    EventKitAccessGateView()
                } else if isWideLayout {
                    HStack(spacing: 0) {
                        calendarContent
                        Divider()
                        CalendarSidebarView(
                            referenceDate: $referenceDate,
                            selectedDate: selectedDate,
                            weekStartDay: preferences.weekStartDay,
                            hiddenCalendarIdentifiers: hiddenCalendarIdentifiers,
                            previewEvent: previewEvent,
                            onSelectDay: { day in
                                selectDay(day)
                                monthJump += 1
                            },
                            onEditEvent: { eventEditorContext = .edit($0) },
                            onAddEvent: { eventEditorContext = .new(defaultDate: $0) },
                            onToggleComplete: { EventCompletionAccess.toggle($0, in: completionRows, context: modelContext) },
                            onDelete: { eventStore.deleteWithUndo($0, undoManager: undoManager) }
                        )
                    }
                } else {
                    calendarContent
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingCalendarList = true
                    } label: {
                        Image(systemName: "calendar.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingQuickAdd = true
                    } label: {
                        Image(systemName: "bolt.fill")
                    }
                    .help("Quick Add from Template")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            eventEditorContext = .new(defaultDate: defaultNewEventDate)
                        } label: {
                            Label("New Event", systemImage: "calendar.badge.plus")
                        }
                        Button {
                            showingQuickAdd = true
                        } label: {
                            Label("Quick Add from Template", systemImage: "bolt.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                    } primaryAction: {
                        eventEditorContext = .new(defaultDate: defaultNewEventDate)
                    }
                }
            }
        }
        .task {
            if eventStore.accessStatus == .notDetermined {
                await eventStore.requestAccess()
            }
            await ReminderScheduler.requestAuthorization()
            await refreshReminders()
            mirrorLocationsFromEventKit()
        }
        .onChange(of: eventStore.externalChangeToken) {
            Task { await refreshReminders() }
            mirrorLocationsFromEventKit()
            Task { await sync.syncNow() }
        }
        .onChange(of: viewMode) { previewEvent = nil }
        .onChange(of: referenceDate) {
            if referenceDate != scrollReportedReference { monthJump += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in rollOverIfNewDay() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { rollOverIfNewDay() } }
        .sheet(isPresented: $showingCalendarList) {
            CalendarListSidebarView()
        }
        .sheet(item: $eventEditorContext) { context in
            EventEditorView(context: context)
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddTemplatesView(targetDate: defaultNewEventDate)
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        VStack(spacing: 0) {
            modeSwitcher
            Divider()
            switch viewMode {
            case .month:
                MonthView(
                    referenceDate: referenceDate,
                    selectedDate: selectedDate,
                    weekStartDay: preferences.weekStartDay,
                    hiddenCalendarIdentifiers: hiddenCalendarIdentifiers,
                    jumpToken: monthJump,
                    onSelectDay: selectDay,
                    onSelectEvent: { eventEditorContext = .edit($0) },
                    onAddEvent: { eventEditorContext = .new(defaultDate: $0) },
                    onPreviewEvent: { previewEvent = $0 },
                    onVisibleDateChange: { date in
                        // Scrolling moves the title/mini calendar to the month on
                        // screen; it must not trigger a jump back (see monthJump).
                        if !DateMath.isSameMonth(date, referenceDate) {
                            scrollReportedReference = date
                            referenceDate = date
                        }
                    }
                )
            case .week:
                WeekView(
                    referenceDate: referenceDate,
                    selectedDate: $selectedDate,
                    weekStartDay: preferences.weekStartDay,
                    hiddenCalendarIdentifiers: hiddenCalendarIdentifiers,
                    onSelectEvent: { eventEditorContext = .edit($0) },
                    onCreateEvent: { eventEditorContext = .new(defaultDate: $0) }
                )
            case .day:
                DayView(
                    date: selectedDate,
                    hiddenCalendarIdentifiers: hiddenCalendarIdentifiers,
                    onSelectEvent: { eventEditorContext = .edit($0) },
                    onCreateEvent: { eventEditorContext = .new(defaultDate: $0) },
                    // Wide layout only -- a single tap with no sidebar to show
                    // the preview in (narrow/iPhone) used to silently do
                    // nothing, since onSelectEvent only fired on the much
                    // less discoverable double-tap in that case.
                    onPreviewEvent: isWideLayout ? { previewEvent = $0 } : nil
                )
            case .agenda:
                AgendaView(
                    hiddenCalendarIdentifiers: hiddenCalendarIdentifiers,
                    onSelectEvent: { eventEditorContext = .edit($0) }
                )
            }
        }
    }

    private var modeSwitcher: some View {
        VStack(spacing: 8) {
            Picker("View", selection: $viewMode) {
                ForEach(CalendarViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if viewMode != .agenda {
                HStack {
                    Button("Today") { goToToday() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    private var title: String {
        switch viewMode {
        case .month, .week:
            return DateMath.monthYearFormatter.string(from: referenceDate)
        case .day:
            return DateMath.fullDateFormatter.string(from: selectedDate)
        case .agenda:
            return "Agenda"
        }
    }

    private var defaultNewEventDate: Date {
        switch viewMode {
        case .day: return selectedDate
        default: return selectedDate
        }
    }

    /// The single path for "the user picked a day" -- used by the Month
    /// grid and the sidebar's mini calendar. Always clears any event
    /// preview, even when re-tapping the day that's already selected (a
    /// plain `selectedDate = day` wouldn't re-trigger onChange in that
    /// case, which was the bug: clicking back onto the same day after
    /// previewing one of its events left the single-event preview showing
    /// instead of reverting to that day's full list).
    private func selectDay(_ day: Date) {
        selectedDate = day
        previewEvent = nil
    }

    private func goToToday() {
        referenceDate = .now
        selectedDate = .now
        previewEvent = nil
        monthJump += 1
    }

    /// When a new day starts (midnight, or the app waking after days asleep),
    /// a view that was sitting on "today" follows it. When the new day also
    /// starts a new week -- after Saturday night -- the week that just ended
    /// scrolls out of the starting position and the new current week takes its
    /// place at the top. Someone browsing elsewhere is left where they are.
    private func rollOverIfNewDay() {
        let today = DateMath.startOfDay(.now)
        guard today != lastKnownToday else { return }
        let previousToday = lastKnownToday
        lastKnownToday = today

        let weekStartDay = preferences.weekStartDay
        let weekChanged = DateMath.startOfWeek(containing: previousToday, weekStartDay: weekStartDay)
            != DateMath.startOfWeek(containing: today, weekStartDay: weekStartDay)
        let wasOnPreviousToday = DateMath.isSameDay(selectedDate, previousToday)
        let wasInPreviousWeek = DateMath.startOfWeek(containing: selectedDate, weekStartDay: weekStartDay)
            == DateMath.startOfWeek(containing: previousToday, weekStartDay: weekStartDay)

        guard wasOnPreviousToday || (weekChanged && wasInPreviousWeek) else { return }
        selectedDate = today
        previewEvent = nil
        // Moving the reference date is what makes the Month list jump, so only
        // do it for a new week -- an ordinary new day shouldn't yank the scroll.
        if weekChanged {
            referenceDate = today
            monthJump += 1
        }
    }

    private func step(_ direction: Int) {
        previewEvent = nil
        switch viewMode {
        case .month:
            referenceDate = DateMath.addingMonths(direction, to: referenceDate)
            monthJump += 1
        case .week:
            referenceDate = DateMath.addingWeeks(direction, to: referenceDate)
            selectedDate = referenceDate
        case .day:
            selectedDate = DateMath.addingDays(direction, to: selectedDate)
        case .agenda:
            break
        }
    }

    /// Fills in any location override this device is missing from what
    /// EventKit itself still reports -- see EventLocationAccess.missingOverrides.
    /// The window reaches a year back so a series' first event (where
    /// EventKit keeps the location) is included even mid-semester.
    private func mirrorLocationsFromEventKit() {
        guard eventStore.accessStatus == .fullAccess else { return }
        let start = Calendar.current.date(byAdding: .day, value: -365, to: .now)!
        let end = Calendar.current.date(byAdding: .day, value: 365, to: .now)!
        EventLocationAccess.mirrorMissing(
            from: eventStore.events(from: start, to: end),
            context: modelContext
        )
    }

    /// Rebuilds this app's own notification queue (see ReminderScheduler)
    /// from every event across every calendar -- reminders aren't a
    /// per-calendar-visibility concept, so this ignores hiddenCalendarIdentifiers
    /// on purpose. Runs at launch and after every EventKit change.
    private func refreshReminders() async {
        let start = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let end = Calendar.current.date(byAdding: .day, value: 180, to: .now)!
        let events = eventStore.events(from: start, to: end)
        await ReminderScheduler.refresh(events: events, reminderRows: reminderRows)
    }
}
