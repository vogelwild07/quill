import Foundation
import Testing
@testable import QuillModel

/// `BlockProperties` als JSON (z. B. in der Zwischenablage): Daten älterer Versionen
/// ohne neuere Felder bleiben lesbar (Phase 11.2, `isRestored`).
@Suite struct BlockPropertiesCodingTests {
    @Test func olderDataWithoutNewFieldsDecodes() throws {
        let old = Data(#"{"indent":1,"isChecked":true,"codeLanguage":"swift"}"#.utf8)
        let decoded = try JSONDecoder().decode(BlockProperties.self, from: old)
        #expect(decoded == BlockProperties(indent: 1, isChecked: true, codeLanguage: "swift"))
        #expect(try JSONDecoder().decode(BlockProperties.self, from: Data("{}".utf8)) == BlockProperties())
    }

    @Test func roundTripKeepsEveryField() throws {
        let full = BlockProperties(indent: 3, isChecked: true, codeLanguage: "swift", assetID: UUID(), isRestored: true)
        #expect(try JSONDecoder().decode(BlockProperties.self, from: JSONEncoder().encode(full)) == full)
    }
}
