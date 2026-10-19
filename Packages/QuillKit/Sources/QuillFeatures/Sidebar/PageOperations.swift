import Foundation
import OSLog
import QuillModel

/// Seitenaktionen eines Fensters mit Rückgängig/Wiederholen.
///
/// Wird pro `body`-Auswertung aus der Umgebung gebaut; hält keinen eigenen Zustand.
@MainActor
struct PageOperations {
    let store: PageStore
    let undoManager: UndoManager?
    /// Wählt eine Seite im Fenster aus (`nil` = keine).
    let select: @MainActor (UUID?) -> Void
    /// Setzt den Fokus auf das Titelfeld einer neuen Seite.
    let focusTitle: @MainActor (UUID) -> Void

    private static let logger = Logger(subsystem: "de.vogel.quill", category: "pages")

    func create(in parentID: UUID?) {
        #if canImport(AppKit)
        QuillSignposts.beginSidebarReload()
        #endif
        perform {
            let id: UUID
            do {
                id = try await store.createPage(in: parentID)
            } catch {
                #if canImport(AppKit)
                QuillSignposts.cancelSidebarReload()
                #endif
                throw error
            }
            select(id)
            focusTitle(id)
            register(String(localized: "Seite anlegen", bundle: .module),
                     undo: { try await store.trash(id) },
                     redo: { try await store.restore(id) })
        }
    }

    func rename(_ id: UUID, to title: String, from oldTitle: String) {
        guard title != oldTitle else { return }
        perform {
            try await store.rename(id, to: title)
            register(String(localized: "Umbenennen", bundle: .module),
                     undo: { try await store.rename(id, to: oldTitle) },
                     redo: { try await store.rename(id, to: title) })
        }
    }

    func move(_ id: UUID, to parentID: UUID?, at position: SiblingPosition) {
        perform {
            let old = try await store.location(of: id)
            try await store.move(id, to: parentID, at: position)
            register(String(localized: "Verschieben", bundle: .module),
                     undo: { try await store.move(id, to: old.parentID, at: old.position) },
                     redo: { try await store.move(id, to: parentID, at: position) })
        }
    }

    func trash(_ id: UUID, selectionAfter: UUID?) {
        perform {
            try await store.trash(id)
            select(selectionAfter)
            register(String(localized: "In den Papierkorb legen", bundle: .module),
                     undo: { try await store.restore(id) },
                     redo: { try await store.trash(id) })
        }
    }

    func restore(_ id: UUID) {
        perform {
            try await store.restore(id)
            register(String(localized: "Wiederherstellen", bundle: .module),
                     undo: { try await store.trash(id) },
                     redo: { try await store.restore(id) })
        }
    }

    /// Hinzufügen an `position` oder Entfernen; Undo stellt den alten Platz wieder her.
    func setFavorite(_ id: UUID, _ isFavorite: Bool, at position: SiblingPosition = .last) {
        let name = if isFavorite {
            String(localized: "Zu Favoriten hinzufügen", bundle: .module)
        } else {
            String(localized: "Aus Favoriten entfernen", bundle: .module)
        }
        perform {
            let old = try await store.favoritePosition(of: id)
            try await store.setFavorite(id, isFavorite, at: position)
            register(name,
                     undo: { try await restoreFavorite(id, at: old) },
                     redo: { try await restoreFavorite(id, at: isFavorite ? position : nil) })
        }
    }

    func moveFavorite(_ id: UUID, at position: SiblingPosition) {
        perform {
            guard let old = try await store.favoritePosition(of: id) else { return }
            try await store.moveFavorite(id, at: position)
            register(String(localized: "Favorit verschieben", bundle: .module),
                     undo: { try await store.moveFavorite(id, at: old) },
                     redo: { try await store.moveFavorite(id, at: position) })
        }
    }

    /// `nil`: kein Favorit. Fehlt der Nachbar inzwischen, ans Ende.
    private func restoreFavorite(_ id: UUID, at position: SiblingPosition?) async throws {
        guard let position else {
            try await store.setFavorite(id, false)
            return
        }
        do {
            try await store.setFavorite(id, true, at: position)
        } catch PageStoreError.siblingNotFound {
            try await store.setFavorite(id, true, at: .last)
        }
    }

    // MARK: - Hilfen

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                Self.logger.error("Seitenaktion fehlgeschlagen: \(error, privacy: .public)")
            }
        }
    }

    /// Registriert `undo`; beim Rückgängigmachen wird synchron das Gegenstück als
    /// Wiederholen registriert, dann erst die asynchrone Aktion gestartet.
    private func register(
        _ name: String,
        undo: @escaping @MainActor () async throws -> Void,
        redo: @escaping @MainActor () async throws -> Void
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: UndoTarget.shared) { _ in
            MainActor.assumeIsolated {
                register(name, undo: redo, redo: undo)
                perform(undo)
            }
        }
        undoManager.setActionName(name)
    }
}

/// Ziel für Undo-Registrierungen; Seitenaktionen gehören keinem Objekt.
private final class UndoTarget: Sendable {
    static let shared = UndoTarget()
}
