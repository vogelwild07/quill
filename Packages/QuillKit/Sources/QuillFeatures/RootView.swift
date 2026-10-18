import QuillDesign
import SwiftUI

/// Hauptansicht eines Quill-Fensters: Sidebar und Editor.
public struct RootView: View {
    public init() {}

    public var body: some View {
        NavigationSplitView {
            List {
                Section("Seiten") {
                    Label("Neue Seite", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ContentUnavailableView(
                "Keine Seite ausgewählt",
                systemImage: "doc.text",
                description: Text("Wähle links eine Seite oder lege eine neue an.")
            )
        }
    }
}

#Preview {
    RootView()
}
