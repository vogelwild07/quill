import Testing
@testable import QuillExport

@Suite struct QuillExportTests {
    @Test func moduleLoads() {
        #expect(String(describing: QuillExport.self) == "QuillExport")
    }
}
