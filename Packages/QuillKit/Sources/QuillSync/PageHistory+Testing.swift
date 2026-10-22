#if DEBUG
import Foundation
import QuillModel

extension PageHistory {
    /// Nur für UI-Tests (`TimeTravelSeed`): Sync-Dokument mit je einer Änderung zur Zeit
    /// `time`, die die Seite auf `blocks` bringt.
    public static func testDocument(_ states: [(time: Date, blocks: [BlockSnapshot])]) throws -> Data {
        let document = PageDocument()
        for state in states {
            document.clock = { state.time }
            try document.update(to: state.blocks)
        }
        return document.save()
    }
}
#endif
