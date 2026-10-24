import SwiftUI

struct CalendarBackgroundView: View {
    @Environment(CalendarBackgroundStore.self) private var background
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            AppTheme.canvas
                .overlay {
                    if background.isEnabled {
                        Image(uiImage: background.image)
                            .resizable()
                            #if targetEnvironment(macCatalyst)
                            // Scale all four image edges to the window bounds. Aspect-fit
                            // leaves bands; aspect-fill crops the top or bottom on resize.
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            #else
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
                            #endif
                            .clipped()
                            .opacity(reduceTransparency ? min(background.opacity, 0.12) : background.opacity)
                    }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CalendarBackgroundRow: ViewModifier {
    @Environment(CalendarBackgroundStore.self) private var background

    func body(content: Content) -> some View {
        content.listRowBackground(background.isEnabled ? AppTheme.calendarSurface.opacity(0.60) : AppTheme.calendarSurface)
    }
}

extension View {
    func calendarBackgroundRow() -> some View { modifier(CalendarBackgroundRow()) }
}
