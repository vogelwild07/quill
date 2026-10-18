import Foundation

/// Sprung zu einer Fundstelle: Block und UTF-16-Bereich in dessen Text (ADR-017).
struct RevealRequest: Equatable {
    let pageID: UUID
    let blockID: UUID
    let range: NSRange
}
