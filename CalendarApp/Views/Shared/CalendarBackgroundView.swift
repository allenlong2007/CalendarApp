import SwiftUI

struct CalendarBackgroundView: View {
    @Environment(CalendarBackgroundStore.self) private var background
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            AppTheme.canvas
                .overlay {
                    if background.isEnabled {
                        Group {
                            #if targetEnvironment(macCatalyst)
                            // Keep all four image edges at the window bounds.
                            Image(uiImage: background.image)
                                .resizable()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            #else
                            if UIDevice.current.userInterfaceIdiom == .phone,
                               geometry.size.height > geometry.size.width {
                                ZStack(alignment: .bottom) {
                                    // A soft backing fills the space above the smaller
                                    // artwork without stretching it or adding a hard band.
                                    Image(uiImage: background.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                        .clipped()
                                        .blur(radius: 18)
                                        .opacity(0.35)
                                    Image(uiImage: background.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geometry.size.width, height: geometry.size.height * 0.86, alignment: .bottom)
                                        .clipped()
                                        .mask {
                                            LinearGradient(stops: [
                                                .init(color: .clear, location: 0),
                                                .init(color: .white, location: 0.12),
                                                .init(color: .white, location: 1)
                                            ], startPoint: .top, endPoint: .bottom)
                                        }
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            } else {
                                Image(uiImage: background.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
                            }
                            #endif
                        }
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
