import QuillModel
import SwiftData
import SwiftUI

/// Sidebar eines Fensters: Favoriten, Seitenbaum, „Neue Seite“ und Papierkorb.
///
/// `body` baut den Seitenbaum aus allen Seiten und läuft deshalb nur neu, wenn sich
/// Seiten ändern, nicht bei jeder Auswahl (docs/performance.md). Dafür ist die Auswahl
/// ein Objekt (`PageSelection`), und `==` vergleicht Bindings nach Wert: SwiftUI hält
/// zwei Bindings auf denselben Zustand sonst für verschieden.
struct SidebarView: View, Equatable {
    let selection: PageSelection
    @Binding var renameRequest: UUID?
    @Binding var isShowingTrash: Bool
    let actions: PageOutlineActions

    @Query(filter: #Predicate<Page> { $0.trashedAt == nil })
    private var pages: [Page]

    /// Ohne Zugriff auf den Main Actor: Objekte nach Identität, Bindings nach Wert.
    nonisolated static func == (lhs: SidebarView, rhs: SidebarView) -> Bool {
        lhs.selection === rhs.selection && lhs.actions === rhs.actions
            && lhs._renameRequest.wrappedValue == rhs._renameRequest.wrappedValue
            && lhs._isShowingTrash.wrappedValue == rhs._isShowingTrash.wrappedValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: actions.search) {
                HStack {
                    Label(String(localized: "Suchen", bundle: .module), systemImage: "magnifyingglass")
                    Spacer()
                    Text(verbatim: "⌘O")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .help(String(localized: "Schnell öffnen (⌘O)", bundle: .module))
            .accessibilityIdentifier("sidebar.search")

            #if canImport(AppKit)
            let _ = QuillSignposts.beginSidebarLoadIfNeeded()
            let entries = pages.map(PageTree.Entry.init)
            let tree = PageTree.build(entries)
            PageOutlineView(
                nodes: tree,
                favorites: PageTree.favorites(entries, in: tree),
                selection: selection,
                renameRequest: $renameRequest,
                actions: actions
            )
            #endif

            Button {
                actions.create(nil)
            } label: {
                Label(String(localized: "Neue Seite", bundle: .module), systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityIdentifier("sidebar.newPage")

            Divider()
            Button {
                selection.pageID = nil
                isShowingTrash = true
            } label: {
                Label(String(localized: "Papierkorb", bundle: .module), systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isShowingTrash ? .primary : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isShowingTrash ? AnyShapeStyle(.selection.opacity(0.25)) : AnyShapeStyle(.clear))
            .accessibilityIdentifier("sidebar.trash")
            .accessibilityAddTraits(isShowingTrash ? .isSelected : [])
        }
    }
}
