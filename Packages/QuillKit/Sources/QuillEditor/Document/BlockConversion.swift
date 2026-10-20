import Foundation
import QuillEditorCore
import QuillModel

/// „Umwandeln in …“: gemeinsame Liste für Format › Blockart und das Kontextmenü am Griff.
public enum BlockConversion {
    /// Textblöcke in Slash-Menü-Reihenfolge; Trenner und Bild werden eingefügt, nicht umgewandelt.
    public static let commands: [SlashCommand] = SlashCommand.all.filter { !$0.kind.isAtomic }

    /// Ziffer für ⌥⌘ in Menü-Reihenfolge. ⌥⌘8 ist „Zoom ein/aus“ der Bedienungshilfen
    /// und kommt dann nie in der App an; Code hat deshalb kein Kürzel.
    public static func shortcutDigit(for kind: BlockKind) -> Character? {
        switch kind {
        case .paragraph: "0"
        case .heading1: "1"
        case .heading2: "2"
        case .heading3: "3"
        case .bulleted: "4"
        case .numbered: "5"
        case .todo: "6"
        case .quote: "7"
        case .code, .divider, .image: nil
        }
    }
}
