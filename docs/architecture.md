# Architektur

## Überblick

- **App-Target `Quill`** (macOS 26+, Apple Silicon): dünn. Scenes, `ModelContainer`, Menüleiste, Ressourcen.
- **Swift Package `QuillKit`** (macOS + iOS): die gesamte Logik, damit iPhone/iPad später nur ein weiteres dünnes App-Target brauchen.

| Modul | Inhalt | Abhängig von |
|---|---|---|
| `QuillDesign` | Tokens: Typografie, Abstände, Farben | – |
| `QuillModel` | SwiftData-Modelle, `SchemaV1`, Migrationen, `PageStore`, `FractionalIndex` | – |
| `QuillEditor` | `EditorDocument`, TextKit-2-Editor (AppKit/UIKit hinter `#if`) | Model, Design |
| `QuillExport` | Markdown-Exporter | Model |
| `QuillFeatures` | Sidebar, Suche, Papierkorb, Favoriten (SwiftUI) | alle oben |

Swift 6 Language Mode, strikte Concurrency. UI auf `@MainActor`, Schreibzugriffe über `@ModelActor`.

## Ordnerstruktur

```
quill/
├─ Quill.xcodeproj
├─ App/                         macOS-App-Target
│  ├─ QuillApp.swift
│  ├─ Commands/                 Menüleiste, Shortcuts
│  ├─ Resources/                Assets.xcassets, Localizable.xcstrings
│  └─ Quill.entitlements        App Sandbox, user-selected files r/w
├─ Packages/QuillKit/
│  ├─ Sources/{QuillModel,QuillEditor,QuillFeatures,QuillExport,QuillDesign}
│  └─ Tests/                    Swift Testing
├─ QuillUITests/                XCUITest
├─ Spikes/EditorSpike/          Wegwerf-Target (Phase 1)
└─ docs/                        architecture, decisions, data-model, design, roadmap, research/
```

Bundle-IDs: `de.vogel.quill`, `de.vogel.quill.UITests`, `de.vogel.quill.EditorSpike`.

## Block-Editor

**Entscheidung (ADR-007, durch den Spike bestätigt):** ein `NSTextView` pro Seite mit TextKit 2. Ein Absatz entspricht einem Block.

Grund: Selektion, Cursorbewegung und Kopieren über Blöcke hinweg, IME, Rechtschreibung, Services und VoiceOver kommen nativ mit. Bei einer TextView pro Block sind genau diese Dinge schwer.

### Abbildung Modell ↔ Text

- Jeder Block ist ein Absatz und endet immer mit `\n`, auch der letzte. Die Auswahl wird vor das letzte `\n` begrenzt.
- Block-ID, Art, Einrückung, Häkchen, Code-Sprache und Listennummer liegen als eigene Attribute (`.quillBlockID` …) auf **jedem** Zeichen des Absatzes.
- Weicher Umbruch (Code, ⇧↩) ist U+2028 im Speicher und `\n` im Modell. Atomare Blöcke (Trenner, Bild) sind ein einzelnes U+FFFC mit Attachment.
- `BlockRenderer.parse` liest den Textspeicher zurück in Blöcke und repariert fehlende oder doppelte IDs.

### Edit-Pfade

1. **Native Edits innerhalb eines Absatzes** (Tippen, IME, Autokorrektur) übernimmt die TextView. Danach gleicht der Controller das Modell ab, im schnellen Pfad nur den betroffenen Absatz.
2. **Strukturelle Edits** (Enter, Backspace am Anfang, Tab, Kürzel, Slash-Befehle, Drop, Einfügen) laufen über `EditorDocument`. Das Ergebnis wird als minimaler Diff über `shouldChangeText`/`replaceCharacters`/`didChangeText` geschrieben und ist damit Teil des Undo-Stacks der TextView.
3. **Undo/Redo** lässt die TextView frei arbeiten. Danach gleicht der Controller über `NSUndoManagerDidUndoChange`/`DidRedoChange` das Modell ab.
4. `shouldChangeTextIn` fängt Änderungen ab, die Blockgrenzen überschreiten, Blöcke einfügen oder atomare Blöcke berühren, und leitet sie über Pfad 2 um. Bei markiertem Text (IME) wird nie eingegriffen.

### Schichten

| Schicht | Typ | Plattform |
|---|---|---|
| Modell | `EditorDocument`, `EditorBlock`, `MarkdownShortcut`, `MarkdownSerializer`, `SlashCommand` | neutral |
| Abbildung | `BlockRenderer`, `BlockStyle`, Attribut-Schlüssel | neutral (Fonts über `#if`) |
| Darstellung | `BlockLayoutFragment` zeichnet Bullet, Nummer, Checkbox, Zitatbalken, Code-Hintergrund und Trenner | neutral (TextKit 2) |
| Eingabe | `BlockEditorController` (`NSTextViewDelegate`, `NSTextStorageDelegate`) | AppKit, iOS-Gegenstück später |
| Oberfläche | `BlockTextView` (Griff, Drop, Checkbox-Klick, Zwischenablage), `SlashMenuController` (Glass-Panel), `BlockEditorView` (`NSViewRepresentable`) | AppKit |
| Persistenz | `EditorPersistenceBridge`: entprellt (≈ 300 ms), Diffs pro Block über `PageStore.applyEdits` | neutral (Phase 3) |

### Erkenntnisse aus dem Spike

- **Fragment-Koordinaten:** Der lokale Ursprung eines `NSTextLayoutFragment` liegt am Textanfang (Padding + Einrückung), nicht am Containerrand. Dekorationen werden in Container-x gerechnet und mit `layoutFragmentFrame.minX` umgerechnet.
- **Attachments:** TextKit 2 reserviert Platz für ein `NSTextAttachment`, zeichnet aber dessen `image(for:…)` nicht zuverlässig. Der Trenner wird deshalb im Fragment gezeichnet. Für Bilder in Phase 4 einen `NSTextAttachmentViewProvider` prüfen.
- **Drag & Drop:** `NSTextView.prepareForDragOperation` lehnt eigene Typen ab und muss für Block-Drags überschrieben werden.
- **Undo-Gruppen:** Vor einem Markdown-Kürzel `breakUndoCoalescing()`, sonst landen Tippen und Umwandeln in einer Gruppe.
- **VoiceOver:** Text und Zeilen sind über die Bedienungshilfen-Schnittstelle erreichbar. Blockart und Häkchenstatus werden noch nicht angesagt, weil Marker nur gezeichnet sind (Phase 7).

### Spike-Ergebnis (Phase 1)

Gemessen im Release-Build, echtes Fenster, 1000 Blöcke:

| # | Kriterium | Ziel | Ergebnis |
|---|---|---|---|
| 1 | 1000 Blöcke laden und tippen | < 16 ms/Tastendruck, Laden < 300 ms | Laden 12–14 ms; Tippen Median 0,85 ms, p95 1,1 ms, max. ≈ 10 ms; Enter Median 0,6 ms ✅ |
| 2 | Enter/Backspace teilen/verbinden, Tab einrücken | korrekt inkl. Undo | Tests ✅ |
| 3 | Markdown-Kürzel für alle MVP-Typen | wandeln beim Leerzeichen | Tests + manuell ✅ |
| 4 | Slash-Menü am Cursor, filtern, Tastatur | funktioniert | manuell ✅ (↑↓, ↩, ⎋) |
| 5 | Block per Griff ziehen, auch Mehrfachauswahl | flüssig, Undo-fähig | manuell ✅ nach Fix `prepareForDragOperation` |
| 6 | Checkbox-Klick, Bild-Attachment, Trenner | funktioniert | Checkbox manuell ✅, Trenner ✅ nach Fix, Bild per Test ✅ |
| 7 | Selektion über Blöcke → ⌘C → Markdown/Plain/RTF | korrekt | Tests ✅ (4 Typen) |
| 8 | IME, VoiceOver-Grundnavigation, Dark Mode | ohne Fehler | IME per Test (markierter Text) ✅, Japanisch nicht manuell geprüft; AX-Text ✅; Dark Mode ✅ |

Der Code in `QuillEditorSpike` und `Spikes/EditorSpike` ist Wegwerf-Code. In Phase 3 wird er nach `QuillEditor` übernommen, aufgeräumt und an `PageStore` angebunden; danach werden Spike-Target und -Modul gelöscht.

## Tests

- Unit: Swift Testing pro Modul. `EditorDocument` und Exporter mit Golden Files, `PageStore` mit In-Memory-`ModelContainer`.
- UI: XCUITest (Seite anlegen, tippen, Slash-Menü, ⌘K, Papierkorb).
