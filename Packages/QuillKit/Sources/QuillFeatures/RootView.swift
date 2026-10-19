import QuillDesign
import QuillModel
import SwiftData
import SwiftUI

/// Hauptansicht eines Quill-Fensters: Sidebar und Seite.
///
/// Die ausgewählte Seite ist Zustand des Fensters (Scene Storage, ADR-004).
public struct RootView: View {
    @SceneStorage("selectedPageID") private var storedSelection = ""
    @State private var selection: UUID?
    @State private var renameRequest: UUID?
    @State private var titleFocusRequest: UUID?
    @State private var isShowingTrash = false
    @State private var isQuickOpenShown = false
    @State private var revealRequest: RevealRequest?
    @State private var isRestoreShown = false
    @State private var quitsAfterRestoreSheet = false
    @State private var restoreOutcome: RestoreOutcome?
    #if canImport(AppKit)
    @State private var window: NSWindow?
    #endif

    @Environment(\.pageStore) private var store
    @Environment(\.quillPersistence) private var persistence
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Page> { $0.trashedAt == nil })
    private var activePages: [Page]

    public init() {}

    public var body: some View {
        NavigationSplitView {
            if let operations {
                SidebarView(
                    selection: $selection,
                    renameRequest: $renameRequest,
                    isShowingTrash: $isShowingTrash,
                    actions: outlineActions(operations),
                    search: { isQuickOpenShown = true }
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
                ContentUnavailableView {
                    Label(String(localized: "Keine Seite ausgewählt", bundle: .module), systemImage: "doc.text")
                } description: {
                    Text("Wähle links eine Seite oder lege mit ⌘N eine neue an.", bundle: .module)
                }
                .navigationTitle("Quill")
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
            restoreOutcome.map { BackupLabel.outcome($0).title } ?? "",
            isPresented: Binding(get: { restoreOutcome != nil }, set: { if !$0 { restoreOutcome = nil } }),
            presenting: restoreOutcome
        ) { _ in
            Button(String(localized: "OK", bundle: .module)) {}
        } message: { outcome in
            Text(BackupLabel.outcome(outcome).message)
        }
        #endif
        .onAppear {
            if selection == nil { selection = UUID(uuidString: storedSelection) }
            // Ergebnis eines Wiederherstellens beim Start zeigt das erste Fenster (ADR-019).
            if restoreOutcome == nil { restoreOutcome = persistence?.takeRestoreOutcome() }
            Task { try? await store?.ensureWorkspace() }
        }
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

    private func outlineActions(_ operations: PageOperations) -> PageOutlineActions {
        PageOutlineActions(
            create: { operations.create(in: $0) },
            rename: { operations.rename($0, to: $1, from: $2) },
            move: { operations.move($0, to: $1, at: $2) },
            trash: { operations.trash($0, selectionAfter: selectionAfterTrashing($0)) },
            setFavorite: { operations.setFavorite($0, $1, at: $2) },
            moveFavorite: { operations.moveFavorite($0, at: $1) },
            openInTab: { open($0, asTab: true) },
            openInWindow: { open($0, asTab: false) },
            export: { exportPage($0) }
        )
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
            restoreBackup: { isRestoreShown = true }
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
        activePages.first { $0.id == pageID }?.isFavorite ?? false
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
        let title = activePages.first { $0.id == pageID }?.title ?? ""
        PageExport.run(pageID: pageID, title: title, store: store, window: window)
        #endif
    }

    /// Bleibt die Auswahl nach dem Papierkorb gültig? Liegt sie in der
    /// weggeworfenen Seite oder darunter, geht sie an die Elternseite.
    private func selectionAfterTrashing(_ trashed: UUID) -> UUID? {
        guard let selection else { return nil }
        let tree = PageTree.build(activePages.map(PageTree.Entry.init))
        guard PageTree.isSelfOrDescendant(selection, of: trashed, in: tree) else { return selection }
        return PageTree.ancestors(of: trashed, in: tree)?.last
    }
}

#Preview {
    RootView()
        .modelContainer(for: Page.self, inMemory: true)
}
