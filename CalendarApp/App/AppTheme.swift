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

    /// Curated calendar-color palette (mirrors the web app's CATEGORY_COLORS,
    /// minus red/green). EKCalendar.cgColor renders unreliably for arbitrary
    /// sampled colors, so categories/calendars always pick from this list.
    static let calendarColors: [Color] = [
        Color(red: 1.00, green: 0.42, blue: 0.62), // pink
        Color(red: 0.66, green: 0.27, blue: 0.42), // wine
        Color(red: 1.00, green: 0.54, blue: 0.40), // coral
        Color(red: 0.72, green: 0.46, blue: 0.29), // terracotta
        Color(red: 0.55, green: 0.35, blue: 0.24), // umber
        Color(red: 1.00, green: 0.76, blue: 0.37), // amber
        Color(red: 0.79, green: 0.64, blue: 0.15), // olive gold
        Color(red: 0.31, green: 0.80, blue: 0.77), // teal
        Color(red: 0.24, green: 0.56, blue: 0.54), // deep teal
        Color(red: 0.24, green: 0.78, blue: 0.88), // sky cyan
        Color(red: 0.36, green: 0.55, blue: 0.94), // blue
        Color(red: 0.18, green: 0.29, blue: 0.49), // navy
        Color(red: 0.56, green: 0.49, blue: 1.00), // violet
        Color(red: 0.48, green: 0.29, blue: 0.58), // plum
        Color(red: 0.72, green: 0.52, blue: 0.88), // lavender
        Color(red: 0.43, green: 0.40, blue: 0.50), // slate
    ]
}
