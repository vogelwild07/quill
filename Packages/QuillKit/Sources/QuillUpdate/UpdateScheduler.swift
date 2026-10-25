import Foundation

/// Entscheidet, wann Quill von selbst sucht (ADR-037): nur bei eingeschaltetem Schalter,
/// höchstens einmal am Tag. Ohne Sparkle; `check` startet die Suche im Hintergrund.
@MainActor
public final class UpdateScheduler {
    private let settings: UpdateSettings
    private let now: () -> Date
    private let check: () -> Void
    private var timer: Timer?

    public init(settings: UpdateSettings, now: @escaping () -> Date = { .now }, check: @escaping () -> Void) {
        self.settings = settings
        self.now = now
        self.check = check
    }

    /// Prüft sofort und danach stündlich, ob eine Suche fällig ist.
    public func start() {
        tick()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: UpdatePolicy.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Sucht, wenn fällig; der Versuch zählt sofort, auch wenn er scheitert.
    public func tick() {
        let date = now()
        guard UpdatePolicy.mayCheckAutomatically(enabled: settings.automaticChecks, lastAttempt: settings.lastAttempt, now: date) else { return }
        settings.recordAttempt(date)
        check()
    }
}
