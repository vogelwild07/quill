import QuillDesign
import QuillModel
import SwiftData
import SwiftUI

/// Kopf einer Seite: Icon und Titel. Der Editor folgt in Phase 3.
struct PageDetailView: View {
    let pageID: UUID
    @Binding var titleFocusRequest: UUID?
    let rename: @MainActor (_ id: UUID, _ title: String) -> Void
    let setIcon: @MainActor (_ id: UUID, _ icon: String?) -> Void

    @Query private var pages: [Page]
    @State private var title = ""
    @State private var icon = ""
    @FocusState private var focusedField: Field?

    private enum Field { case title, icon }

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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(
                        String(localized: "Icon", bundle: .module),
                        text: $icon,
                        prompt: Text(Image(systemName: "face.smiling"))
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 40))
                    .frame(width: 56)
                    .focused($focusedField, equals: .icon)
                    .help(String(localized: "Emoji eingeben oder mit ⌃⌘Leertaste auswählen", bundle: .module))
                    .accessibilityIdentifier("detail.icon")

                    TextField(
                        String(localized: "Titel", bundle: .module),
                        text: $title,
                        prompt: Text("Ohne Titel", bundle: .module),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: QuillDesign.Typography.pageTitleSize, weight: .bold))
                    .focused($focusedField, equals: .title)
                    .accessibilityIdentifier("detail.title")

                    Text("Der Editor folgt in Phase 3.", bundle: .module)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: QuillDesign.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.top, 96)
                .padding(.horizontal, 48)
            }
            .navigationTitle(page.title.isEmpty ? String(localized: "Ohne Titel", bundle: .module) : page.title)
            .onAppear { load(page) }
            .onChange(of: page.title) { if focusedField != .title { title = page.title } }
            .onChange(of: page.icon) { if focusedField != .icon { icon = page.icon ?? "" } }
            .onChange(of: title) { if title != page.title { rename(pageID, title) } }
            .onChange(of: icon) { applyIcon(page) }
            .onChange(of: titleFocusRequest, initial: true) {
                if titleFocusRequest == pageID {
                    focusedField = .title
                    titleFocusRequest = nil
                }
            }
        } else {
            ContentUnavailableView(
                String(localized: "Seite nicht gefunden", bundle: .module),
                systemImage: "doc.questionmark"
            )
        }
    }

    private func load(_ page: Page) {
        title = page.title
        icon = page.icon ?? ""
    }

    /// Behält nur das erste Zeichen (ein Emoji); leer entfernt das Icon.
    private func applyIcon(_ page: Page) {
        let first = icon.first.map(String.init)
        if icon != (first ?? "") {
            icon = first ?? ""
            return
        }
        if first != page.icon {
            setIcon(pageID, first)
        }
    }
}
