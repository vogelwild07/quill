import Foundation
import Testing
@testable import QuillFeatures

/// Startargumente für UI-Tests wirken nur aus der Kommandozeile (ADR-019).
@MainActor
@Suite struct TestStoreArgumentTests {
    @Test func readsArgumentsFromCommandLine() {
        #expect(QuillPersistence.testStore(arguments: ["Quill", "-QuillInMemoryStore", "YES"]) == .inMemory)
        #expect(QuillPersistence.testStore(arguments: ["Quill", "-QuillStoreDirectory", "uitest-1"]) == .directory("uitest-1"))
        #expect(QuillPersistence.testStore(arguments: ["Quill"]) == nil)
    }

    @Test func rejectsUnsafeDirectoryNames() {
        for name in ["", "../Quill", "a/b", ".versteckt", ".."] {
            #expect(QuillPersistence.testStore(arguments: ["Quill", "-QuillStoreDirectory", name]) == nil, "\(name)")
        }
        #expect(QuillPersistence.testStore(arguments: ["Quill", "-QuillStoreDirectory"]) == nil)
        #expect(QuillPersistence.testStore(arguments: ["Quill", "-QuillInMemoryStore", "NO"]) == nil)
    }

    /// Ein gespeicherter Wert (z. B. per `defaults write`) lenkt den Store nicht um.
    @Test func ignoresPersistentDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: QuillPersistence.inMemoryArgument)
        defaults.set("uitest-gespeichert", forKey: QuillPersistence.storeDirectoryArgument)
        defer {
            defaults.removeObject(forKey: QuillPersistence.inMemoryArgument)
            defaults.removeObject(forKey: QuillPersistence.storeDirectoryArgument)
        }
        #expect(QuillPersistence.testStore(arguments: ProcessInfo.processInfo.arguments) == nil)
    }
}
