import QuillDesign
import QuillEditor
import QuillEditorCore
import QuillModel
import SwiftData
import SwiftUI

/// Eine Seite: Kopf (Icon, Titel) und Block-Editor in einer gemeinsamen Scrollfläche.
struct PageDetailView: View {
    let pageID: UUID
    @Binding var titleFocusRequest: UUID?
    /// ⇧Tab aus der Sidebar: Fokus in den Editor (`WindowFocus`).
    @Binding var editorFocusRequest: UUID?
    /// Fundstelle aus „Schnell öffnen“; wird nach dem Springen zurückgesetzt.
    @Binding var revealRequest: RevealRequest?
    let rename: @MainActor (_ id: UUID, _ title: String) -> Void
    let setIcon: @MainActor (_ id: UUID, _ icon: String?) -> Void
    /// Seitenaktionen zu den Hinweisen des Sync (Marke entfernen, Papierkorb).
    let syncActions: PageSyncActions

    @Query private var pages: [Page]
    @Environment(\.pageStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.quillPersistence) private var persistence
    #if canImport(AppKit)
    @State private var session: PageEditorSession?
    @State private var isLoaded = false
    #endif

    init(
        pageID: UUID,
        titleFocusRequest: Binding<UUID?>,
        editorFocusRequest: Binding<UUID?>,
        revealRequest: Binding<RevealRequest?>,
        rename: @escaping @MainActor (UUID, String) -> Void,
        setIcon: @escaping @MainActor (UUID, String?) -> Void,
        syncActions: PageSyncActions = PageSyncActions()
    ) {
        self.syncActions = syncActions
        self.pageID = pageID
        self._titleFocusRequest = titleFocusRequest
        self._editorFocusRequest = editorFocusRequest
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
            EmptyStateView(.pageNotFound, id: "detail.notFound")
        }
    }

    #if canImport(AppKit)
    private var editor: some View {
        Group {
            if let session {
                BlockEditorView(controller: session.controller)
            } else {
                Color(nsColor: EditorColor.background)
            }
        }
        .task {
            guard session == nil, let store else { return }
            let page = pages.first
            var actions = syncActions
            let context = context
            actions.pageTitle = { id in
                try? context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.id == id })).first?.title
            }
            let session = PageEditorSession(
                pageID: pageID, title: page?.title ?? "", icon: page?.icon,
                store: store, context: context, rename: rename, setIcon: setIcon,
                sync: persistence?.sync, reminders: persistence?.reminders, pageActions: actions
            )
            self.session = session
            applyTitleFocusRequest()
            await session.load()
            updateConflictBlocks()
            updateReminderBlocks()
            isLoaded = true
            QuillSignposts.pageDidLoad()
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
        .onChange(of: editorFocusRequest) { applyEditorFocusRequest() }
        .onChange(of: revealRequest) { applyRevealRequest() }
        .onChange(of: persistence?.sync.conflicts(onPage: pageID)) { updateConflictBlocks() }
        .onChange(of: persistence?.reminders.blocks(onPage: pageID)) { updateReminderBlocks() }
    }

    /// Zeichen am Rand für Blöcke mit Konflikt (11.6).
    private func updateConflictBlocks() {
        let conflicts = persistence?.sync.conflicts(onPage: pageID) ?? []
        session?.controller.conflictBlocks = Set(conflicts.filter { !$0.isPageField }.map(\.conflict.objectID))
    }

    /// Zeichen am Rand für To-dos mit Erinnerung (15.4).
    private func updateReminderBlocks() {
        session?.controller.reminderBlocks = persistence?.reminders.blocks(onPage: pageID) ?? []
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

    private func applyEditorFocusRequest() {
        guard editorFocusRequest == pageID, let session else { return }
        editorFocusRequest = nil
        session.controller.focus()
    }
    #else
    private var editor: some View { EmptyView() }
    #endif
}
