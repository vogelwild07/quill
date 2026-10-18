import Testing
@testable import QuillEditor

@Suite struct QuillEditorTests {
    @Test func moduleLoads() {
        #expect(String(describing: QuillEditor.self) == "QuillEditor")
    }
}
