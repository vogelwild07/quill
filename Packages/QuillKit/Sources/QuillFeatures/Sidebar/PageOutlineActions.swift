import Foundation
import QuillModel

/// Aktionen, die die Sidebar auslöst. Bezugsseite ist die angeklickte, nicht
/// zwingend die ausgewählte Seite.
struct PageOutlineActions {
    var create: @MainActor (_ parentID: UUID?) -> Void
    var rename: @MainActor (_ id: UUID, _ title: String, _ oldTitle: String) -> Void
    var move: @MainActor (_ id: UUID, _ parentID: UUID?, _ position: SiblingPosition) -> Void
    var trash: @MainActor (_ id: UUID) -> Void
    var openInTab: @MainActor (_ id: UUID) -> Void
    var openInWindow: @MainActor (_ id: UUID) -> Void
}
