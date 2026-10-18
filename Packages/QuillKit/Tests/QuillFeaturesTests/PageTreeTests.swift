import Foundation
import Testing
import QuillModel
@testable import QuillFeatures

@Suite struct PageTreeTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()

    func entry(_ id: UUID, _ title: String, parent: UUID? = nil, key: String) -> PageTree.Entry {
        PageTree.Entry(id: id, parentID: parent, title: title, icon: nil, sortKey: key, createdAt: .distantPast)
    }

    @Test func buildsSortedTree() {
        let tree = PageTree.build([
            entry(b, "B", key: "W"),
            entry(a, "A", key: "V"),
            entry(d, "D", parent: a, key: "W"),
            entry(c, "C", parent: a, key: "V"),
        ])
        #expect(tree.map(\.title) == ["A", "B"])
        #expect(tree[0].children.map(\.title) == ["C", "D"])
        #expect(tree[1].children.isEmpty)
    }

    @Test func pagesUnderMissingParentAreHidden() {
        let trashedParent = UUID()
        let tree = PageTree.build([
            entry(a, "A", key: "V"),
            entry(b, "Unter Papierkorb", parent: trashedParent, key: "V"),
        ])
        #expect(tree.map(\.title) == ["A"])
    }

    @Test func dropPositionSkipsDraggedPage() {
        let siblings = [a, b, c]
        #expect(PageTree.dropPosition(of: d, into: siblings, at: 0) == .first)
        #expect(PageTree.dropPosition(of: d, into: siblings, at: 2) == .after(b))
        #expect(PageTree.dropPosition(of: d, into: siblings, at: 3) == .after(c))
        // b zwischen a und c fallen lassen ändert nichts: nach a.
        #expect(PageTree.dropPosition(of: b, into: siblings, at: 2) == .after(a))
        // a ans Ende: nach c.
        #expect(PageTree.dropPosition(of: a, into: siblings, at: 3) == .after(c))
        // a an den Anfang: first.
        #expect(PageTree.dropPosition(of: a, into: siblings, at: 0) == .first)
        #expect(PageTree.dropPosition(of: a, into: siblings, at: 1) == .first)
        #expect(PageTree.dropPosition(of: d, into: siblings, at: 99) == .after(c))
    }

    @Test func descendantsAndAncestors() {
        let tree = [
            PageNode(id: a, title: "A", children: [
                PageNode(id: b, title: "B", children: [PageNode(id: c, title: "C")]),
            ]),
            PageNode(id: d, title: "D"),
        ]
        #expect(PageTree.isSelfOrDescendant(c, of: a, in: tree))
        #expect(PageTree.isSelfOrDescendant(a, of: a, in: tree))
        #expect(!PageTree.isSelfOrDescendant(a, of: c, in: tree))
        #expect(!PageTree.isSelfOrDescendant(d, of: a, in: tree))
        #expect(PageTree.ancestors(of: c, in: tree) == [a, b])
        #expect(PageTree.ancestors(of: d, in: tree) == [])
        #expect(PageTree.ancestors(of: e, in: tree) == nil)
    }

    // MARK: Favoriten (ADR-017)

    @Test func favoritesAreOrderedAndSkipTrashedSubtrees() {
        let trashedParent = UUID()
        let entries = [
            PageTree.Entry(id: a, parentID: nil, title: "A", icon: nil, sortKey: "V", createdAt: .distantPast, isFavorite: true, favoriteSortKey: "W"),
            PageTree.Entry(id: b, parentID: nil, title: "B", icon: nil, sortKey: "W", createdAt: .distantPast, isFavorite: true, favoriteSortKey: "V"),
            PageTree.Entry(id: c, parentID: a, title: "C", icon: nil, sortKey: "V", createdAt: .distantPast),
            PageTree.Entry(id: d, parentID: trashedParent, title: "D", icon: nil, sortKey: "V", createdAt: .distantPast, isFavorite: true, favoriteSortKey: "U"),
        ]
        let favorites = PageTree.favorites(entries, in: PageTree.build(entries))
        #expect(favorites.map(\.title) == ["B", "A"])
        #expect(favorites.flatMap(\.children).isEmpty)
    }

    @Test func dropsIntoFavorites() {
        let tree = PageTree.build([entry(a, "A", key: "V"), entry(b, "B", key: "W"), entry(c, "C", key: "X")])
        let favorites = [a, b]
        func resolve(_ dragged: UUID, _ source: SidebarDrop.Source, _ target: SidebarDrop.Target, _ index: Int?) -> SidebarDrop? {
            SidebarDrop.resolve(dragged, from: source, onto: target, childIndex: index, favorites: favorites, tree: tree)
        }
        // Aus dem Baum: auf die Gruppe ans Ende, zwischen Favoriten an die Stelle.
        #expect(resolve(c, .page, .favorites, nil) == .addFavorite(.last))
        #expect(resolve(c, .page, .favorites, 1) == .addFavorite(.after(a)))
        #expect(resolve(c, .page, .favorite(a), nil) == .addFavorite(.first))
        // Schon Favorit: auf die Gruppe nichts, zwischen Favoriten verschieben.
        #expect(resolve(a, .page, .favorites, nil) == nil)
        #expect(resolve(a, .page, .favorites, 2) == .moveFavorite(.after(b)))
        // Innerhalb der Favoriten umsortieren; nicht auf sich selbst.
        #expect(resolve(b, .favorite, .favorites, 0) == .moveFavorite(.first))
        #expect(resolve(b, .favorite, .favorite(a), nil) == .moveFavorite(.first))
        #expect(resolve(b, .favorite, .favorite(b), nil) == nil)
        #expect(resolve(b, .favorite, .favorites, nil) == nil)
    }

    @Test func dropsIntoPageTree() {
        let tree = PageTree.build([entry(a, "A", key: "V"), entry(b, "B", parent: a, key: "V"), entry(c, "C", key: "W")])
        func resolve(_ dragged: UUID, _ source: SidebarDrop.Source, _ target: SidebarDrop.Target, _ index: Int?) -> SidebarDrop? {
            SidebarDrop.resolve(dragged, from: source, onto: target, childIndex: index, favorites: [], tree: tree)
        }
        #expect(resolve(c, .page, .pages, 0) == .movePage(parentID: nil, position: .first))
        #expect(resolve(c, .page, .pages, nil) == .movePage(parentID: nil, position: .last))
        #expect(resolve(c, .page, .page(a), nil) == .movePage(parentID: a, position: .last))
        #expect(resolve(c, .page, .page(a), 1) == .movePage(parentID: a, position: .after(b)))
        // Zyklen und Favoriten in den Baum sind nicht erlaubt.
        #expect(resolve(a, .page, .page(b), nil) == nil)
        #expect(resolve(a, .page, .page(a), nil) == nil)
        #expect(resolve(c, .favorite, .pages, 0) == nil)
        #expect(resolve(c, .favorite, .page(a), nil) == nil)
    }
}
