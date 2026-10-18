import Testing
@testable import QuillModel

@Suite struct QuillModelTests {
    @Test func moduleLoads() {
        #expect(String(describing: QuillModel.self) == "QuillModel")
    }
}
