import QuillDesign
import QuillModel
import SwiftData
import SwiftUI

/// Kopf einer Seite: Icon und Titel. Sitzt im Editor über dem ersten Block.
///
/// ↩ im Titel springt in den ersten Block (`submitTitle`), ↑ in der ersten Zeile
/// des Editors zurück (`HeaderFocus`).
struct PageHeaderView: View {
    let pageID: UUID
    let focus: HeaderFocus
    let rename: @MainActor (_ id: UUID, _ title: String) -> Void
    let setIcon: @MainActor (_ id: UUID, _ icon: String?) -> Void
    let submitTitle: @MainActor () -> Void

    @Query private var pages: [Page]
    @State private var title = ""
    @State private var icon = ""
    @State private var titleSelection: TextSelection?
    @FocusState private var focusedField: Field?

    private enum Field { case title, icon }

    /// `title` und `icon` sind die Startwerte, damit schon die erste Messung der
    /// Kopfhöhe stimmt (sonst überdeckt ein mehrzeiliger Titel kurz den Text).
    init(
        pageID: UUID,
        title: String,
        icon: String?,
        focus: HeaderFocus,
        rename: @escaping @MainActor (UUID, String) -> Void,
        setIcon: @escaping @MainActor (UUID, String?) -> Void,
        submitTitle: @escaping @MainActor () -> Void
    ) {
        self.pageID = pageID
        self.focus = focus
        self.rename = rename
        self.setIcon = setIcon
        self.submitTitle = submitTitle
        _title = State(initialValue: title)
        _icon = State(initialValue: icon ?? "")
        _pages = Query(filter: #Predicate<Page> { $0.id == pageID })
    }

    var body: some View {
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
            .accessibilityLabel(String(localized: "Seitensymbol", bundle: .module))
            .accessibilityValue(icon.isEmpty ? String(localized: "Kein Symbol", bundle: .module) : icon)
            .accessibilityIdentifier("detail.icon")

            TextField(
                String(localized: "Titel", bundle: .module),
                text: $title,
                selection: $titleSelection,
                prompt: Text("Ohne Titel", bundle: .module),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: QuillDesign.Typography.pageTitleSize, weight: .bold))
            .focused($focusedField, equals: .title)
            .onSubmit { submitTitle() }
            .accessibilityLabel(String(localized: "Seitentitel", bundle: .module))
            .accessibilityIdentifier("detail.title")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: page?.title) { if focusedField != .title, let page { title = page.title } }
        .onChange(of: page?.icon) { if focusedField != .icon, let page { icon = page.icon ?? "" } }
        .onChange(of: title) { if let page, title != page.title { rename(pageID, title) } }
        .onChange(of: icon) { applyIcon() }
        .onChange(of: focus.titleRequest, initial: true) {
            guard focus.titleRequest > 0 else { return }
            // Cursor ans Ende statt alles markieren: Weitertippen ergänzt den Titel.
            // Das Feld markiert beim Fokussieren alles; deshalb einen Durchlauf später.
            focusedField = .title
            Task { titleSelection = TextSelection(insertionPoint: title.endIndex) }
        }
    }

    private var page: Page? { pages.first }

    /// Behält nur das erste Zeichen (ein Emoji); leer entfernt das Icon.
    private func applyIcon() {
        guard let page else { return }
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

/// Fokus-Anfragen an den Titel im Kopf (über die Grenze des `NSHostingController`).
@MainActor
@Observable
final class HeaderFocus {
    private(set) var titleRequest = 0

    func requestTitle() { titleRequest += 1 }
}
