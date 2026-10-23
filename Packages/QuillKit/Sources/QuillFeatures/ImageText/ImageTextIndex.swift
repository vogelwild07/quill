import Foundation
import OSLog
import QuillEditorCore
import QuillModel
import SwiftData

/// Text in Bildern (17.1, ADR-034): erkennt den Text aller Bilder auf Seiten außerhalb des
/// Papierkorbs und hält ihn nur im Speicher. Nach dem Start und nach jeder Speicherung im
/// Store, gesammelt, nur neue Bilder, der Reihe nach.
@MainActor
public final class ImageTextIndex {
    /// Erkannter Text je Bild (`Asset.id`), leer bei Bildern ohne Text.
    private(set) var texts: [UUID: String] = [:]
    private let store: PageStore
    private let recognizer: any TextRecognizer
    /// Wartezeit nach dem Start und nach einer Speicherung, damit mehrere zusammenkommen.
    private let delay: Duration
    private var observation: NotificationObservation?
    private var pending: Task<Void, Never>?
    private var work: Task<Void, Never>?

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "imageText")

    init(store: PageStore, recognizer: any TextRecognizer, delay: Duration = .seconds(2)) {
        self.store = store
        self.recognizer = recognizer
        self.delay = delay
    }

    /// Nach dem Start; erkennt erst nach einer Wartezeit, der Start soll das nicht tragen.
    /// Mehrfach aufrufen schadet nicht.
    public func start() {
        guard observation == nil else { return }
        // Ohne Queue, wie bei Spotlight: `queue: .main` hielte den Thread des Stores an.
        observation = NotificationObservation(ModelContext.didSave, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        scheduleRefresh()
    }

    /// Ausschnitt um die Fundstelle je Bild, dessen Text den Begriff enthält.
    public func excerpts(matching term: String) -> [UUID: String] {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [:] }
        var result: [UUID: String] = [:]
        for (id, text) in texts {
            let match = (text as NSString).range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            if match.location != NSNotFound {
                result[id] = TextSnippet.excerpt(text, around: match)
            }
        }
        return result
    }

    /// Wartet, bis alles Angestoßene erkannt ist.
    func settle() async {
        while true {
            let (waiting, running) = (pending, work)
            await waiting?.value
            await running?.value
            if waiting == pending, running == work { return }
        }
    }

    private func scheduleRefresh() {
        pending?.cancel()
        let delay = delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.enqueue()
        }
    }

    private func enqueue() {
        let previous = work
        work = Task(priority: .utility) { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await refresh()
            } catch {
                Self.logger.error("Text in Bildern nicht erkannt: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func refresh() async throws {
        let assets = Set(try await store.activeImages().map(\.assetID))
        texts = texts.filter { assets.contains($0.key) }
        for id in assets where texts[id] == nil {
            guard let image = try await store.imageData(id) else { continue }
            do {
                texts[id] = try await recognizer.text(in: image.data)
            } catch {
                // Ein Bild, das Vision nicht lesen kann, gilt als ohne Text.
                Self.logger.error("Bild nicht gelesen: \(String(describing: error), privacy: .public)")
                texts[id] = ""
            }
        }
    }
}
