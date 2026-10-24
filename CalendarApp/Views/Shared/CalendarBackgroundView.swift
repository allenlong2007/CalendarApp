import SwiftUI

struct CalendarBackgroundView: View {
    @Environment(CalendarBackgroundStore.self) private var background
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            Color.black
                .overlay {
                    if background.isEnabled {
                        Image(uiImage: background.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
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
        content.listRowBackground(background.isEnabled ? Color.black.opacity(0.35) : Color.black)
    }
}

extension View {
    func calendarBackgroundRow() -> some View { modifier(CalendarBackgroundRow()) }
}
