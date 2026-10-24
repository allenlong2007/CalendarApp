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
        restored.useIncludedImage()
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
}
