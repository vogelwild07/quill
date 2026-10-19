import Foundation
import Observation
import QuillModel

/// Verbindet einen Editor mit dem `PageStore` (ADR-013).
///
/// - Lädt die Blöcke einer Seite und merkt sich den gespeicherten Stand (`baseline`).
/// - Speichert entprellt (≈ 300 ms) nur, was sich gegenüber diesem Stand geändert hat.
///   `flush()` speichert sofort (Seitenwechsel, Fenster schließen, Beenden).
/// - Scheitert das Speichern, bleiben die Änderungen offen. `lastError` zeigt das an
///   (Hinweis in der Seite), und die Bridge versucht es selbst erneut, mit wachsendem
///   Abstand (`retryDelay` verdoppelt bis `maxRetryDelay`). Nichts wird verworfen.
/// - Mehrere Fenster mit derselben Seite: Nach dem Speichern meldet die Bridge das
///   (`didSave`). Andere Bridges derselben Seite ohne offene Änderungen laden neu.
///   Bearbeiten beide, gewinnt pro Block die letzte Speicherung (bewusste
///   Vereinfachung bis zum CloudKit-Sync). `load()` speichert vorher offene
///   Änderungen anderer Bridges derselben Seite, z. B. einer gerade geschlossenen.
@MainActor
@Observable
public final class EditorPersistenceBridge {
    public static let didSave = Notification.Name("io.github.vogelwild07.quill.editorDidSave")

    public let pageID: UUID
    @ObservationIgnored private let store: PageStore
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let retryDelay: Duration
    @ObservationIgnored private let maxRetryDelay: Duration

    /// Gespeicherter Stand aus Sicht dieses Editors.
    @ObservationIgnored private var baseline: [UUID: EditorBlock] = [:]
    @ObservationIgnored private var baselineOrder: [UUID] = []
    /// Neuester, noch nicht gespeicherter Stand.
    @ObservationIgnored private var pending: EditorDocument?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Bool, Never>?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryAttempt = 0
    /// Ein Neuladen wurde abgelehnt (markierter Text); nach dem nächsten Speichern nachholen.
    @ObservationIgnored private var needsReload = false

    /// Letzter Fehler beim Speichern; `nil` nach erfolgreichem Speichern. Beobachtbar
    /// für den Hinweis „nicht gespeichert“ in der Seite.
    public private(set) var lastError: (any Error)?
    /// Wird aufgerufen, wenn ein anderes Fenster dieselbe Seite gespeichert hat und
    /// dieser Editor neu geladen werden soll. Gibt zurück, ob der Editor das Dokument
    /// übernommen hat (nicht bei markiertem Text, z. B. IME).
    @ObservationIgnored public var onExternalChange: ((EditorDocument) -> Bool)?

    public init(
        pageID: UUID,
        store: PageStore,
        delay: Duration = .milliseconds(300),
        retryDelay: Duration = .seconds(1),
        maxRetryDelay: Duration = .seconds(30)
    ) {
        self.pageID = pageID
        self.store = store
        self.delay = delay
        self.retryDelay = retryDelay
        self.maxRetryDelay = maxRetryDelay
        observeOtherBridges()
        Self.live.add(self)
    }

    isolated deinit {
        debounceTask?.cancel()
        retryTask?.cancel()
        observer?.cancel()
    }

    public var hasUnsavedChanges: Bool { pending != nil || saving != nil }

    // MARK: Alle Editoren

    @ObservationIgnored private static let live = NSHashTable<EditorPersistenceBridge>.weakObjects()

    /// Ob irgendein Editor noch ungespeicherte Änderungen hat (vor dem Beenden).
    public static var hasAnyUnsavedChanges: Bool {
        live.allObjects.contains { $0.hasUnsavedChanges }
    }

    /// Speichert alle Editoren sofort, z. B. vor dem Beenden der App. Gibt den ersten
    /// Fehler zurück, wenn ein Editor nicht speichern konnte, sonst `nil`.
    @discardableResult
    public static func flushAll() async -> (any Error)? {
        var firstError: (any Error)?
        for bridge in live.allObjects where !(await bridge.flush()) {
            firstError = firstError ?? bridge.lastError
        }
        return firstError
    }

    /// Lädt die Seite. Eine leere Seite ergibt einen leeren Absatz, der erst beim
    /// ersten Tippen gespeichert wird.
    public func load() async throws -> EditorDocument {
        // Eine gerade geschlossene Bridge derselben Seite speichert evtl. noch.
        for other in Self.live.allObjects where other !== self && other.pageID == pageID && other.hasUnsavedChanges {
            await other.flush()
        }
        let blocks = try await storedBlocks()
        setBaseline(blocks)
        return EditorDocument(blocks: blocks)
    }

    /// Blöcke der Seite, wie sie im Store stehen.
    private func storedBlocks() async throws -> [EditorBlock] {
        try await store.blocks(of: pageID).map(EditorBlock.init(snapshot:))
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

    /// Speichert offene Änderungen sofort und wartet darauf. `false`, wenn danach noch
    /// Änderungen offen sind (Speichern gescheitert; ein neuer Versuch ist geplant).
    @discardableResult
    public func flush() async -> Bool {
        debounceTask?.cancel()
        debounceTask = nil
        while true {
            if let saving {
                _ = await saving.value
                continue
            }
            guard let document = pending else { return true }
            pending = nil
            // Die Task setzt `saving` selbst zurück. Sonst sähe ein zweiter Aufrufer
            // von `flush()` die fertige Task weiter und würde sie endlos abfragen.
            let task = Task { () -> Bool in
                let succeeded = await self.save(document)
                self.saving = nil
                return succeeded
            }
            saving = task
            guard await task.value else {
                scheduleRetry()
                return false
            }
            retryAttempt = 0
            retryTask?.cancel()
            retryTask = nil
            if needsReload, pending == nil {
                needsReload = false
                await reloadIfUnchanged()
            }
        }
    }

    /// Nächster Versuch nach `retryDelay`, dann doppelt so lange, höchstens `maxRetryDelay`.
    private func scheduleRetry() {
        let wait = min(retryDelay * (1 << min(retryAttempt, 16)), maxRetryDelay)
        retryAttempt += 1
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.flush()
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
              let blocks = try? await storedBlocks(),
              !hasUnsavedChanges else { return }
        // Lehnt der Editor ab, bleibt der alte Stand die Vergleichsbasis: Sonst würden
        // seine veralteten Blöcke beim nächsten Speichern als Änderung gelten.
        guard onExternalChange(EditorDocument(blocks: blocks)) else {
            needsReload = true
            return
        }
        setBaseline(blocks)
    }
}

extension EditorBlock {
    /// Leerer Absatz ohne Formatierung, wie ihn eine neue Seite zeigt.
    var isPristine: Bool {
        kind == .paragraph && text.isEmpty && spans.isEmpty && properties == BlockProperties()
    }

    /// Unbekannte Blockarten werden als Absatz gelesen. Solange der Block nicht
    /// bearbeitet wird, überschreibt die Bridge ihn nicht.
    public init(snapshot: BlockSnapshot) {
        let kind = BlockKind(rawValue: snapshot.kindRaw) ?? .paragraph
        let content = InlineText(text: snapshot.text, richText: snapshot.richText.flatMap(RichText.decode))
        var properties = snapshot.properties
        properties.indent = max(0, min(properties.indent, EditorDocument.maxIndent))
        self.init(id: snapshot.id, kind: kind, text: content.text, spans: content.spans, properties: properties)
    }

    public var snapshot: BlockSnapshot {
        BlockSnapshot(
            id: id,
            kindRaw: kind.rawValue,
            text: text,
            richText: try? content.richText?.encoded(),
            properties: properties
        )
    }
}
