#if canImport(AppKit)
import AppKit
import QuillModel
import UniformTypeIdentifiers

/// Bild-Blöcke (ADR-015): Bilder laden, einfügen (Slash-Menü, Einsetzen, Ablegen)
/// und den Hinweis „Bild wurde verkleinert“.
extension BlockEditorController {
    /// Bildtypen, die beim Einsetzen und Ablegen als Bild gelten (Reihenfolge = Vorrang).
    static let imageDataTypes: [NSPasteboard.PasteboardType] = [
        .png, NSPasteboard.PasteboardType(UTType.heic.identifier), NSPasteboard.PasteboardType(UTType.jpeg.identifier), .tiff,
    ]

    // MARK: Laden

    /// Lädt Bilder, die noch nicht im Cache sind, und erneuert danach ihr Layout.
    func loadMissingImages() {
        guard let imageStore else { return }
        let missing = Set(document.blocks.compactMap { $0.kind == .image ? $0.assetID : nil })
            .filter { EditorImageCache.shared.entry(for: $0) == nil && !loadingImages.contains($0) }
        for id in missing {
            loadingImages.insert(id)
            Task {
                defer { loadingImages.remove(id) }
                guard let data = try? await imageStore.imageData(id)?.data else { return }
                let entry = await Task.detached(priority: .userInitiated) { EditorImageCache.decode(data) }.value
                guard let entry else { return }
                EditorImageCache.shared.store(entry, for: id)
                invalidateLayout(ofImage: id)
            }
        }
    }

    private func invalidateLayout(ofImage id: UUID) {
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager else { return }
        for index in document.blocks.indices where document[index].assetID == id {
            let range = paragraphRange(ofBlock: index)
            if let from = content.location(content.documentRange.location, offsetBy: range.location),
               let to = content.location(from, offsetBy: range.length),
               let textRange = NSTextRange(location: from, end: to) {
                manager.invalidateLayout(for: textRange)
            }
        }
        textView.needsLayout = true
        textView.needsDisplay = true
    }

    // MARK: Einfügen

    /// Importiert Bilder (GPS entfernt, ggf. verkleinert) und fügt sie als Bild-Blöcke
    /// an `position` ein, als ein Undo-Schritt. Ein leerer Absatz wird ersetzt.
    func insertImages(_ images: [Data], at position: BlockPosition) async {
        guard let imageStore, !images.isEmpty else { return }
        var imported: [ImportedImage] = []
        for data in images {
            if let image = try? await imageStore.importImage(data) { imported.append(image) }
        }
        guard !imported.isEmpty else {
            showNotice(String(localized: "Bild konnte nicht gelesen werden", bundle: .module))
            return
        }
        let blocks = imported.map { EditorBlock(kind: .image, properties: BlockProperties(assetID: $0.assetID)) }
        var newDocument = document
        let safe = BlockPosition(block: min(position.block, newDocument.count - 1), offset: position.offset)
        let last = newDocument.insertBlocks(blocks, at: safe)
        if last.block == newDocument.count - 1 { newDocument.blocks.append(EditorBlock()) }
        apply(newDocument, cursor: BlockPosition(block: last.block + 1, offset: 0), actionName: UndoAction.insertImage)
        if imported.contains(where: \.wasDownscaled) {
            showNotice(String(localized: "Bild wurde verkleinert", bundle: .module))
        }
    }

    /// Slash-Menü „Bild“: Dateiauswahl, dann einfügen.
    func chooseImages(at location: Int) {
        let position = position(atCharacter: location)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { [weak self] in
                let images = await Task.detached { urls.compactMap { try? Data(contentsOf: $0) } }.value
                await self?.insertImages(images, at: position)
            }
        }
        if let window = textView.window {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    /// Bilder aus Zwischenablage oder Ziehvorgang: zuerst Bilddateien (Finder),
    /// sonst Bilddaten, aber nur ohne Text. Sonst würde Text aus anderen Apps, der
    /// nebenbei ein Bild mitbringt, als Bild eingesetzt.
    static func images(from pasteboard: NSPasteboard) -> [Data] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls.compactMap { try? Data(contentsOf: $0) }
        }
        guard pasteboard.availableType(from: [.string]) == nil,
              let type = pasteboard.availableType(from: imageDataTypes),
              let data = pasteboard.data(forType: type) else { return [] }
        return [data]
    }

    /// Günstige Prüfung während des Ziehens, ohne Dateien zu lesen.
    static func hasImages(_ pasteboard: NSPasteboard) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: options) { return true }
        return pasteboard.availableType(from: [.string]) == nil && pasteboard.availableType(from: imageDataTypes) != nil
    }

    /// Bild-Blöcke aus der Zwischenablage bekommen eigene Assets: Ein Asset gehört
    /// genau einem Block (ADR-015).
    func withDuplicatedAssets(_ blocks: [EditorBlock]) async -> [EditorBlock] {
        guard let imageStore else { return blocks.filter { $0.kind != .image } }
        var result: [EditorBlock] = []
        for var block in blocks {
            if block.kind == .image, let id = block.assetID {
                guard let copy = try? await imageStore.duplicateAsset(id) else { continue }
                block.assetID = copy
            }
            result.append(block)
        }
        return result
    }

    // MARK: Hinweis

    /// Kurzer, dezenter Hinweis unten im Editor; auch für VoiceOver angesagt.
    func showNotice(_ text: String) {
        noticeView.show(text, in: scrollView)
        NSAccessibility.post(element: textView, notification: .announcementRequested, userInfo: [
            .announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }
}

/// Hinweis-Kapsel wie ein Popover (Material erlaubt, kein Inhalt), blendet sich aus.
final class EditorNoticeView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        material = .popover
        state = .active
        blendingMode = .withinWindow
        wantsLayer = true
        layer?.cornerRadius = 8
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        setAccessibilityIdentifier("editor.notice")
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    var text: String { label.stringValue }

    func show(_ text: String, in container: NSView) {
        label.stringValue = text
        if superview !== container {
            removeFromSuperview()
            translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(self)
            NSLayoutConstraint.activate([
                centerXAnchor.constraint(equalTo: container.centerXAnchor),
                bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            ])
        }
        alphaValue = 1
        isHidden = false
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            await NSAnimationContext.runAnimationGroup { $0.duration = 0.3; self.animator().alphaValue = 0 }
            if !Task.isCancelled { self.isHidden = true }
        }
    }
}
#endif
