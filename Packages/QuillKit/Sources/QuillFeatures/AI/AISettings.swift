import Foundation
import Observation
import QuillAI

/// KI-Funktionen (ADR-032): ob sie verfügbar sind und ob der Nutzer sie verwenden will.
/// Die Wahl gilt pro Mac (`UserDefaults`), wie Theme und Frist für Bilder; Test-Stores
/// lesen und speichern sie nie.
@MainActor
@Observable
public final class AISettings {
    /// Schlüssel in `UserDefaults`.
    public static let defaultsKey = "QuillAIEnabled"

    /// Will der Nutzer die KI-Funktionen? Standard: ja, sobald das Modell bereitsteht.
    public private(set) var isEnabled: Bool
    public private(set) var availability: AIAvailability
    @ObservationIgnored public let model: any TextModel
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let checkAvailability: @MainActor () -> AIAvailability

    /// Ohne `defaults` gilt die Wahl nur bis zum Beenden.
    public init(
        defaults: UserDefaults?, model: any TextModel = OnDeviceModel(),
        availability: @escaping @MainActor () -> AIAvailability = { OnDeviceModel.availability }
    ) {
        self.defaults = defaults
        self.model = model
        self.checkAvailability = availability
        self.availability = availability()
        isEnabled = defaults?.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    /// Befehle der KI zeigen: nur mit bereitem Modell und eingeschaltet.
    public var isUsable: Bool { isEnabled && availability == .available }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults?.set(enabled, forKey: Self.defaultsKey)
    }

    /// Verfügbarkeit neu prüfen, z. B. nachdem das Modell fertig geladen ist.
    public func refresh() {
        let current = checkAvailability()
        if current != availability { availability = current }
    }
}
