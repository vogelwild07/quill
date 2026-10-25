import Foundation
import QuillEditorCore
@testable import QuillFeatures
import Testing

/// Die Testvarianten Synctest A und B für `SyncTwoAppsUITests` (ADR-029): Test-Schalter
/// nur unter `QUILL_SYNCTEST` aus `Scripts/make-synctest.sh`, eine Ordner-Ausnahme nur
/// in ihren eigenen Entitlements. Debug, Release und die echte App bleiben, wie sie sind.
@MainActor
@Suite("Synctest A und B: nur Testvarianten bekommen Test-Schalter und Ordner-Ausnahme")
struct SynctestVariantTests {
    static let root = LocalizationTests.root

    static func entitlements(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appending(path: path))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    static func appConfigurations() throws -> [BuildSettings.Configuration] {
        let project = try String(contentsOf: root.appending(path: "Quill.xcodeproj/project.pbxproj"), encoding: .utf8)
        return BuildSettings.configurations(in: project).filter { $0.settings["INFOPLIST_KEY_CFBundleDisplayName"] != nil }
    }

    /// Die echte App: Sandbox, Mikrofon, Lesezeichen, vom Nutzer gewählte Ordner, Kalender,
    /// Netz und fremde Bibliothek für Sparkle samt seinen Diensten (ADR-037), sonst nichts.
    static let realEntitlements = [
        "com.apple.security.app-sandbox",
        // Sparkle lädt sein Framework mit Ad-hoc-Signatur (ADR-037).
        "com.apple.security.cs.disable-library-validation",
        // Nur während einer Sprachnotiz (17.2, ADR-034).
        "com.apple.security.device.audio-input",
        "com.apple.security.files.bookmarks.app-scope",
        "com.apple.security.files.user-selected.read-write",
        // Nur Sparkle: Versionsliste und Update von GitHub (ADR-037).
        "com.apple.security.network.client",
        // Nur gelesen, nur auf Klick: „Heutige Termine einfügen“ (15.5, ADR-033).
        "com.apple.security.personal-information.calendars",
    ]
    static let exceptionKey = "com.apple.security.temporary-exception.files.home-relative-path.read-write"
    /// Einzige weitere Ausnahme der echten App: Sparkles Dienste zum Installieren aus der
    /// Sandbox heraus (ADR-037), nur mit der eigenen Kennung.
    static let sparkleKey = "com.apple.security.temporary-exception.mach-lookup.global-name"
    static let sparkleServices = ["$(PRODUCT_BUNDLE_IDENTIFIER)-spks", "$(PRODUCT_BUNDLE_IDENTIFIER)-spki"]

    @Test func realAppEntitlementsAreUnchanged() throws {
        let real = try Self.entitlements("App/Quill.entitlements")
        #expect(real.keys.sorted() == (Self.realEntitlements + [Self.sparkleKey]).sorted())
        for key in Self.realEntitlements { #expect(real[key] as? Bool == true, "\(key)") }
        #expect(real[Self.sparkleKey] as? [String] == Self.sparkleServices)

        for configuration in try Self.appConfigurations() {
            let expected = configuration.name.hasPrefix("Synctest") ? "App/QuillSynctest.entitlements" : "App/Quill.entitlements"
            #expect(configuration.settings["CODE_SIGN_ENTITLEMENTS"] == expected, "\(configuration.name)")
        }
    }

    /// Ohne Text der Rückfrage beendet macOS die App, sobald sie Kalender oder Mikrofon
    /// anfragt; die Testvarianten haben die Entitlements der echten App.
    @Test func everyVariantExplainsCalendarAndMicrophone() throws {
        let keys = ["INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription", "INFOPLIST_KEY_NSMicrophoneUsageDescription"]
        let configurations = try Self.appConfigurations()
        #expect(configurations.count == 5)
        for configuration in configurations {
            for key in keys {
                #expect(configuration.settings[key]?.isEmpty == false, "\(configuration.name): \(key)")
            }
        }
    }

    @Test func synctestVariantsGetExactlyOneFolderException() throws {
        let synctest = try Self.entitlements("App/QuillSynctest.entitlements")
        #expect(synctest.keys.sorted() == (Self.realEntitlements + [Self.sparkleKey, Self.exceptionKey]).sorted())
        #expect(synctest[Self.sparkleKey] as? [String] == Self.sparkleServices)
        #if DEBUG
        // Genau der Ordner, den `-QuillSyncSharedFolder` nimmt, im temporären Ordner des Test-Runners.
        #expect(synctest[Self.exceptionKey] as? [String] == ["/\(QuillPersistence.syncSharedFolderRoot)/"])
        #expect(QuillPersistence.syncSharedFolderRoot.hasPrefix("Library/Containers/io.github.vogelwild07.quill.UITests.xctrunner/Data/tmp/"))
        #endif
    }

    @Test func onlyTheScriptSetsTheSynctestCondition() throws {
        let project = try String(contentsOf: Self.root.appending(path: "Quill.xcodeproj/project.pbxproj"), encoding: .utf8)
        #expect(!project.contains("QUILL_SYNCTEST"), "QUILL_SYNCTEST in einer Konfiguration der Projektdatei")
        let script = try String(contentsOf: Self.root.appending(path: "Scripts/make-synctest.sh"), encoding: .utf8)
        #expect(script.contains("'SWIFT_ACTIVE_COMPILATION_CONDITIONS=QUILL_SYNCTEST $(inherited)'"))
        // Die Release-Prüfung sucht nach den Namen der Synctest-Schalter.
        let check = try String(contentsOf: Self.root.appending(path: "Scripts/check-release-binary.sh"), encoding: .utf8)
        for marker in ["QuillSyncSharedFolder", "QuillSyncHaltBeforePage", "QuillSaveDelay", "QuillSyncDeviceName", "QuillSyncTestFolder", "QuillSyncUITests", "temporary-exception"] {
            #expect(check.contains(marker), "\(marker) fehlt in check-release-binary.sh")
        }
    }

    // Die Test-Schalter gibt es nur im Debug-Build (und in Synctest A und B).
    #if DEBUG
    @Test func sharedFolderOnlyByNameAndOnlyWithATestStore() throws {
        let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)
        #expect(QuillPersistence.syncSharedFolder("lauf-main", home: home).path(percentEncoded: false)
            == "/Users/test/Library/Containers/io.github.vogelwild07.quill.UITests.xctrunner/Data/tmp/QuillSyncUITests/lauf-main/")
        for unsafe in ["../x", "a/b", ".versteckt", ""] {
            let persistence = try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES", "-QuillSyncSharedFolder", unsafe]) { _, _ in .migrate }
            #expect(persistence.syncTestFolder == nil, "\(unsafe)")
        }
    }

    @Test func haltOnlyWithAPositiveNumber() throws {
        func halt(_ value: String) throws -> Int? {
            try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES", "-QuillSyncHaltBeforePage", value]) { _, _ in .migrate }
                .sync.testHaltBeforeStoringPage
        }
        #expect(try halt("4") == 4)
        #expect(try halt("0") == nil)
        #expect(try halt("x") == nil)
        #expect(try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES"]) { _, _ in .migrate }.sync.testHaltBeforeStoringPage == nil)
    }

    @Test func deviceNameOnlyWithATestStore() throws {
        func name(_ arguments: [String]) throws -> String {
            try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES"] + arguments) { _, _ in .migrate }.sync.localDeviceName
        }
        #expect(try name(["-QuillSyncDeviceName", "Gerät A"]) == "Gerät A")
        #expect(try name(["-QuillSyncDeviceName", ""]) == SyncController.defaultDeviceName)
        #expect(try name([]) == SyncController.defaultDeviceName)
    }

    @Test func saveDelayOnlyWithAPositiveNumber() throws {
        defer { EditorPersistenceBridge.testDelay = nil }
        _ = try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES", "-QuillSaveDelay", "3000"]) { _, _ in .migrate }
        #expect(EditorPersistenceBridge.testDelay == .milliseconds(3000))
        _ = try QuillPersistence.open(arguments: ["Quill", "-QuillInMemoryStore", "YES", "-QuillSaveDelay", "-1"]) { _, _ in .migrate }
        #expect(EditorPersistenceBridge.testDelay == nil)
    }
    #endif
}
