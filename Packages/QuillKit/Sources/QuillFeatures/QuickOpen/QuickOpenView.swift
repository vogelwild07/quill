#if canImport(AppKit)
import QuillModel
import SwiftUI

/// Schwebendes Feld „Schnell öffnen“ (⌘O, ADR-017) über dem Fenster.
///
/// ↑↓ wählen, ↩ öffnen, ⌘↩ in neuem Tab, ⎋ schließen; Maus wie im Slash-Menü.
struct QuickOpenView: View {
    let store: PageStore
    let open: @MainActor (_ hit: SearchHit, _ inNewTab: Bool) -> Void
    let dismiss: @MainActor () -> Void

    @State private var model = QuickOpenModel()
    @FocusState private var isFieldFocused: Bool

    private static let selectedText = Color(nsColor: .alternateSelectedControlTextColor)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(String(localized: "Seiten und Inhalte durchsuchen", bundle: .module), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFieldFocused)
                    .accessibilityIdentifier("quickOpen.field")
                    .onKeyPress(.upArrow) { move(by: -1) }
                    .onKeyPress(.downArrow) { move(by: 1) }
                    .onKeyPress(keys: [.return]) { press in
                        openSelection(inNewTab: press.modifiers.contains(.command))
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
            }
            .padding(14)
            Divider()
            results
            Divider()
            Text("↑↓ wählen   ↩ öffnen   ⌘↩ in neuem Tab   ⎋ schließen", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .accessibilityIdentifier("quickOpen.hint")
        }
        .frame(width: 560)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .task(id: model.query) { await model.load(from: store) }
        // Einen Durchlauf später: Beim Erscheinen hält noch der Editor oder das
        // Titelfeld den Fokus und würde ihn sofort zurückholen.
        .onAppear { DispatchQueue.main.async { isFieldFocused = true } }
        // Der Fokus bleibt im Feld, solange das Panel offen ist (z. B. nach ⇥),
        // damit ⎋, ↑↓ und ↩ immer wirken; Klick daneben schließt ohnehin.
        .onChange(of: isFieldFocused) { _, focused in
            if !focused { DispatchQueue.main.async { isFieldFocused = true } }
        }
        // Ohne `.isModal`: Das Merkmal (wie auch ein ausgeblendeter Hintergrund)
        // bricht die Eltern-Kind-Kette der Bedienungshilfen (Audit, Befund A6).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Schnell öffnen", bundle: .module))
        .accessibilityIdentifier("quickOpen.panel")
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if model.hasLoaded && model.hits.isEmpty {
                        Text(model.query.isEmpty ? String(localized: "Noch keine Seiten", bundle: .module) : String(localized: "Keine Treffer", bundle: .module))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .accessibilityIdentifier("quickOpen.empty")
                    }
                    let offsets = sectionOffsets
                    ForEach(model.sections) { section in
                        Text(title(of: section.kind).uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 22, alignment: .bottom)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(section.hits.enumerated()), id: \.element.id) { offset, hit in
                            let index = (offsets[section.kind] ?? 0) + offset
                            row(hit, index: index).id(index)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: model.selection) { _, selection in proxy.scrollTo(selection) }
        }
    }

    private var sectionOffsets: [QuickOpenModel.SectionKind: Int] {
        var offsets: [QuickOpenModel.SectionKind: Int] = [:]
        var total = 0
        for section in model.sections {
            offsets[section.kind] = total
            total += section.hits.count
        }
        return offsets
    }

    private func title(of kind: QuickOpenModel.SectionKind) -> String {
        switch kind {
        case .recent: String(localized: "Zuletzt bearbeitet", bundle: .module)
        case .pages: String(localized: "Seiten", bundle: .module)
        case .content: String(localized: "Inhalt", bundle: .module)
        }
    }

    private func row(_ hit: SearchHit, index: Int) -> some View {
        let isSelected = index == model.selection
        let title = PageLabel.title(hit.title)
        let path = PageLabel.path(hit.path)
        return HStack(alignment: .top, spacing: 10) {
            PageIconView(icon: hit.icon, symbolStyle: isSelected ? Self.selectedText : Color.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).lineLimit(1)
                    if !path.isEmpty {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(isSelected ? Self.selectedText.opacity(0.8) : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                if let excerpt = hit.excerpt {
                    Text(highlighted(excerpt))
                        .font(.callout)
                        .foregroundStyle(isSelected ? Self.selectedText.opacity(0.9) : Color.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? Self.selectedText : Color.primary)
        .background(isSelected ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onTapGesture { open(hit, false) }
        // Nur echte Mausbewegung wählt aus, nicht das Scrollen per Tastatur.
        .onContinuousHover { phase in
            if case .active = phase, model.selection != index { model.select(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(hit, title: title, path: path))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("quickOpen.row")
        .accessibilityAction { open(hit, false) }
    }

    /// Fundstelle im Ausschnitt fett.
    private func highlighted(_ excerpt: String) -> AttributedString {
        var text = AttributedString(excerpt)
        let term = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty, let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    private func accessibilityLabel(_ hit: SearchHit, title: String, path: String) -> String {
        [title, path, hit.excerpt ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func move(by delta: Int) -> KeyPress.Result {
        model.moveSelection(by: delta)
        if let hit = model.selectedHit {
            AccessibilityNotification.Announcement(PageLabel.title(hit.title)).post()
        }
        return .handled
    }

    private func openSelection(inNewTab: Bool) {
        guard let hit = model.selectedHit else { return }
        open(hit, inNewTab)
    }
}
#endif
