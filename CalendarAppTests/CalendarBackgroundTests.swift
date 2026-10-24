import Foundation
import Testing
import UIKit
@testable import CalendarApp

@MainActor
struct CalendarBackgroundTests {
    private func fixture() throws -> (CalendarBackgroundStore, UserDefaults, URL) {
        let defaults = try #require(UserDefaults(suiteName: "BackgroundTests.\(UUID().uuidString)"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (CalendarBackgroundStore(defaults: defaults, directory: directory), defaults, directory)
    }

    @Test func artworkIsEnabledByDefaultAndSettingsPersist() throws {
        let (store, defaults, directory) = try fixture()
        #expect(store.isEnabled)
        #expect(store.opacity == 0.22)
        #expect(!store.hasCustomImage)
        store.isEnabled = false
        store.opacity = 0.3
        let restored = CalendarBackgroundStore(defaults: defaults, directory: directory)
        #expect(!restored.isEnabled)
        #expect(restored.opacity == 0.3)
    }

    @Test func customImageSurvivesRelaunchAndCanBeReset() async throws {
        let (store, defaults, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        try await store.importImage(data: #require(image.pngData()))
        let restored = CalendarBackgroundStore(defaults: defaults, directory: directory)
        #expect(restored.hasCustomImage)
        #expect(restored.image.size.width / restored.image.size.height == 2)
        try restored.useIncludedImage()
        #expect(!CalendarBackgroundStore(defaults: defaults, directory: directory).hasCustomImage)
    }

    @Test func invalidImageDoesNotReplaceExistingChoice() async throws {
        let (store, _, _) = try fixture()
        store.isEnabled = false
        await #expect(throws: (any Error).self) {
            try await store.importImage(data: Data("not an image".utf8))
        }
        #expect(!store.hasCustomImage)
        #expect(!store.isEnabled)
    }

    @Test func opacityStaysInReadableRange() throws {
        let (store, defaults, directory) = try fixture()
        store.opacity = 1
        #expect(store.opacity == 0.30)
        store.opacity = -1
        #expect(store.opacity == 0.08)
        store.opacity = .nan
        #expect(store.opacity == 0.22)
        defaults.set(Double.infinity, forKey: "calendarBackground.opacity")
        #expect(CalendarBackgroundStore(defaults: defaults, directory: directory).opacity == 0.22)
    }

    @Test func fileImportDownsamplesAndRejectsBadReplacement() async throws {
        let (store, _, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.jpg")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 2000), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 2000))
        }
        try #require(image.jpegData(compressionQuality: 0.9)).write(to: source)
        try await store.importImage(url: source)
        #expect(store.hasCustomImage)
        #expect(store.image.size.width == 3000)
        #expect(store.image.size.height == 1500)
        await #expect(throws: (any Error).self) {
            try await store.importImage(data: Data("invalid replacement".utf8))
        }
        #expect(store.hasCustomImage)
        #expect(store.image.size.width == 3000)
        await #expect(throws: (any Error).self) {
            try await store.importImage(data: Data(count: 31 * 1024 * 1024))
        }
    }

    @Test func missingFileAndWriteFailureLeaveIncludedImageIntact() async throws {
        let (store, _, directory) = try fixture()
        await #expect(throws: (any Error).self) {
            try await store.importImage(url: directory.appendingPathComponent("missing.jpg"))
        }
        // A file at the destination directory makes persistence fail without touching the selected image.
        try Data().write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        await #expect(throws: (any Error).self) {
            try await store.importImage(data: #require(image.pngData()))
        }
        #expect(!store.hasCustomImage)
    }
}
