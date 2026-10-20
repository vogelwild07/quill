#if canImport(AppKit)
import AppKit
import QuillDesign
import QuillEditorCore
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
            .filter {
                EditorImageCache.shared.entry(for: $0) == nil && !loadingImages.contains($0)
                    && !pendingImports.contains($0) && !failedImages.contains($0)
            }
        for id in missing {
            loadingImages.insert(id)
            Task {
                defer { loadingImages.remove(id) }
                let data = try? await imageStore.imageData(id)?.data
                let entry = await Task.detached(priority: .userInitiated) { data.flatMap { EditorImageCache.decode($0) } }.value
                guard let entry else {
                    failedImages.insert(id)
                    return
                }
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

    /// Liest und prüft die Bilder im Hintergrund, fügt die lesbaren als Bild-Blöcke ein
    /// (bis zum Ende des Imports mit Platzhalter) und importiert sie (GPS entfernt,
    /// ggf. verkleinert). Unlesbares kommt gar nicht erst ins Dokument, also auch nicht
    /// über Undo zurück; es gibt nur einen Hinweis.
    ///
    /// Der Bereich `start`…`end` wird ersetzt; Löschen und Einfügen sind ein
    /// Undo-Schritt. Wurde inzwischen weitergetippt, gilt die Auswahl von dann. Die
    /// Asset-IDs stehen schon beim Einfügen fest, der Block ändert sich danach nicht
    /// mehr. Deshalb bleibt Undo/Redo auch während des Imports korrekt;
    /// `PageStore.importImage` verknüpft einen schon gespeicherten Block.
    @discardableResult
    func insertImages(_ sources: [ImageSource], from start: BlockPosition, to end: BlockPosition) -> Task<Void, Never>? {
        guard let imageStore, !sources.isEmpty else { return nil }
        let before = document
        let anchor = characterLocation(of: start)
        return Task {
            // Dauert das Lesen, zeigt eine Ladeanzeige an der Einfügestelle, dass etwas kommt.
            let delay = imageLoadingIndicatorDelay
            let indicator = Task {
                try? await Task.sleep(for: delay)
                return Task.isCancelled ? nil : showImageLoadingIndicator(atCharacter: anchor)
            }
            let read = readImageSource
            let loaded = await Task.detached(priority: .userInitiated) {
                sources.map { read($0).flatMap { ImageImport.isReadable($0) ? $0 : nil } }
            }.value
            indicator.cancel()
            if let shown = await indicator.value { hideImageLoadingIndicator(shown) }
            let images = loaded.compactMap { $0 }
            if images.count < loaded.count {
                showNotice(String(localized: "Bild konnte nicht gelesen werden", bundle: .module))
            }
            guard !images.isEmpty else { return }
            var range = (start, end)
            if document != before {
                let selection = textView.selectedRange()
                range = (position(atCharacter: selection.location), position(atCharacter: NSMaxRange(selection)))
            }
            let imports = placeImageBlocks(count: images.count, from: range.0, to: range.1)
            var downscaled = false
            var failed: Set<UUID> = []
            var failure: (any Error)?
            for (item, data) in zip(imports, images) {
                do {
                    let imported = try await imageStore.importImage(data, assetID: item.assetID, linkTo: item.blockID)
                    downscaled = downscaled || imported.wasDownscaled
                } catch {
                    failed.insert(item.assetID)
                    failure = error
                }
                pendingImports.remove(item.assetID)
            }
            loadMissingImages()
            if let failure { removeImageBlocks(withAssets: failed, notice: Self.importFailureNotice(for: failure)) }
            if downscaled {
                showNotice(String(localized: "Bild wurde verkleinert", bundle: .module))
            }
        }
    }

    /// Kleine Ladeanzeige über dem Text an der Einfügestelle; nicht im Dokument, nicht im Undo.
    private func showImageLoadingIndicator(atCharacter location: Int) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isDisplayedWhenStopped = false
        indicator.setAccessibilityIdentifier("editor.imageLoading")
        indicator.setAccessibilityLabel(String(localized: "Bild wird geladen", bundle: .module))
        let size: CGFloat = 16
        let line = lineRect(atCharacter: min(location, max(0, textView.string.utf16.count - 1)))
        indicator.frame = CGRect(x: line.minX, y: line.midY - size / 2, width: size, height: size)
        textView.addSubview(indicator)
        indicator.startAnimation(nil)
        imageLoadingIndicators.append(indicator)
        return indicator
    }

    private func hideImageLoadingIndicator(_ indicator: NSProgressIndicator) {
        indicator.stopAnimation(nil)
        indicator.removeFromSuperview()
        imageLoadingIndicators.removeAll { $0 === indicator }
    }

    /// Zeilenrechteck des Zeichens in Koordinaten der Text-View.
    private func lineRect(atCharacter location: Int) -> CGRect {
        guard let manager = textView.textLayoutManager, let content = manager.textContentManager,
              let textLocation = content.location(content.documentRange.location, offsetBy: location),
              let fragment = manager.textLayoutFragment(for: textLocation) else {
            return CGRect(origin: textView.textContainerOrigin, size: CGSize(width: 16, height: 20))
        }
        let frame = textView.viewFrame(of: fragment)
        let block = document[blockIndex(atCharacter: location)]
        let inset = BlockStyle.textInset(kind: block.kind, indent: block.indent)
        let lineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? frame.height
        return CGRect(x: textView.textContainerOrigin.x + inset, y: frame.minY, width: frame.width, height: lineHeight)
    }

    /// Bild-Blöcke mit festen Asset-IDs an die Stelle setzen; ein Undo-Schritt.
    private func placeImageBlocks(count: Int, from start: BlockPosition, to end: BlockPosition) -> [(blockID: UUID, assetID: UUID)] {
        let blocks = (0..<count).map { _ in EditorBlock(kind: .image, properties: BlockProperties(assetID: UUID())) }
        var newDocument = document
        var caret = start
        if start != end {
            caret = newDocument.replace(from: start, to: end, with: "")
        }
        let last = newDocument.insertBlocks(blocks, at: caret)
        newDocument.ensureEditableEnd()
        let imports = blocks.map { (blockID: $0.id, assetID: $0.assetID!) }
        pendingImports.formUnion(imports.map(\.assetID))
        apply(newDocument, cursor: BlockPosition(block: last.block + 1, offset: 0), actionName: UndoAction.insertImage)
        return imports
    }

    /// Unlesbares Bild oder Fehler beim Speichern: Der Hinweis sagt, was passiert ist.
    static func importFailureNotice(for error: any Error) -> String {
        if error as? ImageImport.Failure == .unreadable {
            String(localized: "Bild konnte nicht gelesen werden", bundle: .module)
        } else {
            String(localized: "Bild konnte nicht gespeichert werden", bundle: .module)
        }
    }

    /// Import gescheitert: Platzhalter wieder entfernen und Bescheid geben.
    private func removeImageBlocks(withAssets ids: Set<UUID>, notice: String) {
        showNotice(notice)
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
        layer?.cornerRadius = QuillDesign.Radius.large
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
            await NSAnimationContext.runAnimationGroup { $0.duration = QuillDesign.Motion.fadeOutDuration(); self.animator().alphaValue = 0 }
            if !Task.isCancelled { self.isHidden = true }
        }
    }
}
#endif
