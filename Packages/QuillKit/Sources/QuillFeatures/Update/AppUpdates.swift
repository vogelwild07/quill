#if canImport(AppKit)
import AppKit
import Observation
import os
import QuillUpdate

/// Updates in der App (ADR-037): Frage beim ersten Start, Menü „Nach Updates suchen …“,
/// Fenster „Update“ und Schalter in den Einstellungen. Nur der echte Store im Release-Build
/// fragt GitHub; Test-Stores nur mit `-QuillUpdateTestFeed` einen Server auf 127.0.0.1,
/// mit Einstellungen im Speicher. Profiling- und Synctest-Builds suchen nie.
@MainActor
public final class AppUpdates {
    public let settings: UpdateSettings
    public let model: UpdateModel
    private let controller: UpdateController?
    /// Frage beim ersten Start stellen, solange sie noch nicht beantwortet ist?
    private let asksOnFirstLaunch: Bool
    private var window: UpdateWindow?

    private static let logger = Logger(subsystem: "io.github.vogelwild07.quill", category: "update")

    /// Nur für Tests: Startargumente, siehe `QuillPersistence`.
    struct TestOptions {
        var feed: URL?
        var automaticChecks: Bool?
        var asksOnFirstLaunch = false
    }

    init(settings: UpdateSettings, model: UpdateModel = UpdateModel(), controller: UpdateController?, asksOnFirstLaunch: Bool) {
        self.settings = settings
        self.model = model
        self.controller = controller
        self.asksOnFirstLaunch = asksOnFirstLaunch
    }

    static func make(isTestStore: Bool, test: TestOptions?, backup: @escaping @MainActor (String) async throws -> Void) -> AppUpdates {
        let model = UpdateModel()
        if !isTestStore {
            UpdateSettings.shared.configure(defaults: .standard)
            #if DEBUG || QUILL_PROFILING || QUILL_SYNCTEST
            // Debug-Builds mit dem echten Store zeigen den Schalter, suchen aber nie: Sie
            // haben dieselbe Kennung wie die echte App und lägen nicht in „Programme“.
            return AppUpdates(settings: .shared, model: model, controller: nil, asksOnFirstLaunch: false)
            #else
            let controller = UpdateController(settings: .shared, model: model, testFeed: nil, backup: backup)
            return AppUpdates(settings: .shared, model: model, controller: controller, asksOnFirstLaunch: true)
            #endif
        }
        let settings = UpdateSettings()
        let test = test ?? TestOptions()
        settings.configure(defaults: nil, automaticChecks: test.automaticChecks ?? false, hasAsked: !test.asksOnFirstLaunch)
        let controller = test.feed.map { UpdateController(settings: settings, model: model, testFeed: $0, backup: backup) }
        return AppUpdates(settings: settings, model: model, controller: controller, asksOnFirstLaunch: test.asksOnFirstLaunch)
    }

    /// Kann Quill hier nach Updates suchen? Sonst ist der Menüpunkt aus.
    public var isAvailable: Bool { controller != nil }

    /// Nach dem Start: Sparkle starten, Fenster dem Zustand folgen lassen und, falls noch
    /// nie beantwortet, einmal fragen. Bis zur Antwort sucht Quill nicht (Standard aus).
    public func start() {
        guard let controller, !controller.isRunning else { return }
        do {
            try controller.start()
        } catch {
            Self.logger.error("Sparkle startet nicht: \(error, privacy: .public)")
            return
        }
        follow()
        if asksOnFirstLaunch, !settings.hasAsked {
            // Erst wenn die App läuft, sonst erreichen Bedienungshilfen den Dialog nicht.
            DispatchQueue.main.async { [self] in
                settings.answerFirstLaunchQuestion(automaticChecks: UpdatePrompt.ask())
                controller.settingsChanged()
            }
        }
    }

    /// Menü „Nach Updates suchen …“.
    public func checkNow() {
        controller?.checkNow()
    }

    public func setAutomaticChecks(_ value: Bool) {
        settings.setAutomaticChecks(value)
        controller?.settingsChanged()
    }

    /// Fenster auf und zu, wie `model` es will.
    private func follow() {
        withObservationTracking {
            _ = model.focusRequests
            if model.isPresented {
                let window = window ?? UpdateWindow(model: model)
                self.window = window
                window.show()
            } else {
                window?.hide()
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }
}
#endif
