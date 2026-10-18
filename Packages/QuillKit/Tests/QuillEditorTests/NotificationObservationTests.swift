#if canImport(AppKit)
import AppKit
import Synchronization
import Testing
@testable import QuillEditor

@MainActor
@Suite("Editor: Beobachter")
struct NotificationObservationTests {
    /// Fehler 4 aus dem Review: Beobachter blieben nach dem Freigeben registriert.
    @Test func observationEndsWhenReleased() {
        let center = NotificationCenter()
        let name = Notification.Name("test")
        let calls = Mutex(0)
        var observation: NotificationObservation? = NotificationObservation(name, object: nil, center: center, queue: nil) { _ in
            calls.withLock { $0 += 1 }
        }
        center.post(name: name, object: nil)
        #expect(calls.withLock { $0 } == 1)

        withExtendedLifetime(observation) {}
        observation = nil
        center.post(name: name, object: nil)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func controllerIsReleasedWithItsObservers() {
        weak var weakEditor: BlockEditorController?
        autoreleasepool {
            let editor = BlockEditorController(document: EditorDocument(blocks: [EditorBlock(text: "a")]))
            weakEditor = editor
            #expect(editor.undoObservations.count == 2)
        }
        #expect(weakEditor == nil)
    }
}
#endif
