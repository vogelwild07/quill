import Foundation
import Observation

/// Wie lange Quill Bilder aufbewahrt, die keinem Block mehr gehören (12.4, ADR-031,
/// ADR-015). Bilder werden nicht versioniert: Holt die Zeitreise einen gelöschten
/// Bild-Block zurück, bekommt er sein Bild nur, solange es noch aufbewahrt wird.
public enum ImageRetention: String, CaseIterable, Identifiable, Sendable {
    case thirtyDays
    case ninetyDays
    case oneYear
    case forever

    public static let standard = ImageRetention.ninetyDays

    public var id: String { rawValue }

    /// Alter, ab dem ein verwaistes Bild gelöscht wird; `nil` heißt nie.
    public var age: TimeInterval? {
        switch self {
        case .thirtyDays: 30 * 24 * 3600
        case .ninetyDays: 90 * 24 * 3600
        case .oneYear: 365 * 24 * 3600
        case .forever: nil
        }
    }

    public var title: String {
        switch self {
        case .thirtyDays: String(localized: "30 Tage", bundle: .module)
        case .ninetyDays: String(localized: "90 Tage", bundle: .module)
        case .oneYear: String(localized: "1 Jahr", bundle: .module)
        case .forever: String(localized: "Immer", bundle: .module)
        }
    }
}

/// Gewählte Frist, pro Gerät in den Einstellungen (`UserDefaults`), nicht im Store, wie
/// Theme und Fokus-Modus. Test-Stores lesen und speichern keine Wahl.
@MainActor
@Observable
public final class ImageRetentionSettings {
    /// Schlüssel in `UserDefaults`.
    public static let defaultsKey = "QuillImageRetention"

    public private(set) var retention: ImageRetention
    @ObservationIgnored private let defaults: UserDefaults?

    /// Ohne `defaults` gilt die Wahl nur bis zum Beenden.
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
        retention = defaults?.string(forKey: Self.defaultsKey).flatMap(ImageRetention.init(rawValue:)) ?? .standard
    }

    /// Wirkt beim nächsten Aufräumen nach dem Start; jetzt wird nichts gelöscht.
    public func select(_ retention: ImageRetention) {
        self.retention = retention
        defaults?.set(retention.rawValue, forKey: Self.defaultsKey)
    }
}
