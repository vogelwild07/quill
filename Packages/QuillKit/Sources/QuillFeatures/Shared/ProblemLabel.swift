import SwiftUI

/// Meldung zu einem Problem: Warnsymbol in den Farben, die das System dafür vorsieht,
/// Text in Primärfarbe. Außerhalb des Editors nur semantische Systemfarben (docs/design.md).
struct ProblemLabel: View {
    let message: String

    var body: some View {
        Label {
            Text(message).foregroundStyle(.primary)
        } icon: {
            ProblemSymbol()
        }
    }
}

/// Das Warnsymbol allein, z. B. neben dem Status in der Sidebar.
struct ProblemSymbol: View {
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .symbolRenderingMode(.multicolor)
    }
}
