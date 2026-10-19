#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import Testing
import QuillModel
@testable import QuillFeatures

/// Auswahl der Sidebar nach einem Verschieben und bei Auswahl von außen. XCUITest kann in der `NSOutlineView`
/// nicht ziehen (`SidebarUITests.testDragOntoPageNestsIt`); deshalb hier mit dem
/// echten `PageOutlineView` in einem `NSHostingView`: Der Baum ändert sich wie nach
/// einem Drop, die Auswahl muss an derselben Seite bleiben.
@MainActor
@Suite("Sidebar-Auswahl")
struct PageOutlineSelectionTests {
    @MainActor
    @Observable
    final class Model {
        var nodes: [PageNode]
        let selection = PageSelection()
        init(nodes: [PageNode], selection: UUID?) {
            self.nodes = nodes
            self.selection.pageID = selection
        }
    }

    struct Host: View {
        @Bindable var model: Model
        let actions = PageOutlineActions()
        var body: some View {
            PageOutlineView(
                nodes: model.nodes,
                favorites: [],
                selection: model.selection,
                renameRequest: .constant(nil),
                actions: actions
            )
        }
    }

    let a = UUID(), a1 = UUID(), b = UUID()

    func node(_ id: UUID, _ title: String, _ children: [PageNode] = []) -> PageNode {
        PageNode(id: id, title: title, children: children)
    }

    func host(_ model: Model) -> (NSHostingView<Host>, NSOutlineView) {
        let hosting = NSHostingView(rootView: Host(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        hosting.layoutSubtreeIfNeeded()
        let outline = try! #require(Self.outline(in: hosting))
        return (hosting, outline)
    }

    static func outline(in view: NSView) -> NSOutlineView? {
        if let outline = view as? NSOutlineView { return outline }
        return view.subviews.lazy.compactMap(outline(in:)).first
    }

    /// Wartet, bis `condition` gilt; SwiftUI überträgt Änderungen erst im nächsten
    /// Durchlauf der Run Loop.
    func settle(_ hosting: NSView, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    func selected(_ outline: NSOutlineView) -> (id: UUID?, parent: UUID?) {
        let item = outline.item(atRow: outline.selectedRow) as? PageOutlineView.Coordinator.Item
        return (item?.id, item?.parent?.id)
    }

    /// Die neue Elternseite ist zugeklappt; die Auswahl klappt sie auf (`reveal`).
    @Test func selectionFollowsPageIntoNewParent() {
        let model = Model(nodes: [node(a, "A", [node(a1, "A1")]), node(b, "B")], selection: a1)
        let (hosting, outline) = host(model)
        settle(hosting) { selected(outline).id == a1 }
        #expect(selected(outline).id == a1)
        #expect(selected(outline).parent == a)

        // A1 unter B verschoben
        model.nodes = [node(a, "A"), node(b, "B", [node(a1, "A1")])]
        settle(hosting) { selected(outline).parent == b }
        #expect(selected(outline).id == a1)
        #expect(selected(outline).parent == b)
        #expect(model.selection.pageID == a1)

        // A1 auf die oberste Ebene, vor A
        model.nodes = [node(a1, "A1"), node(a, "A"), node(b, "B")]
        settle(hosting) { selected(outline).parent == nil && outline.selectedRow >= 0 }
        #expect(selected(outline).id == a1)
        #expect(selected(outline).parent == nil)
        #expect(model.selection.pageID == a1)
    }

    /// Auswahl von außen (⌘O, nach dem Löschen): Die Outline folgt, obwohl sich der
    /// Baum nicht ändert und `PageOutlineView` keinen neuen Wert bekommt.
    @Test func outlineFollowsSelectionFromOutside() {
        let model = Model(nodes: [node(a, "A", [node(a1, "A1")]), node(b, "B")], selection: b)
        let (hosting, outline) = host(model)
        settle(hosting) { selected(outline).id == b }
        #expect(selected(outline).id == b)

        model.selection.pageID = a1
        settle(hosting) { selected(outline).id == a1 }
        #expect(selected(outline).id == a1)

        model.selection.pageID = nil
        settle(hosting) { outline.selectedRow < 0 }
        #expect(outline.selectedRow < 0)
    }

    /// Gleiche Objekte und gleiche Werte der Bindings: gleich, auch wenn die Bindings
    /// neu gebaut sind. Nur so baut ein Seitenwechsel den Seitenbaum nicht neu.
    @Test func sidebarViewComparesObjectsByIdentityAndBindingsByValue() {
        let selection = PageSelection()
        let actions = PageOutlineActions()
        let request = UUID()
        func view(_ selection: PageSelection, _ actions: PageOutlineActions, rename: UUID?, trash: Bool) -> SidebarView {
            SidebarView(selection: selection, renameRequest: .constant(rename), isShowingTrash: .constant(trash), actions: actions)
        }
        let base = view(selection, actions, rename: request, trash: false)
        selection.pageID = UUID()
        #expect(base == view(selection, actions, rename: request, trash: false))
        #expect(base != view(PageSelection(), actions, rename: request, trash: false))
        #expect(base != view(selection, PageOutlineActions(), rename: request, trash: false))
        #expect(base != view(selection, actions, rename: nil, trash: false))
        #expect(base != view(selection, actions, rename: request, trash: true))
    }
}
#endif
