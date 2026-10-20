import CryptoKit
import Foundation

/// Prüft Daten im Binärformat von Automerge, bevor sie übernommen werden. Automerge
/// selbst nimmt leere, fremde und abgeschnittene Daten ohne Fehler an (geprüft mit
/// 0.7.2); eine halb geladene Datei würde dann als gelesen gelten, und ihre Änderungen
/// fehlten für immer. Jeder Block der Daten beginnt mit einer festen Kennung, einer
/// Prüfsumme (die ersten 4 Bytes von SHA-256 über Art, Länge und Inhalt), der Art und
/// der Länge (LEB128); die Daten müssen genau aus solchen Blöcken bestehen. Bei
/// komprimierten Blöcken gilt die Prüfsumme den entpackten Daten; dort zählen hier nur
/// Kennung und Länge, was eine abgeschnittene Datei weiterhin erkennt.
enum ChunkCheck {
    static let magic: [UInt8] = [0x85, 0x6F, 0x4A, 0x83]
    static let compressedType: UInt8 = 2

    static func validate(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { throw SyncError.unreadable("chunk.empty") }
        var index = 0
        while index < bytes.count {
            guard bytes.count - index >= 9, Array(bytes[index..<index + 4]) == magic else {
                throw SyncError.unreadable("chunk.magic@\(index)")
            }
            let checksum = Array(bytes[index + 4..<index + 8])
            let headerStart = index + 8
            var cursor = headerStart + 1
            var length = 0
            var shift = 0
            while true {
                guard cursor < bytes.count, shift < 63 else { throw SyncError.unreadable("chunk.length@\(index)") }
                let byte = bytes[cursor]
                length |= Int(byte & 0x7F) << shift
                cursor += 1
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            guard length <= bytes.count - cursor else { throw SyncError.unreadable("chunk.truncated@\(index)") }
            let end = cursor + length
            // Komprimierte Blöcke tragen die Prüfsumme der unkomprimierten Fassung.
            let compressed = bytes[headerStart] == compressedType
            guard compressed || Array(SHA256.hash(data: bytes[headerStart..<end]).prefix(4)) == checksum else {
                throw SyncError.unreadable("chunk.checksum@\(index)")
            }
            index = end
        }
    }
}
