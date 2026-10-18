#if canImport(AppKit)
import AppKit
import QuillModel
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// Gezogene Seite innerhalb der Sidebar (UUID als String).
    static let quillPageID = NSPasteboard.PasteboardType("de.vogel.quill.page-id")
}

/// Seitenbaum als `NSOutlineView`.
///
/// AppKit statt SwiftUI-`List`, weil Ziehen zwischen und auf Zeilen in
/// verschachtelten Listen, Umbenennen in der Zeile, Tastatur und Ausklappen beim
/// Ziehen hier nativ und zuverlässig sind.
struct PageOutlineView: NSViewRepresentable {
    var nodes: [PageNode]
    @Binding var selection: UUID?
    /// Seite, deren Titel in der Zeile bearbeitet werden soll; wird danach zurückgesetzt.
    @Binding var renameRequest: UUID?
    var actions: PageOutlineActions

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = PageOutlineTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.isEditable = true
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.backgroundColor = .clear
        outline.autoresizesOutlineColumn = true
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.registerForDraggedTypes([.quillPageID])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setAccessibilityIdentifier("sidebar.pages")

        let coordinator = context.coordinator
        coordinator.outline = outline
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.coordinator = coordinator
        let menu = NSMenu()
        menu.delegate = coordinator
        outline.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(from: self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSTextFieldDelegate {
        /// Referenztyp pro Seite; NSOutlineView braucht stabile Objekte.
        final class Item: NSObject {
            let id: UUID
            var node: PageNode
            var children: [Item] = []
            weak var parent: Item?

            init(node: PageNode) {
                self.id = node.id
                self.node = node
            }
        }

        weak var outline: NSOutlineView?
        private var parent: PageOutlineView?
        private var nodes: [PageNode] = []
        private var roots: [Item] = []
        private var items: [UUID: Item] = [:]
        private var isSyncingSelection = false

        private static let expandedKey = "QuillSidebarExpandedPages"
        private var expanded: Set<UUID> = Set(
            (UserDefaults.standard.stringArray(forKey: expandedKey) ?? []).compactMap(UUID.init(uuidString:))
        )

        func update(from view: PageOutlineView) {
            parent = view
            guard let outline else { return }
            if view.nodes != nodes {
                nodes = view.nodes
                rebuildItems()
                isSyncingSelection = true
                outline.reloadData()
                restoreExpansion(in: roots)
                isSyncingSelection = false
            }
            syncSelection(to: view.selection)
            if let id = view.renameRequest {
                DispatchQueue.main.async { [weak self] in
                    self?.beginEditing(id)
                    self?.parent?.renameRequest = nil
                }
            }
        }

        // MARK: Daten

        private func rebuildItems() {
            var reused: [UUID: Item] = [:]
            func make(_ node: PageNode, parent: Item?) -> Item {
                let item = items[node.id] ?? Item(node: node)
                item.node = node
                item.parent = parent
                item.children = node.children.map { make($0, parent: item) }
                reused[node.id] = item
                return item
            }
            roots = nodes.map { make($0, parent: nil) }
            items = reused
        }

        private func restoreExpansion(in items: [Item]) {
            for item in items where expanded.contains(item.id) && !item.children.isEmpty {
                outline?.expandItem(item)
                restoreExpansion(in: item.children)
            }
        }

        private func children(of item: Any?) -> [Item] {
            (item as? Item)?.children ?? roots
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            !((item as? Item)?.children.isEmpty ?? true)
        }

        // MARK: Zellen

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Item else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("PageCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? PageCellView
                ?? PageCellView(identifier: identifier)
            cell.configure(with: item.node)
            cell.textField?.delegate = self
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            nil
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let outline,
                  let item = outline.item(atRow: outline.row(for: field)) as? Item
            else { return }
            let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.stringValue = title
            parent?.actions.rename(item.id, title, item.node.title)
        }

        private func beginEditing(_ id: UUID) {
            guard let outline else { return }
            reveal(id)
            guard let item = items[id] else { return }
            let row = outline.row(forItem: item)
            guard row >= 0 else { return }
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.editColumn(0, row: row, with: nil, select: true)
        }

        // MARK: Auswahl

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let outline else { return }
            let id = (outline.item(atRow: outline.selectedRow) as? Item)?.id
            if parent?.selection != id {
                parent?.selection = id
            }
        }

        private func syncSelection(to id: UUID?) {
            guard let outline else { return }
            let current = (outline.item(atRow: outline.selectedRow) as? Item)?.id
            guard current != id else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            guard let id, items[id] != nil else {
                outline.deselectAll(nil)
                return
            }
            reveal(id)
            let row = outline.row(forItem: items[id])
            if row >= 0 {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
        }

        /// Klappt alle Vorfahren auf, damit die Seite sichtbar ist.
        private func reveal(_ id: UUID) {
            var chain: [Item] = []
            var current = items[id]?.parent
            while let item = current {
                chain.insert(item, at: 0)
                current = item.parent
            }
            chain.forEach { outline?.expandItem($0) }
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let item = notification.userInfo?["NSObject"] as? Item else { return }
            expanded.insert(item.id)
            saveExpansion()
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isSyncingSelection, let item = notification.userInfo?["NSObject"] as? Item else { return }
            expanded.remove(item.id)
            saveExpansion()
        }

        private func saveExpansion() {
            UserDefaults.standard.set(expanded.map(\.uuidString), forKey: Self.expandedKey)
        }

        // MARK: Ziehen und Ablegen

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let item = item as? Item else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(item.id.uuidString, forType: .quillPageID)
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard let dragged = draggedID(info) else { return [] }
            if let target = item as? Item, PageTree.isSelfOrDescendant(target.id, of: dragged, in: nodes) {
                return []
            }
            return .move
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: any NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let dragged = draggedID(info) else { return false }
            let target = item as? Item
            if let target, PageTree.isSelfOrDescendant(target.id, of: dragged, in: nodes) {
                return false
            }
            let position: SiblingPosition
            if index == NSOutlineViewDropOnItemIndex {
                position = .last
                if let target {
                    expanded.insert(target.id)
                    saveExpansion()
                }
            } else {
                position = PageTree.dropPosition(of: dragged, into: children(of: target).map(\.id), at: index)
            }
            parent?.actions.move(dragged, target?.id, position)
            return true
        }

        private func draggedID(_ info: any NSDraggingInfo) -> UUID? {
            info.draggingPasteboard.string(forType: .quillPageID).flatMap(UUID.init(uuidString:))
        }

        // MARK: Kontextmenü und Tastatur

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline else { return }
            let clicked = (outline.item(atRow: outline.clickedRow) as? Item)
            guard let clicked else {
                menu.addItem(menuItem(String(localized: "Neue Seite", bundle: .module)) { [weak self] in
                    self?.parent?.actions.create(nil)
                })
                return
            }
            let id = clicked.id
            menu.addItem(menuItem(String(localized: "Neue Unterseite", bundle: .module)) { [weak self] in
                self?.parent?.actions.create(id)
            })
            menu.addItem(menuItem(String(localized: "Umbenennen", bundle: .module)) { [weak self] in
                self?.beginEditing(id)
            })
            menu.addItem(.separator())
            menu.addItem(menuItem(String(localized: "In neuem Tab öffnen", bundle: .module)) { [weak self] in
                self?.parent?.actions.openInTab(id)
            })
            menu.addItem(menuItem(String(localized: "In neuem Fenster öffnen", bundle: .module)) { [weak self] in
                self?.parent?.actions.openInWindow(id)
            })
            menu.addItem(.separator())
            menu.addItem(menuItem(String(localized: "In den Papierkorb legen", bundle: .module)) { [weak self] in
                self?.parent?.actions.trash(id)
            })
        }

        private func menuItem(_ title: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            let target = MenuAction(action)
            item.target = target
            item.representedObject = target
            return item
        }

        /// ↩ benennt um, ⌘⌫ legt in den Papierkorb.
        func handleKey(_ event: NSEvent) -> Bool {
            guard let outline, let item = outline.item(atRow: outline.selectedRow) as? Item else { return false }
            // Nur echte Modifikatoren; .function/.numericPad hängen je nach Tastatur dran.
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            switch (event.keyCode, modifiers) {
            case (36, []), (76, []):
                beginEditing(item.id)
                return true
            case (51, .command):
                parent?.actions.trash(item.id)
                return true
            default:
                return false
            }
        }
    }
}

/// Führt eine Closure aus einem `NSMenuItem` aus.
@MainActor
private final class MenuAction: NSObject {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @objc func run() { action() }
}

/// Outline mit eigener Tastaturbehandlung.
final class PageOutlineTableView: NSOutlineView {
    weak var coordinator: PageOutlineView.Coordinator?

    /// Ein Klick holt den Tastaturfokus in die Sidebar (wie im Finder), auch wenn
    /// vorher das Titelfeld der Seite fokussiert war. Sonst landen ↩ und ⌘⌫ dort.
    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if coordinator?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }
}

/// Zeile: Emoji oder Symbol, dann bearbeitbarer Titel.
final class PageCellView: NSTableCellView {
    private let iconLabel = NSTextField(labelWithString: "")
    private let symbolView = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        symbolView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        symbolView.contentTintColor = .secondaryLabelColor
        symbolView.symbolConfiguration = .init(scale: .medium)
        iconLabel.alignment = .center

        let title = NSTextField(labelWithString: "")
        title.isEditable = true
        title.isSelectable = true
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.placeholderString = String(localized: "Ohne Titel", bundle: .module)
        textField = title

        for view in [symbolView, iconLabel, title] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 18),
            iconLabel.centerXAnchor.constraint(equalTo: symbolView.centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with node: PageNode) {
        textField?.stringValue = node.title
        let icon = node.icon ?? ""
        iconLabel.stringValue = icon
        iconLabel.isHidden = icon.isEmpty
        symbolView.isHidden = !icon.isEmpty
        setAccessibilityLabel(node.title.isEmpty ? String(localized: "Ohne Titel", bundle: .module) : node.title)
    }
}
#endif
