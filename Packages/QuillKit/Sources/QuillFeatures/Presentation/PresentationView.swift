#if canImport(AppKit)
import AppKit
import QuillDesign
import QuillEditor
import QuillModel
import SwiftData
import SwiftUI

/// Fenster „Präsentation“ (⌥⌘P, 18.2, ADR-035): eins je Seite, im Vollbild. `QuillApp`
/// legt die Szene an; `QuillCommands` öffnet sie mit der ausgewählten Seite.
public struct PresentationScene: Scene {
    public static let windowID = "presentation"
    let persistence: QuillPersistence?

    public init(persistence: QuillPersistence?) {
        self.persistence = persistence
    }

    public var body: some Scene {
        WindowGroup(String(localized: "Präsentation", bundle: .module), id: Self.windowID, for: UUID.self) { $pageID in
            if let persistence, let pageID {
                PresentationView(pageID: pageID, persistence: persistence)
                    .modelContainer(persistence.container)
            }
        }
        .windowStyle(.hiddenTitleBar)
        // Nach einem Neustart keine Präsentation von selbst wieder öffnen.
        .restorationBehavior(.disabled)
    }
}

struct PresentationView: View {
    let pageID: UUID
    let persistence: QuillPersistence

    @Query private var pages: [Page]
    @State private var model: PresentationModel
    @State private var keys = PresentationKeys()
    @Environment(\.dismiss) private var dismiss

    init(pageID: UUID, persistence: QuillPersistence) {
        self.pageID = pageID
        self.persistence = persistence
        _pages = Query(filter: #Predicate<Page> { $0.id == pageID })
        _model = State(initialValue: PresentationModel(pageID: pageID, store: persistence.store))
    }

    var body: some View {
        content
            .frame(minWidth: QuillDesign.Presentation.minWindowWidth, minHeight: QuillDesign.Presentation.minWindowHeight)
            .background(Color(nsColor: EditorColor.background))
            .navigationTitle(String(localized: "Präsentation: \(PageLabel.title(pages.first?.title ?? ""))", bundle: .module))
            .background(WindowAccessor { window in
                keys.start(in: window) { key in
                    if key == .close { dismiss() } else { model.handle(key) }
                }
                // Test-Stores bleiben im Fenster: Vollbild wechselt den Space (ADR-035).
                if !persistence.isTestStore, !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            })
            .task { await model.load(title: PageLabel.title(pages.first?.title ?? "")) }
            .onDisappear { keys.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .failed:
            EmptyStateView(.pageNotFound, id: "presentation.failed")
        case .ready:
            ZStack(alignment: .bottomTrailing) {
                GeometryReader { proxy in
                    BlockEditorView(controller: model.controller)
                        .onChange(of: proxy.size.width, initial: true) { _, width in
                            model.fit(width: width)
                        }
                }
                Text("Folie \(model.index + 1) von \(model.slides.count)", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(QuillDesign.Presentation.counterPadding)
                    .accessibilityIdentifier("presentation.counter")
            }
        }
    }
}

/// Tasten der Präsentation. Ein Monitor nur für dieses Fenster statt `onKeyPress`: Im
/// Fenster nimmt keine Ansicht den Fokus, der Editor ist ohne Schreibmarke.
@MainActor
final class PresentationKeys {
    enum Key: Equatable {
        case next, previous, first, last, close
    }

    private var monitor: Any?
    private var closing: (any NSObjectProtocol)?

    /// Endet mit `stop()` oder spätestens, wenn das Fenster schließt.
    func start(in window: NSWindow, handle: @escaping @MainActor (Key) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            guard let window, event.window === window,
                  let key = Self.key(special: event.specialKey, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
            else { return event }
            handle(key)
            return nil
        }
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let closing { NotificationCenter.default.removeObserver(closing) }
        monitor = nil
        closing = nil
    }

    /// →, ↓, Leertaste, Bild ab, ↩ weiter; ←, ↑, Bild auf, ⇧-Leertaste zurück; Pos1, Ende; Esc.
    /// Mit ⌘, ⌥ oder ⌃ gehört die Taste dem Menü oder dem System.
    nonisolated static func key(special: NSEvent.SpecialKey?, characters: String?, modifiers: NSEvent.ModifierFlags = []) -> Key? {
        guard modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }
        let shift = modifiers.contains(.shift)
        switch special {
        case .rightArrow, .downArrow, .pageDown, .carriageReturn, .enter: return .next
        case .leftArrow, .upArrow, .pageUp: return .previous
        case .home: return .first
        case .end: return .last
        default: break
        }
        switch characters {
        case " ": return shift ? .previous : .next
        case "\u{1b}": return .close
        default: return nil
        }
    }
}
#endif
