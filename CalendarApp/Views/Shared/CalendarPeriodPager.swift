import SwiftUI

/// Stable page identities let native scrolling handle dragging, interruption,
/// and VoiceOver without resetting a three-page carousel during its animation.
struct CalendarPeriodPager<Content: View>: View {
    let period: CalendarPagePeriod
    let referenceDate: Date
    let weekStartDay: Int
    let onChangeDate: (Date) -> Void
    @ViewBuilder let content: (Date) -> Content

    @State private var anchor: Date
    @State private var visiblePage: Int? = 0
    @State private var pages = -24...24

    init(period: CalendarPagePeriod, referenceDate: Date, weekStartDay: Int,
         onChangeDate: @escaping (Date) -> Void, @ViewBuilder content: @escaping (Date) -> Content) {
        self.period = period
        self.referenceDate = referenceDate
        self.weekStartDay = weekStartDay
        self.onChangeDate = onChangeDate
        self.content = content
        _anchor = State(initialValue: referenceDate)
    }

    var body: some View {
        GeometryReader { geometry in
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages, id: \.self) { page in
                    content(period.date(at: page, from: anchor))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("calendarPage.\(page)")
                        .accessibilityHidden(page != visiblePage)
                        .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("calendarPeriodPager")
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $visiblePage, anchor: .leading)
        .onScrollPhaseChange { _, phase in
            guard phase == .idle, let page = visiblePage else { return }
            expand(around: page)
            if page != period.index(of: referenceDate, from: anchor, weekStartDay: weekStartDay) {
                onChangeDate(period.date(at: page, from: anchor))
            }
        }
        .onChange(of: referenceDate) {
            let page = period.index(of: referenceDate, from: anchor, weekStartDay: weekStartDay)
            guard page != visiblePage else { return }
            expand(around: page)
            Motion.perform(Motion.easeOut(0.25)) { visiblePage = page }
        }
        .onChange(of: weekStartDay) {
            visiblePage = period.index(of: referenceDate, from: anchor, weekStartDay: weekStartDay)
        }
        .accessibilityScrollAction { edge in
            let step = edge == .leading ? -1 : edge == .trailing ? 1 : 0
            guard step != 0 else { return }
            let page = (visiblePage ?? 0) + step
            expand(around: page)
            visiblePage = page
            onChangeDate(period.date(at: page, from: anchor))
        }
        }
        .clipped()
    }

    private func expand(around page: Int) {
        if page < pages.lowerBound + 6 || page > pages.upperBound - 6 {
            pages = min(pages.lowerBound, page - 24)...max(pages.upperBound, page + 24)
        }
    }
}
