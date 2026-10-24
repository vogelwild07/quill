import Foundation
import Observation

/// Regler für Liquid Glass (Phase 19, ADR-036): „Wie System“ oder eine Stufe zwischen
/// klar und getönt. Pro Gerät in den Einstellungen (`UserDefaults`), nicht im Store,
/// im Sync, in Backups oder im Export, wie Theme und Fokus-Modus.
///
/// Ein Wechsel wirkt sofort in allen Fenstern: SwiftUI beobachtet die Werte, AppKit
/// (Seitenbaum) `didChange`.
@MainActor
@Observable
public final class GlassSettings {
    public static let shared = GlassSettings()
    public static let didChange = Notification.Name("io.github.vogelwild07.quill.glassDidChange")
    /// Schlüssel in `UserDefaults`.
    public static let followsSystemKey = "QuillGlassFollowsSystem"
    public static let levelKey = "QuillGlassLevel"
    /// Rasterpunkte des Reglers: 0, 25, 50, 75 und 100 %.
    public static let step = 0.25
    public static let defaultLevel = 0.5

    /// Standard an: Quill ändert nichts am Glas des Systems.
    public private(set) var followsSystem = true
    /// 0 = klar, 1 = getönt, immer auf einem Rasterpunkt.
    public private(set) var level = defaultLevel
    /// „Transparenz reduzieren“ in den Bedienungshilfen; hat Vorrang vor dem Regler.
    public private(set) var reduceTransparency = false
    /// Ohne `UserDefaults` (UI-Tests, Unit-Tests) gilt die Wahl nur bis zum Beenden.
    @ObservationIgnored private var defaults: UserDefaults?
    /// Fester Wert aus einem Startargument der UI-Tests; die Bedienungshilfen ändern ihn nicht.
    @ObservationIgnored private var reduceTransparencyIsFixed = false

    init() {}

    /// Quill steuert das Glas selbst (Regler oder „Transparenz reduzieren“).
    public var isCustom: Bool { !followsSystem }

    /// Liest die gespeicherte Wahl und speichert künftige Wechsel in `defaults`.
    /// Unbekannte oder fehlende Werte ergeben die Standards.
    public func configure(
        defaults: UserDefaults?, followsSystem: Bool? = nil, level: Double? = nil, reduceTransparency: Bool? = nil
    ) {
        self.defaults = defaults
        let storedFollows = defaults?.object(forKey: Self.followsSystemKey) as? Bool
        let storedLevel = defaults?.object(forKey: Self.levelKey) as? Double
        self.followsSystem = followsSystem ?? storedFollows ?? true
        self.level = Self.snapped(level ?? storedLevel ?? Self.defaultLevel)
        if let reduceTransparency {
            self.reduceTransparency = reduceTransparency
        }
        reduceTransparencyIsFixed = reduceTransparency != nil
        notify()
    }

    public func setFollowsSystem(_ followsSystem: Bool) {
        guard followsSystem != self.followsSystem else { return }
        self.followsSystem = followsSystem
        defaults?.set(followsSystem, forKey: Self.followsSystemKey)
        notify()
    }

    public func setLevel(_ level: Double) {
        let level = Self.snapped(level)
        guard level != self.level else { return }
        self.level = level
        defaults?.set(level, forKey: Self.levelKey)
        notify()
    }

    /// Von der Plattform, wenn sich die Bedienungshilfen ändern; nie gespeichert.
    public func setReduceTransparency(_ reduceTransparency: Bool) {
        guard !reduceTransparencyIsFixed, reduceTransparency != self.reduceTransparency else { return }
        self.reduceTransparency = reduceTransparency
        notify()
    }

    /// Nächster Rasterpunkt in 0 … 1.
    public static func snapped(_ level: Double) -> Double {
        guard level.isFinite else { return defaultLevel }
        return (min(max(level, 0), 1) / step).rounded() * step
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
