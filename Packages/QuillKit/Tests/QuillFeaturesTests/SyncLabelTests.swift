import Foundation
@testable import QuillFeatures
import QuillSync
import Testing

@Suite struct SyncLabelTests {
    /// Eine Lücke im Ordner nennt Seite (oder Seitenbaum), Gerät und Beginn.
    @Test func gapNamesPageDeviceAndSince() {
        let since = Date(timeIntervalSince1970: 1_900_000_000)
        let gap = SyncGap(document: UUID(), device: UUID(), since: since)
        let time = since.formatted(date: .abbreviated, time: .shortened)
        #expect(SyncLabel.gap(gap, device: "MacBook", pageTitle: "Reise") == "„Reise“ von „MacBook“: Dateien fehlen seit \(time).")
        #expect(SyncLabel.gap(gap, device: "MacBook", pageTitle: "") == "„Ohne Titel“ von „MacBook“: Dateien fehlen seit \(time).")
        #expect(SyncLabel.gap(gap, device: "MacBook", pageTitle: nil) == "Seitenbaum von „MacBook“: Dateien fehlen seit \(time).")
    }
}
