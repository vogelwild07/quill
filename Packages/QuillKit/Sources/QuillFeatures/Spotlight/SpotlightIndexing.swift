import Foundation
import Observation
import OSLog
import QuillEditorCore
import QuillModel
import SwiftData

/// Seiten in Spotlight (15.2, ADR-033): Wahl pro Mac in `UserDefaults`, Standard aus.
/// Eingeschaltet baut Quill den Index nach dem Start neu auf und trägt danach geänderte
/// Seiten nach, gesammelt nach jeder Speicherung im Store. Alles der Reihe nach.
@MainActor
@Observable
public final class SpotlightIndexing {
    /// Schlüssel in `UserDefaults`.
    public static let defaultsKey = "QuillSpotlightEnabled"
    /// Text einer Seite im Index, längere mit ihrem Anfang.
    static let textLimit = 10_000

    public private(set) var isEnabled: Bool
    @ObservationIgnored private let store: PageStore
    @ObservationIgnored let index: any SpotlightIndex
    @ObservationIgnored private let defaults: UserDefaults?
    /// Wartezeit nach dem Start und nach einer Speicherung, damit mehrere zusammenkommen.
    @ObservationIgnored private let delay: Duration
    /// Stand jeder Seite im Index.
    @ObservationIgnored private var indexed: [UUID: Date] = [:]
    /// Nach dem Einschalten oder Start: alles neu statt nur Geändertes.
    @ObservationIgnored private var needsRebuild = false
    @ObservationIgnored private var observation: NotificationObservation?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var work: Task<Void, Never>?

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "spotlight")

    /// Ohne `defaults` gilt die Wahl nur bis zum Beenden.
    init(store: PageStore, index: any SpotlightIndex, defaults: UserDefaults?, delay: Duration = .seconds(2)) {
        self.store = store
        self.index = index
        self.defaults = defaults
        self.delay = delay
        isEnabled = defaults?.bool(forKey: Self.defaultsKey) ?? false
    }

    /// Nach dem Start; baut den Index erst nach einer Wartezeit neu auf, der Start soll das
    /// nicht tragen. Mehrfach aufrufen schadet nicht.
    public func start() {
        guard isEnabled, observation == nil else { return }
        begin()
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults?.set(enabled, forKey: Self.defaultsKey)
        if enabled {
            begin()
        } else {
            observation = nil
            pending?.cancel()
            enqueue { try await $0.clear() }
        }
    }

    /// Wartet, bis alles Angestoßene im Index ist.
    func settle() async {
        while true {
            let (waiting, running) = (pending, work)
            await waiting?.value
            await running?.value
            if waiting == pending, running == work { return }
        }
    }

    private func begin() {
        // Ohne Queue: Mit `queue: .main` hielte NotificationCenter den Thread des Stores an,
        // bis der Main Thread die Meldung nimmt (wie beim Sync).
        observation = NotificationObservation(ModelContext.didSave, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        needsRebuild = true
        scheduleRefresh()
    }

    /// Nach der Wartezeit; eine neue Anfrage ersetzt eine wartende.
    private func scheduleRefresh() {
        pending?.cancel()
        let delay = delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.enqueue { try await $0.refresh() }
        }
    }

    private func enqueue(_ step: @escaping @MainActor (SpotlightIndexing) async throws -> Void) {
        let previous = work
        work = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await step(self)
            } catch {
                Self.logger.error("Spotlight-Index nicht aktualisiert: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func refresh() async throws {
        guard isEnabled else { return }
        if needsRebuild {
            try await rebuild()
        } else {
            try await update()
        }
    }

    private func rebuild() async throws {
        let dates = try await store.activePageDates()
        try await index.replaceAll(with: try await entries(for: Array(dates.keys), dates: dates))
        indexed = dates
        needsRebuild = false
    }

    private func update() async throws {
        let dates = try await store.activePageDates()
        let changed = dates.filter { indexed[$0.key] != $0.value }.map(\.key)
        let removed = indexed.keys.filter { dates[$0] == nil }
        try await index.update(try await entries(for: changed, dates: dates))
        try await index.delete(Array(removed))
        indexed = dates
    }

    private func clear() async throws {
        indexed = [:]
        try await index.deleteAll()
    }

    private func entries(for pageIDs: [UUID], dates: [UUID: Date]) async throws -> [SpotlightEntry] {
        let titles = try await store.activeTitles(of: pageIDs)
        var entries: [SpotlightEntry] = []
        for id in pageIDs {
            guard let title = titles[id], let modified = dates[id] else { continue }
            let text = PageSummarizer.plainText(try await store.blocks(of: id))
            entries.append(SpotlightEntry(pageID: id, title: title, text: String(text.prefix(Self.textLimit)), modified: modified))
        }
        return entries
    }
}
