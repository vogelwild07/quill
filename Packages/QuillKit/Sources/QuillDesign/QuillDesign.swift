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
}
