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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var preferencesRows: [AppPreferences]
    @Query private var completionRows: [EventCompletionStatus]

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
                            onSelectDay: selectDay,
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
        }
        .onChange(of: viewMode) { previewEvent = nil }
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
                    onSelectDay: selectDay,
                    onSelectEvent: { eventEditorContext = .edit($0) },
                    onAddEvent: { eventEditorContext = .new(defaultDate: $0) },
                    onPreviewEvent: { previewEvent = $0 }
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
                    onPreviewEvent: { previewEvent = $0 }
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
    }

    private func step(_ direction: Int) {
        previewEvent = nil
        switch viewMode {
        case .month:
            referenceDate = DateMath.addingMonths(direction, to: referenceDate)
        case .week:
            referenceDate = DateMath.addingWeeks(direction, to: referenceDate)
            selectedDate = referenceDate
        case .day:
            selectedDate = DateMath.addingDays(direction, to: selectedDate)
        case .agenda:
            break
        }
    }
}
