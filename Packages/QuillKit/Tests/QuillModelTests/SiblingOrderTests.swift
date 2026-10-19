import Foundation
import SwiftData
import Testing
@testable import QuillModel

/// Reihenfolge unter Geschwistern (ADR-009). Referenz ist der Vergleich, wie er bis
/// Phase 7.2 an jeder Stelle einzeln stand; Optimierungen dürfen daran nichts ändern.
@Suite("Reihenfolge unter Geschwistern")
struct SiblingOrderTests {
    struct Item: Equatable {
        let tag: Int
        let sortKey: String?
        let createdAt: Date
        let id: UUID

        var order: SiblingOrder { SiblingOrder(sortKey: sortKey, createdAt: createdAt, id: id) }
    }

    /// Der frühere Vergleich, wörtlich.
    static func reference(_ items: [Item]) -> [Item] {
        items.sorted { ($0.sortKey ?? "", $0.createdAt, $0.id.uuidString) < ($1.sortKey ?? "", $1.createdAt, $1.id.uuidString) }
    }

    /// Deterministischer Zufall (SplitMix64).
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Viele Gleichstände: drei Schlüssel (einer fehlt), drei Zeitpunkte, ab und zu
    /// dieselbe `id` doppelt (wie nach einem Sync-Konflikt).
    static func items(count: Int, seed: UInt64) -> [Item] {
        var generator = Generator(state: seed)
        let keys: [String?] = ["a", "a", "b", nil, ""]
        let dates = [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200), Date(timeIntervalSince1970: 300)]
        var ids: [UUID] = []
        return (0..<count).map { tag in
            let id = !ids.isEmpty && Int.random(in: 0..<10, using: &generator) == 0
                ? ids.randomElement(using: &generator)!
                : UUID()
            ids.append(id)
            return Item(
                tag: tag,
                sortKey: keys.randomElement(using: &generator)!,
                createdAt: dates.randomElement(using: &generator)!,
                id: id
            )
        }
    }

    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
    func matchesPreviousComparator(seed: UInt64) {
        for count in [0, 1, 2, 7, 50, 300] {
            let items = Self.items(count: count, seed: seed &* 1000 &+ UInt64(count))
            #expect(items.sortedInSiblingOrder(by: \.order) == Self.reference(items))
        }
    }

    @Test func tiesFallBackToCreationDateThenID() {
        let early = Date(timeIntervalSince1970: 1)
        let late = Date(timeIntervalSince1970: 2)
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!
        let items = [
            Item(tag: 0, sortKey: "b", createdAt: early, id: low),
            Item(tag: 1, sortKey: "a", createdAt: late, id: low),
            Item(tag: 2, sortKey: "a", createdAt: early, id: high),
            Item(tag: 3, sortKey: "a", createdAt: early, id: low),
            Item(tag: 4, sortKey: nil, createdAt: late, id: high),
            Item(tag: 5, sortKey: "", createdAt: early, id: high),
        ]
        #expect(items.sortedInSiblingOrder(by: \.order).map(\.tag) == [5, 4, 3, 2, 1, 0])
    }

    /// Gleiche Schlüssel samt `id`: Die Eingabereihenfolge bleibt.
    @Test func identicalKeysKeepInputOrder() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 5)
        let items = (0..<20).map { Item(tag: $0, sortKey: "k", createdAt: date, id: id) }
        #expect(items.sortedInSiblingOrder(by: \.order).map(\.tag) == Array(0..<20))
        #expect(items.reversed().sortedInSiblingOrder(by: \.order).map(\.tag) == Array((0..<20).reversed()))
    }

    /// Über den Store: Blöcke und Unterseiten mit doppelten Schlüsseln und gleichem
    /// Anlagedatum kommen in derselben Reihenfolge wie mit dem früheren Vergleich.
    @Test func storeOrdersDuplicateKeysLikeBefore() async throws {
        let container = try QuillStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let date = Date(timeIntervalSince1970: 1000)
        let root = Page(title: "Wurzel")
        context.insert(root)
        var expectedBlocks: [Item] = []
        var expectedChildren: [Item] = []
        for index in 0..<40 {
            let block = Block(text: "Block \(index)")
            block.sortKey = ["a", "b", "b"][index % 3]
            block.createdAt = index % 2 == 0 ? date : date.addingTimeInterval(1)
            context.insert(block)
            block.page = root
            expectedBlocks.append(Item(tag: index, sortKey: block.sortKey, createdAt: block.createdAt, id: block.id))

            let child = Page(title: "Kind \(index)")
            child.sortKey = ["x", "x", "y"][index % 3]
            child.createdAt = index % 4 == 0 ? date : date.addingTimeInterval(2)
            context.insert(child)
            child.parent = root
            expectedChildren.append(Item(tag: index, sortKey: child.sortKey, createdAt: child.createdAt, id: child.id))
        }
        try context.save()
        let store = PageStore(modelContainer: container)

        let blocks = try await store.blocks(of: root.id).map(\.text)
        #expect(blocks == Self.reference(expectedBlocks).map { "Block \($0.tag)" })

        let snapshot = try await store.exportSnapshot(of: root.id, includeSubpages: true)
        #expect(snapshot.children.map(\.title) == Self.reference(expectedChildren).map { "Kind \($0.tag)" })
    }
}
