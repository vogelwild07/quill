import AppKit
import QuillEditor
import QuillEditorSpike
import SwiftUI

/// Wegwerf-App für den Editor-Spike (Phase 1). Wird nach dem ADR entfernt.
@main
struct EditorSpikeApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: SpikeAppDelegate
    @State private var session = SpikeSession()

    var body: some Scene {
        WindowGroup("Editor-Spike") {
            SpikeRootView(session: session)
        }
        .defaultSize(width: 1100, height: 800)
        .commands {
            CommandMenu("Spike") {
                Button("Willkommensdokument") { session.load(SpikeSamples.welcome) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("1000 Blöcke laden") { session.load(SpikeSamples.large(blockCount: 1000)) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Divider()
                Button(session.showsMarkdown ? "Markdown ausblenden" : "Markdown einblenden") {
                    session.showsMarkdown.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
            }
        }
    }
}

@MainActor
@Observable
final class SpikeSession {
    let controller = BlockEditorController(document: SpikeSamples.welcome)
    var markdown = ""
    var showsMarkdown = true

    init() {
        controller.onChange = { [weak self] document in
            self?.markdown = MarkdownSerializer.markdown(for: document, blocks: 0..<document.count)
        }
        markdown = MarkdownSerializer.markdown(for: controller.document, blocks: 0..<controller.document.count)
    }

    func load(_ document: EditorDocument) {
        controller.load(document)
        markdown = MarkdownSerializer.markdown(for: document, blocks: 0..<document.count)
    }
}

struct SpikeRootView: View {
    @Bindable var session: SpikeSession

    var body: some View {
        BlockEditorView(controller: session.controller)
            .onAppear { session.controller.focus() }
            .inspector(isPresented: $session.showsMarkdown) {
                ScrollView {
                    Text(session.markdown)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .inspectorColumnWidth(min: 220, ideal: 300, max: 420)
            }
    }
}

/// `-benchmark`: misst im echten Fenster, schreibt JSON nach stdout und beendet sich.
final class SpikeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("-snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                MainActor.assumeIsolated { Self.writeSnapshots() }
            }
            return
        }
        guard CommandLine.arguments.contains("-benchmark") else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let window = NSWindow(
                    contentRect: CGRect(x: 120, y: 120, width: 1100, height: 800),
                    styleMask: [.titled, .resizable], backing: .buffered, defer: false
                )
                window.makeKeyAndOrderFront(nil)
                let result = SpikeBenchmark.run(in: window)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(result), let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
                fflush(stdout)
                NSApp.terminate(nil)
            }
        }
    }

    /// `-snapshot`: rendert das Hauptfenster hell und dunkel als PNG (ohne Bildschirmaufnahme).
    @MainActor
    private static func writeSnapshots() {
        guard let window = NSApp.windows.first(where: { $0.contentView is NSHostingView<AnyView> || $0.title == "Editor-Spike" }),
              let view = window.contentView else {
            print("Kein Fenster für den Snapshot gefunden.")
            NSApp.terminate(nil)
            return
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        for (name, appearance) in [("hell", NSAppearance.Name.aqua), ("dunkel", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            view.needsDisplay = true
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = directory.appendingPathComponent("spike-\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print(url.path)
        }
        fflush(stdout)
        NSApp.terminate(nil)
    }
}
