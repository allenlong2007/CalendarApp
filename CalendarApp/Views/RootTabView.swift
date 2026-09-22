import SwiftUI

/// Top-level tab structure: real dates live under "Calendar" (with its own
/// Month/Week/Day/Agenda segmented switch), the imaginary-week scratch
/// planner gets its own destination since it shares no dates with the rest
/// of the app.
struct RootTabView: View {
    @Environment(UndoManagerService.self) private var undoManager

    var body: some View {
        // UndoToastView is a ZStack sibling, not a `.overlay` on the TabView:
        // an overlay attached to TabView composites behind its own floating
        // tab bar chrome (the toast rendered but was invisible), while a
        // sibling layer draws on top of everything, tab bar included.
        ZStack(alignment: .bottom) {
            TabView {
                CalendarRootView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }

                PlannerView()
                    .tabItem { Label("Planner", systemImage: "square.grid.3x3") }
            }

            UndoToastView()
                // Matches the fixed clearance MonthView's Add Event button
                // needs under iOS 26's floating tab bar (see its comment).
                .padding(.bottom, 90)
                .allowsHitTesting(undoManager.pending != nil)
        }
        .animation(.default, value: undoManager.pending != nil)
    }
}
