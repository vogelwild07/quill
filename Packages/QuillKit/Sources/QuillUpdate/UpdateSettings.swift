import Foundation
import Observation

/// Einstellungen für Updates (ADR-037), pro Mac in `UserDefaults`, nie im Store. Standard:
/// nicht automatisch suchen. Test-Stores lesen und schreiben die Werte des Nutzers nie
/// (`defaults` = `nil`, nur im Speicher).
@MainActor
@Observable
public final class UpdateSettings {
    public static let shared = UpdateSettings()

    static let automaticKey = "QuillUpdateAutomaticChecks"
    static let askedKey = "QuillUpdateAsked"
    static let lastAttemptKey = "QuillUpdateLastAttempt"
    static let lastSuccessKey = "QuillUpdateLastSuccess"

    /// Sucht Quill einmal am Tag von selbst?
    public private(set) var automaticChecks = false
    /// Wurde die Frage beim ersten Start schon gestellt?
    public private(set) var hasAsked = false
    /// Letzte Suche, auch gescheiterte; danach richtet sich „höchstens einmal am Tag“.
    public private(set) var lastAttempt: Date?
    /// Letzte Suche, bei der die Versionsliste ankam („Zuletzt geprüft“).
    public private(set) var lastSuccess: Date?

    @ObservationIgnored private var defaults: UserDefaults?

    public init() {}

    /// Liest die Werte aus `defaults`; `nil`: nur im Speicher. Die übrigen Parameter setzen
    /// Werte für Tests, ohne sie zu speichern.
    public func configure(defaults: UserDefaults?, automaticChecks: Bool? = nil, hasAsked: Bool? = nil) {
        self.defaults = defaults
        self.automaticChecks = automaticChecks ?? (defaults?.object(forKey: Self.automaticKey) as? Bool ?? false)
        self.hasAsked = hasAsked ?? (defaults?.object(forKey: Self.askedKey) as? Bool ?? false)
        lastAttempt = defaults?.object(forKey: Self.lastAttemptKey) as? Date
        lastSuccess = defaults?.object(forKey: Self.lastSuccessKey) as? Date
    }

    public func setAutomaticChecks(_ value: Bool) {
        automaticChecks = value
        defaults?.set(value, forKey: Self.automaticKey)
    }

    /// Antwort auf die Frage beim ersten Start; danach fragt Quill nie wieder.
    public func answerFirstLaunchQuestion(automaticChecks value: Bool) {
        setAutomaticChecks(value)
        hasAsked = true
        defaults?.set(true, forKey: Self.askedKey)
    }

    public func recordAttempt(_ date: Date) {
        lastAttempt = date
        defaults?.set(date, forKey: Self.lastAttemptKey)
    }

    public func recordSuccess(_ date: Date) {
        lastSuccess = date
        defaults?.set(date, forKey: Self.lastSuccessKey)
    }
}
