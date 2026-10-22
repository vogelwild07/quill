import AppKit
import Foundation
@testable import QuillFeatures
import QuillModel
import SwiftData
import Testing

/// Frist für Bilder ohne Block (12.4, ADR-031): Einstellung und Aufräumen beim Start.
/// Store nur im Arbeitsspeicher, Einstellungen in einer eigenen Suite.
@MainActor
@Suite("Zeitreise: Frist für gelöschte Bilder")
struct ImageRetentionTests {
    private static let day: TimeInterval = 24 * 3600

    @Test func choiceIsStoredPerMacAndDefaultsToNinetyDays() throws {
        let suite = "io.github.vogelwild07.quill.tests.retention.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ImageRetentionSettings(defaults: defaults).retention == .ninetyDays)
        ImageRetentionSettings(defaults: defaults).select(.oneYear)
        #expect(ImageRetentionSettings(defaults: defaults).retention == .oneYear)
        defaults.set("unbekannt", forKey: ImageRetentionSettings.defaultsKey)
        #expect(ImageRetentionSettings(defaults: defaults).retention == .ninetyDays)

        // Ohne `UserDefaults` (Test-Store) gilt die Wahl nur bis zum Beenden.
        let memory = ImageRetentionSettings(defaults: nil)
        memory.select(.forever)
        #expect(memory.retention == .forever)
        #expect(ImageRetention.forever.age == nil)
    }

    @Test func orphanedImagesStayForTheChosenPeriod() async throws {
        for (retention, kept) in [(ImageRetention.thirtyDays, false), (.ninetyDays, true), (.forever, true)] {
            let (persistence, assetID) = try await orphanedImage(age: 60 * Self.day)
            persistence.imageRetention.select(retention)
            await persistence.removeOrphanedAssets()?.value
            #expect((try await persistence.store.imageData(assetID) != nil) == kept, "\(retention)")
        }
    }

    /// Wozu die Frist da ist: Holt die Zeitreise einen gelöschten Bild-Block zurück,
    /// bekommt er sein aufbewahrtes Bild wieder, und es zählt nicht mehr als verwaist.
    @Test func restoredImageBlockGetsItsKeptImageBack() async throws {
        let (persistence, assetID) = try await orphanedImage(age: 60 * Self.day)
        let page = try await persistence.store.createPage(title: "Zurück")
        let block = BlockSnapshot(id: UUID(), kindRaw: BlockKind.image.rawValue, properties: BlockProperties(assetID: assetID))
        try await persistence.store.applyEdits(page, BlockEdits(upserts: [block], order: [block.id]))

        persistence.imageRetention.select(.thirtyDays)
        await persistence.removeOrphanedAssets()?.value
        #expect(try await persistence.store.imageData(assetID) != nil)
    }

    /// Bild, das seit `age` keinem Block mehr gehört.
    private func orphanedImage(age: TimeInterval) async throws -> (QuillPersistence, UUID) {
        let persistence = QuillPersistence(container: try QuillStore.makeInMemoryContainer(), backup: nil)
        let imported = try await persistence.store.importImage(Self.png())
        let context = ModelContext(persistence.container)
        for asset in try context.fetch(FetchDescriptor<Asset>()) {
            asset.updatedAt = .now.addingTimeInterval(-age)
        }
        try context.save()
        return (persistence, imported.assetID)
    }

    private static func png() -> Data {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }
}
