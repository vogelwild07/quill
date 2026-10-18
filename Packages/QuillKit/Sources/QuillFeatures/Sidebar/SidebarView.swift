import QuillModel
import SwiftData
import SwiftUI

/// Sidebar eines Fensters: Seitenbaum und „Neue Seite“.
struct SidebarView: View {
    @Binding var selection: UUID?
    @Binding var renameRequest: UUID?
    let actions: PageOutlineActions

    @Query(filter: #Predicate<Page> { $0.trashedAt == nil })
    private var pages: [Page]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Seiten", bundle: .module)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            #if canImport(AppKit)
            PageOutlineView(
                nodes: PageTree.build(pages.map(PageTree.Entry.init)),
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
        }
    }
}
