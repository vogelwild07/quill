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
}
