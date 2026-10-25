import Foundation
import Observation

/// Zustand des Fensters „Update“ und Ablauf einer Installation (ADR-037), ohne Sparkle.
/// Die Texte stehen in QuillFeatures. Wichtig: Quill antwortet auf „Update gefunden“ erst
/// nach dem Backup mit „installieren“. Sparkle installiert ein bereitgelegtes Update auch
/// dann, wenn Quill die Installation später verweigert (Spike, ADR-037).
@MainActor
@Observable
public final class UpdateModel {
    /// Neue Version laut Versionsliste.
    public struct Offer: Equatable, Sendable {
        public var version: String
        public var notes: String?

        public init(version: String, notes: String?) {
            self.version = version
            self.notes = notes
        }
    }

    public enum Failure: Equatable, Sendable {
        /// Quill läuft nicht aus „Programme“ (verlagert oder direkt aus der .dmg).
        case notInApplications
        /// Signatur oder Prüfsumme stimmt nicht.
        case badSignature
        /// Archiv beschädigt.
        case damaged
        /// Keine Verbindung oder Versionsliste nicht lesbar.
        case network
        /// Feed oder Archiv nicht von `github.com/vogelwild07/quill` über HTTPS.
        case notAllowed
        /// Backup vor der Installation gescheitert; nichts installiert.
        case backupFailed
        /// Quill ließ sich nicht beenden (z. B. Rückfrage zu ungesicherten Änderungen abgebrochen).
        case couldNotQuit
        case other(String)
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case checking
        case upToDate
        case found(Offer)
        case backingUp
        case downloading(fraction: Double?)
        case preparing
        case installing
        case failed(Failure)
    }

    /// Wahl im Fenster bei „Update gefunden“.
    public enum Choice: Sendable { case install, later, skip }

    /// Antwort an Sparkle.
    public enum Decision: Equatable, Sendable { case install, dismiss, skip }

    public private(set) var phase = Phase.idle
    /// Fenster offen?
    public private(set) var isPresented = false
    /// Zählt hoch, wenn Sparkle das Fenster nach vorn holen will.
    public private(set) var focusRequests = 0

    @ObservationIgnored private var pendingChoice: CheckedContinuation<Choice, Never>?
    /// Abbrechen (Suche, Laden) bzw. erneut versuchen (Beenden), solange angeboten.
    @ObservationIgnored private var cancelAction: (() -> Void)?
    @ObservationIgnored private var retryAction: (() -> Void)?
    /// Bestätigung an Sparkle, sobald der Nutzer das Fenster schließt.
    @ObservationIgnored private var acknowledgement: (() -> Void)?

    public init() {}

    public var canCancel: Bool { cancelAction != nil }
    public var canRetry: Bool { retryAction != nil }

    // MARK: Von Sparkle (über den Treiber)

    public func beginUserInitiatedCheck(cancel: @escaping () -> Void) {
        phase = .checking
        cancelAction = cancel
        isPresented = true
    }

    /// Wartet auf die Wahl im Fenster und legt bei „Installieren“ vorher das Backup an.
    /// Scheitert es, bleibt alles, wie es ist: Antwort „schließen“.
    public func offer(_ offer: Offer, backup: @MainActor () async throws -> Void) async -> Decision {
        cancelAction = nil
        pendingChoice?.resume(returning: .later)
        phase = .found(offer)
        isPresented = true
        let choice = await withCheckedContinuation { pendingChoice = $0 }
        switch choice {
        case .later:
            close()
            return .dismiss
        case .skip:
            close()
            return .skip
        case .install:
            phase = .backingUp
            do {
                try await backup()
            } catch {
                fail(.backupFailed)
                return .dismiss
            }
            return .install
        }
    }

    public func noUpdate(acknowledgement: @escaping () -> Void) {
        cancelAction = nil
        phase = .upToDate
        self.acknowledgement = acknowledgement
    }

    /// Fehler; ohne offenes Fenster (Suche im Hintergrund) bleibt er still.
    public func failed(_ failure: Failure, acknowledgement: @escaping () -> Void) {
        cancelAction = nil
        guard isPresented else {
            acknowledgement()
            return
        }
        phase = .failed(failure)
        self.acknowledgement = acknowledgement
    }

    public func downloadStarted(cancel: @escaping () -> Void) {
        phase = .downloading(fraction: nil)
        cancelAction = cancel
    }

    public func downloadProgress(_ fraction: Double) {
        phase = .downloading(fraction: min(max(fraction, 0), 1))
    }

    public func preparing() {
        cancelAction = nil
        phase = .preparing
    }

    public func installing(applicationTerminated: Bool, retry: @escaping () -> Void) {
        cancelAction = nil
        if applicationTerminated {
            retryAction = nil
            phase = .installing
        } else {
            retryAction = retry
            phase = .failed(.couldNotQuit)
        }
    }

    public func bringToFront() {
        isPresented = true
        focusRequests += 1
    }

    /// Sparkle ist fertig; das Fenster geht zu. Ein eigener Fehler (Backup gescheitert)
    /// bleibt stehen, bis der Nutzer ihn schließt.
    public func dismissedBySparkle() {
        pendingChoice?.resume(returning: .later)
        pendingChoice = nil
        cancelAction = nil
        retryAction = nil
        acknowledgement = nil
        if case .failed = phase, isPresented { return }
        isPresented = false
        phase = .idle
    }

    // MARK: Aus dem Fenster

    public func choose(_ choice: Choice) {
        pendingChoice?.resume(returning: choice)
        pendingChoice = nil
    }

    public func cancel() {
        let action = cancelAction
        cancelAction = nil
        action?()
    }

    public func retry() {
        let action = retryAction
        retryAction = nil
        phase = .installing
        action?()
    }

    /// Fenster schließen: offene Wahl gilt als „Später“, eine Suche wird abgebrochen,
    /// Sparkle bekommt seine Bestätigung.
    public func close() {
        if let pendingChoice {
            self.pendingChoice = nil
            pendingChoice.resume(returning: .later)
            return
        }
        cancel()
        let ack = acknowledgement
        acknowledgement = nil
        retryAction = nil
        isPresented = false
        phase = .idle
        ack?()
    }

    private func fail(_ failure: Failure) {
        cancelAction = nil
        phase = .failed(failure)
        isPresented = true
    }
}
