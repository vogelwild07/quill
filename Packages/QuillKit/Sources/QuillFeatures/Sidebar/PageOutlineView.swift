#if canImport(AppKit)
import AppKit
import Carbon.HIToolbox
import QuillDesign
import QuillEditor
import QuillEditorCore
import QuillModel
import SwiftUI

extension NSPasteboard.PasteboardType {
    /// Gezogene Seite innerhalb der Sidebar (UUID als String).
    static let quillPageID = NSPasteboard.PasteboardType("io.github.vogelwild07.quill.page-id")
    /// Zusätzlich gesetzt, wenn aus den Favoriten gezogen wird.
    static let quillFavoriteDrag = NSPasteboard.PasteboardType("io.github.vogelwild07.quill.favorite-drag")
}

/// Seitenbaum als `NSOutlineView`, darüber die Favoriten als eigener Abschnitt
/// (Gruppenzeilen „Favoriten“ und „Seiten“, ADR-017). Beim Ziehen einer Seite
/// erscheint „Favoriten“ auch leer als Ablageziel.
///
/// AppKit statt SwiftUI-`List`, weil Ziehen zwischen und auf Zeilen in
/// verschachtelten Listen, Umbenennen in der Zeile, Tastatur und Ausklappen beim
/// Ziehen hier nativ und zuverlässig sind.
struct PageOutlineView: NSViewRepresentable {
    var nodes: [PageNode]
    /// Flach, in Favoriten-Reihenfolge; leer blendet den Abschnitt aus (außer beim Ziehen).
    var favorites: [PageNode]
    /// Gelesen in `updateNSView`; SwiftUI ruft es bei jeder Änderung von `pageID` neu auf.
    let selection: PageSelection
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
        // Verschieben im Baum, Kopieren (= als Favorit hinzufügen) in die Favoriten.
        outline.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        outline.setAccessibilityIdentifier("sidebar.pages")
        outline.setAccessibilityLabel(String(localized: "Seiten", bundle: .module))

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
        /// Referenztyp pro Zeile; NSOutlineView braucht stabile Objekte. Eine
        /// favorisierte Seite hat zwei Zeilen, also zwei Items.
        final class Item: NSObject {
            enum Role {
                case favoritesGroup, pagesGroup, favorite, page
            }

            let id: UUID
            let role: Role
            var node: PageNode
            var children: [Item] = []
            weak var parent: Item?

            init(node: PageNode, role: Role) {
                self.id = node.id
                self.role = role
                self.node = node
            }

            var isGroup: Bool {
                switch role {
                case .favoritesGroup, .pagesGroup: true
                case .favorite, .page: false
                }
            }
        }

        weak var outline: NSOutlineView?
        private var parent: PageOutlineView?
        private var nodes: [PageNode] = []
        private var favoriteNodes: [PageNode] = []
        private let favoritesGroup = Item(node: PageNode(id: UUID(), title: String(localized: "Favoriten", bundle: .module)), role: .favoritesGroup)
        private let pagesGroup = Item(node: PageNode(id: UUID(), title: String(localized: "Seiten", bundle: .module)), role: .pagesGroup)
        /// Seiten im Baum.
        private var items: [UUID: Item] = [:]
        private var favoriteItems: [UUID: Item] = [:]
        private var isSyncingSelection = false
        private var hasReloaded = false
        /// „Favoriten“ auch leer zeigen, während eine Seite gezogen wird und kurz
        /// nach dem Ablegen dort.
        private var dropTarget: SidebarSection.DropTarget = .hidden

        /// Regler für Liquid Glass und Theme: Textfarben der sichtbaren Zeilen neu (ADR-036).
        private var glassObservations: [NotificationObservation] = []

        private static let expandedKey = "QuillSidebarExpandedPages"
        private var expanded: Set<UUID> = Set(
            (UserDefaults.standard.stringArray(forKey: expandedKey) ?? []).compactMap(UUID.init(uuidString:))
        )

        func update(from view: PageOutlineView) {
            parent = view
            guard let outline else { return }
            if glassObservations.isEmpty {
                glassObservations = [GlassSettings.didChange, EditorThemeSettings.didChange].map { name in
                    NotificationObservation(name, object: nil) { [weak self] _ in
                        MainActor.assumeIsolated { self?.applyGlassColors() }
                    }
                }
            }
            if view.nodes != nodes || view.favorites != favoriteNodes {
                if !view.favorites.isEmpty { dropTarget = .hidden }
                nodes = view.nodes
                favoriteNodes = view.favorites
                rebuildItems()
                isSyncingSelection = true
                outline.reloadData()
                roots.forEach { outline.expandItem($0) }
                restoreExpansion(in: pagesGroup.children)
                isSyncingSelection = false
                QuillSignposts.sidebarDidReload()
            } else if !hasReloaded {
                // Erster Aufruf ohne Seiten: Die Sidebar steht trotzdem.
                QuillSignposts.sidebarDidReload()
            }
            hasReloaded = true
            syncSelection(to: view.selection.pageID)
            if let id = view.renameRequest {
                DispatchQueue.main.async { [weak self] in
                    self?.beginEditing(id)
                    self?.parent?.renameRequest = nil
                }
            }
        }

        // MARK: Daten

        private var roots: [Item] {
            SidebarSection.visible(hasFavorites: !favoriteNodes.isEmpty, dropTarget: dropTarget).map { section in
                switch section {
                case .favorites: favoritesGroup
                case .pages: pagesGroup
                }
            }
        }

        private func rebuildItems() {
            var reused: [UUID: Item] = [:]
            func make(_ node: PageNode, parent: Item?) -> Item {
                let item = items[node.id] ?? Item(node: node, role: .page)
                item.node = node
                item.parent = parent
                item.children = node.children.map { make($0, parent: item) }
                reused[node.id] = item
                return item
            }
            pagesGroup.children = nodes.map { make($0, parent: nil) }
            items = reused

            var reusedFavorites: [UUID: Item] = [:]
            favoritesGroup.children = favoriteNodes.map { node in
                let item = favoriteItems[node.id] ?? Item(node: node, role: .favorite)
                item.node = node
                reusedFavorites[node.id] = item
                return item
            }
            favoriteItems = reusedFavorites
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
            guard let item = item as? Item else { return false }
            return item.isGroup || !item.children.isEmpty
        }

        // MARK: Gruppen

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            (item as? Item)?.isGroup ?? false
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            !((item as? Item)?.isGroup ?? true)
        }

        /// Gruppen bleiben immer offen (kein „Ausblenden“).
        func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
            !((item as? Item)?.isGroup ?? false)
        }

        func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
            !((item as? Item)?.isGroup ?? false)
        }

        // MARK: Zellen

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Item else { return nil }
            if item.isGroup {
                let identifier = NSUserInterfaceItemIdentifier("GroupCell")
                let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? GroupCellView
                    ?? GroupCellView(identifier: identifier)
                cell.configure(title: item.node.title)
                cell.glassColor = glassStyle(in: outlineView)?.secondaryNSColor
                return cell
            }
            let identifier = NSUserInterfaceItemIdentifier("PageCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? PageCellView
                ?? PageCellView(identifier: identifier)
            cell.configure(with: item.node, isFavoriteRow: item.role == .favorite)
            cell.glassColor = glassStyle(in: outlineView)?.textNSColor
            cell.textField?.delegate = self
            return cell
        }

        /// Stil des Glases für die Darstellung der Sidebar; `nil` bei „Wie System“.
        private func glassStyle(in outlineView: NSOutlineView) -> GlassStyle? {
            GlassStyle.current(dark: outlineView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }

        /// Textfarben der sichtbaren Zeilen nach Regler, Theme und Darstellung.
        func applyGlassColors() {
            guard let outline else { return }
            let style = glassStyle(in: outline)
            outline.enumerateAvailableRowViews { rowView, _ in
                for case let cell as GlassTextColoring in rowView.subviews {
                    cell.glassColor = cell is GroupCellView ? style?.secondaryNSColor : style?.textNSColor
                }
            }
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            nil
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let outline,
                  let item = outline.item(atRow: outline.row(for: field)) as? Item,
                  !item.isGroup
            else { return }
            let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            field.stringValue = title
            parent?.actions.rename(item.id, title, item.node.title)
        }

        /// Bearbeitet den Titel im Baum (Menü „Umbenennen“, neue Seiten).
        private func beginEditing(_ id: UUID) {
            reveal(id)
            guard let item = items[id] else { return }
            beginEditing(item)
        }

        private func beginEditing(_ item: Item) {
            guard let outline else { return }
            let row = outline.row(forItem: item)
            guard row >= 0 else { return }
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.editColumn(0, row: row, with: nil, select: true)
        }

        // MARK: Auswahl

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let outline else { return }
            let id = (outline.item(atRow: outline.selectedRow) as? Item)?.id
            if let selection = parent?.selection, selection.pageID != id {
                if id != nil { QuillSignposts.beginPageSwitch() }
                selection.pageID = id
            }
        }

        /// Ist die Seite schon ausgewählt (auch über ihre Favoriten-Zeile), bleibt es
        /// dabei; sonst wird die Zeile im Baum ausgewählt.
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
            guard let item = notification.userInfo?["NSObject"] as? Item, item.role == .page else { return }
            expanded.insert(item.id)
            saveExpansion()
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isSyncingSelection, let item = notification.userInfo?["NSObject"] as? Item, item.role == .page else { return }
            expanded.remove(item.id)
            saveExpansion()
        }

        private func saveExpansion() {
            UserDefaults.standard.set(expanded.map(\.uuidString), forKey: Self.expandedKey)
        }

        // MARK: Ziehen und Ablegen

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            guard let item = item as? Item, !item.isGroup else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(item.id.uuidString, forType: .quillPageID)
            if item.role == .favorite {
                pasteboardItem.setString("1", forType: .quillFavoriteDrag)
            }
            return pasteboardItem
        }

        /// Ohne Favoriten den leeren Abschnitt einfügen (ohne `reloadData`, das
        /// würde das laufende Ziehen stören).
        func outlineView(
            _ outlineView: NSOutlineView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forItems draggedItems: [Any]
        ) {
            guard favoriteNodes.isEmpty, dropTarget == .hidden, (draggedItems.first as? Item)?.role == .page else { return }
            dropTarget = .dragging
            outlineView.insertItems(at: IndexSet(integer: 0), inParent: nil, withAnimation: QuillDesign.Motion.rowAnimation(.slideDown))
            outlineView.expandItem(favoritesGroup)
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            guard dropTarget == .dragging, favoriteNodes.isEmpty else { return }
            guard operation == .copy else {
                hideEmptyFavorites()
                return
            }
            // Als Favorit abgelegt: Der Abschnitt bleibt, bis er ankommt. Kommt er
            // nicht (Speichern gescheitert), verschwindet der Abschnitt wieder.
            dropTarget = .awaitingFavorite(since: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + SidebarSection.DropTarget.timeout + 0.1) { [weak self] in
                guard let self, self.dropTarget.isExpired(now: .now), self.favoriteNodes.isEmpty else { return }
                self.hideEmptyFavorites()
            }
        }

        private func hideEmptyFavorites() {
            dropTarget = .hidden
            outline?.removeItems(at: IndexSet(integer: 0), inParent: nil, withAnimation: QuillDesign.Motion.rowAnimation(.slideUp))
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard let drop = resolveDrop(info, item: item, index: index) else { return [] }
            // Auf einen Favoriten fallen lassen heißt davor einordnen; so zeigt
            // es auch die Linie statt der Umrandung der Zeile.
            if let target = item as? Item, target.role == .favorite,
               let position = favoritesGroup.children.firstIndex(of: target) {
                outlineView.setDropItem(favoritesGroup, dropChildIndex: position)
            }
            switch drop {
            case .addFavorite: return .copy
            case .moveFavorite, .movePage: return .move
            }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: any NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let dragged = draggedID(info), let drop = resolveDrop(info, item: item, index: index) else { return false }
            switch drop {
            case .movePage(let parentID, let position):
                if let parentID, index == NSOutlineViewDropOnItemIndex {
                    expanded.insert(parentID)
                    saveExpansion()
                }
                parent?.actions.move(dragged, parentID, position)
            case .addFavorite(let position):
                parent?.actions.setFavorite(dragged, true, position)
            case .moveFavorite(let position):
                parent?.actions.moveFavorite(dragged, position)
            }
            return true
        }

        private func resolveDrop(_ info: any NSDraggingInfo, item: Any?, index: Int) -> SidebarDrop? {
            guard let dragged = draggedID(info), let target = item as? Item else { return nil }
            let source: SidebarDrop.Source = info.draggingPasteboard.string(forType: .quillFavoriteDrag) == nil ? .page : .favorite
            let dropTarget: SidebarDrop.Target = switch target.role {
            case .favoritesGroup: .favorites
            case .pagesGroup: .pages
            case .favorite: .favorite(target.id)
            case .page: .page(target.id)
            }
            return SidebarDrop.resolve(
                dragged, from: source, onto: dropTarget,
                childIndex: index == NSOutlineViewDropOnItemIndex ? nil : index,
                favorites: favoriteNodes.map(\.id), tree: nodes
            )
        }

        private func draggedID(_ info: any NSDraggingInfo) -> UUID? {
            info.draggingPasteboard.string(forType: .quillPageID).flatMap(UUID.init(uuidString:))
        }

        // MARK: Kontextmenü und Tastatur

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline else { return }
            let clicked = (outline.item(atRow: outline.clickedRow) as? Item)
            guard let clicked, !clicked.isGroup else {
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
                self?.beginEditing(clicked)
            })
            menu.addItem(.separator())
            menu.addItem(menuItem(String(localized: "In neuem Tab öffnen", bundle: .module)) { [weak self] in
                self?.parent?.actions.openInTab(id)
            })
            menu.addItem(menuItem(String(localized: "In neuem Fenster öffnen", bundle: .module)) { [weak self] in
                self?.parent?.actions.openInWindow(id)
            })
            menu.addItem(.separator())
            menu.addItem(menuItem(String(localized: "Exportieren …", bundle: .module)) { [weak self] in
                self?.parent?.actions.export(id)
            })
            menu.addItem(.separator())
            if favoriteItems[id] != nil {
                menu.addItem(menuItem(String(localized: "Aus Favoriten entfernen", bundle: .module)) { [weak self] in
                    self?.parent?.actions.setFavorite(id, false, .last)
                })
            } else {
                menu.addItem(menuItem(String(localized: "Zu Favoriten hinzufügen", bundle: .module)) { [weak self] in
                    self?.parent?.actions.setFavorite(id, true, .last)
                })
            }
            menu.addItem(menuItem(String(localized: "In den Papierkorb legen", bundle: .module)) { [weak self] in
                self?.parent?.actions.trash(id)
            })
            if clicked.node.isRestored {
                menu.addItem(.separator())
                menu.addItem(menuItem(String(localized: "Markierung entfernen", bundle: .module)) { [weak self] in
                    self?.parent?.actions.clearRestored(id)
                })
            }
        }

        private func menuItem(_ title: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            let target = MenuAction(action)
            item.target = target
            item.representedObject = target
            return item
        }

        /// ↩ benennt um, ⌘⌫ legt in den Papierkorb (auch aus den Favoriten heraus).
        func moveFocus(to target: PageFocusTarget) {
            parent?.actions.focusPage(target)
        }

        func handleKey(_ event: NSEvent) -> Bool {
            guard let outline, let item = outline.item(atRow: outline.selectedRow) as? Item, !item.isGroup else { return false }
            // Nur echte Modifikatoren; .function/.numericPad hängen je nach Tastatur dran.
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            switch (event.keyCode, modifiers) {
            case (36, []), (76, []):
                beginEditing(item)
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

    /// Hell und dunkel haben eigene Textfarben auf dem Glas (ADR-036).
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        coordinator?.applyGlassColors()
    }

    /// Ein Klick holt den Tastaturfokus in die Sidebar (wie im Finder), auch wenn
    /// vorher das Titelfeld der Seite fokussiert war. Sonst landen ↩ und ⌘⌫ dort.
    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    /// Tab verlässt die Sidebar zum Titel, ⇧Tab zum Editor (`WindowFocus`), statt in
    /// das Titelfeld einer Zeile zu springen. Mit ⌃ genauso.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Tab), let coordinator {
            coordinator.moveFocus(to: event.modifierFlags.contains(.shift) ? .editor : .title)
            return
        }
        if coordinator?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }
}

/// Zelle mit eigener Textfarbe auf dem Glas von Quill (ADR-036). Nur in nicht
/// ausgewählten Zeilen: Auf der Auswahl gelten die Farben des Systems.
@MainActor
protocol GlassTextColoring: NSTableCellView {
    var glassColor: NSColor? { get set }
}

/// Merkt sich die Farbe des Systems, solange eine eigene gilt, und setzt sie danach zurück.
@MainActor
final class GlassTextColor {
    private var systemColor: NSColor?

    func apply(_ glassColor: NSColor?, to field: NSTextField?, style: NSView.BackgroundStyle) {
        guard let field else { return }
        if let glassColor, style == .normal {
            if systemColor == nil { systemColor = field.textColor }
            field.textColor = glassColor
        } else if let systemColor {
            field.textColor = systemColor
            self.systemColor = nil
        }
    }
}

/// Überschrift eines Abschnitts („Favoriten“, „Seiten“).
final class GroupCellView: NSTableCellView, GlassTextColoring {
    private let glassText = GlassTextColor()
    var glassColor: NSColor? {
        didSet { needsDisplay = true }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { needsDisplay = true }
    }

    override func viewWillDraw() {
        glassText.apply(glassColor, to: textField, style: backgroundStyle)
        super.viewWillDraw()
    }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        // Schrift und Farbe setzt die Source-List für Gruppenzeilen selbst (Befund A10).
        let title = NSTextField(labelWithString: "")
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        textField = title
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        textField?.stringValue = title
        textField?.setAccessibilityIdentifier("sidebar.group")
    }
}

/// Zeile: Emoji oder Symbol, dann bearbeitbarer Titel.
final class PageCellView: NSTableCellView, GlassTextColoring {
    private let glassText = GlassTextColor()
    var glassColor: NSColor? {
        didSet { needsDisplay = true }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { needsDisplay = true }
    }

    override func viewWillDraw() {
        glassText.apply(glassColor, to: textField, style: backgroundStyle)
        super.viewWillDraw()
    }

    private let iconLabel = NSTextField(labelWithString: "")
    private let symbolView = DecorativeImageView()
    /// Marke „wiederhergestellt“ am Zeilenende (11.6); VoiceOver hört sie im Wert der Zeile.
    private let restoredView = DecorativeImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        symbolView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        symbolView.contentTintColor = .secondaryLabelColor
        symbolView.symbolConfiguration = .init(scale: .medium)
        iconLabel.alignment = .center
        restoredView.image = NSImage(systemSymbolName: "arrow.uturn.backward.circle", accessibilityDescription: nil)
        restoredView.contentTintColor = .secondaryLabelColor
        restoredView.symbolConfiguration = .init(scale: .small)
        restoredView.toolTip = String(localized: "Wiederhergestellt nach dem Abgleich", bundle: .module)
        restoredView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let title = NSTextField(labelWithString: "")
        title.isEditable = true
        title.isSelectable = true
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.placeholderString = String(localized: "Ohne Titel", bundle: .module)
        textField = title

        for view in [symbolView, iconLabel, title, restoredView] as [NSView] {
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
            title.trailingAnchor.constraint(equalTo: restoredView.leadingAnchor, constant: -4),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            restoredView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            restoredView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with node: PageNode, isFavoriteRow: Bool) {
        // Am Titelfeld: Den Identifier der Zelle reicht die Outline nicht an AX weiter.
        textField?.setAccessibilityIdentifier(isFavoriteRow ? "sidebar.favorite" : "sidebar.page")
        textField?.stringValue = node.title
        let icon = node.icon ?? ""
        iconLabel.stringValue = icon
        iconLabel.isHidden = icon.isEmpty
        symbolView.isHidden = !icon.isEmpty
        restoredView.isHidden = !node.isRestored
        setAccessibilityLabel(PageLabel.title(node.title))
        // Leeres Feld: Der Platzhalter reicht AX nicht als Beschreibung, sonst liest der Wert.
        textField?.setAccessibilityLabel(node.title.isEmpty ? PageLabel.title(node.title) : nil)
        textField?.setAccessibilityValueDescription(
            node.isRestored ? String(localized: "Wiederhergestellt nach dem Abgleich", bundle: .module) : nil
        )
    }
}

/// Bild nur als Schmuck: VoiceOver liest den Titel der Zeile, nicht den Namen des
/// Symbols („Textdokument“, Befund A9). Erst ohne Element und ohne Rolle
/// verschwindet das Bild; `setAccessibilityElement(false)` allein reicht nicht.
final class DecorativeImageView: NSImageView {
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { nil }
}
#endif
