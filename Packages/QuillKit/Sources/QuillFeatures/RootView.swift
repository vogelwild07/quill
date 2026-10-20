import QuillDesign
import QuillModel
import SwiftData
import SwiftUI

/// Hauptansicht eines Quill-Fensters: Sidebar und Seite.
///
/// Die ausgewählte Seite ist Zustand des Fensters (Scene Storage, ADR-004).
public struct RootView: View {
    @SceneStorage("selectedPageID") private var storedSelection = ""
    @State private var pageSelection = PageSelection()
    @State private var renameRequest: UUID?
    @State private var titleFocusRequest: UUID?
    @State private var editorFocusRequest: UUID?
    @State private var isShowingTrash = false
    @State private var isQuickOpenShown = false
    @State private var revealRequest: RevealRequest?
    @State private var isRestoreShown = false
    @State private var quitsAfterRestoreSheet = false
    @State private var sidebarActions = PageOutlineActions()
    private var selection: UUID? {
        get { pageSelection.pageID }
        nonmutating set { pageSelection.pageID = newValue }
    }
    #if canImport(AppKit)
    @State private var window: NSWindow?
    @State private var launchNotice: LaunchNotice?
    #endif

    @Environment(\.pageStore) private var store
    @Environment(\.quillPersistence) private var persistence
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var context
    /// Nur Favoriten: Der Stern braucht nicht alle Seiten. Eine Abfrage über alle Seiten
    /// liefe bei jeder Änderung neu (docs/performance.md).
    @Query(filter: #Predicate<Page> { $0.trashedAt == nil && $0.isFavorite })
    private var activeFavorites: [Page]

    public init() {}

    public var body: some View {
        NavigationSplitView {
            if operations != nil {
                SidebarView(
                    selection: pageSelection,
                    renameRequest: $renameRequest,
                    isShowingTrash: $isShowingTrash,
                    actions: sidebarActions
                )
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            }
        } detail: {
            if isShowingTrash, let operations {
                TrashView(restore: { operations.restore($0) })
            } else if let selection, let store {
                PageDetailView(
                    pageID: selection,
                    titleFocusRequest: $titleFocusRequest,
                    editorFocusRequest: $editorFocusRequest,
                    revealRequest: $revealRequest,
                    rename: { id, title in Task { try? await store.rename(id, to: title) } },
                    setIcon: { id, icon in Task { try? await store.setIcon(id, to: icon) } }
                )
                .id(selection)
                .toolbar {
                    ToolbarItem {
                        favoriteButton(selection, operations: operations)
                    }
                }
            } else {
                EmptyStateView(
                    .noSelection,
                    id: "detail.emptyState",
                    actionTitle: String(localized: "Neue Seite", bundle: .module),
                    action: { sidebarActions.create(nil) }
                )
                .navigationTitle(Text(verbatim: "Quill"))
            }
        }
        #if canImport(AppKit)
        .overlay { quickOpen }
        .background(WindowAccessor { window in
            self.window = window
            if let pageID = WindowRouter.shared.claim(for: window) {
                selection = pageID
            }
        })
        #endif
        .focusedSceneValue(\.pageActions, operations.map(pageActions))
        .focusedSceneValue(\.windowActions, persistence.map { _ in WindowActions(restoreBackup: { isRestoreShown = true }) })
        #if canImport(AppKit)
        .sheet(isPresented: $isRestoreShown, onDismiss: quitIfRestoreRequested) {
            if let persistence {
                BackupRestoreView(
                    persistence: persistence,
                    dismiss: { isRestoreShown = false },
                    requested: {
                        quitsAfterRestoreSheet = true
                        isRestoreShown = false
                    }
                )
            }
        }
        .alert(
            launchNotice?.title ?? "",
            isPresented: Binding(get: { launchNotice != nil }, set: { if !$0 { launchNotice = nil } }),
            presenting: launchNotice
        ) { _ in
            Button(String(localized: "OK", bundle: .module)) {}
        } message: { notice in
            Text(notice.message)
        }
        #endif
        .onAppear {
            if selection == nil { selection = UUID(uuidString: storedSelection) }
            // Ergebnis der Vorbereitung beim Start zeigt das erste Fenster (ADR-019).
            #if canImport(AppKit)
            if launchNotice == nil, let preparation = persistence?.takePreparation() {
                launchNotice = BackupLabel.launchNotice(for: preparation)
            }
            #endif
            Task { try? await store?.ensureWorkspace() }
        }
        .onChange(of: actionDependencies, initial: true) { updateSidebarActions() }
        .onChange(of: selection) {
            storedSelection = selection?.uuidString ?? ""
            if selection != nil { isShowingTrash = false }
        }
    }

    // MARK: - Aktionen

    private var operations: PageOperations? {
        guard let store else { return nil }
        return PageOperations(
            store: store,
            undoManager: undoManager,
            select: { selection = $0 },
            focusTitle: { titleFocusRequest = $0 }
        )
    }

    /// Wovon die Closures der Sidebar abhängen: Store und Undo-Manager aus der Umgebung.
    /// Zustand des Fensters lesen sie beim Ausführen selbst.
    private var actionDependencies: [ObjectIdentifier?] {
        [store.map(ObjectIdentifier.init), undoManager.map(ObjectIdentifier.init)]
    }

    /// Setzt die Closures der immer gleichen Instanz (siehe `PageOutlineActions`), nur
    /// wenn sich ihre Abhängigkeiten ändern, nie während `body`.
    private func updateSidebarActions() {
        guard let operations else { return }
        let actions = sidebarActions
        actions.create = { operations.create(in: $0) }
        actions.rename = { operations.rename($0, to: $1, from: $2) }
        actions.move = { operations.move($0, to: $1, at: $2) }
        actions.trash = { operations.trash($0, selectionAfter: selectionAfterTrashing($0)) }
        actions.setFavorite = { operations.setFavorite($0, $1, at: $2) }
        actions.moveFavorite = { operations.moveFavorite($0, at: $1) }
        actions.openInTab = { open($0, asTab: true) }
        actions.openInWindow = { open($0, asTab: false) }
        actions.export = { exportPage($0) }
        actions.search = { isQuickOpenShown = true }
        actions.focusPage = { target in
            guard let selection else { return }
            switch target {
            case .title: titleFocusRequest = selection
            case .editor: editorFocusRequest = selection
            }
        }
    }

    private func pageActions(_ operations: PageOperations) -> PageActions {
        PageActions(
            selection: selection,
            isFavorite: isFavorite(selection),
            isQuickOpenShown: isQuickOpenShown,
            newPage: { operations.create(in: nil) },
            newSubpage: { if let selection { operations.create(in: selection) } },
            rename: { renameRequest = selection },
            quickOpen: { isQuickOpenShown = true },
            trash: {
                if let selection {
                    operations.trash(selection, selectionAfter: selectionAfterTrashing(selection))
                }
            },
            toggleFavorite: { if let selection { operations.setFavorite(selection, !isFavorite(selection)) } },
            openInTab: { if let selection { open(selection, asTab: true) } },
            openInWindow: { if let selection { open(selection, asTab: false) } },
            exportPage: { if let selection { exportPage(selection) } }
        )
    }

    #if canImport(AppKit)
    /// „Schnell öffnen“ über dem ganzen Fenster; Klick daneben schließt.
    @ViewBuilder
    private var quickOpen: some View {
        if isQuickOpenShown, let store {
            ZStack(alignment: .top) {
                Color(nsColor: .shadowColor).opacity(0.08)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture { isQuickOpenShown = false }
                    .accessibilityHidden(true)
                QuickOpenView(store: store, open: openHit, dismiss: { isQuickOpenShown = false })
                    .padding(.top, 56)
            }
        }
    }
    #endif

    /// Inhaltstreffer springen zur Fundstelle; in einem neuen Tab öffnet nur die Seite.
    private func openHit(_ hit: SearchHit, inNewTab: Bool) {
        isQuickOpenShown = false
        if inNewTab {
            open(hit.pageID, asTab: true)
            return
        }
        if case .content(let blockID, let match) = hit.kind {
            revealRequest = RevealRequest(pageID: hit.pageID, blockID: blockID, range: match)
        }
        selection = hit.pageID
    }

    private func isFavorite(_ pageID: UUID?) -> Bool {
        activeFavorites.contains { $0.id == pageID }
    }

    /// Stern in der Symbolleiste: Seite zu den Favoriten (ADR-017).
    @ViewBuilder
    private func favoriteButton(_ pageID: UUID, operations: PageOperations?) -> some View {
        let favorite = isFavorite(pageID)
        Button {
            operations?.setFavorite(pageID, !favorite)
        } label: {
            if favorite {
                Label(String(localized: "Aus Favoriten entfernen", bundle: .module), systemImage: "star.fill")
            } else {
                Label(String(localized: "Zu Favoriten hinzufügen", bundle: .module), systemImage: "star")
            }
        }
        .accessibilityIdentifier("page.favorite")
        .accessibilityAddTraits(favorite ? .isSelected : [])
    }

    private func open(_ pageID: UUID, asTab: Bool) {
        #if canImport(AppKit)
        WindowRouter.shared.prepare(pageID: pageID, asTabOf: asTab ? window : nil)
        openWindow(id: WindowRouter.windowID)
        #endif
    }

    #if canImport(AppKit)
    /// Ein Backup ist vorgemerkt: beenden, beim nächsten Start wird getauscht (ADR-019).
    private func quitIfRestoreRequested() {
        guard quitsAfterRestoreSheet else { return }
        quitsAfterRestoreSheet = false
        NSApp.terminate(nil)
    }
    #endif

    /// Markdown-Export der Seite mit Ordnerdialog (ADR-018).
    private func exportPage(_ pageID: UUID) {
        #if canImport(AppKit)
        guard let store else { return }
        let title = activePages().first { $0.id == pageID }?.title ?? ""
        PageExport.run(pageID: pageID, title: title, store: store, window: window)
        #endif
    }

    /// Seiten außerhalb des Papierkorbs, erst beim Ausführen einer Aktion gelesen.
    private func activePages() -> [Page] {
        (try? context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.trashedAt == nil }))) ?? []
    }

    /// Bleibt die Auswahl nach dem Papierkorb gültig? Liegt sie in der
    /// weggeworfenen Seite oder darunter, geht sie an die Elternseite.
    private func selectionAfterTrashing(_ trashed: UUID) -> UUID? {
        guard let selection else { return nil }
        let tree = PageTree.build(activePages().map(PageTree.Entry.init))
        guard PageTree.isSelfOrDescendant(selection, of: trashed, in: tree) else { return selection }
        return PageTree.ancestors(of: trashed, in: tree)?.last
    }
}

#Preview {
    RootView()
        .modelContainer(for: Page.self, inMemory: true)
}
