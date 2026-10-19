#if canImport(AppKit)
import AppKit
import QuillModel

/// VoiceOver im Editor: Die Text-View liefert den Fließtext, dazu
/// - je To-do eine Checkbox und je Bild ein Bild als eigenes Element,
/// - die Blockart im Text der Bedienungshilfen (Listenpräfix, Ebene, Beschreibung),
/// - einen Rotor „Überschriften“.
extension BlockTextView: @MainActor NSAccessibilityCustomRotorItemSearchDelegate {
    /// Checkboxen und Bilder in Dokumentreihenfolge. Elemente bleiben pro Block
    /// erhalten, damit VoiceOver seinen Fokus behält.
    func blockAccessibilityElements() -> [BlockAccessibilityElement] {
        guard let editor else { return [] }
        var kept: [UUID: BlockAccessibilityElement] = [:]
        var result: [BlockAccessibilityElement] = []
        for block in editor.document.blocks {
            let role: BlockAccessibilityElement.Role
            switch block.kind {
            case .todo: role = .checkbox
            case .image: role = .image
            case .paragraph, .heading1, .heading2, .heading3, .bulleted, .numbered, .quote, .code, .divider: continue
            }
            let element = blockElements[block.id].flatMap { $0.role == role ? $0 : nil }
                ?? BlockAccessibilityElement(blockID: block.id, role: role, textView: self)
            kept[block.id] = element
            result.append(element)
        }
        blockElements = kept
        return result
    }

    /// Rahmen eines Blocks (oder seiner Checkbox) in Bildschirmkoordinaten.
    func accessibilityScreenFrame(ofBlock blockID: UUID, checkbox: Bool) -> NSRect {
        guard let editor, let window, let layoutManager = textLayoutManager,
              let index = editor.document.blocks.firstIndex(where: { $0.id == blockID }),
              let start = layoutManager.location(layoutManager.documentRange.location,
                                                 offsetBy: editor.paragraphRange(ofBlock: index).location)
        else { return .zero }
        layoutManager.ensureLayout(for: NSTextRange(location: start))
        guard let fragment = layoutManager.textLayoutFragment(for: start) as? BlockLayoutFragment else { return .zero }
        let frame = viewFrame(of: fragment)
        let rect = checkbox ? fragment.checkboxRect.offsetBy(dx: frame.minX, dy: frame.minY) : frame
        return window.convertToScreen(convert(rect, to: nil))
    }

    func accessibilityLabel(ofBlock blockID: UUID, role: BlockAccessibilityElement.Role) -> String {
        switch role {
        case .checkbox:
            let text = editor?.document.blocks.first { $0.id == blockID }?.text ?? ""
            return text.isEmpty ? String(localized: "To-do", bundle: .module) : text
        case .image:
            return String(localized: "Bild", bundle: .module)
        }
    }

    func isChecked(block blockID: UUID) -> Bool {
        editor?.document.blocks.first { $0.id == blockID }?.isChecked == true
    }

    /// Checkbox per Bedienungshilfen drücken; wie ein Klick, mit Undo.
    func toggleChecked(block blockID: UUID) -> Bool {
        guard let editor, let index = editor.document.blocks.firstIndex(where: { $0.id == blockID }) else { return false }
        editor.toggleChecked(atCharacter: editor.paragraphRange(ofBlock: index).location)
        return true
    }

    // MARK: Blockart im Text

    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        guard let base = super.accessibilityAttributedString(for: range), let editor, editor.document.count > 0 else {
            return super.accessibilityAttributedString(for: range)
        }
        let result = NSMutableAttributedString(attributedString: base)
        let ordinals = BlockRenderer.ordinals(for: editor.document)
        var listIndex = 0
        for (index, block) in editor.document.blocks.enumerated() {
            let paragraph = editor.paragraphRange(ofBlock: index)
            let isListItem = block.kind.isListItem
            defer { listIndex = isListItem ? listIndex + 1 : 0 }
            let overlap = NSIntersectionRange(paragraph, range)
            guard overlap.length > 0 else { continue }
            let local = NSRange(location: overlap.location - range.location, length: overlap.length)
            result.addAttribute(.accessibilityCustomText, value: [Self.accessibilityDescription(of: block)], range: local)
            if isListItem, let prefix = Self.listPrefix(of: block, ordinal: ordinals[block.id]) {
                result.addAttribute(.accessibilityListItemPrefix, value: NSAttributedString(string: prefix), range: local)
                result.addAttribute(.accessibilityListItemIndex, value: listIndex, range: local)
                result.addAttribute(.accessibilityListItemLevel, value: block.indent, range: local)
            }
        }
        return result
    }

    /// Blockart, wie VoiceOver sie ansagt.
    static func accessibilityDescription(of block: EditorBlock) -> String {
        switch block.kind {
        case .paragraph: String(localized: "Text", bundle: .module)
        case .heading1: String(localized: "Überschrift 1", bundle: .module)
        case .heading2: String(localized: "Überschrift 2", bundle: .module)
        case .heading3: String(localized: "Überschrift 3", bundle: .module)
        case .bulleted: String(localized: "Aufzählung", bundle: .module)
        case .numbered: String(localized: "Nummerierte Liste", bundle: .module)
        case .todo:
            block.isChecked
                ? String(localized: "To-do, erledigt", bundle: .module)
                : String(localized: "To-do, offen", bundle: .module)
        case .quote: String(localized: "Zitat", bundle: .module)
        case .code: String(localized: "Code", bundle: .module)
        case .divider: String(localized: "Trennlinie", bundle: .module)
        case .image: String(localized: "Bild", bundle: .module)
        }
    }

    private static func listPrefix(of block: EditorBlock, ordinal: Int?) -> String? {
        switch block.kind {
        case .bulleted: "•"
        case .numbered: "\(ordinal ?? 1)."
        case .todo: block.isChecked ? "☑" : "☐"
        case .paragraph, .heading1, .heading2, .heading3, .quote, .code, .divider, .image: nil
        }
    }

    // MARK: Rotor „Überschriften“

    override func accessibilityCustomRotors() -> [NSAccessibilityCustomRotor] {
        [NSAccessibilityCustomRotor(rotorType: .heading, itemSearchDelegate: self)]
    }

    func rotor(
        _ rotor: NSAccessibilityCustomRotor,
        resultFor searchParameters: NSAccessibilityCustomRotor.SearchParameters
    ) -> NSAccessibilityCustomRotor.ItemResult? {
        guard let editor else { return nil }
        let filter = searchParameters.filterString.trimmingCharacters(in: .whitespaces)
        let headings = editor.document.blocks.indices.filter { index in
            let block = editor.document[index]
            let isHeading = switch block.kind {
            case .heading1, .heading2, .heading3: true
            case .paragraph, .bulleted, .numbered, .todo, .quote, .code, .divider, .image: false
            }
            return isHeading && (filter.isEmpty || block.text.localizedCaseInsensitiveContains(filter))
        }
        let current = searchParameters.currentItem?.targetRange.location
        let index: Int? = switch searchParameters.searchDirection {
        case .next: headings.first { current == nil || editor.paragraphRange(ofBlock: $0).location > current! }
        case .previous: headings.last { current == nil || editor.paragraphRange(ofBlock: $0).location < current! }
        @unknown default: nil
        }
        guard let index else { return nil }
        let paragraph = editor.paragraphRange(ofBlock: index)
        let item = NSAccessibilityCustomRotor.ItemResult(targetElement: self)
        item.targetRange = NSRange(location: paragraph.location, length: max(0, paragraph.length - 1))
        item.customLabel = editor.document[index].text
        return item
    }
}

/// Checkbox eines To-dos oder Bild-Block als eigenes Element unter der Text-View.
/// Rahmen, Wert und Beschriftung liest die Text-View bei jeder Abfrage aus dem Dokument.
///
/// AppKit ruft die Bedienungshilfen nur auf dem Main Thread auf; die geerbten
/// Methoden von `NSAccessibilityElement` sind aber nicht isoliert. Die Overrides
/// reichen deshalb nur Sendable-Werte an die Text-View weiter (`MainActor.assumeIsolated`).
final class BlockAccessibilityElement: NSAccessibilityElement {
    enum Role: Sendable { case checkbox, image }

    let blockID: UUID
    let role: Role
    nonisolated(unsafe) private weak var textView: BlockTextView?

    init(blockID: UUID, role: Role, textView: BlockTextView) {
        self.blockID = blockID
        self.role = role
        self.textView = textView
        super.init()
        setAccessibilityIdentifier(role == .checkbox ? "editor.todo" : "editor.image")
    }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityParent() -> Any? { textView }

    override func accessibilityRole() -> NSAccessibility.Role? {
        switch role {
        case .checkbox: .checkBox
        case .image: .image
        }
    }

    override func accessibilityLabel() -> String? {
        let (view, id, role) = (textView, blockID, role)
        return MainActor.assumeIsolated { view?.accessibilityLabel(ofBlock: id, role: role) }
    }

    override func accessibilityValue() -> Any? {
        guard role == .checkbox else { return nil }
        let (view, id) = (textView, blockID)
        let isChecked = MainActor.assumeIsolated { view?.isChecked(block: id) ?? false }
        return NSNumber(value: isChecked)
    }

    override func accessibilityFrame() -> NSRect {
        let (view, id, isCheckbox) = (textView, blockID, role == .checkbox)
        return MainActor.assumeIsolated { view?.accessibilityScreenFrame(ofBlock: id, checkbox: isCheckbox) ?? .zero }
    }

    override func accessibilityPerformPress() -> Bool {
        guard role == .checkbox else { return false }
        let (view, id) = (textView, blockID)
        return MainActor.assumeIsolated { view?.toggleChecked(block: id) ?? false }
    }
}
#endif
