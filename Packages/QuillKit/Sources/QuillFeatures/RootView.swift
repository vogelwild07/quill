#if canImport(AppKit)
import CoreSpotlight
#endif
import QuillDesign
import QuillEditor
import QuillEditorCore
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
    #if canImport(AppKit)
    @Environment(\.appearsActive) private var appearsActive
    #endif
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
    @State private var isSyncReconnectShown = false
    @State private var summaryRequest: SummaryRequest?
    @State private var todoRequest: TodoRequest?
    @State private var reminderRequest: ReminderRequest?
    @State private var voiceNoteRequest: VoiceNoteRequest?
    @State private var relatedRequest: RelatedRequest?
    @State private var isAskShown = false
    /// Hinweis zu „Heute“ oder „Heutige Termine einfügen“.
    @State private var todayNotice: String?
    /// Hinweis zu „Sprachnotiz …“ ohne Einfügemarke.
    @State private var voiceNotice: String?
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
                #if canImport(AppKit)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let sync = persistence?.sync { SyncSidebarStatus(sync: sync) }
                }
                #endif
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
                    setIcon: { id, icon in Task { try? await store.setIcon(id, to: icon) } },
                    syncActions: PageSyncActions(
                        clearRestored: { operations?.clearRestored($0) },
                        trash: { id in operations?.trash(id, selectionAfter: selectionAfterTrashing(id)) }
                    )
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
            PageJumpRouter.shared.register(window, openWindow: openWindow)
            if let pageID = WindowRouter.shared.claim(for: window) {
                selection = pageID
            }
        })
        .onChange(of: PageJumpRouter.shared.request) { applyPageJump() }
        // Treffer aus Spotlight (ADR-033).
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init) {
                showPage(id)
            }
        }
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
        .alert(
            String(localized: "Heute", bundle: .module),
            isPresented: Binding(get: { todayNotice != nil }, set: { if !$0 { todayNotice = nil } }),
            presenting: todayNotice
        ) { _ in
            Button(String(localized: "OK", bundle: .module)) {}
        } message: { notice in
            Text(notice)
        }
        .alert(
            String(localized: "Sprachnotiz", bundle: .module),
            isPresented: Binding(get: { voiceNotice != nil }, set: { if !$0 { voiceNotice = nil } }),
            presenting: voiceNotice
        ) { _ in
            Button(String(localized: "OK", bundle: .module)) {}
        } message: { notice in
            Text(notice)
        }
        .sheet(isPresented: $isSyncReconnectShown) {
            if let persistence {
                SyncReconnectView(
                    sync: persistence.sync, testFolder: persistence.syncTestFolder,
                    dismiss: { isSyncReconnectShown = false }
                )
            }
        }
        .sheet(item: $summaryRequest) { request in
            if let store, let ai = persistence?.ai {
                SummaryView(
                    request: request,
                    model: SummaryModel(pageID: request.pageID, store: store, model: ai.model),
                    dismiss: { summaryRequest = nil }
                )
            }
        }
        .sheet(item: $todoRequest) { request in
            if let ai = persistence?.ai {
                TodoView(
                    request: request, model: TodoModel(blocks: request.blocks, model: ai.model),
                    dismiss: { todoRequest = nil }
                )
            }
        }
        .sheet(item: $reminderRequest) { request in
            if let reminders = persistence?.reminders {
                ReminderView(request: request, reminders: reminders, dismiss: { reminderRequest = nil })
            }
        }
        .sheet(item: $voiceNoteRequest) { request in
            if let persistence {
                VoiceNoteView(
                    request: request,
                    model: VoiceNoteModel(transcriber: persistence.voice),
                    dismiss: { voiceNoteRequest = nil }
                )
            }
        }
        .sheet(item: $relatedRequest) { request in
            if let store, let ai = persistence?.ai {
                RelatedView(
                    request: request,
                    model: RelatedModel(request: request, store: store, model: ai.model),
                    open: { pageID in
                        relatedRequest = nil
                        showPage(pageID)
                    },
                    dismiss: { relatedRequest = nil }
                )
            }
        }
        .sheet(isPresented: $isAskShown) {
            if let store, let ai = persistence?.ai {
                AskView(
                    model: AskModel(store: store, model: ai.model),
                    open: { pageID in
                        isAskShown = false
                        showPage(pageID)
                    },
                    dismiss: { isAskShown = false }
                )
            }
        }
        // Erst nach der Meldung zum eingespielten Backup fragen, wie der Sync weitergeht.
        .onChange(of: launchNotice == nil) { askToReconnectSync() }
        // Modell fertig geladen oder Apple Intelligence umgeschaltet: Menü der KI anpassen (ADR-032).
        .onChange(of: appearsActive) { if appearsActive { Task { await persistence?.ai.refresh() } } }
        #endif
        .onAppear {
            if selection == nil { selection = UUID(uuidString: storedSelection) }
            // Ergebnis der Vorbereitung beim Start zeigt das erste Fenster (ADR-019).
            #if canImport(AppKit)
            if launchNotice == nil, let preparation = persistence?.takePreparation() {
                launchNotice = BackupLabel.launchNotice(for: preparation)
            }
            askToReconnectSync()
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
        actions.clearRestored = { operations.clearRestored($0) }
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
            exportPage: { if let selection { exportPage(selection) } },
            summarize: { if let selection { summarize(selection) } },
            suggestTodos: { suggestTodos() },
            relatedPages: { if let selection { relatedPages(selection) } },
            askNotes: { askNotes() },
            remind: { remind() },
            openToday: { openToday() },
            insertTodayEvents: { insertTodayEvents() },
            voiceNote: { voiceNote() }
        )
    }

    #if canImport(AppKit)
    /// Zusammenfassung der Seite; einfügen lässt sie sich nur, wenn ihr Editor den Fokus hat.
    private func summarize(_ pageID: UUID) {
        let editor = BlockEditorController.focused(in: window)
        summaryRequest = SummaryRequest(
            pageID: pageID,
            title: PageLabel.title(storedTitle(pageID)),
            editor: editor?.allowsEditing == true ? editor : nil
        )
    }

    /// To-dos aus der Markierung im Editor, der den Fokus hat.
    private func suggestTodos() {
        todoRequest = TodoRequest(focusedIn: window)
    }

    private func relatedPages(_ pageID: UUID) {
        relatedRequest = RelatedRequest(pageID: pageID, title: storedTitle(pageID))
    }

    /// Titel wie gespeichert, leer bei „Ohne Titel“.
    private func storedTitle(_ pageID: UUID) -> String {
        (try? context.fetch(FetchDescriptor<Page>(predicate: #Predicate { $0.id == pageID })).first?.title) ?? ""
    }

    /// Seite aus einem Blatt der KI öffnen (Quelle, verwandte Seite).
    private func showPage(_ pageID: UUID) {
        isShowingTrash = false
        selection = pageID
    }

    private func askNotes() {
        isAskShown = true
    }

    /// Erinnerung an das To-do an der Einfügemarke.
    private func remind() {
        reminderRequest = ReminderRequest(pageID: selection, focusedIn: window)
    }

    /// Tagesseite öffnen, bei Bedarf anlegen.
    private func openToday() {
        guard let store else { return }
        Task {
            do {
                showPage(try await TodayPage(store: store).open())
            } catch {
                todayNotice = String(localized: "Die Seite für heute ließ sich nicht öffnen.", bundle: .module)
            }
        }
    }

    /// Termine des Tages unter den Block an der Einfügemarke, als ein Schritt für ⌘Z.
    private func insertTodayEvents() {
        let editor = BlockEditorController.focused(in: window)
        guard let editor, editor.allowsEditing, let anchor = editor.cursorBlockID, let persistence else {
            todayNotice = String(localized: "Setze die Einfügemarke in eine Seite.", bundle: .module)
            return
        }
        let events = TodayEvents(source: persistence.calendar)
        Task {
            switch await events.lines() {
            case .denied:
                todayNotice = String(localized: "Quill darf deinen Kalender nicht lesen. Du kannst das in den Systemeinstellungen unter „Datenschutz & Sicherheit › Kalender“ ändern.", bundle: .module)
            case .empty:
                todayNotice = String(localized: "Heute stehen keine Termine in deinem Kalender.", bundle: .module)
            case .lines(let lines):
                // Während der Rückfrage zum Kalender kann der Block oder die Seite weg sein.
                guard editor.acceptsInsertion, editor.document.blocks.contains(where: { $0.id == anchor }) else {
                    todayNotice = String(localized: "Setze die Einfügemarke in eine Seite.", bundle: .module)
                    return
                }
                editor.focus()
                editor.insertBlocks(
                    lines.map { EditorBlock(kind: .bulleted, text: $0) }, after: anchor,
                    actionName: String(localized: "Termine einfügen", bundle: .module)
                )
            }
        }
    }

    /// Sprachnotiz unter den Block an der Einfügemarke.
    private func voiceNote() {
        guard let request = VoiceNoteRequest(focusedIn: window) else {
            voiceNotice = String(localized: "Setze die Einfügemarke in eine Seite.", bundle: .module)
            return
        }
        voiceNoteRequest = request
    }
    #else
    private func voiceNote() {}
    private func openToday() {}
    private func insertTodayEvents() {}
    private func summarize(_ pageID: UUID) {}
    private func suggestTodos() {}
    private func relatedPages(_ pageID: UUID) {}
    private func askNotes() {}
    private func remind() {}
    #endif

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
                QuickOpenView(store: store, imageText: persistence?.imageText, open: openHit, dismiss: { isQuickOpenShown = false })
                    .padding(.top, 56)
            }
        }
    }
    #endif

    #if canImport(AppKit)
    /// Sprung aus einem anderen Fenster (Einstellungen › Sync): Seite wählen und zum Block.
    private func applyPageJump() {
        guard let request = PageJumpRouter.shared.claim(for: window) else { return }
        isShowingTrash = false
        if let blockID = request.blockID {
            revealRequest = RevealRequest(pageID: request.pageID, blockID: blockID, range: NSRange(location: 0, length: 0))
        }
        selection = request.pageID
    }
    #endif

    /// Inhaltstreffer springen zur Fundstelle; in einem neuen Tab öffnet nur die Seite.
    private func openHit(_ hit: SearchHit, inNewTab: Bool) {
        isQuickOpenShown = false
        if inNewTab {
            open(hit.pageID, asTab: true)
            return
        }
        switch hit.kind {
        case .page:
            break
        case .content(let blockID, let match):
            revealRequest = RevealRequest(pageID: hit.pageID, blockID: blockID, range: match)
        case .image(let blockID):
            // Einfügemarke vor dem Bild: Eine Auswahl über dem Bild nähme Tippen nicht an.
            revealRequest = RevealRequest(pageID: hit.pageID, blockID: blockID, range: NSRange(location: 0, length: 0))
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
    /// Nach einem eingespielten Backup fragt das erste Fenster, wie der Sync weitergeht
    /// (ADR-029), sobald keine andere Meldung mehr offen ist.
    private func askToReconnectSync() {
        guard launchNotice == nil, !isSyncReconnectShown, let persistence, persistence.sync.asksToReconnect,
              persistence.claimSyncReconnectPrompt()
        else { return }
        isSyncReconnectShown = true
    }

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
