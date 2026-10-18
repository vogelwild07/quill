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

**Vorläufige Entscheidung (Spike validiert):** ein `NSTextView` pro Seite mit TextKit 2. Ein Absatz entspricht einem Block.

Grund: Selektion, Cursorbewegung und Kopieren über Blöcke hinweg, IME, Rechtschreibung, Services und VoiceOver kommen nativ mit. Bei einer TextView pro Block sind genau diese Dinge schwer.

### Schichten

1. **`EditorDocument`** (Value-Type): `[EditorBlock]` mit id, kind, indent, Runs. Einzige Wahrheit im Editor, unit-testbar.
2. **`BlockTextContentManager`** (`NSTextContentStorage`-Delegate): Blöcke ↔ Absätze. Block-ID und Art als eigene Attribute am Absatz.
3. **Eigene `NSTextLayoutFragment`-Subklassen**: zeichnen Bullet, Nummer, Checkbox, Zitatbalken, Code-Hintergrund (plattformneutral).
4. **`NSTextAttachmentViewProvider`**: Bild, Trenner.
5. **`BlockInputController`**: Enter teilt, Backspace am Anfang verbindet / setzt auf Text zurück, Tab rückt ein, Markdown-Kürzel, Slash-Trigger.
6. **Overlay**: Griff ⋮⋮ und ＋ positioniert über `textLayoutFragment(for:)`. Drag & Drop via `NSDraggingSource`, Pasteboard-Typ `de.vogel.quill.block` plus Markdown und Plain Text für fremde Apps.
7. **`SlashMenuController`**: Glass-Popover, verankert an `firstRect(forCharacterRange:)`.
8. **`EditorPersistenceBridge`**: entprellt (≈ 300 ms), schreibt Diffs pro Block über `PageStore.applyEdits`. Kein SwiftData-Write pro Tastendruck. Undo über den `NSUndoManager` der TextView.

Einbettung per `NSViewRepresentable`; iOS später `UIViewRepresentable` + `UITextView`, Schichten 1–3, 5, 8 geteilt.

### Spike (Phase 1)

Timebox 7–10 Arbeitstage, Target `EditorSpike`, Wegwerf-Code.

| # | Kriterium | Ziel |
|---|---|---|
| 1 | 1000 Blöcke laden und tippen | < 16 ms/Tastendruck, Laden < 300 ms |
| 2 | Enter/Backspace teilen/verbinden, Tab einrücken | korrekt inkl. Undo |
| 3 | Markdown-Kürzel für alle MVP-Typen | wandeln beim Leerzeichen |
| 4 | Slash-Menü am Cursor, filtern, Tastatur | funktioniert |
| 5 | Block per Griff ziehen, auch Mehrfachauswahl | flüssig, Undo-fähig |
| 6 | Checkbox-Klick, Bild-Attachment, Trenner | funktioniert |
| 7 | Selektion über Blöcke → ⌘C → Markdown/Plain/RTF | korrekt |
| 8 | IME (Japanisch), VoiceOver-Grundnavigation, Dark Mode | ohne Fehler |

Ergebnis: ADR in `decisions.md`. Fallback, wenn 1, 5 oder 7 scheitern: TextView pro Block in `NSStackView` plus eigener Selektionskoordinator.

## Tests

- Unit: Swift Testing pro Modul. `EditorDocument` und Exporter mit Golden Files, `PageStore` mit In-Memory-`ModelContainer`.
- UI: XCUITest (Seite anlegen, tippen, Slash-Menü, ⌘K, Papierkorb).
