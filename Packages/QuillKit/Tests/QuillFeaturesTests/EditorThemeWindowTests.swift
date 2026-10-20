#if canImport(AppKit)
import AppKit
import QuillModel
import QuillTestFixtures
import SwiftData
import SwiftUI
import Testing
@testable import QuillEditor
@testable import QuillFeatures

/// Theme beim Start und im ganzen Fenster (ADR-024). Das Theme gilt prozessweit,
/// deshalb alles in einer Suite nacheinander.
@MainActor
@Suite("Theme: Start und Fenster", .serialized, .renderingLock)
struct EditorThemeWindowTests {
    init() { EditorThemeSettings.shared.configure(defaults: nil, initial: .standard) }

    // MARK: Start

    /// UI-Tests lesen und schreiben das Theme des Nutzers nie; Startargument nur mit Test-Store.
    @Test func testStoreNeverTouchesTheUsersChoice() {
        let key = EditorThemeSettings.defaultsKey
        UserDefaults.standard.set("sonne", forKey: key)
        defer {
            UserDefaults.standard.removeObject(forKey: key)
            EditorThemeSettings.shared.configure(defaults: nil, initial: .standard)
        }
        let settings = EditorThemeSettings.shared

        EditorThemeSetup.configure(arguments: ["Quill", "-QuillInMemoryStore", "YES"])
        #expect(settings.selection == .standard, "Gespeicherte Wahl des Nutzers nicht gelesen")
        settings.select(.abend)
        #expect(UserDefaults.standard.string(forKey: key) == "sonne", "Nichts geschrieben")

        EditorThemeSetup.configure(arguments: ["Quill", "-QuillStoreDirectory", "t", "-QuillEditorTheme", "lagune"])
        #expect(settings.selection == .lagune)
        EditorThemeSetup.configure(arguments: ["Quill", "-QuillInMemoryStore", "YES", "-QuillEditorTheme", "neon"])
        #expect(settings.selection == .standard)

        // Ohne Test-Store: die gespeicherte Wahl, Wechsel werden gespeichert.
        EditorThemeSetup.configure(arguments: ["Quill"])
        #expect(settings.selection == .sonne)
        settings.select(.tinte)
        #expect(UserDefaults.standard.string(forKey: key) == "tinte")
    }

    // MARK: Fenster mit Sidebar

    /// Echtes Fenster aus Sidebar im Systemstil und Editor mit Seitenkopf. Feste Themes
    /// gegen das System: Die Sidebar folgt dem System, der Editor dem Theme.
    /// PNGs in `$TMPDIR/QuillEditorSnapshots` (`window-<theme>-system-<hell|dunkel>`).
    @Test(arguments: EditorTheme.ID.allCases)
    func windowSnapshot(_ id: EditorTheme.ID) async throws {
        EditorThemeSettings.shared.select(id)
        defer { EditorThemeSettings.shared.select(.standard) }
        let container = try QuillStore.makeInMemoryContainer()
        let store = PageStore(modelContainer: container)
        let pageID = try await store.createPage(title: "Wochenplan")
        try await store.setIcon(pageID, to: "🌿")

        for system in [NSAppearance.Name.aqua, .darkAqua] {
            let session = PageEditorSession(
                pageID: pageID, title: "Wochenplan", icon: "🌿", store: store, context: container.mainContext,
                rename: { _, _ in }, setIcon: { _, _ in }
            )
            await session.load()
            session.controller.load(Self.demo)

            let size = CGSize(width: 1000, height: 680)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: system)
            let split = NSSplitView(frame: CGRect(origin: .zero, size: size))
            split.isVertical = true
            split.dividerStyle = .thin
            let sidebar = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 240, height: size.height))
            sidebar.material = .sidebar
            sidebar.blendingMode = .behindWindow
            let list = NSHostingView(rootView: DemoSidebar())
            list.frame = sidebar.bounds
            list.autoresizingMask = [.width, .height]
            sidebar.addSubview(list)
            split.addArrangedSubview(sidebar)
            split.addArrangedSubview(session.controller.scrollView)
            window.contentView = split
            split.setPosition(240, ofDividerAt: 0)
            split.layoutSubtreeIfNeeded()
            session.controller.textView.layoutSubtreeIfNeeded()

            let rep = try #require(split.bitmapImageRepForCachingDisplay(in: split.bounds))
            split.cacheDisplay(in: split.bounds, to: rep)
            let suffix = system == .aqua ? "hell" : "dunkel"
            let directory = FileManager.default.temporaryDirectory.appending(path: "QuillEditorSnapshots")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: directory.appending(path: "window-\(id.rawValue)-system-\(suffix).png"))

            // Sidebar im System, Editor im Theme (unten links bzw. unten rechts).
            func brightness(x: Int, fromBottom: Int) throws -> Double {
                let color = try #require(rep.colorAt(x: x, y: rep.pixelsHigh - fromBottom)?.usingColorSpace(.sRGB))
                return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
            }
            let sidebarBrightness = try brightness(x: 20, fromBottom: 20)
            #expect(system == .aqua ? sidebarBrightness > 0.6 : sidebarBrightness < 0.4, "Sidebar folgt dem System")
            let editorDark = try brightness(x: rep.pixelsWide - 20, fromBottom: 20) < 0.4
            let theme = EditorTheme.with(id: id)
            let expectDark = switch theme.appearance {
            case .followsSystem: system == .darkAqua
            case .light: false
            case .dark: true
            }
            #expect(editorDark == expectDark, "Editor im Theme \(id)")
            session.close()
        }
    }

    /// Einstellungen › Darstellung, hell und dunkel, mit „Quill“ und „Abend“ gewählt.
    @Test(arguments: [EditorTheme.ID.quill, .abend])
    func settingsSnapshot(_ id: EditorTheme.ID) throws {
        EditorThemeSettings.shared.select(id)
        defer { EditorThemeSettings.shared.select(.standard) }
        for system in [NSAppearance.Name.aqua, .darkAqua] {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: system)
            let hosting = NSHostingView(rootView: AppearanceSettingsView().background(Color(nsColor: .windowBackgroundColor)))
            hosting.frame = CGRect(x: 0, y: 0, width: 640, height: 440)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let directory = FileManager.default.temporaryDirectory.appending(path: "QuillEditorSnapshots")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: directory.appending(path: "settings-\(id.rawValue)-system-\(system == .aqua ? "hell" : "dunkel").png"))
        }
    }

    /// Eigene Beispieltexte, keine echten Daten.
    static let demo = EditorDocument(blocks: [
        EditorBlock(kind: .heading2, text: "Diese Woche"),
        EditorBlock(text: "Quill hält Notizen lokal und zeichnet sie in einem ruhigen Theme."),
        EditorBlock(kind: .todo, text: "Entwurf für das Treffen schreiben", isChecked: true),
        EditorBlock(kind: .todo, text: "Bilder für den Bericht auswählen"),
        EditorBlock(kind: .bulleted, text: "Montag: Plan"),
        EditorBlock(kind: .bulleted, text: "Freitag: Rückblick"),
        EditorBlock(kind: .quote, text: "Erst schreiben, dann ordnen."),
        EditorBlock(kind: .code, text: "let woche = 42", codeLanguage: "swift"),
        EditorBlock(kind: .heading3, text: "Notizen"),
        EditorBlock(text: "Ein Absatz mit etwas mehr Text, damit man Zeilenabstand und Farbe gut sieht."),
    ])
}

/// Sidebar im Systemstil mit Beispielseiten.
private struct DemoSidebar: View {
    var body: some View {
        List {
            Section("Favoriten") {
                Label("Wochenplan", systemImage: "doc.text")
            }
            Section("Seiten") {
                Label("Wochenplan", systemImage: "doc.text")
                Label("Rezepte", systemImage: "doc.text")
                Label("Reise im Herbst", systemImage: "doc.text")
                Label("Leseliste", systemImage: "doc.text")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}
#endif
