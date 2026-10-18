import Foundation
import QuillModel

/// Verbindet einen Editor mit dem `PageStore` (ADR-013).
///
/// - Lädt die Blöcke einer Seite und merkt sich den gespeicherten Stand (`baseline`).
/// - Speichert entprellt (≈ 300 ms) nur, was sich gegenüber diesem Stand geändert hat.
///   `flush()` speichert sofort (Seitenwechsel, Fenster schließen, Beenden).
/// - Scheitert das Speichern, bleiben die Änderungen offen und werden beim nächsten
///   Speichern erneut versucht; nichts wird verworfen.
/// - Mehrere Fenster mit derselben Seite: Nach dem Speichern meldet die Bridge das
///   (`didSave`). Andere Bridges derselben Seite ohne offene Änderungen laden neu.
///   Bearbeiten beide, gewinnt pro Block die letzte Speicherung (bewusste
///   Vereinfachung bis zum CloudKit-Sync).
@MainActor
public final class EditorPersistenceBridge {
    public static let didSave = Notification.Name("de.vogel.quill.editorDidSave")

    public let pageID: UUID
    private let store: PageStore
    private let delay: Duration

    /// Gespeicherter Stand aus Sicht dieses Editors.
    private var baseline: [UUID: EditorBlock] = [:]
    private var baselineOrder: [UUID] = []
    /// Neuester, noch nicht gespeicherter Stand.
    private var pending: EditorDocument?
    private var debounceTask: Task<Void, Never>?
    private var saving: Task<Bool, Never>?
    private var observer: Task<Void, Never>?

    /// Letzter Fehler beim Speichern; `nil` nach erfolgreichem Speichern.
    public private(set) var lastError: (any Error)?
    /// Wird aufgerufen, wenn ein anderes Fenster dieselbe Seite gespeichert hat und
    /// dieser Editor neu geladen werden soll.
    public var onExternalChange: ((EditorDocument) -> Void)?

    public init(pageID: UUID, store: PageStore, delay: Duration = .milliseconds(300)) {
        self.pageID = pageID
        self.store = store
        self.delay = delay
        observeOtherBridges()
        Self.live.add(self)
    }

    isolated deinit {
        debounceTask?.cancel()
        observer?.cancel()
    }

    public var hasUnsavedChanges: Bool { pending != nil || saving != nil }

    // MARK: Alle Editoren

    private static let live = NSHashTable<EditorPersistenceBridge>.weakObjects()

    /// Ob irgendein Editor noch ungespeicherte Änderungen hat (vor dem Beenden).
    public static var hasAnyUnsavedChanges: Bool {
        live.allObjects.contains { $0.hasUnsavedChanges }
    }

    /// Speichert alle Editoren sofort, z. B. vor dem Beenden der App.
    public static func flushAll() async {
        for bridge in live.allObjects {
            await bridge.flush()
        }
    }

    /// Lädt die Seite. Eine leere Seite ergibt einen leeren Absatz, der erst beim
    /// ersten Tippen gespeichert wird.
    public func load() async throws -> EditorDocument {
        let snapshots = try await store.blocks(of: pageID)
        let blocks = snapshots.map(EditorBlock.init(snapshot:))
        setBaseline(blocks)
        return EditorDocument(blocks: blocks)
    }

    /// Nach jeder Änderung im Editor aufrufen; speichert entprellt.
    public func documentDidChange(_ document: EditorDocument) {
        pending = document
        debounceTask?.cancel()
        debounceTask = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Speichert offene Änderungen sofort und wartet darauf.
    public func flush() async {
        debounceTask?.cancel()
        debounceTask = nil
        while true {
            if let saving {
                _ = await saving.value
                continue
            }
            guard let document = pending else { return }
            pending = nil
            // Die Task setzt `saving` selbst zurück. Sonst sähe ein zweiter Aufrufer
            // von `flush()` die fertige Task weiter und würde sie endlos abfragen.
            let task = Task { () -> Bool in
                let succeeded = await self.save(document)
                self.saving = nil
                return succeeded
            }
            saving = task
            guard await task.value else { return }
        }
    }

    /// Änderungen gegenüber dem gespeicherten Stand.
    func edits(for document: EditorDocument) -> BlockEdits {
        if baseline.isEmpty, document.count == 1, document[0].isPristine {
            return BlockEdits()
        }
        let ids = document.blocks.map(\.id)
        let current = Set(ids)
        var edits = BlockEdits()
        edits.upserts = document.blocks.filter { baseline[$0.id] != $0 }.map(\.snapshot)
        edits.deletions = baselineOrder.filter { !current.contains($0) }
        if ids != baselineOrder.filter(current.contains) || edits.upserts.contains(where: { baseline[$0.id] == nil }) {
            edits.order = ids
        }
        return edits
    }

    private func save(_ document: EditorDocument) async -> Bool {
        let edits = edits(for: document)
        guard !edits.isEmpty else { return true }
        do {
            try await store.applyEdits(pageID, edits)
            lastError = nil
            setBaseline(document.blocks)
            NotificationCenter.default.post(name: Self.didSave, object: self, userInfo: ["pageID": pageID])
            return true
        } catch {
            lastError = error
            // Neuere Änderungen enthalten diese mit, weil gegen `baseline` verglichen wird.
            if pending == nil { pending = document }
            return false
        }
    }

    private func setBaseline(_ blocks: [EditorBlock]) {
        baseline = Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        baselineOrder = blocks.map(\.id)
    }

    // MARK: Andere Fenster

    private func observeOtherBridges() {
        let pageID = pageID
        observer = Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: Self.didSave) {
                guard note.userInfo?["pageID"] as? UUID == pageID else { continue }
                let sender = note.object as AnyObject?
                guard let self, sender !== self else { continue }
                await self.reloadIfUnchanged()
            }
        }
    }

    /// Lädt neu, wenn dieser Editor keine offenen Änderungen hat.
    func reloadIfUnchanged() async {
        guard !hasUnsavedChanges, let onExternalChange,
              let snapshots = try? await store.blocks(of: pageID),
              !hasUnsavedChanges else { return }
        let blocks = snapshots.map(EditorBlock.init(snapshot:))
        setBaseline(blocks)
        onExternalChange(EditorDocument(blocks: blocks))
    }
}

extension EditorBlock {
    /// Leerer Absatz ohne Formatierung, wie ihn eine neue Seite zeigt.
    var isPristine: Bool {
        kind == .paragraph && text.isEmpty && indent == 0 && spans.isEmpty
    }

    /// Unbekannte Blockarten werden als Absatz gelesen. Solange der Block nicht
    /// bearbeitet wird, überschreibt die Bridge ihn nicht.
    init(snapshot: BlockSnapshot) {
        let kind = BlockKind(rawValue: snapshot.kindRaw) ?? .paragraph
        let content = InlineText(text: snapshot.text, richText: snapshot.richText.flatMap(RichText.decode))
        self.init(
            id: snapshot.id,
            kind: kind,
            text: content.text,
            spans: content.spans,
            indent: max(0, min(snapshot.indent, EditorDocument.maxIndent)),
            isChecked: snapshot.isChecked,
            codeLanguage: snapshot.codeLanguage
        )
    }

    var snapshot: BlockSnapshot {
        BlockSnapshot(
            id: id,
            kindRaw: kind.rawValue,
            text: text,
            richText: try? content.richText?.encoded(),
            indent: indent,
            isChecked: isChecked,
            codeLanguage: codeLanguage
        )
    }
}
