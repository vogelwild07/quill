#if canImport(AppKit)
import QuillDesign
import QuillEditor
import QuillEditorCore
import SwiftData
import SwiftUI

/// Einstellungen (⌘,): Darstellung, Sync, Zeitreise, KI, Spotlight, Schnellnotiz, Lizenzen.
public struct SettingsView: View {
    private enum Pane: Hashable { case appearance, sync, timeTravel, ai, spotlight, quickNote, licenses }

    private let persistence: QuillPersistence?
    /// Eigene Auswahl: Die Einstellungen öffnen nach jedem Start mit „Darstellung“.
    @State private var pane = Pane.appearance

    public init(persistence: QuillPersistence?) {
        self.persistence = persistence
    }

    public var body: some View {
        TabView(selection: $pane) {
            Tab(String(localized: "Darstellung", bundle: .module), systemImage: "paintpalette", value: .appearance) {
                AppearanceSettingsView()
            }
            if let persistence {
                Tab(String(localized: "Sync", bundle: .module), systemImage: "arrow.triangle.2.circlepath", value: .sync) {
                    SyncSettingsView(sync: persistence.sync, testFolder: persistence.syncTestFolder)
                        .frame(minHeight: 420)
                        // Titel der Seiten mit Konflikt; die Einstellungen sind eine eigene Szene.
                        .modelContainer(persistence.container)
                }
                Tab(String(localized: "Zeitreise", bundle: .module), systemImage: "clock.arrow.circlepath", value: .timeTravel) {
                    TimeTravelSettingsView(retention: persistence.imageRetention)
                }
                Tab(String(localized: "KI", bundle: .module), systemImage: "sparkles", value: .ai) {
                    AISettingsView(ai: persistence.ai)
                }
                Tab(String(localized: "Spotlight", bundle: .module), systemImage: "magnifyingglass", value: .spotlight) {
                    SpotlightSettingsView(spotlight: persistence.spotlight)
                }
                Tab(String(localized: "Schnellnotiz", bundle: .module), systemImage: "square.and.pencil", value: .quickNote) {
                    QuickNoteSettingsView(note: persistence.quickNote)
                }
            }
            Tab(String(localized: "Lizenzen", bundle: .module), systemImage: "doc.text", value: .licenses) {
                LicensesView()
            }
        }
        .frame(width: 640)
    }
}

/// Lizenztexte der Bausteine anderer, unverändert und daher nicht übersetzt
/// (`Scripts/third-party-licenses.py`). Rund 200 KB: in Abschnitten, die erst beim
/// Scrollen gesetzt werden.
struct LicensesView: View {
    private static let sections: [String] = (Bundle.module.url(forResource: "ThirdPartyLicenses", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
        .components(separatedBy: "\n\n")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quill steht unter der GPL-3.0-or-later. Es enthält diese Bausteine anderer:", bundle: .module)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.sections.indices, id: \.self) { index in
                        Text(verbatim: Self.sections[index])
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                // Die LazyVStack ist für VoiceOver eine eigene Gruppe und braucht einen Namen.
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Lizenztexte", bundle: .module))
            }
            .background(.background.secondary, in: .rect(cornerRadius: QuillDesign.Radius.large))
            .accessibilityIdentifier("settings.licenses")
        }
        .padding(20)
        .frame(height: 420)
    }
}

/// Theme des Editors: Liste mit kleinen Vorschauen, daneben eine große (ADR-024);
/// darunter der Fokus-Modus. Ein Klick wirkt sofort in allen Fenstern.
struct AppearanceSettingsView: View {
    private var settings = EditorThemeSettings.shared
    private var focus = EditorFocusSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            themes
            Divider()
            Toggle(isOn: Binding(get: { focus.isEnabled }, set: { focus.setEnabled($0) })) {
                Text("Fokus-Modus", bundle: .module)
                Text("Die Zeile mit dem Cursor bleibt in der Mitte, die übrigen Absätze treten zurück. Auch über Darstellung › Fokus-Modus (⇧⌘F).", bundle: .module)
            }
            .accessibilityIdentifier("settings.focusMode")
        }
        .padding(20)
    }

    private var themes: some View {
        HStack(alignment: .top, spacing: 20) {
            List(selection: selection) {
                ForEach(EditorTheme.all) { theme in
                    ThemeRow(theme: theme)
                        .tag(theme.id)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds(.disabled)
            .frame(width: 230)
            .accessibilityLabel(String(localized: "Theme", bundle: .module))
            .accessibilityIdentifier("settings.themes")

            ThemePreview(theme: settings.theme)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 360)
    }

    private var selection: Binding<EditorTheme.ID?> {
        Binding(
            get: { settings.selection },
            set: { if let id = $0 { settings.select(id) } }
        )
    }
}

/// Zeile: kleine Vorschau, Name, hell/dunkel.
private struct ThemeRow: View {
    let theme: EditorTheme

    var body: some View {
        HStack(spacing: 10) {
            ThemeSwatch(theme: theme)
            // Kennung nur am Text: Der Audit misst den Kontrast im Rahmen des Elements,
            // mit der farbigen Vorschau darin schlüge er fehl.
            VStack(alignment: .leading, spacing: 1) {
                Text(theme.name)
                Text(Self.caption(theme.appearance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.theme.\(theme.id.rawValue)")
        }
        .padding(.vertical, 3)
    }

    static func caption(_ appearance: EditorTheme.Appearance) -> String {
        switch appearance {
        case .followsSystem: String(localized: "Hell und dunkel", bundle: .module)
        case .light: String(localized: "Nur hell", bundle: .module)
        case .dark: String(localized: "Nur dunkel", bundle: .module)
        }
    }
}

/// Theme-Farben passend zur Darstellung: im System hell oder dunkel, feste Themes immer gleich.
private struct ThemeColorsReader<Content: View>: View {
    let theme: EditorTheme
    @ViewBuilder let content: (EditorThemeColors) -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let settings = EditorThemeSettings.shared
        let colors = theme.colors(dark: colorScheme == .dark, increaseContrast: settings.increaseContrast)
        content(colors)
            .environment(\.colorScheme, scheme)
    }

    /// Systemfarben in der Vorschau (z. B. Standard) wie im Editor: feste Themes erzwingen ihre Darstellung.
    private var scheme: ColorScheme {
        switch theme.appearance {
        case .followsSystem: colorScheme
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Kleine Vorschau: Fläche mit Überschrift, zwei Textzeilen und Akzentpunkt.
private struct ThemeSwatch: View {
    let theme: EditorTheme

    var body: some View {
        ThemeColorsReader(theme: theme) { colors in
            RoundedRectangle(cornerRadius: QuillDesign.Radius.small)
                .fill(Color(nsColor: colors.background))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Capsule().fill(Color(nsColor: colors.heading)).frame(width: 22, height: 4)
                        Capsule().fill(Color(nsColor: colors.text)).frame(width: 30, height: 2.5)
                        HStack(spacing: 3) {
                            Capsule().fill(Color(nsColor: colors.quoteBar)).frame(width: 2.5, height: 6)
                            Capsule().fill(Color(nsColor: colors.link)).frame(width: 16, height: 2.5)
                        }
                    }
                    .padding(6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: QuillDesign.Radius.small)
                        .strokeBorder(.separator)
                }
                .frame(width: 48, height: 34)
        }
        .accessibilityHidden(true)
    }
}

/// Große Vorschau mit eigenen Beispieltexten, gezeichnet in den Farben des Themes.
private struct ThemePreview: View {
    let theme: EditorTheme

    var body: some View {
        ThemeColorsReader(theme: theme) { colors in
            VStack(alignment: .leading, spacing: 10) {
                Text("Ein ruhiger Morgen", bundle: .module)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(nsColor: colors.heading))
                let link = Text("Link", bundle: .module).foregroundStyle(Color(nsColor: colors.link)).underline()
                Text("Notizen, die bleiben, und ein \(link)", bundle: .module)
                    .foregroundStyle(Color(nsColor: colors.text))
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(nsColor: colors.quoteBar))
                        .frame(width: QuillDesign.EditorLayout.quoteBarWidth)
                    Text("Gute Werkzeuge treten zurück.", bundle: .module)
                        .foregroundStyle(Color(nsColor: colors.secondary))
                }
                .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "let theme = \"\(theme.name)\"")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(nsColor: colors.text))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: colors.codeBackground), in: .rect(cornerRadius: QuillDesign.Radius.large))
                todo(String(localized: "Entwurf fertig", bundle: .module), checked: true, colors: colors)
                todo(String(localized: "Theme wählen", bundle: .module), checked: false, colors: colors)
                Text("Markierter Text", bundle: .module)
                    .foregroundStyle(Color(nsColor: colors.text))
                    .background(Color(nsColor: colors.selection))
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: colors.background), in: .rect(cornerRadius: QuillDesign.Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: QuillDesign.Radius.large).strokeBorder(.separator)
            }
        }
        // Ein Bild: Die Beispieltexte sind nur Anschauung; das Label nennt das Theme.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(String(localized: "Vorschau: \(theme.name)", bundle: .module))
        .accessibilityIdentifier("settings.preview")
    }

    private func todo(_ title: String, checked: Bool, colors: EditorThemeColors) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: QuillDesign.Radius.small)
                .fill(checked ? Color(nsColor: colors.accent) : .clear)
                .strokeBorder(checked ? .clear : Color(nsColor: colors.done), lineWidth: 1.2)
                .overlay {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(nsColor: colors.onAccent))
                    }
                }
                .frame(width: 14, height: 14)
            Text(title)
                .strikethrough(checked)
                .foregroundStyle(Color(nsColor: checked ? colors.done : colors.text))
        }
    }
}
#endif
