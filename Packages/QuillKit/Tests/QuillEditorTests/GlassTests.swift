import Foundation
@testable import QuillEditorCore
import Testing

/// Regler für Liquid Glass (Phase 19, ADR-036): Einstellung und Kontrast der Tönung.
@Suite("Liquid Glass")
@MainActor
struct GlassTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "QuillGlassTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func followsSystemByDefault() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = GlassSettings()
        settings.configure(defaults: defaults)
        #expect(settings.followsSystem)
        #expect(!settings.isCustom)
        #expect(settings.level == GlassSettings.defaultLevel)
    }

    @Test func savesAndLoads() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = GlassSettings()
        settings.configure(defaults: defaults)
        settings.setFollowsSystem(false)
        settings.setLevel(0.75)

        let reloaded = GlassSettings()
        reloaded.configure(defaults: defaults)
        #expect(!reloaded.followsSystem)
        #expect(reloaded.isCustom)
        #expect(reloaded.level == 0.75)
        #expect(defaults.object(forKey: GlassSettings.followsSystemKey) as? Bool == false)
        #expect(defaults.object(forKey: GlassSettings.levelKey) as? Double == 0.75)
    }

    @Test func withoutDefaultsNothingIsStored() {
        let settings = GlassSettings()
        settings.configure(defaults: nil, followsSystem: false, level: 1)
        #expect(settings.isCustom)
        #expect(settings.level == 1)
        settings.setLevel(0)
        #expect(settings.level == 0)
    }

    @Test(arguments: [(-1.0, 0.0), (0.1, 0.0), (0.13, 0.25), (0.6, 0.5), (0.9, 1.0), (7.0, 1.0), (Double.nan, 0.5)])
    func levelsSnapToTheRaster(input: Double, expected: Double) {
        #expect(GlassSettings.snapped(input) == expected)
    }

    @Test func storedNonsenseGivesDefaults() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("ja", forKey: GlassSettings.followsSystemKey)
        defaults.set(3.0, forKey: GlassSettings.levelKey)
        let settings = GlassSettings()
        settings.configure(defaults: defaults)
        #expect(settings.followsSystem)
        #expect(settings.level == 1)
    }

    @Test func changesAreAnnounced() async {
        let settings = GlassSettings()
        settings.configure(defaults: nil)
        let counter = Counter()
        let observation = NotificationCenter.default.addObserver(forName: GlassSettings.didChange, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { counter.value += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observation) }
        settings.setFollowsSystem(false)
        settings.setLevel(1)
        settings.setLevel(1)
        settings.setReduceTransparency(true)
        #expect(counter.value == 3)
    }

    @Test func reduceTransparencyMakesOpaqueAndAFixedValueStays() {
        let settings = GlassSettings()
        settings.configure(defaults: nil, followsSystem: false, level: 0, reduceTransparency: true)
        #expect(settings.reduceTransparency)
        settings.setReduceTransparency(false)
        #expect(settings.reduceTransparency, "Startargument der UI-Tests bleibt")
        let tint = GlassTint(theme: .standard, dark: false, increaseContrast: false)
        #expect(tint.opacity(level: 0, reduceTransparency: true) == 1)
        #expect(tint.opacity(level: 0, reduceTransparency: false) == tint.floor)
        #expect(tint.opacity(level: 1, reduceTransparency: false) == 1)
    }

    /// Jede Stufe, jedes Theme, hell und dunkel, mit und ohne „Kontrast erhöhen“:
    /// Text und Nebentext halten den Mindestkontrast über allen Hintergründen.
    @Test func textKeepsContrastInEveryPosition() {
        for theme in EditorTheme.all {
            for dark in [false, true] {
                for increaseContrast in [false, true] {
                    let tint = GlassTint(theme: theme, dark: dark, increaseContrast: increaseContrast)
                    for step in 0...4 {
                        let opacity = tint.opacity(level: Double(step) / 4, reduceTransparency: false)
                        let weakest = tint.weakestContrast(opacity: opacity)
                        #expect(weakest >= tint.minimum, "\(theme.id) dunkel \(dark) Kontrast+ \(increaseContrast) Stufe \(step): \(weakest)")
                    }
                }
            }
        }
    }

    /// Gegenprobe zur Rechnung: knapp unter dem Boden reißt ein Hintergrund das Ziel.
    @Test func belowTheFloorSomeBackdropFails() {
        for theme in EditorTheme.all {
            for dark in [false, true] {
                let tint = GlassTint(theme: theme, dark: dark, increaseContrast: false)
                guard tint.floor > 0 else { continue }
                #expect(tint.weakestContrast(opacity: tint.floor - 0.01) < tint.minimum + GlassTint.reserve, "\(theme.id) dunkel \(dark)")
            }
        }
    }

    @Test func fixedThemesOfTheOtherAppearanceTintWithStandard() {
        let abendInLight = GlassTint(theme: .abend, dark: false, increaseContrast: false)
        #expect(abendInLight == GlassTint(theme: .standard, dark: false, increaseContrast: false))
        let sonneInDark = GlassTint(theme: .sonne, dark: true, increaseContrast: false)
        #expect(sonneInDark == GlassTint(theme: .standard, dark: true, increaseContrast: false))
        let abendInDark = GlassTint(theme: .abend, dark: true, increaseContrast: false)
        #expect(abendInDark.color == EditorTheme.abend.palette(for: .dark).background.approximation(.dark))
    }

    @Test func printFloors() {
        for theme in EditorTheme.all {
            let light = GlassTint(theme: theme, dark: false, increaseContrast: false).floor
            let dark = GlassTint(theme: theme, dark: true, increaseContrast: false).floor
            print("Boden \(theme.id.rawValue): hell \(light) dunkel \(dark)")
        }
    }
}

@MainActor
private final class Counter {
    var value = 0
}
