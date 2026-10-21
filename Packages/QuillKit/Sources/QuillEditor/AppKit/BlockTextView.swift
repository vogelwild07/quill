#if canImport(AppKit)
import AppKit
import Carbon.HIToolbox
import QuillDesign
import QuillEditorCore
import QuillModel

/// Kopf mit eigener Höhenberechnung (z. B. ein `NSHostingView` mit mehrzeiligem Titel).
@MainActor
protocol HeaderSizing {
    func height(forWidth width: CGFloat) -> CGFloat
}

/// Text-View des Block-Editors. Strukturelle Logik liegt im `BlockEditorController`;
/// hier sitzen nur Ereignisse, die eine View braucht.
final class BlockTextView: NSTextView, EditorFormattingActions {
    weak var editor: BlockEditorController?

    let handle = BlockHandleView()
    let insertButton = BlockInsertButton()
    private let dropIndicator = NSView()
    private var hoverTrackingArea: NSTrackingArea?
    /// Checkboxen für VoiceOver, pro Block (`BlockTextView+Accessibility`).
    var checkboxElements: [UUID: CheckboxAccessibilityElement] = [:]
    /// Zeichen am rechten Rand für VoiceOver, pro Block (`BlockEditorController+Markers`).
    var markerElements: [UUID: MarkerAccessibilityElement] = [:]
    /// Zuletzt gezeichneter Stand des Hinweises (`BlockTextView+EmptyPageHint`).
    var isShowingEmptyPageHint = false

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        handle.isHidden = true
        handle.textView = self
        addSubview(handle)
        insertButton.isHidden = true
        insertButton.textView = self
        addSubview(insertButton)
        dropIndicator.wantsLayer = true
        updateLayerColors()
        dropIndicator.layer?.cornerRadius = 1
        dropIndicator.isHidden = true
        addSubview(dropIndicator)
    }

    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
        editor?.updateHeaderDimming()
    }

    /// Ebenen kennen keine dynamischen Farben; nach Theme- oder Darstellungswechsel neu setzen.
    func updateLayerColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dropIndicator.layer?.backgroundColor = EditorColor.accent.cgColor
        }
    }

    // MARK: Layout: zentrierte Textspalte

    /// Abstand über dem Text bzw. über dem Kopf.
    var topPadding: CGFloat = QuillDesign.EditorLayout.topPadding {
        didSet { needsLayout = true }
    }

    /// Kopf über dem ersten Block (Icon und Titel der Seite). Sitzt im oberen
    /// Inset, scrollt also mit dem Text.
    var headerView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let headerView { addSubview(headerView) }
            needsLayout = true
        }
    }

    /// Fokus-Modus: Unter dem Text eine halbe Fensterhöhe Platz, damit auch die letzte
    /// Zeile in die Mitte scrollen kann (`BlockEditorController+Focus`).
    var isTypewriterScrolling = false {
        didSet {
            guard oldValue != isTypewriterScrolling else { return }
            // `sizeToFit` setzt die Größe nur, wenn sie sich ändert; beim Einschalten
            // braucht `setFrameSize` den Platz aber auch bei gleicher Texthöhe.
            sizeToFit()
            setFrameSize(frame.size)
        }
    }

    /// Höhe, die die Text-View selbst zuletzt verlangt hat, und die daraus gesetzte.
    /// Eine verlangte Höhe gleich der gesetzten ist die aktuelle Größe (z. B. bei
    /// Breitenänderung) und bekommt den Platz kein zweites Mal.
    private var typewriterHeights: (natural: CGFloat, applied: CGFloat)?

    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if isTypewriterScrolling, let clip = enclosingScrollView?.contentView {
            let natural = typewriterHeights.map { abs($0.applied - newSize.height) < 0.5 ? $0.natural : newSize.height } ?? newSize.height
            size.height = natural + ceil(clip.bounds.height / 2)
            typewriterHeights = (natural, size.height)
        } else {
            typewriterHeights = nil
        }
        super.setFrameSize(size)
        updateInsets()
    }

    override func layout() {
        super.layout()
        updateInsets()
    }

    /// Zentrierte Textspalte; oben Platz für den Kopf.
    private func updateInsets() {
        let side = max(QuillDesign.EditorLayout.minSideMargin, (bounds.width - QuillDesign.contentMaxWidth) / 2)
        var top = topPadding
        if let headerView {
            let padding = textContainer?.lineFragmentPadding ?? 5
            let width = max(0, bounds.width - 2 * side - 2 * padding)
            let height = headerHeight(headerView, width: width)
            headerView.frame = CGRect(x: side + padding, y: topPadding, width: width, height: height)
            top += height + QuillDesign.EditorLayout.headerGap
        }
        if abs(textContainerInset.width - side) > 0.5 || abs(textContainerInset.height - top) > 0.5 {
            textContainerInset = NSSize(width: side, height: top)
        }
    }

    private func headerHeight(_ view: NSView, width: CGFloat) -> CGFloat {
        if let sizing = view as? any HeaderSizing {
            return ceil(sizing.height(forWidth: width))
        }
        return view.fittingSize.height
    }

    /// Der Kopf ist für VoiceOver und XCUITest ein Kind der Text-View.
    override func accessibilityChildren() -> [Any]? {
        prepareAttachmentCells()
        var children = super.accessibilityChildren() ?? []
        if let headerView, !children.contains(where: { ($0 as AnyObject) === headerView }) {
            children.insert(headerView, at: 0)
        }
        // Griff und ＋ nur, solange sie zu sehen sind.
        for view in [handle, insertButton] as [NSView] where !view.isHidden
            && !children.contains(where: { ($0 as AnyObject) === view }) {
            children.append(view)
        }
        children.append(contentsOf: checkboxAccessibilityElements())
        children.append(contentsOf: markerAccessibilityElements())
        return children
    }

    /// ⌃Tab verlässt den Editor zur Sidebar, ⇧⌃Tab zum Titel; Tab allein rückt ein.
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == UInt16(kVK_Tab), !hasMarkedText(), let editor {
            switch modifiers {
            case .control:
                if let exit = editor.onExitForward { exit(); return }
            case [.control, .shift]:
                if let exit = editor.onExitTop { exit(); return }
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    /// Fokus woanders (Sidebar, anderer Tab): Slash-Menü schließen, im Fokus-Modus
    /// nichts mehr abdunkeln.
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            editor?.slashMenu.close()
            editor?.scheduleFocusUpdate()
        }
        return resigned
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { editor?.scheduleFocusUpdate() }
        return became
    }

    // MARK: Auswahl nie hinter das abschließende `\n` des letzten Blocks

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        let limit = max(0, (textStorage?.length ?? 0) - 1)
        let clamped = ranges.map { value -> NSValue in
            let range = value.rangeValue
            let location = min(range.location, limit)
            let end = min(NSMaxRange(range), limit)
            return NSValue(range: NSRange(location: location, length: max(0, end - location)))
        }
        super.setSelectedRanges(clamped, affinity: affinity, stillSelecting: stillSelecting)
    }

    // MARK: Fragmente

    func containerPoint(for viewPoint: NSPoint) -> CGPoint {
        CGPoint(x: viewPoint.x - textContainerOrigin.x, y: viewPoint.y - textContainerOrigin.y)
    }

    func fragment(atViewPoint point: NSPoint) -> BlockLayoutFragment? {
        textLayoutManager?.textLayoutFragment(for: containerPoint(for: point)) as? BlockLayoutFragment
    }

    func characterOffset(of fragment: NSTextLayoutFragment) -> Int? {
        guard let manager = textLayoutManager, let contentManager = manager.textContentManager else { return nil }
        return contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
    }

    /// Rahmen eines Fragments in View-Koordinaten.
    func viewFrame(of fragment: NSTextLayoutFragment) -> CGRect {
        fragment.layoutFragmentFrame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // MARK: Checkbox

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleMarkerClick(at: point) { return }
        if let fragment = fragment(atViewPoint: point), fragment.kind == .todo,
           let offset = characterOffset(of: fragment) {
            let frame = viewFrame(of: fragment)
            let box = fragment.checkboxRect.offsetBy(dx: frame.minX, dy: frame.minY).insetBy(dx: -4, dy: -4)
            if box.contains(point) {
                editor?.toggleChecked(atCharacter: offset)
                return
            }
        }
        // Kehrt erst nach dem Loslassen zurück (Auswahl per Ziehen ist dann fertig).
        super.mouseDown(with: event)
        editor?.focusMouseSelectionDidEnd()
    }

    // MARK: Griff und ＋ bei Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHandle(for: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if !handle.frame.union(insertButton.frame).insetBy(dx: -8, dy: -8).contains(point) { setHoverControlsHidden(true) }
    }

    func updateHandle(for point: NSPoint) {
        guard let fragment = fragment(atViewPoint: CGPoint(x: textContainerOrigin.x + 1, y: point.y)),
              let offset = characterOffset(of: fragment) else {
            setHoverControlsHidden(true)
            return
        }
        let frame = viewFrame(of: fragment)
        let lineTop = fragment.textLineFragments.first.map { $0.typographicBounds.minY } ?? 0
        let lineHeight = fragment.textLineFragments.first.map { $0.typographicBounds.height } ?? 20
        let width = QuillDesign.EditorLayout.blockControlWidth
        let height = QuillDesign.EditorLayout.blockControlHeight
        let x = textContainerOrigin.x + BlockStyle.leadingInset(kind: fragment.kind, indent: fragment.indent)
            - (width + QuillDesign.EditorLayout.blockControlGap)
        let y = frame.minY + lineTop + (lineHeight - height) / 2
        // „⋮⋮ ＋ Text“: der ＋ direkt vor dem Text, der Griff links daneben.
        insertButton.frame = CGRect(x: x, y: y, width: width, height: height)
        handle.frame = CGRect(x: x - width, y: y, width: width, height: height)
        handle.characterOffset = offset
        insertButton.characterOffset = offset
        setHoverControlsHidden(false)
    }

    private func setHoverControlsHidden(_ hidden: Bool) {
        handle.isHidden = hidden
        insertButton.isHidden = hidden
    }

    // MARK: Ziehen und Ablegen von Blöcken

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.quillBlockDrag, .fileURL] + BlockEditorController.imageDataTypes
    }

    private func isBlockDrag(_ info: any NSDraggingInfo) -> Bool {
        info.draggingPasteboard.availableType(from: [.quillBlockDrag]) != nil
    }

    /// Bilder aus dem Finder oder anderen Apps; werden als Bild-Blöcke zwischen Blöcken abgelegt.
    private func isImageDrop(_ info: any NSDraggingInfo) -> Bool {
        !isBlockDrag(info) && BlockEditorController.hasImages(info.draggingPasteboard)
    }

    private func handlesDrop(_ info: any NSDraggingInfo) -> Bool {
        isBlockDrag(info) || isImageDrop(info)
    }

    /// Zielindex (Block) und y-Position der Einfügelinie.
    private func dropTarget(for info: any NSDraggingInfo) -> (index: Int, y: CGFloat)? {
        let point = convert(info.draggingLocation, from: nil)
        guard let editor else { return nil }
        guard let fragment = fragment(atViewPoint: CGPoint(x: textContainerOrigin.x + 1, y: point.y)),
              let offset = characterOffset(of: fragment) else {
            return (editor.document.count, bounds.maxY)
        }
        let frame = viewFrame(of: fragment)
        let block = editor.blockIndex(atCharacter: offset)
        return point.y < frame.midY ? (block, frame.minY) : (block + 1, frame.maxY)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        handlesDrop(sender) ? draggingUpdated(sender) : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard handlesDrop(sender) else { return super.draggingUpdated(sender) }
        guard let target = dropTarget(for: sender) else { return [] }
        autoscrollForDrag(at: convert(sender.draggingLocation, from: nil))
        dropIndicator.frame = dropIndicatorFrame(index: target.index, y: target.y)
        dropIndicator.isHidden = false
        return isBlockDrag(sender) ? .move : .copy
    }

    /// Einfügelinie ab dem Textbeginn des Zielblocks (Einrückung, Listenmarker), nicht über die volle Breite.
    func dropIndicatorFrame(index: Int, y: CGFloat) -> CGRect {
        let padding = textContainer?.lineFragmentPadding ?? 5
        let right = textContainerOrigin.x + (textContainer?.size.width ?? bounds.width) - padding
        var left = textContainerOrigin.x + padding
        if let editor, let block = index < editor.document.count ? editor.document[index] : editor.document.blocks.last {
            left += BlockStyle.leadingInset(kind: block.kind, indent: block.indent)
        }
        return CGRect(x: left, y: y - 1, width: max(20, right - left), height: 2)
    }

    /// Beim Ziehen nah am oberen oder unteren Rand mitscrollen. `draggingUpdated`
    /// kommt auch ohne Mausbewegung regelmäßig, so scrollt es weiter.
    func autoscrollForDrag(at point: NSPoint) {
        let visible = visibleRect
        let edge: CGFloat = 40, step: CGFloat = 20
        var y = visible.minY
        if point.y < visible.minY + edge {
            y = max(0, visible.minY - step)
        } else if point.y > visible.maxY - edge {
            y = min(bounds.height - visible.height, visible.minY + step)
        }
        if y != visible.minY { scroll(NSPoint(x: visible.minX, y: y)) }
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropIndicator.isHidden = true
        super.draggingExited(sender)
    }

    /// `NSTextView` lehnt unbekannte Typen hier ab; Block-Drags erledigt `performDragOperation`.
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        handlesDrop(sender) ? true : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if isImageDrop(sender) {
            dropIndicator.isHidden = true
            guard let editor, let target = dropTarget(for: sender) else { return false }
            let images = BlockEditorController.imageSources(from: sender.draggingPasteboard)
            guard !images.isEmpty else { return false }
            let position = target.index < editor.document.count
                ? BlockPosition(block: target.index, offset: 0)
                : BlockPosition(block: editor.document.count - 1, offset: editor.document[editor.document.count - 1].length)
            editor.insertImages(images, from: position, to: position)
            return true
        }
        guard isBlockDrag(sender) else { return super.performDragOperation(sender) }
        dropIndicator.isHidden = true
        guard let target = dropTarget(for: sender),
              let data = sender.draggingPasteboard.data(forType: .quillBlockDrag),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return false }
        return editor?.moveBlocks(withIDs: ids, to: target.index) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        dropIndicator.isHidden = true
        super.concludeDragOperation(sender)
    }

    /// Wird auch bei Abbruch aufgerufen; die Einfügelinie darf nie stehen bleiben.
    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dropIndicator.isHidden = true
        super.draggingEnded(sender)
    }

    // MARK: Format

    @objc func quillToggleBold(_ sender: Any?) { editor?.toggleMark(.bold) }
    @objc func quillToggleItalic(_ sender: Any?) { editor?.toggleMark(.italic) }
    @objc func quillToggleInlineCode(_ sender: Any?) { editor?.toggleMark(.code) }
    @objc func quillToggleStrikethrough(_ sender: Any?) { editor?.toggleMark(.strikethrough) }
    @objc func quillEditLink(_ sender: Any?) { editor?.editLink() }
    @objc func quillSetBlockKind(_ sender: Any?) {
        guard let request = sender as? BlockKindRequest else { return }
        editor?.convertSelectedBlocks(to: request.kind)
    }
    @objc func quillToggleChecked(_ sender: Any?) { editor?.toggleCheckedInSelection() }
    @objc func quillMoveBlockUp(_ sender: Any?) { editor?.moveSelectedBlocks(by: -1) }
    @objc func quillMoveBlockDown(_ sender: Any?) { editor?.moveSelectedBlocks(by: 1) }
    @objc func quillDuplicateBlock(_ sender: Any?) { editor?.duplicateSelectedBlocks() }

    // MARK: Zwischenablage

    #if DEBUG || QUILL_SYNCTEST
    /// Startargument `-QuillPasteboardName <Name>`: Kopieren und Einsetzen nutzen eine
    /// eigene Zwischenablage. Für UI-Tests, damit die des Nutzers unberührt bleibt.
    /// Nur in Debug und in den Testvarianten Synctest A und B (`QUILL_SYNCTEST`), damit
    /// Release den Namen nicht enthält (`check-release-binary.sh`).
    public static let pasteboardArgument = "QuillPasteboardName"
    #endif

    /// Name der eigenen Zwischenablage nur aus der Kommandozeile, nie aus gespeicherten
    /// Einstellungen: Ein `defaults write` darf Kopieren und Einsetzen nicht still
    /// umleiten (wie die Store-Argumente, ADR-019). In Release-Builds immer `nil`.
    static func clipboardName(arguments: [String]) -> String? {
        #if DEBUG || QUILL_SYNCTEST
        guard let index = arguments.firstIndex(of: "-\(pasteboardArgument)"), arguments.indices.contains(index + 1),
              !arguments[index + 1].isEmpty else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }

    static let defaultClipboard: NSPasteboard = {
        guard let name = clipboardName(arguments: ProcessInfo.processInfo.arguments) else { return .general }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        #if DEBUG || QUILL_SYNCTEST
        TestImage.put(arguments: ProcessInfo.processInfo.arguments, on: pasteboard)
        #endif
        return pasteboard
    }()

    var clipboard = BlockTextView.defaultClipboard

    /// Übernimmt `NSTextView`, wenn der Editor nichts tun konnte? Die Text-View kennt
    /// nur die allgemeine Zwischenablage; mit einer eigenen bleibt es deshalb dabei,
    /// sonst läse ein UI-Test die Zwischenablage des Nutzers.
    static func shouldFallBackToTextView(handled: Bool, clipboard: NSPasteboard) -> Bool {
        !handled && clipboard.name == .general
    }

    override func copy(_ sender: Any?) {
        let handled = editor?.copySelection(to: clipboard) == true
        if Self.shouldFallBackToTextView(handled: handled, clipboard: clipboard) { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        let handled = editor?.cutSelection(to: clipboard) == true
        if Self.shouldFallBackToTextView(handled: handled, clipboard: clipboard) { super.cut(sender) }
    }

    override func paste(_ sender: Any?) {
        let handled = editor?.paste(from: clipboard) == true
        if Self.shouldFallBackToTextView(handled: handled, clipboard: clipboard) { super.paste(sender) }
    }

    /// „Einsetzen und Stil anpassen“: mit eigener Zwischenablage als Klartext aus ihr.
    override func pasteAsPlainText(_ sender: Any?) {
        guard clipboard.name != .general else { return super.pasteAsPlainText(sender) }
        if let string = clipboard.string(forType: .string) { insertText(string, replacementRange: selectedRange()) }
    }

    override func pasteAsRichText(_ sender: Any?) {
        guard clipboard.name != .general else { return super.pasteAsRichText(sender) }
        paste(sender)
    }
}

/// Griff ⋮⋮ links neben einem Block: Ziehen verschiebt, Klick wählt den Block aus,
/// Rechtsklick öffnet das Kontextmenü (Löschen, Duplizieren, Umwandeln in …).
final class BlockHandleView: NSView, NSDraggingSource {
    weak var textView: BlockTextView?
    var characterOffset = 0

    /// Unter dem Mauszeiger kräftiger, in den Farben des Themes.
    var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel(String(localized: "Block verschieben", bundle: .module))
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: String(localized: "Nach oben verschieben", bundle: .module)) { [weak self] in
                self?.perform { $0.moveSelectedBlocks(by: -1) } ?? false
            },
            NSAccessibilityCustomAction(name: String(localized: "Nach unten verschieben", bundle: .module)) { [weak self] in
                self?.perform { $0.moveSelectedBlocks(by: 1) } ?? false
            },
            NSAccessibilityCustomAction(name: String(localized: "Duplizieren", bundle: .module)) { [weak self] in
                self?.perform { $0.duplicateSelectedBlocks() } ?? false
            },
            NSAccessibilityCustomAction(name: String(localized: "Löschen", bundle: .module)) { [weak self] in
                self?.perform { $0.deleteSelectedBlocks() } ?? false
            },
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    /// ⋮⋮ als 2 × 3 Punkte; SF Symbols hat unter macOS 26 kein passendes Zeichen.
    override func draw(_ dirtyRect: NSRect) {
        (isHovered ? EditorColor.secondary : EditorColor.control).setFill()
        let diameter: CGFloat = 3, spacing: CGFloat = 4.5
        let width = diameter + spacing, height = diameter + 2 * spacing
        let origin = CGPoint(x: ((bounds.width - width) / 2).rounded(), y: ((bounds.height - height) / 2).rounded())
        for column in 0..<2 {
            for row in 0..<3 {
                let dot = CGRect(
                    x: origin.x + CGFloat(column) * spacing, y: origin.y + CGFloat(row) * spacing,
                    width: diameter, height: diameter
                )
                NSBezierPath(ovalIn: dot).fill()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override var isHidden: Bool {
        didSet { if isHidden { isHovered = false } }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    /// Klick ohne Ziehen wählt die Blöcke aus; erst ab ein paar Punkten Bewegung wird gezogen.
    override func mouseDown(with event: NSEvent) {
        let start = event.locationInWindow
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp {
                perform { _ in }
                return
            }
            if hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 3 {
                beginBlockDrag(with: event)
                return
            }
        }
    }

    /// Wählt die Blöcke des Griffs aus und führt dann die Aktion auf der Auswahl aus.
    @discardableResult
    func perform(_ action: (BlockEditorController) -> Void) -> Bool {
        // Bei markiertem Text (IME) nie eingreifen, auch nicht in die Auswahl.
        guard let textView, let editor = textView.editor, !textView.hasMarkedText() else { return false }
        editor.selectBlocks(editor.handleBlockRange(atCharacter: characterOffset))
        textView.window?.makeFirstResponder(textView)
        action(editor)
        return true
    }

    // MARK: Kontextmenü

    override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }

    override func accessibilityPerformShowMenu() -> Bool {
        makeMenu().popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Löschen", bundle: .module), action: #selector(deleteBlocks(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Duplizieren", bundle: .module), action: #selector(duplicateBlocks(_:)), keyEquivalent: "d").target = self
        menu.addItem(.separator())
        let convert = NSMenuItem(title: String(localized: "Umwandeln in", bundle: .module), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for command in BlockConversion.commands {
            let item = NSMenuItem(title: command.title, action: #selector(convertBlocks(_:)), keyEquivalent: "")
            if let digit = BlockConversion.shortcutDigit(for: command.kind) {
                item.keyEquivalent = String(digit)
                item.keyEquivalentModifierMask = [.command, .option]
            }
            item.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
            item.representedObject = BlockKindRequest(command.kind)
            item.target = self
            submenu.addItem(item)
        }
        convert.submenu = submenu
        menu.addItem(convert)
        return menu
    }

    @objc private func deleteBlocks(_ sender: Any?) { perform { $0.deleteSelectedBlocks() } }
    @objc private func duplicateBlocks(_ sender: Any?) { perform { $0.duplicateSelectedBlocks() } }
    @objc func convertBlocks(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? BlockKindRequest else { return }
        perform { $0.convertSelectedBlocks(to: request.kind) }
    }

    private func beginBlockDrag(with event: NSEvent) {
        guard let textView, let editor = textView.editor else { return }
        let blocks = editor.dragBlocks(forHandleAtCharacter: characterOffset)
        guard !blocks.ids.isEmpty, let data = try? JSONEncoder().encode(blocks.ids) else { return }

        let item = NSPasteboardItem()
        item.setData(data, forType: .quillBlockDrag)
        item.setString(blocks.markdown, forType: .string)
        item.setString(blocks.markdown, forType: .markdown)

        let dragging = NSDraggingItem(pasteboardWriter: item)
        let frame = blocks.viewFrame
        let image = NSImage(size: frame.size)
        if let rep = textView.bitmapImageRepForCachingDisplay(in: frame) {
            textView.cacheDisplay(in: frame, to: rep)
            image.addRepresentation(rep)
        }
        let local = convert(frame, from: textView)
        dragging.setDraggingFrame(local, contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : .copy
    }
}
#endif
