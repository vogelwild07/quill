import Foundation

/// Fehler der Sync-Schicht. Unlesbare Daten führen zur Quarantäne, nie zum Löschen (ADR-026).
public enum SyncError: Error, Equatable, Sendable {
    /// Aufbau des Dokuments passt nicht: Schlüssel des Objekts mit fehlenden oder
    /// falschen Feldern (Block-ID, Seiten-ID oder `blocks`/`pages`).
    case malformed(String)
    /// Daten aus einer neueren Version von Quill; werden erst nach einem Update gelesen.
    case newerFormat(Int)
    /// Automerge oder JSON konnte die Daten nicht laden; Beschreibung des Fehlers fürs Protokoll.
    case unreadable(String)
}
