import WidgetKit
import SwiftUI

@main
struct CalendarAppWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextEventWidget()
        TodayAgendaWidget()
    }
}
