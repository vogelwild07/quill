import Foundation

/// Kurzer Ausschnitt aus Klartext: für Suchtreffer um die Fundstelle, für den
/// Papierkorb vom Anfang (ADR-017).
public enum TextSnippet {
    public static let maxLength = 80

    /// Ausschnitt um `match` (UTF-16-Bereich in `text`), ohne Fundstelle vom Anfang.
    /// Schneidet an Wortgrenzen, Kürzungen mit „…“; Umbrüche werden zu Leerzeichen.
    public static func excerpt(_ text: String, around match: NSRange? = nil, maxLength: Int = maxLength) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let ns = flat as NSString
        guard ns.length > maxLength else { return flat }
        var start = 0
        if let match, match.location != NSNotFound, NSMaxRange(match) <= ns.length {
            // Etwas Text vor der Fundstelle zeigen, damit sie nicht am Rand klebt.
            start = max(0, min(match.location - maxLength / 4, ns.length - maxLength))
        }
        var end = min(ns.length, start + maxLength)
        if start > 0 { start = wordStart(in: ns, from: start) }
        if end < ns.length { end = wordEnd(in: ns, before: end, after: start) }
        let body = ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespaces)
        return (start > 0 ? "…" : "") + body + (end < ns.length ? "…" : "")
    }

    /// Erste Worte einer Seite: der Text der ersten nicht leeren Blöcke.
    public static func preview(of blockTexts: [String], maxLength: Int = maxLength) -> String {
        var joined = ""
        for text in blockTexts where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            joined += (joined.isEmpty ? "" : " ") + text
            if (joined as NSString).length > maxLength { break }
        }
        return excerpt(joined, maxLength: maxLength)
    }

    private static func wordStart(in text: NSString, from index: Int) -> Int {
        let space = text.rangeOfCharacter(from: .whitespaces, options: [], range: NSRange(location: index, length: min(20, text.length - index)))
        return space.location == NSNotFound ? index : NSMaxRange(space)
    }

    private static func wordEnd(in text: NSString, before index: Int, after start: Int) -> Int {
        let space = text.rangeOfCharacter(from: .whitespaces, options: .backwards, range: NSRange(location: start, length: index - start))
        return space.location == NSNotFound || space.location <= start ? index : space.location
    }
}
