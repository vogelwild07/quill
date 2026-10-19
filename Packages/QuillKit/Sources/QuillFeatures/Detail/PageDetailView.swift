import QuillDesign
import QuillEditor
import QuillModel
import SwiftData
import SwiftUI

/// Eine Seite: Kopf (Icon, Titel) und Block-Editor in einer gemeinsamen Scrollfläche.
struct PageDetailView: View {
    let pageID: UUID
    @Binding var titleFocusRequest: UUID?
    /// Fundstelle aus „Schnell öffnen“; wird nach dem Springen zurückgesetzt.
    @Binding var revealRequest: RevealRequest?
    let rename: @MainActor (_ id: UUID, _ title: String) -> Void
    let setIcon: @MainActor (_ id: UUID, _ icon: String?) -> Void

    @Query private var pages: [Page]
    @Environment(\.pageStore) private var store
    @Environment(\.modelContext) private var context
    #if canImport(AppKit)
    @State private var session: PageEditorSession?
    @State private var isLoaded = false
    #endif

    init(
        pageID: UUID,
        titleFocusRequest: Binding<UUID?>,
        revealRequest: Binding<RevealRequest?>,
        rename: @escaping @MainActor (UUID, String) -> Void,
        setIcon: @escaping @MainActor (UUID, String?) -> Void
    ) {
        self.pageID = pageID
        self._titleFocusRequest = titleFocusRequest
        self._revealRequest = revealRequest
        self.rename = rename
        self.setIcon = setIcon
        _pages = Query(filter: #Predicate<Page> { $0.id == pageID })
    }

    var body: some View {
        if let page = pages.first, page.trashedAt == nil {
            editor
                .navigationTitle(PageLabel.title(page.title))
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
            isLoaded = true
            applyRevealRequest()
        }
        .overlay(alignment: .topTrailing) {
            if let error = session?.bridge.lastError {
                SaveProblemBadge(error: error)
                    .padding(12)
            }
        }
        .onDisappear { session?.close() }
        .onChange(of: titleFocusRequest) { applyTitleFocusRequest() }
        .onChange(of: revealRequest) { applyRevealRequest() }
    }

    /// Erst nach dem Laden und einen Durchlauf später, wenn der Editor im Fenster
    /// steht und gelayoutet ist; sonst greifen Fokus und Scrollen nicht.
    private func applyRevealRequest() {
        guard isLoaded, let request = revealRequest, request.pageID == pageID, let session else { return }
        revealRequest = nil
        DispatchQueue.main.async {
            session.controller.reveal(blockID: request.blockID, range: request.range)
        }
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
