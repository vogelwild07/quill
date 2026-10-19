#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

/// Design-Tokens für Quill. Werte siehe `docs/design.md`.
public enum QuillDesign {
    /// Maximale Breite des Editor-Textkörpers in Punkt.
    public static let contentMaxWidth: CGFloat = 720

    /// Schriftgrößen und Zeilenhöhen des Editors.
    public enum Typography {
        public static let pageTitleSize: CGFloat = 32
        public static let heading1Size: CGFloat = 26
        public static let heading2Size: CGFloat = 21
        public static let heading3Size: CGFloat = 17
        public static let bodySize: CGFloat = 15
        public static let codeSize: CGFloat = 13

        public static let bodyLineHeight: CGFloat = 1.5
        public static let headingLineHeight: CGFloat = 1.25
        public static let codeLineHeight: CGFloat = 1.45
    }

    /// Abstände im 4-pt-Raster.
    public enum Spacing {
        public static let blockGap: CGFloat = 4
        public static let beforeHeading: CGFloat = 16
        /// Einrückung pro Ebene und Breite der Listen-Marker.
        public static let indentStep: CGFloat = 24
        public static let quoteInset: CGFloat = 16
        public static let codePadding: CGFloat = 12
    }

    /// Maße der Editorseite und der selbst gezeichneten Elemente darin.
    public enum EditorLayout {
        /// Mindestabstand der Textspalte zum Fensterrand.
        public static let minSideMargin: CGFloat = 56
        /// Abstand über dem Text, wenn der Editor allein steht.
        public static let topPadding: CGFloat = 48
        /// Abstand über dem Kopf einer Seite (Icon, Titel).
        public static let pageTopPadding: CGFloat = 96
        /// Zwischen Kopf (Icon, Titel) und erstem Block.
        public static let headerGap: CGFloat = 12
        /// Griff ⋮⋮ und ＋ links vom Block, je ein Feld dieser Größe.
        public static let blockControlWidth: CGFloat = 20
        public static let blockControlHeight: CGFloat = 22
        /// Zwischen ＋ und Textanfang.
        public static let blockControlGap: CGFloat = 6
        public static let checkboxSize: CGFloat = 14
        public static let quoteBarWidth: CGFloat = 3
    }

    /// Eckenradien.
    public enum Radius {
        /// Inline-Code, Checkbox, Bild, Hover-Fläche des ＋.
        public static let small: CGFloat = 4
        /// Platzhalter eines Bildes, solange es lädt.
        public static let medium: CGFloat = 6
        /// Code-Block, Hinweis unter einem Bild.
        public static let large: CGFloat = 8
    }

    #if canImport(AppKit)
    /// Bewegung. Bei „Bewegung reduzieren“ (Bedienungshilfen) blenden Zeilen ein
    /// statt zu gleiten, Hinweise verschwinden ohne Animation.
    public enum Motion {
        public static var isReduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

        /// Zeilen einfügen oder entfernen (Sidebar).
        public static func rowAnimation(
            _ preferred: NSTableView.AnimationOptions,
            reduceMotion: Bool = isReduced
        ) -> NSTableView.AnimationOptions {
            reduceMotion ? .effectFade : preferred
        }

        /// Ausblenden eines Hinweises in Sekunden.
        public static func fadeOutDuration(reduceMotion: Bool = isReduced) -> TimeInterval {
            reduceMotion ? 0 : 0.3
        }
    }
    #endif
}
