import QuillDesign
import QuillEditor
import QuillModel
import SwiftData
import SwiftUI

/// Eine Seite: Kopf (Icon, Titel) und Block-Editor in einer gemeinsamen Scrollfläche.
struct PageDetailView: View {
    let pageID: UUID
    @Binding var titleFocusRequest: UUID?
    let rename: @MainActor (_ id: UUID, _ title: String) -> Void
    let setIcon: @MainActor (_ id: UUID, _ icon: String?) -> Void

    @Query private var pages: [Page]
    @Environment(\.pageStore) private var store
    @Environment(\.modelContext) private var context
    #if canImport(AppKit)
    @State private var session: PageEditorSession?
    #endif

    init(
        pageID: UUID,
        titleFocusRequest: Binding<UUID?>,
        rename: @escaping @MainActor (UUID, String) -> Void,
        setIcon: @escaping @MainActor (UUID, String?) -> Void
    ) {
        self.pageID = pageID
        self._titleFocusRequest = titleFocusRequest
        self.rename = rename
        self.setIcon = setIcon
        _pages = Query(filter: #Predicate<Page> { $0.id == pageID })
    }

    var body: some View {
        if let page = pages.first, page.trashedAt == nil {
            editor
                .navigationTitle(page.title.isEmpty ? String(localized: "Ohne Titel", bundle: .module) : page.title)
        } else {
            ContentUnavailableView(
                String(localized: "Seite nicht gefunden", bundle: .module),
                systemImage: "doc.questionmark"
            )
        }
    }

    #if canImport(AppKit)
    private var editor: some View {
        Group {
            if let session {
                BlockEditorView(controller: session.controller)
            } else {
                Color(nsColor: .textBackgroundColor)
            }
        }
        .task {
            guard session == nil, let store else { return }
            let page = pages.first
            let session = PageEditorSession(
                pageID: pageID, title: page?.title ?? "", icon: page?.icon,
                store: store, context: context, rename: rename, setIcon: setIcon
            )
            self.session = session
            applyTitleFocusRequest()
            await session.load()
        }
        .onDisappear { session?.close() }
        .onChange(of: titleFocusRequest) { applyTitleFocusRequest() }
    }

    /// Neue Seite (⌘N): Fokus in den Titel, sobald der Editor steht.
    private func applyTitleFocusRequest() {
        guard titleFocusRequest == pageID, let session else { return }
        session.headerFocus.requestTitle()
        titleFocusRequest = nil
    }
    #else
    private var editor: some View { EmptyView() }
    #endif
}
