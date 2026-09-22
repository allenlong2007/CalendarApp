import EventKit
import SwiftData
import SwiftUI

/// The "imaginary week" scratch planner -- a practice schedule keyed by
/// weekday (0-6), never touching EventKit or real dates. Ported from the web
/// app's Planner tab.
struct PlannerView: View {
    @Environment(EventStoreManager.self) private var eventStore
    @Environment(UndoManagerService.self) private var undoManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlannerEvent.startMinutes) private var allPlannerEvents: [PlannerEvent]
    @Query private var preferencesRows: [AppPreferences]

    @State private var editorContext: PlannerEditorContext?
    @State private var showingClearConfirmation = false

    private let hourHeight: CGFloat = 52
    private let gutterWidth: CGFloat = 40

    private var preferences: AppPreferences { AppPreferencesAccess.ensure(preferencesRows, in: modelContext) }

    private var orderedWeekdays: [Int] {
        let start = preferences.weekStartDay
        return (0..<7).map { (start + $0) % 7 }
    }

    private var weekdaySymbols: [String] { DateMath.weekdayHeaderSymbols }

    private func events(for weekday: Int) -> [PlannerEvent] {
        allPlannerEvents.filter { $0.weekday == weekday && !$0.isAllDay }
    }

    private func allDayEvents(for weekday: Int) -> [PlannerEvent] {
        allPlannerEvents.filter { $0.weekday == weekday && $0.isAllDay }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekHeader
                Divider()
                allDayRow
                Divider()
                ScrollView(.vertical) {
                    hourGrid
                }
                .defaultScrollAnchor(.init(x: 0, y: 7.0 / 24.0))
            }
            .navigationTitle("Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear Practice Planner", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Clear the entire practice planner? This can't be undone.",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Practice Planner", role: .destructive) { clearAll() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $editorContext) { context in
                PlannerEventEditorView(context: context)
            }
        }
    }

    private var weekHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth)
            ForEach(orderedWeekdays, id: \.self) { weekday in
                Text(weekdaySymbols[weekday].uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        // Color.clear (the gutter-width spacer above) has no height
        // constraint of its own and defaults to greedily filling all
        // available vertical space, stretching this whole row -- fixedSize
        // forces the row back to its content's own ideal height.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var allDayRow: some View {
        if orderedWeekdays.contains(where: { !allDayEvents(for: $0).isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("All-day").font(.caption2).foregroundStyle(.secondary).frame(width: gutterWidth, alignment: .leading)
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    VStack(spacing: 2) {
                        ForEach(allDayEvents(for: weekday), id: \.id) { event in
                            Text(event.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .padding(.horizontal, 3)
                                .frame(maxWidth: .infinity)
                                .background(colorFor(event).opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
                                .onTapGesture { editorContext = .edit(event) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var hourGrid: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: gutterWidth, height: hourHeight, alignment: .top)
                        .offset(y: -6)
                }
            }
            ForEach(orderedWeekdays, id: \.self) { weekday in
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { _ in
                                Divider().frame(height: hourHeight, alignment: .top)
                            }
                        }
                        ForEach(events(for: weekday), id: \.id) { event in
                            let frame = layout(for: event, width: geo.size.width)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorFor(event))
                                .overlay(alignment: .topLeading) {
                                    Text(event.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .lineLimit(2)
                                }
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: frame.x, y: frame.y)
                                .onTapGesture { editorContext = .edit(event) }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            editorContext = .new(weekday: weekday, startMinutes: minutesFor(y: value.location.y))
                        }
                    )
                }
                .frame(height: hourHeight * 24)
                .frame(maxWidth: .infinity)
            }
        }
        // Matches the hour labels' own -6pt offset above (which visually
        // aligns each label with its divider line) so "12 AM" has room to
        // render fully instead of being clipped by the scroll content's own
        // top edge.
        .padding(.top, 6)
    }

    private func colorFor(_ event: PlannerEvent) -> Color {
        guard let identifier = event.categoryIdentifier,
              let calendar = eventStore.calendars.first(where: { $0.calendarIdentifier == identifier })
        else { return AppTheme.ultramarine }
        return AppTheme.calendarColor(for: calendar)
    }

    private func hourLabel(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12) \(period)"
    }

    private func layout(for event: PlannerEvent, width: CGFloat) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let startMinutes = Double(event.startMinutes ?? 0)
        let endMinutes = max(startMinutes + 20, Double(event.endMinutes ?? Int(startMinutes) + 60))
        let top = CGFloat(startMinutes / 60) * hourHeight
        let height = CGFloat((endMinutes - startMinutes) / 60) * hourHeight
        return (x: 2, y: top, width: max(0, width - 4), height: height)
    }

    private func minutesFor(y: CGFloat) -> Int {
        Int((y / hourHeight) * 60)
    }

    private func clearAll() {
        let snapshots = allPlannerEvents.map { event in
            (
                weekday: event.weekday,
                title: event.title,
                isAllDay: event.isAllDay,
                startMinutes: event.startMinutes,
                endMinutes: event.endMinutes,
                categoryIdentifier: event.categoryIdentifier,
                notes: event.notes
            )
        }
        for event in allPlannerEvents {
            modelContext.delete(event)
        }
        undoManager.register(message: "Practice Planner Cleared") {
            for snapshot in snapshots {
                modelContext.insert(PlannerEvent(
                    weekday: snapshot.weekday,
                    title: snapshot.title,
                    isAllDay: snapshot.isAllDay,
                    startMinutes: snapshot.startMinutes,
                    endMinutes: snapshot.endMinutes,
                    categoryIdentifier: snapshot.categoryIdentifier,
                    notes: snapshot.notes
                ))
            }
        }
    }
}

enum PlannerEditorContext: Identifiable {
    case new(weekday: Int, startMinutes: Int)
    case edit(PlannerEvent)

    var id: String {
        switch self {
        case .new(let weekday, let start): return "new-\(weekday)-\(start)"
        case .edit(let event): return "edit-\(event.id)"
        }
    }
}
