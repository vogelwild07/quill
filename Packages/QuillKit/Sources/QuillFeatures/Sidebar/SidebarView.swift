import QuillModel
import SwiftData
import SwiftUI

/// Sidebar eines Fensters: Favoriten, Seitenbaum, „Neue Seite“ und Papierkorb.
struct SidebarView: View {
    @Binding var selection: UUID?
    @Binding var renameRequest: UUID?
    @Binding var isShowingTrash: Bool
    let actions: PageOutlineActions

    @Query(filter: #Predicate<Page> { $0.trashedAt == nil })
    private var pages: [Page]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if canImport(AppKit)
            let entries = pages.map(PageTree.Entry.init)
            let tree = PageTree.build(entries)
            PageOutlineView(
                nodes: tree,
                favorites: PageTree.favorites(entries, in: tree),
                selection: $selection,
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
                selection = nil
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
