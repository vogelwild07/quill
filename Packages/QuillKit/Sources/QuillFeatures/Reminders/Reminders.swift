import Foundation
import Observation
import OSLog
import QuillEditorCore
import QuillModel
import SwiftData

/// Erinnerungen an To-dos (15.4, ADR-033). Quelle sind die geplanten Mitteilungen; nach
/// jeder Speicherung im Store gleicht Quill sie mit den Blöcken ab: Abgehakt, gelöscht oder
/// im Papierkorb heißt entfernen, geänderter Text heißt neu planen.
@MainActor
@Observable
public final class Reminders {
    public enum Failure: Error, Equatable {
        /// Block fehlt, ist kein To-do oder die Seite liegt im Papierkorb.
        case notATodo
        /// Zeitpunkt nicht in der Zukunft.
        case past
    }

    /// Noch nicht fällige Erinnerungen je Block.
    public private(set) var byBlock: [UUID: Reminder] = [:]
    @ObservationIgnored let center: any ReminderCenter
    @ObservationIgnored private let store: PageStore
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var observation: NotificationObservation?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "reminders")

    init(store: PageStore, center: any ReminderCenter, delay: Duration = .seconds(1)) {
        self.store = store
        self.center = center
        self.delay = delay
    }

    /// Nach dem Start: liest die geplanten Erinnerungen und gleicht danach nach jeder
    /// Speicherung ab. Mehrfach aufrufen schadet nicht.
    public func start() {
        guard observation == nil else { return }
        // Ohne Queue, wie bei Spotlight: `queue: .main` hielte den Thread des Stores an.
        observation = NotificationObservation(ModelContext.didSave, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.scheduleReconcile() }
        }
        enqueue { try await $0.reconcile() }
    }

    /// To-dos mit Erinnerung auf einer Seite.
    public func blocks(onPage pageID: UUID) -> Set<UUID> {
        Set(byBlock.values.filter { $0.pageID == pageID }.map(\.blockID))
    }

    /// Plant die Erinnerung (ersetzt eine vorhandene). `false`, wenn Mitteilungen für
    /// Quill aus sind; gefragt wird beim ersten Mal. In der Reihe mit dem Abgleich, sonst
    /// überschriebe ein laufender Abgleich die neue Erinnerung.
    public func set(blockID: UUID, pageID: UUID, date: Date) async throws -> Bool {
        guard date > .now else { throw Failure.past }
        return try await serially { try await $0.schedule(blockID: blockID, pageID: pageID, date: date) }
    }

    /// In der Reihe mit dem Abgleich, sonst plante ein laufender Abgleich sie wieder.
    public func remove(blockID: UUID) async {
        _ = try? await serially { reminders in
            await reminders.center.cancel([blockID])
            reminders.byBlock[blockID] = nil
            reminders.scheduleExpiry()
        }
    }

    private func schedule(blockID: UUID, pageID: UUID, date: Date) async throws -> Bool {
        guard let title = try await store.activeTitles(of: [pageID])[pageID],
              let block = try await store.blocks(of: pageID).first(where: { $0.id == blockID }), Self.isOpenTodo(block)
        else { throw Failure.notATodo }
        guard try await center.authorize() else { return false }
        let reminder = Reminder(blockID: blockID, pageID: pageID, date: date, text: block.text, pageTitle: title)
        try await center.schedule(reminder)
        byBlock[blockID] = reminder
        scheduleExpiry()
        return true
    }

    /// Wartet, bis alles Angestoßene abgeglichen ist.
    func settle() async {
        while true {
            let (waiting, running) = (pending, work)
            await waiting?.value
            await running?.value
            if waiting == pending, running == work { return }
        }
    }

    private func scheduleReconcile() {
        pending?.cancel()
        let delay = delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.enqueue { try await $0.reconcile() }
        }
    }

    private func enqueue(_ step: @escaping @MainActor (Reminders) async throws -> Void) {
        let previous = work
        work = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await step(self)
            } catch {
                Self.logger.error("Erinnerungen nicht abgeglichen: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Wie `enqueue`, gibt aber Ergebnis und Fehler an den Aufrufer.
    private func serially<T: Sendable>(_ step: @escaping @MainActor (Reminders) async throws -> T) async throws -> T {
        let previous = work
        let task = Task { [weak self] () throws -> T in
            await previous?.value
            guard let self else { throw CancellationError() }
            return try await step(self)
        }
        work = Task { _ = try? await task.value }
        return try await task.value
    }

    private func reconcile() async throws {
        var kept: [UUID: Reminder] = [:]
        var dropped: [UUID] = []
        for (pageID, reminders) in Dictionary(grouping: await center.pending(), by: \.pageID) {
            let title = try await store.activeTitles(of: [pageID])[pageID]
            let blocks = title == nil ? [] : try await store.blocks(of: pageID)
            for reminder in reminders {
                guard let title, let block = blocks.first(where: { $0.id == reminder.blockID }), Self.isOpenTodo(block) else {
                    dropped.append(reminder.blockID)
                    continue
                }
                if block.text != reminder.text || title != reminder.pageTitle {
                    let updated = Reminder(blockID: reminder.blockID, pageID: pageID, date: reminder.date, text: block.text, pageTitle: title)
                    try await center.schedule(updated)
                    kept[reminder.blockID] = updated
                } else {
                    kept[reminder.blockID] = reminder
                }
            }
        }
        await center.cancel(dropped)
        if kept != byBlock { byBlock = kept }
        scheduleExpiry()
    }

    /// Fällige Erinnerungen verschwinden aus den geplanten; danach neu lesen, damit das
    /// Zeichen am To-do geht. Steht eine schon fällige noch da, erst nach einer Minute
    /// wieder, nicht jede Sekunde.
    private func scheduleExpiry() {
        expiry?.cancel()
        guard let next = byBlock.values.map(\.date).min() else { return }
        let wait = next > .now ? next.timeIntervalSinceNow + 1 : 60
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.enqueue { try await $0.reconcile() }
        }
    }

    private static func isOpenTodo(_ block: BlockSnapshot) -> Bool {
        block.kindRaw == BlockKind.todo.rawValue && !block.properties.isChecked
    }
}
