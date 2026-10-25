#if canImport(Sparkle)
import Foundation
import os
import Sparkle

/// Updates über Sparkle (ADR-037). Quill plant die Suche selbst (`UpdateScheduler`), Sparkles
/// eigener Zeitplan bleibt aus. Feed und Archiv nur über HTTPS von
/// `github.com/vogelwild07/quill`; die EdDSA-Signaturen von Appcast und Archiv prüft Sparkle
/// (`SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction` im Info.plist).
@MainActor
public final class UpdateController: NSObject {
    public let model: UpdateModel
    private let settings: UpdateSettings
    /// Feed auf `127.0.0.1` für UI-Tests; sonst `nil`.
    private let testFeed: URL?
    private let backup: @MainActor (String) async throws -> Void
    private var updater: SPUUpdater?
    private var driver: UpdateUserDriver?
    private var scheduler: UpdateScheduler?

    nonisolated static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "update")

    /// Fehler, mit dem Quill einen Feed oder ein Archiv von anderswo ablehnt.
    nonisolated static let notAllowedDomain = "io.github.vogelwild07.quill.update"
    nonisolated static let notAllowedCode = 1
    /// Fehler, wenn der Schalter aus ist und Sparkle trotzdem im Hintergrund suchen will.
    nonisolated static let switchedOffCode = 2

    /// `backup` bekommt die neue Version und legt das Backup vor der Installation an.
    public init(settings: UpdateSettings, model: UpdateModel, testFeed: URL?, backup: @escaping @MainActor (String) async throws -> Void) {
        self.settings = settings
        self.model = model
        self.testFeed = testFeed
        self.backup = backup
    }

    public var isRunning: Bool { updater != nil }

    public func start() throws {
        guard updater == nil else { return }
        let driver = UpdateUserDriver(model: model, backup: backup)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        try updater.start()
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false
        updater.userAgentString = "Quill"
        self.driver = driver
        self.updater = updater
        let scheduler = UpdateScheduler(settings: settings) { [weak self] in
            Self.logger.notice("Suche nach Updates im Hintergrund")
            self?.updater?.checkForUpdatesInBackground()
        }
        self.scheduler = scheduler
        scheduler.start()
    }

    /// Menü „Nach Updates suchen …“.
    public func checkNow() {
        guard let updater else { return }
        settings.recordAttempt(.now)
        updater.checkForUpdates()
    }

    /// Nach dem Einschalten des Schalters sofort prüfen, ob eine Suche fällig ist.
    public func settingsChanged() {
        scheduler?.tick()
    }

    nonisolated static func notAllowed(_ what: String) -> NSError {
        NSError(domain: notAllowedDomain, code: notAllowedCode, userInfo: [NSLocalizedDescriptionKey: "\(what) nicht von github.com/vogelwild07/quill über HTTPS"])
    }
}

extension UpdateController: SPUUpdaterDelegate {
    public nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { (testFeed ?? UpdatePolicy.feedURL).absoluteString }
    }

    /// Letzte Schranke vor jeder Anfrage: Feed erlaubt, und im Hintergrund nur mit Schalter an.
    public nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try MainActor.assumeIsolated {
            let feed = testFeed ?? UpdatePolicy.feedURL
            guard UpdatePolicy.isAllowed(feed, allowsTestServer: testFeed != nil) else { throw Self.notAllowed("Versionsliste") }
            if updateCheck == .updatesInBackground, !settings.automaticChecks {
                throw NSError(domain: Self.notAllowedDomain, code: Self.switchedOffCode)
            }
        }
    }

    public nonisolated func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        MainActor.assumeIsolated { settings.recordSuccess(.now) }
    }

    public nonisolated func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        try MainActor.assumeIsolated {
            guard let url = updateItem.fileURL, UpdatePolicy.isAllowed(url, allowsTestServer: testFeed != nil) else {
                Self.logger.error("Archiv von anderswo abgelehnt")
                throw Self.notAllowed("Archiv")
            }
        }
    }

    public nonisolated func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        false
    }
}
#endif
