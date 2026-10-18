/// Sortierschlüssel für Reihenfolgen ohne geordnete Beziehungen (CloudKit).
///
/// Schlüssel sind Strings aus Ziffern zur Basis 62 (`0-9A-Za-z`), werden per
/// Byte-Vergleich sortiert und enden nie auf `0`. Dadurch passt zwischen zwei
/// Schlüssel immer ein weiterer, und Verschieben ändert genau ein Objekt.
public enum FractionalIndex {
    public enum Error: Swift.Error, Equatable {
        /// Schlüssel enthält fremde Zeichen oder endet auf `0`.
        case invalidKey(String)
        /// Untere Grenze ist nicht kleiner als die obere.
        case invalidOrder(lower: String, upper: String)
    }

    static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
    static let base = digits.count

    /// Schlüssel echt zwischen `lower` und `upper`.
    ///
    /// `nil` oder `""` heißt offen: `key(between: nil, and: nil)` ist der erste
    /// Schlüssel, `key(between: last, and: nil)` hängt hinten an. Am offenen Ende
    /// wird nur um eine Ziffer weitergegangen statt halbiert, damit Anhängen und
    /// Voranstellen die Schlüssel kaum verlängert.
    public static func key(between lower: String?, and upper: String?) throws(Error) -> String {
        let a = try digitValues(lower)
        let b = try digitValues(upper)
        if !a.isEmpty, !b.isEmpty, !(a.lexicographicallyPrecedes(b)) {
            throw .invalidOrder(lower: lower ?? "", upper: upper ?? "")
        }

        let result: [Int]
        switch (a.isEmpty, b.isEmpty) {
        case (true, true): result = [base / 2]
        case (false, true): result = after(a)
        case (true, false): result = before(b)
        case (false, false): result = midpoint(a, b)
        }
        return String(decoding: result.map { digits[$0] }, as: UTF8.self)
    }

    /// `count` aufsteigende Schlüssel ab dem Anfang, z. B. zum Neuordnen von
    /// Geschwistern mit doppelten oder kaputten Schlüsseln.
    public static func keys(count: Int) -> [String] {
        var keys: [String] = []
        keys.reserveCapacity(count)
        for _ in 0..<count {
            // Kann nicht werfen: Der Vorgänger ist ein gültiger Schlüssel.
            keys.append(try! key(between: keys.last, and: nil))
        }
        return keys
    }

    /// `count` aufsteigende Schlüssel zwischen `lower` und `upper`. Halbiert rekursiv,
    /// damit auch viele Schlüssel in einer engen Lücke kurz bleiben (Tiefe log₂ n).
    public static func keys(count: Int, between lower: String?, and upper: String?) throws(Error) -> [String] {
        guard count > 0 else { return [] }
        let middle = try key(between: lower, and: upper)
        let left = try keys(count: (count - 1) / 2, between: lower, and: middle)
        let right = try keys(count: count - 1 - left.count, between: middle, and: upper)
        return left + [middle] + right
    }

    /// Ob `key` ein gültiger, nicht leerer Schlüssel ist.
    public static func isValid(_ key: String) -> Bool {
        guard !key.isEmpty, let values = try? digitValues(key) else { return false }
        return !values.isEmpty
    }

    // MARK: - Ziffernfolgen

    private static func digitValues(_ key: String?) throws(Error) -> [Int] {
        guard let key, !key.isEmpty else { return [] }
        var values: [Int] = []
        values.reserveCapacity(key.utf8.count)
        for byte in key.utf8 {
            guard let value = value(of: byte) else { throw .invalidKey(key) }
            values.append(value)
        }
        if values.last == 0 { throw .invalidKey(key) }
        return values
    }

    private static func value(of byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): Int(byte - UInt8(ascii: "A")) + 10
        case UInt8(ascii: "a")...UInt8(ascii: "z"): Int(byte - UInt8(ascii: "a")) + 36
        default: nil
        }
    }

    /// Kurzer Schlüssel größer als `a`. Eine neue Stelle beginnt bei `1`, damit
    /// sie für 61 weitere Anhänge reicht.
    private static func after(_ a: [Int]) -> [Int] {
        guard let first = a.first else { return [1] }
        if first < base - 1 { return [first + 1] }
        return [first] + after(Array(a.dropFirst()))
    }

    /// Kurzer Schlüssel kleiner als `b`, ohne `0` am Ende. Eine neue Stelle
    /// beginnt bei `z`, damit sie für 61 weitere Voranstellungen reicht.
    private static func before(_ b: [Int]) -> [Int] {
        guard let first = b.first else { return [base - 1] }
        if first > 1 { return [first - 1] }
        // Ist `b` genau "1", liegt nur noch "0…" darunter.
        return [0] + before(Array(b.dropFirst()))
    }

    /// Mitte zwischen `a` < `b`; fehlende Stellen von `a` zählen als `0`.
    private static func midpoint(_ a: [Int], _ b: [Int]) -> [Int] {
        var prefix = 0
        while prefix < b.count, (prefix < a.count ? a[prefix] : 0) == b[prefix] {
            prefix += 1
        }
        if prefix > 0 {
            return Array(b[..<prefix]) + midpointTail(Array(a.dropFirst(prefix)), Array(b.dropFirst(prefix)))
        }
        return midpointTail(a, b)
    }

    /// Mitte, wenn sich die erste Stelle unterscheidet; `b` leer = offen nach oben.
    private static func midpointTail(_ a: [Int], _ b: [Int]) -> [Int] {
        let digitA = a.first ?? 0
        let digitB = b.first ?? base
        if digitB - digitA > 1 {
            return [(digitA + digitB + 1) / 2]
        }
        if b.count > 1 {
            return [b[0]]
        }
        return [digitA] + midpointTail(Array(a.dropFirst()), [])
    }
}
