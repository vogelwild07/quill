import Foundation
import Testing
@testable import QuillFeatures

@Suite struct PageLabelTests {
    @Test func titleAndPathFallBackToUntitled() {
        #expect(PageLabel.title("Reise") == "Reise")
        #expect(PageLabel.title("") == "Ohne Titel")
        #expect(PageLabel.path([]) == "")
        #expect(PageLabel.path(["Projekte", "", "Quill"]) == "Projekte › Ohne Titel › Quill")
    }

    @Test func trashRetentionIsThirtyDays() {
        #expect(QuillPersistence.trashRetentionDays == 30)
        #expect(QuillPersistence.trashRetention == 30 * 24 * 60 * 60)
    }
}
