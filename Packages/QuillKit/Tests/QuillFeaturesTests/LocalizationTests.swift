import Foundation
import Testing

/// Lokalisierung (Phase 7.3): Jeder Text für Nutzer steht in einem String-Katalog,
/// Ausgangssprache Deutsch. Liest die Quellen von App-Target und Packages und die
/// Kataloge (`Localizable.xcstrings`, `InfoPlist.xcstrings`):
/// - kein Prosa-Literal außerhalb einer lokalisierenden API (`String(localized:)`,
///   `Text`, `Button` …), außer in `allowed` mit Begründung;
/// - in Packages jede lokalisierende API mit `bundle: .module`;
/// - Schlüssel im Code und im Katalog decken sich (keiner fehlt, keiner veraltet);
/// - Zahlen in Sätzen mit Pluralformen;
/// - jeder sichtbare Info.plist-Eintrag im `InfoPlist.xcstrings`.
@Suite("Lokalisierung: Kataloge vollständig")
struct LocalizationTests {
    /// Prosa-Literale, die bewusst nicht lokalisiert werden: Datei (Ende des Pfads),
    /// Anfang des Literals, Begründung.
    static let allowed: [(file: String, prefix: String, reason: String)] = [
        ("App/ProfilingSeed.swift", "", "Nur im Schema „Quill Profiling“ (QUILL_PROFILING): Testbestand und Abbrüche."),
        ("QuillModel/Schema/SchemaV1.swift", "Mein Workspace", "Vorgabe im eingefrorenen Schema V1 (ADR-011), nirgends angezeigt."),
        ("QuillModel/Backup/StoreBackup+Layout.swift", "", "`StoreLayoutError.description` nur fürs Protokoll; angezeigt wird `PersistenceErrorView.detail(for:)`."),
        ("QuillModel/Backup/StoreBackup+Restore.swift", "Alte Markierung", "`RestoreError.fileOperation` nur fürs Protokoll; angezeigt wird `BackupRestoreView.message(for:)`."),
        ("QuillModel/Backup/StoreBackup+Restore.swift", "Tausch nicht möglich", "`RestoreError.fileOperation` nur fürs Protokoll; angezeigt wird `BackupRestoreView.message(for:)`."),
        ("QuillModel/Backup/StoreBackup.swift", "VACUUM INTO", "SQL."),
        ("QuillModel/Backup/StoreBackup.swift", "PRAGMA", "SQL."),
        ("QuillExport/ExportWriter.swift", "(Quill ", "Ordnername mit Produktname und ISO-Datum, sprachneutral."),
        ("QuillExport/MarkdownExporter.swift", "---", "YAML-Kopf; Schlüssel gehören zum Format, nicht zur Sprache."),
        ("QuillFeatures/Shared/QuillSignposts.swift", "", "Signpost-Namen für Instruments (docs/performance.md)."),
    ]

    /// Zahlen in diesen Sätzen brauchen keine Pluralform (Form „Wort: Zahl“ oder Maße).
    static let pluralFree: Set<String> = [
        "Fehlende Bilder: %lld",
        "Seiten: %lld · Bilder: %lld",
        "Bild, %lld × %lld Punkte",
    ]

    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct Module: CustomTestStringConvertible, Sendable {
        let name: String
        let sources: String
        /// `nil`: Modul ohne Katalog, darf nichts lokalisieren.
        let catalog: String?
        let isPackage: Bool
        var testDescription: String { name }
    }

    static let modules: [Module] = [
        Module(name: "App", sources: "App", catalog: "App/Resources/Localizable.xcstrings", isPackage: false),
        Module(name: "QuillFeatures", sources: "Packages/QuillKit/Sources/QuillFeatures", catalog: "Packages/QuillKit/Sources/QuillFeatures/Resources/Localizable.xcstrings", isPackage: true),
        Module(name: "QuillEditor", sources: "Packages/QuillKit/Sources/QuillEditor", catalog: "Packages/QuillKit/Sources/QuillEditor/Resources/Localizable.xcstrings", isPackage: true),
        Module(name: "QuillModel", sources: "Packages/QuillKit/Sources/QuillModel", catalog: nil, isPackage: true),
        Module(name: "QuillExport", sources: "Packages/QuillKit/Sources/QuillExport", catalog: nil, isPackage: true),
        Module(name: "QuillDesign", sources: "Packages/QuillKit/Sources/QuillDesign", catalog: nil, isPackage: true),
    ]

    /// Jedes Modul unter `Sources` ist hier aufgeführt; ein neues fiele sonst durch.
    @Test func everyModuleIsChecked() throws {
        let sources = Self.root.appending(path: "Packages/QuillKit/Sources")
        let names = try FileManager.default.contentsOfDirectory(atPath: sources.path(percentEncoded: false))
            .filter { !$0.hasPrefix(".") }
        #expect(Set(names) == Set(Self.modules.filter(\.isPackage).map { URL(filePath: $0.sources).lastPathComponent }))
    }

    @Test(arguments: modules)
    func noHardcodedText(_ module: Module) throws {
        let scan = try SourceScan(module: module)
        for literal in scan.literals where literal.isProse {
            switch literal.usage {
            case .localized(let hasModuleBundle):
                if module.catalog == nil {
                    Issue.record("\(literal.location): lokalisiert, aber \(module.name) hat keinen Katalog: \(literal.text)")
                } else if module.isPackage, !hasModuleBundle, !literal.isCustomLocalizedCall {
                    Issue.record("\(literal.location): ohne `bundle: .module`, sucht im Bundle der App: \(literal.text)")
                }
            case .technical:
                break
            case .unknown:
                let file = literal.file
                if !Self.allowed.contains(where: { file.hasSuffix($0.file) && literal.trimmedText.hasPrefix($0.prefix) }) {
                    Issue.record("\(literal.location): hart codierter Text: \(literal.trimmedText)")
                }
            }
        }
    }

    /// Schlüssel im Code fehlen nicht im Katalog, und der Katalog hat keine veralteten.
    @Test(arguments: modules.filter { $0.catalog != nil })
    func catalogMatchesCode(_ module: Module) throws {
        let scan = try SourceScan(module: module)
        let catalog = try Catalog(path: try #require(module.catalog))
        let used = Set(scan.literals.filter(\.isLocalized).map { Catalog.normalized($0.text) })
        let keys = Set(catalog.keys.map(Catalog.normalized))
        for key in used.subtracting(keys).sorted() {
            Issue.record("Fehlt im Katalog von \(module.name): \(Catalog.readable(key))")
        }
        for key in keys.subtracting(used).sorted() {
            Issue.record("Veraltet im Katalog von \(module.name): \(Catalog.readable(key))")
        }
        for key in catalog.staleKeys {
            Issue.record("Als veraltet markiert in \(module.name): \(key)")
        }
        #expect(catalog.sourceLanguage == "de")
    }

    /// Ganzzahlen in Sätzen haben Pluralformen („eine Seite“, „2 Seiten“).
    @Test(arguments: modules.compactMap(\.catalog))
    func numbersHavePlurals(_ path: String) throws {
        let catalog = try Catalog(path: path)
        for key in catalog.keys where key.contains(/%(\d+\$)?l{0,2}[du]/) && !Self.pluralFree.contains(key) {
            let forms = catalog.pluralForms(key)
            #expect(forms.contains("one") && forms.contains("other"), "Ohne Pluralformen „one“ und „other“: \(key)")
        }
    }

    /// Sichtbare Info.plist-Einträge der App (Debug und Release) stehen mit dem
    /// gleichen Wert im `InfoPlist.xcstrings`. Im Schema „Quill Profiling“ ist der
    /// Katalog ausgenommen, sonst hieße die Profiling-App wieder „Quill“.
    @Test func infoPlistIsInCatalog() throws {
        let catalog = try Catalog(path: "App/Resources/InfoPlist.xcstrings")
        #expect(catalog.sourceLanguage == "de")
        let project = try String(contentsOf: Self.root.appending(path: "Quill.xcodeproj/project.pbxproj"), encoding: .utf8)
        let configurations = BuildSettings.configurations(in: project)
        let app = try #require(configurations.filter { $0.settings["INFOPLIST_KEY_CFBundleDisplayName"] != nil }.nilIfEmpty)
        var expected: [String: String] = [:]
        for configuration in app where configuration.name != "Profiling" {
            for (setting, value) in configuration.settings where setting.hasPrefix("INFOPLIST_KEY_") && !value.isEmpty {
                let key = String(setting.dropFirst("INFOPLIST_KEY_".count))
                guard BuildSettings.isVisible(key) else { continue }
                #expect(expected[key] == nil || expected[key] == value, "\(key) unterscheidet sich zwischen Debug und Release")
                expected[key] = value
            }
        }
        #expect(!expected.isEmpty)
        for (key, value) in expected {
            #expect(catalog.sourceValue(key) == value, "\(key): Katalog \(catalog.sourceValue(key) ?? "fehlt"), Build \(value)")
        }
        for key in catalog.keys where expected[key] == nil && key != "CFBundleName" {
            Issue.record("Veraltet im InfoPlist.xcstrings: \(key)")
        }
        let profiling = try #require(app.first { $0.name == "Profiling" })
        #expect(profiling.settings["EXCLUDED_SOURCE_FILE_NAMES"]?.contains("InfoPlist.xcstrings") == true,
                "Profiling nimmt InfoPlist.xcstrings nicht aus")
    }

    // MARK: - Gegenproben des Lexers

    @Test func lexerFindsLiteralsAndContext() {
        let source = #"""
        // Text("Kommentar")
        let a = Text("Hallo Welt", bundle: .module)
        let b = String(localized: "Seite \(count ?? "") von \(total)", bundle: .module)
        view.setAccessibilityIdentifier("sidebar.pages")
        label.stringValue = "Hart codiert"
        Text(verbatim: "Quill Notizen")
        Button("Ohne Bundle") {}
        Text(title ?? "Kein Titel")
        """#
        let literals = SourceScan.literals(in: source, file: "Test.swift", customLocalized: [])
        let top = literals.filter { !$0.isNested }
        #expect(top.map(\.text) == ["Hallo Welt", "Seite \u{1} von \u{1}", "sidebar.pages", "Hart codiert", "Quill Notizen", "Ohne Bundle", "Kein Titel"])
        #expect(top[0].usage == .localized(hasModuleBundle: true))
        #expect(top[1].usage == .localized(hasModuleBundle: true))
        #expect(top[2].usage == .technical)
        #expect(top[3].usage == .unknown)
        #expect(top[4].usage == .technical)
        #expect(top[5].usage == .localized(hasModuleBundle: false))
        // Nach `??` ein `String`, kein Schlüssel: SwiftUI lokalisiert das nicht.
        #expect(top[6].usage == .unknown)
        #expect(top[3].line == 5)
    }
}

// MARK: - Quellen lesen

/// String-Literale eines Moduls mit dem Aufruf, in dem sie stehen.
struct SourceScan {
    enum Usage: Equatable {
        case localized(hasModuleBundle: Bool)
        case technical
        case unknown
    }

    struct Literal {
        let text: String
        let file: String
        let line: Int
        let usage: Usage
        let isNested: Bool
        let isCustomLocalizedCall: Bool

        var location: String { "\(file):\(line)" }
        var isLocalized: Bool { if case .localized = usage { !isNested } else { false } }

        /// Text für Menschen: Wörter mit Leerzeichen, Umlaute oder deutsche
        /// Satzzeichen, oder ein großgeschriebenes Wort wie „Papierkorb“. Bezeichner
        /// wie `sidebar.pages`, `GroupCell` oder `-wal` nicht.
        var isProse: Bool {
            guard !isNested else { return false }
            return (text.contains(/\s/) && text.contains(/\p{L}\p{L}/))
                || text.contains(/[ÄÖÜäöüß„“]/)
                || text.wholeMatch(of: /[A-ZÄÖÜ][a-zäöüß]{2,}/) != nil
        }

        /// Ohne Einrückung und Zeilenumbrüche am Rand (mehrzeilige Literale).
        var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Aufrufe, deren erstes Argument lokalisiert wird (SwiftUI nimmt dort einen
    /// `LocalizedStringKey`).
    static let localizingCalls: Set<String> = [
        "Text", "Button", "Label", "Toggle", "Section", "TextField", "SecureField", "Menu", "Picker",
        "LabeledContent", "ContentUnavailableView", "Link", "navigationTitle", "help", "accessibilityLabel",
        "accessibilityHint", "accessibilityValue", "alert", "confirmationDialog", "LocalizedStringKey",
        "LocalizedStringResource",
    ]

    /// Beschriftungen und Aufrufe für Literale, die kein Text für Nutzer sind.
    static let technicalLabels: Set<String> = [
        "verbatim", "systemName", "systemSymbolName", "systemImage", "path", "subsystem", "category",
        "forKey", "forType", "ofType", "withExtension", "named", "identifier", "rawValue",
    ]
    static let technicalCalls: Set<String> = [
        "accessibilityIdentifier", "setAccessibilityIdentifier", "fatalError", "precondition",
        "preconditionFailure", "assert", "assertionFailure", "Name", "PasteboardType", "Key", "Logger",
        "debug", "info", "notice", "warning", "error", "fault", "log", "trace", "critical",
        "appending", "appendingPathComponent", "URL", "UTType", "Image", "NSImage", "beginInterval",
        "endInterval", "emitEvent", "OSSignposter", "OSSignpostID", "firstIndex", "contains", "hasPrefix",
        "hasSuffix", "replacingOccurrences", "split", "components",
    ]

    let literals: [Literal]

    init(module: LocalizationTests.Module) throws {
        let directory = LocalizationTests.root.appending(path: module.sources)
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        let sources = try files.map { file in
            (file: "\(module.sources)/\(file)", text: try String(contentsOf: directory.appending(path: file), encoding: .utf8))
        }
        let custom = Set(sources.flatMap { Self.customLocalizedFunctions(in: $0.text) })
        literals = sources.flatMap { Self.literals(in: $0.text, file: $0.file, customLocalized: custom) }
    }

    /// Eigene Funktionen, die einen lokalisierbaren Wert als erstes Argument nehmen,
    /// etwa `formatButton(_ title: String.LocalizationValue, …)`.
    static func customLocalizedFunctions(in source: String) -> [String] {
        source.matches(of: /func\s+(\w+)\s*\(\s*_\s+\w+\s*:\s*(?:String\.LocalizationValue|LocalizedStringResource|LocalizedStringKey)\b/)
            .map { String($0.output.1) }
    }

    private final class Call {
        let name: String
        var label: String?
        var argument = 0
        var hasModuleBundle = false
        init(name: String) { self.name = name }
    }

    private struct Pending {
        let text: String
        let offset: Int
        let call: Call?
        let label: String?
        let argument: Int
        let isNested: Bool
        /// Steht das Literal allein als Argument (nicht etwa nach `??` oder `+`)?
        var isDirect = true
    }

    /// Liest Literale samt Aufruf, Beschriftung und Position. Interpolationen
    /// erscheinen im Text als U+0001. Kommentare werden übersprungen.
    static func literals(in source: String, file: String, customLocalized: Set<String>) -> [Literal] {
        let chars = Array(source)
        var pending: [Pending] = []
        var calls: [Call?] = []
        var index = 0

        func identifier(endingAt end: Int) -> String {
            var start = end
            while start > 0, chars[start - 1].isLetter || chars[start - 1].isNumber || chars[start - 1] == "_" { start -= 1 }
            return String(chars[start..<end])
        }

        func previousNonSpace(_ position: Int) -> Int {
            var position = position - 1
            while position >= 0, chars[position].isWhitespace { position -= 1 }
            return position
        }

        /// Liest ein Literal ab `start` (auf dem ersten `"`), gibt Text und Ende zurück.
        func readLiteral(at start: Int, nested: Bool) -> (String, Int) {
            let delimiter = start + 2 < chars.count && chars[start + 1] == "\"" && chars[start + 2] == "\"" ? 3 : 1
            var position = start + delimiter
            var text = ""
            while position < chars.count {
                let char = chars[position]
                if char == "\\", position + 1 < chars.count {
                    let next = chars[position + 1]
                    if next == "(" {
                        position = skipInterpolation(from: position + 2)
                        text.append("\u{1}")
                        continue
                    }
                    switch next {
                    case "n": text.append("\n")
                    case "t": text.append("\t")
                    case "u":
                        if let close = chars[position...].firstIndex(of: "}"),
                           let value = UInt32(String(chars[(position + 3)..<close]), radix: 16), let scalar = Unicode.Scalar(value) {
                            text.unicodeScalars.append(scalar)
                            position = close + 1
                            continue
                        }
                    default: text.append(next)
                    }
                    position += 2
                    continue
                }
                if char == "\"", delimiter == 1 || (position + 2 < chars.count && chars[position + 1] == "\"" && chars[position + 2] == "\"") {
                    return (text, position + delimiter)
                }
                text.append(char)
                position += 1
            }
            return (text, position)
        }

        /// Überspringt `\( … )`; Literale darin zählen als verschachtelt.
        func skipInterpolation(from start: Int) -> Int {
            var depth = 1
            var position = start
            while position < chars.count, depth > 0 {
                switch chars[position] {
                case "(": depth += 1
                case ")": depth -= 1
                case "\"":
                    let (text, end) = readLiteral(at: position, nested: true)
                    pending.append(Pending(text: text, offset: position, call: nil, label: nil, argument: 0, isNested: true))
                    position = end
                    continue
                default: break
                }
                position += 1
            }
            return position
        }

        while index < chars.count {
            let char = chars[index]
            let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
            if char == "/", next == "/" {
                while index < chars.count, chars[index] != "\n" { index += 1 }
                continue
            }
            if char == "/", next == "*" {
                index += 2
                while index + 1 < chars.count, !(chars[index] == "*" && chars[index + 1] == "/") { index += 1 }
                index += 2
                continue
            }
            switch char {
            case "\"":
                let (text, end) = readLiteral(at: index, nested: false)
                let call = calls.last ?? nil
                let before = previousNonSpace(index)
                var item = Pending(text: text, offset: index, call: call, label: call?.label, argument: call?.argument ?? 0, isNested: false)
                item.isDirect = before >= 0 && ["(", ":", ","].contains(chars[before])
                pending.append(item)
                index = end
                continue
            case "(":
                let before = previousNonSpace(index)
                let name = before >= 0 ? identifier(endingAt: before + 1) : ""
                calls.append(Call(name: name))
            case "[", "{":
                calls.append(nil)
            case ")", "]", "}":
                _ = calls.popLast()
            case ",":
                if let call = calls.last ?? nil { call.argument += 1; call.label = nil }
            case ":":
                if let call = calls.last ?? nil, next != ":" {
                    let before = previousNonSpace(index)
                    let label = before >= 0 ? identifier(endingAt: before + 1) : ""
                    if !label.isEmpty { call.label = label }
                }
            case ".":
                // `bundle: .module`
                if let call = calls.last ?? nil, call.label == "bundle",
                   String(chars[index..<min(index + 7, chars.count)]) == ".module" {
                    call.hasModuleBundle = true
                }
            default:
                break
            }
            index += 1
        }

        var lineStarts = [0]
        for (offset, char) in chars.enumerated() where char == "\n" { lineStarts.append(offset + 1) }
        func line(of offset: Int) -> Int {
            var low = 0, high = lineStarts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
            }
            return low + 1
        }

        return pending.sorted { $0.offset < $1.offset }.map { item in
            let name = item.call?.name ?? ""
            let isCustom = customLocalized.contains(name) && item.label == nil && item.argument == 0
            let usage: Usage
            if let label = item.label, technicalLabels.contains(label) {
                usage = .technical
            } else if !item.isDirect {
                usage = technicalCalls.contains(name) ? .technical : .unknown
            } else if name == "String", item.label == "localized" {
                usage = .localized(hasModuleBundle: item.call?.hasModuleBundle == true)
            } else if (localizingCalls.contains(name) || isCustom) && item.label == nil && item.argument == 0 {
                usage = .localized(hasModuleBundle: item.call?.hasModuleBundle == true)
            } else if technicalCalls.contains(name) {
                usage = .technical
            } else {
                usage = .unknown
            }
            return Literal(text: item.text, file: file, line: line(of: item.offset), usage: usage, isNested: item.isNested, isCustomLocalizedCall: isCustom)
        }
    }
}

// MARK: - Kataloge

struct Catalog {
    let sourceLanguage: String
    private let strings: [String: [String: Any]]

    init(path: String) throws {
        let data = try Data(contentsOf: LocalizationTests.root.appending(path: path))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        sourceLanguage = json["sourceLanguage"] as? String ?? ""
        strings = json["strings"] as? [String: [String: Any]] ?? [:]
    }

    var keys: [String] { strings.keys.sorted() }

    var staleKeys: [String] {
        strings.filter { $0.value["extractionState"] as? String == "stale" }.keys.sorted()
    }

    private func sourceLocalization(_ key: String) -> [String: Any]? {
        (strings[key]?["localizations"] as? [String: Any])?[sourceLanguage] as? [String: Any]
    }

    func pluralForms(_ key: String) -> Set<String> {
        let plural = (sourceLocalization(key)?["variations"] as? [String: Any])?["plural"] as? [String: Any]
        return Set(plural?.keys.map { $0 } ?? [])
    }

    func sourceValue(_ key: String) -> String? {
        (sourceLocalization(key)?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// Platzhalter (`%@`, `%lld`, `%1$@` …) werden zu U+0001 wie Interpolationen im Code.
    static func normalized(_ key: String) -> String {
        key.replacing(/%(\d+\$)?(lld|llu|ld|lu|d|u|@|lf|f|g|e|c|s)/, with: "\u{1}").replacing("%%", with: "%")
    }

    static func readable(_ key: String) -> String {
        key.replacing("\u{1}", with: "…").debugDescription
    }
}

// MARK: - Projektdatei

enum BuildSettings {
    struct Configuration {
        let name: String
        let settings: [String: String]
    }

    /// Info.plist-Schlüssel, die Nutzer sehen (Name, Copyright, Begründungen für Zugriffe).
    static func isVisible(_ key: String) -> Bool {
        ["CFBundleDisplayName", "CFBundleName", "NSHumanReadableCopyright"].contains(key)
            || key.hasSuffix("UsageDescription")
    }

    /// `XCBuildConfiguration`-Einträge der Projektdatei mit ihren Einstellungen.
    static func configurations(in project: String) -> [Configuration] {
        project.matches(of: /isa = XCBuildConfiguration;\s*buildSettings = \{(?<body>.*?)\n\t\t\t\};\s*name = (?<name>[^;]+);/.dotMatchesNewlines())
            .map { match in
                var settings: [String: String] = [:]
                for line in match.output.body.split(separator: "\n") {
                    guard let setting = line.wholeMatch(of: /\s*"?([\w\[\]=*]+)"?\s*=\s*(.*);/) else { continue }
                    settings[String(setting.output.1)] = String(setting.output.2).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                return Configuration(name: String(match.output.name).trimmingCharacters(in: CharacterSet(charactersIn: "\"")), settings: settings)
            }
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
