import EventKit
import SwiftUI

/// Central theme constants. The app is always dark, with a fixed Ultramarine
/// accent (the iPhone 16 "Ultramarine" finish) standing in for Apple Calendar's
/// red -- both are defined as *fixed* colors in Assets.xcassets (Any Appearance,
/// not Light/Dark variants), so nothing here needs to branch on color scheme.
enum AppTheme {
    static let ultramarine = Color("Ultramarine")
    /// Non-optional fallback for spots that need a CGColor synchronously
    /// (Color.cgColor is optional and best avoided as a force-unwrap).
    static let ultramarineCGColor: CGColor = CGColor(red: 0.435, green: 0.435, blue: 0.949, alpha: 1)

    static func calendarColor(for calendar: EKCalendar?) -> Color {
        guard let cg = calendar?.cgColor else { return ultramarine }
        return Color(cgColor: cg)
    }

    /// Event status colors -- reserved for completed/overdue only, never used
    /// as a category color, so a category swatch is never mistaken for a status.
    static let completed = Color(red: 0.2, green: 0.72, blue: 0.42)   // #33B76B-ish
    static let overdue = Color(red: 0.89, green: 0.34, blue: 0.29)    // matches the web app's overdue red

    /// Curated calendar-color palette. EKCalendar.cgColor renders unreliably
    /// for arbitrary sampled colors, so categories/calendars always pick from
    /// this list.
    ///
    /// Hues are spaced ~20 apart around the wheel (computed, not eyeballed)
    /// and deliberately kept clear of both reserved status hues -- red ~5
    /// (`overdue`) and green ~145 (`completed`) -- with a wider margin
    /// around green, since even an unrelated yellow-green category color
    /// reads as "greenish" at a glance. Saturation/brightness are varied too,
    /// not just hue, since several neighboring entries are still in the same
    /// blue/violet family and hue alone isn't enough to tell them apart at
    /// the tiny dot/chip sizes the Month grid renders them at. An earlier
    /// version of this palette had several near-duplicate jewel tones
    /// (teal/deep-teal/sky-cyan, violet/plum/lavender) that were easy to
    /// confuse on the actual calendar grid -- this one trades a couple of
    /// those for more distinct options instead.
    static let calendarColors: [Color] = [
        Color(red: 0.86, green: 0.48, blue: 0.15), // orange
        Color(red: 0.80, green: 0.64, blue: 0.18), // amber
        Color(red: 0.65, green: 0.72, blue: 0.23), // mustard
        Color(red: 0.23, green: 0.75, blue: 0.66), // teal
        Color(red: 0.30, green: 0.75, blue: 0.85), // sky
        Color(red: 0.25, green: 0.52, blue: 0.82), // azure
        Color(red: 0.35, green: 0.42, blue: 0.88), // blue
        Color(red: 0.43, green: 0.34, blue: 0.75), // indigo
        Color(red: 0.60, green: 0.33, blue: 0.82), // violet
        Color(red: 0.66, green: 0.31, blue: 0.70), // purple
        Color(red: 0.85, green: 0.26, blue: 0.71), // magenta
        Color(red: 0.86, green: 0.21, blue: 0.48), // rose

        // Second set, chosen by measured perceptual distance (CIELAB delta-E)
        // against every swatch above and the completed/overdue colors, not by
        // eye: all at least ~25 apart. Constrained to stay visible on the
        // always-dark background (no near-black) and to keep clear of the
        // green/red zones reserved for status. Mostly earth tones and deeper or
        // more saturated variants of hues the first set already covers --
        // the open hue arcs themselves are used up.
        Color(red: 0.40, green: 0.34, blue: 0.24), // umber
        Color(red: 0.60, green: 0.33, blue: 0.18), // rust
        Color(red: 0.80, green: 0.61, blue: 0.48), // sand
        Color(red: 0.50, green: 0.46, blue: 0.15), // olive
        Color(red: 0.60, green: 0.27, blue: 0.34), // wine
        Color(red: 0.70, green: 0.52, blue: 0.65), // mauve
        Color(red: 0.06, green: 0.40, blue: 0.40), // deep teal
        Color(red: 0.30, green: 0.37, blue: 0.50), // slate
        Color(red: 0.14, green: 0.29, blue: 0.90), // royal blue
        Color(red: 0.44, green: 0.14, blue: 0.90), // ultraviolet
        Color(red: 0.47, green: 0.30, blue: 0.50), // plum
        Color(red: 0.86, green: 0.14, blue: 0.90), // fuchsia
    ]
}
