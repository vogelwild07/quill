import Foundation
import Testing
@testable import QuillFeatures

@Suite struct PageLabelTests {
    @Test func titleAndPathFallBackToUntitled() {
        #expect(PageLabel.title("Reise") == "Reise")
        #expect(PageLabel.title("") == "Untitled")
        #expect(PageLabel.path([]) == "")
        #expect(PageLabel.path(["Projekte", "", "Quill"]) == "Projekte › Untitled › Quill")
    }

    @Test func trashRetentionIsThirtyDays() {
        #expect(QuillPersistence.trashRetentionDays == 30)
        #expect(QuillPersistence.trashRetention == 30 * 24 * 60 * 60)
    }
}
