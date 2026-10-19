import Foundation
import QuillEditor
import QuillModel
import UniformTypeIdentifiers

/// Lokalisierte Texte, die in exportierten Dateien landen. Kommen aus der App,
/// weil `QuillExport` keine eigenen Ressourcen hat.
public struct ExportStrings: Sendable {
    /// Titel und Dateiname von Seiten ohne Titel.
    public var untitled: String
    /// Überschrift der Liste mit Unterseiten am Ende einer Seite.
    public var subpages: String
    /// Kommentar an der Stelle eines Bildes, dessen Daten fehlen.
    public var missingImage: String

    public init(untitled: String, subpages: String, missingImage: String) {
        self.untitled = untitled
        self.subpages = subpages
        self.missingImage = missingImage
    }
}

/// Dateien eines Exports, relativ zum Export-Ordner. Reiner Werttyp, damit
/// Aufbau und Inhalt ohne Dateisystem testbar sind.
public struct ExportPlan: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case markdown(String)
        /// Bilddaten des Assets mit dieser ID.
        case image(UUID)
    }

    public struct File: Equatable, Sendable {
        /// Pfad mit `/`, relativ zum Export-Ordner.
        public var path: String
        public var content: Content
    }

    public var files: [File]

    public var pageCount: Int {
        files.count { if case .markdown = $0.content { true } else { false } }
    }

    public var imageCount: Int {
        files.count { if case .image = $0.content { true } else { false } }
    }
}

/// Seite oder Seitenbaum als Markdown-Ordner (ADR-006, ADR-018):
///
///     Projekte.md
///     Projekte/Quill.md          Unterseiten im gleichnamigen Ordner
///     Projekte/Quill/Notizen.md
///     assets/3F2A9C1E.png        alle Bilder ganz oben, relativ verlinkt
public enum MarkdownExporter {
    /// Ordner der Bilder im Export.
    public static let assetsFolder = "assets"

    public static func plan(for root: PageExportSnapshot, strings: ExportStrings) -> ExportPlan {
        var builder = Builder(strings: strings)
        var names = ExportNameRegistry(reserved: [assetsFolder])
        builder.add(root, in: [], names: &names)
        return ExportPlan(files: builder.files)
    }

    private struct Builder {
        let strings: ExportStrings
        var files: [ExportPlan.File] = []
        var assetNames = ExportNameRegistry()

        init(strings: ExportStrings) {
            self.strings = strings
        }

        /// Legt die Seite in `directory` an (Pfadteile ab Export-Ordner), ihre
        /// Unterseiten in einem gleichnamigen Ordner daneben. Gibt den Namen ohne
        /// Endung zurück.
        @discardableResult
        mutating func add(_ page: PageExportSnapshot, in directory: [String], names: inout ExportNameRegistry) -> String {
            let title = page.title.isEmpty ? strings.untitled : page.title
            let base = ExportFileName.base(for: page.title, untitled: strings.untitled)
            let stem = names.claim(base: base, extensions: page.children.isEmpty ? ["md"] : ["md", ""])
            // Platz vor den Unterseiten freihalten, damit die Reihenfolge der Sidebar folgt.
            let path = (directory + [stem + ".md"]).joined(separator: "/")
            let slot = files.endIndex
            files.append(ExportPlan.File(path: path, content: .markdown("")))

            let toRoot = String(repeating: "../", count: directory.count)
            let document = EditorDocument(blocks: page.blocks.map(EditorBlock.init(snapshot:)))
            var body = MarkdownSerializer.markdown(for: document) { block in
                imageLine(block, page: page, toRoot: toRoot)
            }
            // Leere Absätze am Ende (der Editor hat oft einen) ergäben nur Leerzeilen.
            while body.hasSuffix("\n") { body.removeLast() }

            // Die Unterseiten nach dem eigenen Inhalt, damit Bildnamen der Sidebar-Reihenfolge
            // folgen; ihre Namen braucht die Liste am Ende der Seite.
            var childNames = ExportNameRegistry()
            var childLinks: [String] = []
            for child in page.children {
                let childStem = add(child, in: directory + [stem], names: &childNames)
                let childTitle = child.title.isEmpty ? strings.untitled : child.title
                let target = MarkdownSerializer.linkDestination(stem + "/" + childStem + ".md")
                childLinks.append("- [" + MarkdownSerializer.linkText(childTitle) + "](" + target + ")")
            }

            var text = frontMatter(page, title: title) + "\n# " + title + "\n"
            if !body.isEmpty { text += "\n" + body + "\n" }
            if !childLinks.isEmpty {
                text += "\n## " + strings.subpages + "\n\n" + childLinks.joined(separator: "\n") + "\n"
            }
            files[slot].content = .markdown(text)
            return stem
        }

        /// `![](../assets/3F2A9C1E.png)`; fehlt das Asset, ein Kommentar statt eines
        /// Links ins Leere.
        mutating func imageLine(_ block: EditorBlock, page: PageExportSnapshot, toRoot: String) -> String {
            guard let id = block.assetID, let uti = page.imageTypes[id] else {
                return "<!-- " + strings.missingImage + " -->"
            }
            let ext = UTType(uti)?.preferredFilenameExtension ?? "bin"
            let stem = assetNames.claim(base: String(id.uuidString.prefix(8)), extensions: [ext])
            let name = stem + "." + ext
            files.append(ExportPlan.File(path: assetsFolder + "/" + name, content: .image(id)))
            return "![](" + MarkdownSerializer.linkDestination(toRoot + assetsFolder + "/" + name) + ")"
        }

        /// YAML-Kopf mit Titel, Daten und ID (für späteren Re-Import).
        func frontMatter(_ page: PageExportSnapshot, title: String) -> String {
            let date = Date.ISO8601FormatStyle()
            return """
            ---
            title: \(yamlString(title))
            created: \(page.createdAt.formatted(date))
            updated: \(page.updatedAt.formatted(date))
            quill-id: \(page.id.uuidString)
            ---

            """
        }
    }

    /// YAML-String in doppelten Anführungszeichen; Steuer- und Zeilentrennzeichen
    /// als `\uXXXX`, weil YAML U+2028/U+2029 als Zeilenumbruch liest.
    static func yamlString(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case _ where scalar.properties.generalCategory == .control
                || scalar.value == 0x2028 || scalar.value == 0x2029 || scalar.value == 0x85:
                result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
