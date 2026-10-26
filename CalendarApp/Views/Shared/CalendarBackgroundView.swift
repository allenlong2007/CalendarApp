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
                                let portraitImage = background.hasCustomImage
                                    ? background.image
                                    : UIImage(named: "CloudBackgroundPortrait") ?? background.image
                                // Added sky increases only the upper canvas; preserve the
                                // landscape's scale and bottom clearance from the prior crop.
                                let originalAspect = background.image.size.width / max(background.image.size.height, 1)
                                let portraitAspect = portraitImage.size.width / max(portraitImage.size.height, 1)
                                let artworkHeight = geometry.size.height * 0.58 * originalAspect / max(portraitAspect, 0.01)
                                let stretchedHeight = artworkHeight * 1.05
                                let artwork = Image(uiImage: portraitImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: artworkHeight, alignment: .bottom)
                                    .clipped()
                                    .scaleEffect(x: 1, y: 1.05, anchor: .bottom)
                                    .frame(width: geometry.size.width, height: stretchedHeight, alignment: .bottom)
                                // Keep the cloud visible while its surrounding sky fades.
                                artwork
                                    .mask {
                                        ZStack {
                                            LinearGradient(stops: [
                                                .init(color: .clear, location: 0),
                                                .init(color: .white, location: background.hasCustomImage ? 0.025 : 0.18),
                                                .init(color: .white, location: 0.93),
                                                .init(color: .white.opacity(0.75), location: 0.96),
                                                .init(color: .white.opacity(0.25), location: 0.985),
                                                .init(color: .clear, location: 1)
                                            ], startPoint: .top, endPoint: .bottom)
                                            if !background.hasCustomImage {
                                                // The bright cloud forms its own mask; the blue
                                                // sky falls below the luminance threshold.
                                                artwork
                                                    .saturation(0)
                                                    .contrast(4)
                                                    .brightness(-0.15)
                                                    .luminanceToAlpha()
                                                    .mask {
                                                        LinearGradient(stops: [
                                                            .init(color: .white, location: 0),
                                                            .init(color: .white, location: 0.10),
                                                            .init(color: .clear, location: 0.18),
                                                            .init(color: .clear, location: 1)
                                                        ], startPoint: .top, endPoint: .bottom)
                                                    }
                                            }
                                        }
                                        .compositingGroup()
                                    }
                                    .background(alignment: .top) {
                                        if !background.hasCustomImage {
                                            // Extend the included artwork's sky above its
                                            // rectangular edge without enlarging the cloud.
                                            let sky = Color(red: 0.06, green: 0.29, blue: 0.77)
                                            LinearGradient(stops: [
                                                .init(color: .clear, location: 0),
                                                .init(color: sky, location: 1)
                                            ], startPoint: .top, endPoint: .bottom)
                                            .frame(height: stretchedHeight * 0.18 + 390)
                                            .offset(y: -390)
                                        }
                                    }
                                    .compositingGroup()
                                    .padding(.bottom, 76)
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
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
