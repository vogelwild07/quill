#if canImport(AppKit)
import AppKit
import QuillModel
import UniformTypeIdentifiers

/// Herkunft eines einzufügenden Bildes. Dateien werden nie auf dem Main Thread gelesen.
enum ImageSource: Sendable {
    case file(URL)
    case data(Data)

    nonisolated func load() -> Data? {
        switch self {
        case .file(let url):
            dispatchPrecondition(condition: .notOnQueue(.main))
            return try? Data(contentsOf: url)
        case .data(let data):
            return data
        }
    }
}

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
            .filter { EditorImageCache.shared.entry(for: $0) == nil && !loadingImages.contains($0) && !pendingImports.contains($0) }
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

    /// Fügt Bild-Blöcke sofort ein (bis zum Ende des Imports mit Platzhalter) und
    /// importiert die Bilder im Hintergrund (GPS entfernt, ggf. verkleinert).
    ///
    /// Der Bereich `start`…`end` wird ersetzt; Löschen und Einfügen sind ein
    /// Undo-Schritt. Die Asset-IDs stehen schon beim Einfügen fest, der Block ändert
    /// sich danach nicht mehr. Deshalb bleibt Undo/Redo auch während des Imports
    /// korrekt; `PageStore.importImage` verknüpft einen schon gespeicherten Block.
    func insertImages(_ sources: [ImageSource], from start: BlockPosition, to end: BlockPosition) {
        guard let imageStore, !sources.isEmpty else { return }
        let blocks = sources.map { _ in EditorBlock(kind: .image, properties: BlockProperties(assetID: UUID())) }
        var newDocument = document
        var caret = start
        if start != end {
            caret = newDocument.replace(from: start, to: end, with: "")
        }
        let last = newDocument.insertBlocks(blocks, at: caret)
        if last.block == newDocument.count - 1 { newDocument.blocks.append(EditorBlock()) }
        let imports = zip(blocks, sources).map { (blockID: $0.id, assetID: $0.assetID!, source: $1) }
        pendingImports.formUnion(imports.map(\.assetID))
        apply(newDocument, cursor: BlockPosition(block: last.block + 1, offset: 0), actionName: UndoAction.insertImage)

        Task {
            var downscaled = false
            var failed: Set<UUID> = []
            for item in imports {
                let data = await Task.detached(priority: .userInitiated) { item.source.load() }.value
                var imported: ImportedImage?
                if let data {
                    imported = try? await imageStore.importImage(data, assetID: item.assetID, linkTo: item.blockID)
                }
                pendingImports.remove(item.assetID)
                if let imported {
                    downscaled = downscaled || imported.wasDownscaled
                } else {
                    failed.insert(item.assetID)
                }
            }
            loadMissingImages()
            if !failed.isEmpty { removeImageBlocks(withAssets: failed) }
            if downscaled {
                showNotice(String(localized: "Bild wurde verkleinert", bundle: .module))
            }
        }
    }

    /// Unlesbare Bilder: Platzhalter wieder entfernen und Bescheid geben.
    private func removeImageBlocks(withAssets ids: Set<UUID>) {
        showNotice(String(localized: "Bild konnte nicht gelesen werden", bundle: .module))
        var newDocument = document
        newDocument.blocks.removeAll { $0.kind == .image && $0.assetID.map(ids.contains) == true }
        guard newDocument.count != document.count else { return }
        if newDocument.blocks.isEmpty { newDocument.blocks = [EditorBlock()] }
        apply(newDocument, cursor: nil, actionName: UndoAction.delete)
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
            self?.insertImages(panel.urls.map(ImageSource.file), from: position, to: position)
        }
        if let window = textView.window {
            panel.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(panel.runModal())
        }
    }

    /// Bilder aus Zwischenablage oder Ziehvorgang: zuerst Bilddateien (Finder, gelesen
    /// erst im Hintergrund), sonst Bilddaten, aber nur ohne Text. Sonst würde Text aus
    /// anderen Apps, der nebenbei ein Bild mitbringt, als Bild eingesetzt.
    static func imageSources(from pasteboard: NSPasteboard) -> [ImageSource] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return urls.map(ImageSource.file)
        }
        guard pasteboard.availableType(from: [.string]) == nil,
              let type = pasteboard.availableType(from: imageDataTypes),
              let data = pasteboard.data(forType: type) else { return [] }
        return [.data(data)]
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
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("editor.notice")
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("nicht unterstützt") }

    var text: String { label.stringValue }

    func show(_ text: String, in container: NSView) {
        label.stringValue = text
        setAccessibilityLabel(text)
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
