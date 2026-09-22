import Foundation
import SwiftData

/// A quick-pick address saved for reuse across events -- separate from any
/// single event's location (which lives on EKEvent.structuredLocation).
@Model
final class SavedAddress {
    var id: UUID = UUID()
    var label: String = ""
    var addressLine: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var createdAt: Date = Date.now

    init(label: String, addressLine: String, latitude: Double, longitude: Double) {
        self.label = label
        self.addressLine = addressLine
        self.latitude = latitude
        self.longitude = longitude
    }
}
