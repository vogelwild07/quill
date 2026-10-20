import Automerge
import Foundation
import QuillModel

/// Formatierung eines Textes als Marks in Automerge, gelesen und geschrieben über
/// `RichText` (ADR-013). Automerge zählt Positionen in Unicode-Skalaren.
///
/// Fett, kursiv usw. wachsen beim Weitertippen am Ende mit, Links nicht (wie im Editor).
/// Unbekannte Marks späterer Versionen bleiben als Name erhalten.
enum TextMarks {
    static let linkName = "link"

    /// Marks je Skalar: Name → Wert (`true` oder die Link-Adresse).
    typealias Assignment = [String: ScalarValue]

    /// Formatierung von `snapshot` je Skalar; leer ohne Formatierung. Passen die Runs
    /// nicht zum Text, gilt der Text ohne Formatierung (wie in `RichText`).
    static func assignments(text: String, richText: Data?) -> [Assignment] {
        let count = text.unicodeScalars.count
        guard let data = richText, let rich = RichText.decode(data), rich.plainText == text else {
            return Array(repeating: [:], count: count)
        }
        var result: [Assignment] = []
        result.reserveCapacity(count)
        for run in rich.runs {
            var assignment: Assignment = [:]
            for mark in run.marks { assignment[mark] = .Boolean(true) }
            if let link = run.link { assignment[linkName] = .String(link) }
            result.append(contentsOf: repeatElement(assignment, count: run.text.unicodeScalars.count))
        }
        return result
    }

    /// Marks aus Automerge je Skalar. Entfernte Marks (mit `null` gesetzt) meldet
    /// Automerge nicht mehr (`PageDocumentTests.removedMarksAreNotReported`).
    static func assignments(of marks: [Mark], count: Int) -> [Assignment] {
        var result = Array(repeating: Assignment(), count: count)
        for mark in marks {
            let start = min(Int(mark.start), count), end = min(Int(mark.end), count)
            guard start < end else { continue }
            for index in start..<end { result[index][mark.name] = mark.value }
        }
        return result
    }

    /// `RichText`-JSON aus Marks je Skalar; `nil` ohne Formatierung.
    static func richText(text: String, assignments: [Assignment]) -> Data? {
        guard assignments.contains(where: { !$0.isEmpty }) else { return nil }
        var runs: [RichText.Run] = []
        var current = ""
        var currentAssignment: Assignment?
        for (scalar, assignment) in zip(text.unicodeScalars, assignments) {
            if assignment != currentAssignment, let previous = currentAssignment {
                runs.append(run(current, previous))
                current = ""
            }
            currentAssignment = assignment
            current.unicodeScalars.append(scalar)
        }
        if let last = currentAssignment { runs.append(run(current, last)) }
        return try? RichText(runs: runs).encoded()
    }

    private static func run(_ text: String, _ assignment: Assignment) -> RichText.Run {
        var marks: [String] = []
        var link: String?
        for (name, value) in assignment {
            switch value {
            case .String(let address) where name == linkName: link = address
            case .Boolean(true): marks.append(name)
            default: break
            }
        }
        return RichText.Run(text: text, marks: marks, link: link)
    }

    /// Setzt die Marks von `obj` auf `desired`; ändert nur Bereiche, die abweichen.
    static func update(_ document: Document, obj: ObjId, to desired: [Assignment]) throws {
        let current = assignments(of: try document.marks(obj: obj), count: desired.count)
        let names = Set(desired.flatMap(\.keys)).union(current.flatMap(\.keys))
        for name in names.sorted() {
            var index = 0
            while index < desired.count {
                let wanted = desired[index][name]
                guard wanted != current[index][name] else {
                    index += 1
                    continue
                }
                var end = index + 1
                while end < desired.count, desired[end][name] == wanted, desired[end][name] != current[end][name] {
                    end += 1
                }
                try document.mark(
                    obj: obj, start: UInt64(index), end: UInt64(end),
                    expand: wanted != nil && name != linkName ? .after : .none,
                    name: name, value: wanted ?? .Null
                )
                index = end
            }
        }
    }
}
