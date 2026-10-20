import Foundation

/// Format der Quill-Blöcke in der Zwischenablage (`io.github.vogelwild07.quill.blocks`).
///
/// Version 2: `{"version":2,"blocks":[…]}`, jeder Block mit `properties`.
/// Version 1 (bis Phase 3) war ein bloßes Array mit flachen Feldern. Ältere,
/// neuere oder unlesbare Daten ergeben `nil`; dann wird Klartext eingesetzt.
package enum BlockClipboard {
    package static let version = 2

    private struct Header: Decodable {
        var version: Int
    }

    private struct Payload: Codable {
        var version: Int
        var blocks: [EditorBlock]
    }

    package static func encode(_ blocks: [EditorBlock]) -> Data? {
        try? JSONEncoder().encode(Payload(version: version, blocks: blocks))
    }

    package static func decode(_ data: Data) -> [EditorBlock]? {
        // Erst die Version, damit eine spätere Version nie halb gelesen wird.
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.version == version else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data).blocks
    }
}
