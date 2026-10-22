import Automerge
import Foundation
import QuillModel

/// Ein Tag in der Geschichte eines Dokuments (ADR-031).
public struct HistoryDay: Hashable, Sendable {
    /// Beginn des Tages im Kalender, mit dem die Tage gebildet wurden.
    public var day: Date
    /// Stand am Ende des Tages.
    public var version: DocumentVersion
}

extension SyncDocument {
    /// Tage mit mindestens einer Änderung, ältester zuerst, je mit dem Stand am Ende des
    /// Tages. Eine Änderung zählt zu dem Tag, an dem sie geschrieben wurde (Zeit des
    /// schreibenden Geräts). Der Stand eines Tages enthält alle Änderungen bis zu seinem
    /// Ende und alles, worauf sie aufbauen: Geht die Uhr eines Geräts nach, steht dessen
    /// Änderung früher da, als ihre Zeit sagt, aber nie ein Stand, den es so nicht gab.
    public func days(in calendar: Calendar = .current) -> [HistoryDay] {
        // Die gemeinsame erste Änderung (feste Zeit) gehört zu keinem Tag.
        let changes = document.getHistory().dropFirst().compactMap { document.change(hash: $0) }
        let byHash = Dictionary(changes.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
        let byDay = Dictionary(grouping: changes) { calendar.startOfDay(for: $0.timestamp) }
        var included = Set<ChangeHash>()
        var depended = Set<ChangeHash>()
        var result: [HistoryDay] = []
        for day in byDay.keys.sorted() {
            var open = byDay[day]!.map(\.hash)
            while let hash = open.popLast() {
                guard included.insert(hash).inserted, let change = byHash[hash] else { continue }
                depended.formUnion(change.deps)
                open.append(contentsOf: change.deps)
            }
            let version = DocumentVersion(heads: included.subtracting(depended))
            // Schon mit einem früheren Tag gekommen (Uhr ging vor): kein neuer Stand.
            if result.last?.version != version { result.append(HistoryDay(day: day, version: version)) }
        }
        return result
    }
}

/// Frühere Stände einer Seite, je Tag der Stand an seinem Ende (12.2, ADR-031). Liest nur;
/// zurückgeholt wird über den Editor wie jede andere Änderung.
public struct PageHistory: Sendable {
    public let pageID: UUID
    /// Ältester zuerst. Leer, wenn die Seite noch keine Geschichte hat.
    public let days: [HistoryDay]
    private let bytes: Data?

    /// `document` ist das Sync-Dokument der Seite (`Page.syncDocument`), `nil` ohne Geschichte.
    public init(pageID: UUID, document: Data?, calendar: Calendar = .current) throws {
        self.pageID = pageID
        bytes = document
        days = try document.map { try PageDocument(bytes: $0).days(in: calendar) } ?? []
    }

    /// Blöcke der Seite am Ende von `day`.
    public func blocks(on day: HistoryDay) throws -> [BlockSnapshot] {
        guard let bytes else { return [] }
        return try PageDocument(bytes: bytes).blocks(at: day.version)
    }
}

extension PageHistory {
    /// Liest die Geschichte aus dem Store, abseits des Main Thread.
    public static func load(_ pageID: UUID, from store: PageStore, calendar: Calendar = .current) async throws -> PageHistory {
        let document = try await store.syncPage(pageID)?.document
        return try PageHistory(pageID: pageID, document: document, calendar: calendar)
    }
}
