import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

/// Backgrounds belong to this device, rather than the EventKit sync payload.
@MainActor @Observable
final class CalendarBackgroundStore {
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "calendarBackground.enabled") }
    }
    var opacity: Double {
        get { storedOpacity }
        set {
            storedOpacity = newValue.isFinite ? min(max(newValue, 0.08), 0.30) : 0.22
            defaults.set(storedOpacity, forKey: "calendarBackground.opacity")
        }
    }
    private(set) var image: UIImage
    private(set) var hasCustomImage: Bool
    private var storedOpacity: Double
    private let defaults: UserDefaults
    private let directory: URL
    private var imageURL: URL { directory.appendingPathComponent("background.jpg") }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("CalendarBackground", isDirectory: true)
        isEnabled = defaults.object(forKey: "calendarBackground.enabled") as? Bool ?? true
        let savedOpacity = defaults.object(forKey: "calendarBackground.opacity") as? Double ?? 0.22
        storedOpacity = savedOpacity.isFinite ? min(max(savedOpacity, 0.08), 0.30) : 0.22
        let customImage = UIImage(contentsOfFile: self.directory.appendingPathComponent("background.jpg").path)
        image = customImage ?? Self.includedImage
        hasCustomImage = customImage != nil
    }

    private static var includedImage: UIImage { UIImage(named: "CloudBackground") ?? UIImage() }

    func importImage(data: Data) async throws {
        let prepared = try await BackgroundImageProcessor.prepareAndSave(data, to: imageURL)
        guard let decoded = UIImage(data: prepared) else { throw BackgroundImageError.invalidImage }
        image = decoded
        hasCustomImage = true
        isEnabled = true
    }

    func importImage(url: URL) async throws {
        let data = try await BackgroundImageProcessor.read(url)
        try await importImage(data: data)
    }

    func useIncludedImage() throws {
        if FileManager.default.fileExists(atPath: imageURL.path) {
            try FileManager.default.removeItem(at: imageURL)
        }
        image = Self.includedImage
        hasCustomImage = false
        isEnabled = true
    }
}

enum BackgroundImageError: LocalizedError {
    case invalidImage, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: "This image couldn’t be opened. Choose a JPEG, PNG, or HEIC image."
        case .tooLarge: "This image is too large. Choose an image smaller than 30 MB."
        }
    }
}

/// Nonisolated async work runs away from the UI actor in this Swift 6 target.
enum BackgroundImageProcessor {
    private static let maximumBytes = 30 * 1024 * 1024

    static func prepareAndSave(_ data: Data, to url: URL) async throws -> Data {
        let prepared = try await prepare(data)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try prepared.write(to: url, options: .atomic)
        return prepared
    }

    static func read(_ url: URL) async throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
            throw BackgroundImageError.tooLarge
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func prepare(_ data: Data) async throws -> Data {
        guard data.count <= maximumBytes else { throw BackgroundImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3000,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw BackgroundImageError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw BackgroundImageError.invalidImage
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BackgroundImageError.invalidImage }
        return output as Data
    }
}
