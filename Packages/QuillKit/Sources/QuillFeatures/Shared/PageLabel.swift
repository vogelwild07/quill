import Foundation
import SwiftUI

/// Anzeige von Seitentitel, Pfad und Icon in Listen (Schnell öffnen, Papierkorb).
enum PageLabel {
    /// Titel oder „Ohne Titel“.
    static func title(_ title: String) -> String {
        title.isEmpty ? String(localized: "Ohne Titel", bundle: .module) : title
    }

    /// Elternseiten von oben nach unten, getrennt mit „ › “; leer ohne Elternseiten.
    static func path(_ titles: [String]) -> String {
        titles.map(title).joined(separator: " › ")
    }
}

/// Emoji der Seite oder das Standardsymbol wie in der Sidebar.
struct PageIconView: View {
    let icon: String?
    var symbolStyle: Color = .secondary

    var body: some View {
        if let icon, !icon.isEmpty {
            Text(icon)
        } else {
            Image(systemName: "doc.text")
                .foregroundStyle(symbolStyle)
                .accessibilityHidden(true)
        }
    }
}
