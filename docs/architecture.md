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
└─ docs/                        architecture, decisions, data-model, design, roadmap, research/
```

Bundle-IDs: `de.vogel.quill`, `de.vogel.quill.UITests`.

## Block-Editor

**Entscheidung (ADR-007, durch den Spike bestätigt):** ein `NSTextView` pro Seite mit TextKit 2. Ein Absatz entspricht einem Block.

Grund: Selektion, Cursorbewegung und Kopieren über Blöcke hinweg, IME, Rechtschreibung, Services und VoiceOver kommen nativ mit. Bei einer TextView pro Block sind genau diese Dinge schwer.

### Abbildung Modell ↔ Text

- Jeder Block ist ein Absatz und endet immer mit `\n`, auch der letzte. Die Auswahl wird vor das letzte `\n` begrenzt.
- Block-ID, Art, Einrückung, Häkchen, Code-Sprache und Listennummer liegen als eigene Attribute (`.quillBlockID` …) auf **jedem** Zeichen des Absatzes.
- Einrückung, Häkchen und Code-Sprache sind gebündelt in `BlockProperties` (ADR-014). Auf die Textattribute bildet sie nur `BlockProperties.textAttributes` / `init(textAttributes:)` ab, auf die Spalten nur `Block.properties`. Regeln je Blockart: `normalized(for:)`.
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
| Modell | `EditorDocument`, `EditorBlock`, `MarkdownShortcut`, `MarkdownSerializer`, `SlashCommand`, `BlockClipboard` (Format `de.vogel.quill.blocks`, Version 2) | neutral |
| Abbildung | `BlockRenderer`, `BlockStyle`, Attribut-Schlüssel | neutral (Fonts über `#if`) |
| Darstellung | `BlockLayoutFragment` zeichnet Bullet, Nummer, Checkbox, Zitatbalken, Code-Hintergrund und Trenner | neutral (TextKit 2) |
| Eingabe | `BlockEditorController` (`NSTextViewDelegate`, `NSTextStorageDelegate`) | AppKit, iOS-Gegenstück später |
| Oberfläche | `BlockTextView` (Griff, Drop, Checkbox-Klick, Zwischenablage), `SlashMenuController` (Glass-Panel), `BlockEditorView` (`NSViewRepresentable`) | AppKit |
| Modell (Inline) | `InlineText`, `InlineSpan`, `InlineMark`, `EditorDocument+Inline` | neutral |
| Persistenz | `EditorPersistenceBridge`: entprellt (≈ 300 ms), Diffs pro Block über `PageStore.applyEdits` | neutral |
| Seite | `PageEditorSession`, `PageHeaderView` (Icon, Titel) in `QuillFeatures` | AppKit + SwiftUI |

Der Controller ist auf Erweiterungen verteilt: `+Input` (Tastatur, Kürzel, Slash), `+Sync` (Text ↔ Modell, Undo), `+Clipboard`, `+Drag`, `+Formatting` (⌘B … ⌘K), `+Page` (Kopf, Fokus, Neuladen).

### Inline-Formatierung

- Im Modell: `EditorBlock.spans` mit UTF-16-Bereichen und `InlineStyle` (Marks + Link). `InlineText.normalized` hält Spans überlappungsfrei und fasst gleiche Nachbarn zusammen. Code-Blöcke und atomare Blöcke tragen keine Marks.
- Im Textspeicher sind `.quillMarks` (sortierte Rohwerte) und `.link` die Quelle; Schrift, Hintergrund und Durchstreichung werden daraus abgeleitet (`BlockStyle.inlineAttributes`).
- Menü **Format** (`CommandGroup(after: .textFormatting)`) schickt Selektoren aus `EditorFormattingActions` über die Responder-Kette, damit die Befehle nur im Editor wirken. Ohne Auswahl ändern sie die Schreibattribute.
- Gespeichert als `Block.richText` (Format in `data-model.md`), Markdown-Export über `MarkdownSerializer.inlineMarkdown`.

### Editor in der Seite

- `PageDetailView` erzeugt pro Seite eine `PageEditorSession`: Controller, Bridge und Kopf. Der Kopf (`PageHeaderView` in `EditorHeaderView`) sitzt im oberen Inset der Text-View und scrollt mit; seine Höhe misst `NSHostingController.sizeThatFits`.
- ↩ im Titel → Anfang des ersten Blocks; ↑ in der ersten Zeile → Titel, Cursor am Ende.
- Jeder Editor hat einen eigenen `UndoManager`, damit Laden oder Neuladen nicht das Undo der Sidebar (Fenster) leert.
- Speichern: entprellt beim Tippen, sofort beim Seitenwechsel und Schließen (`close()` → `flush()`; eine neu geöffnete Bridge derselben Seite wartet darauf), beim Beenden `applicationShouldTerminate` → `.terminateLater` → `QuitGuard.shouldTerminate()` (alle Editoren speichern, bei Fehler Rückfrage), danach Backup. Fehlschläge: automatischer erneuter Versuch mit Backoff, Hinweis `SaveProblemBadge` über `lastError` (die Bridge ist `@Observable`). Regeln in ADR-013.

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
| 8 | IME, VoiceOver-Grundnavigation, Dark Mode | ohne Fehler | Markierter Text per Test ✅; tote Tasten (´e, ^a, ⌥n n) vom Nutzer manuell ✅, gleicher Pfad wie IME; Japanisch nicht manuell geprüft; AX-Text ✅; Dark Mode ✅ |

Der Spike ist in Phase 3 nach `QuillEditor` überführt und gelöscht worden (ADR-007). Letzter Stand: Git-Tag `editor-spike`. `-benchmark` ist jetzt der Performance-Test, `-snapshot` der Snapshot-Test.

### Erkenntnisse aus Phase 3

- **SF Symbols einfärben:** `NSColor.set()` färbt ein Symbolbild beim `draw(in:)` nicht ein; es bleibt schwarz und verschwindet im Dunkelmodus. Selbst gezeichnete Elemente deshalb mit Pfaden in Systemfarben zeichnen (Griff ⋮⋮) oder das Symbol über `SymbolConfiguration` färben.
- **Kein ⋮⋮-Symbol:** `grip.vertical` und `circle.grid.2x3` gibt es unter macOS 26 nicht; der Griff sind sechs gezeichnete Punkte.
- **SwiftUI-Textfeld fokussieren** markiert den ganzen Inhalt. Eine Einfügemarke per `TextSelection` muss einen Durchlauf später gesetzt werden.
- **Kopfhöhe:** Der Kopf muss Titel und Icon schon beim ersten Messen kennen, sonst überdeckt ein mehrzeiliger Titel kurz den Text.

## Persistenz und Fenster (Phase 2)

- **Start:** `AppDelegate` ruft `QuillPersistence.open()` vor dem ersten Fenster auf: Backup vor dem Öffnen (ADR-010), `ModelContainer` mit `QuillMigrationPlan`, danach `markOpened()`. Scheitert das Backup vor einer Migration, wird nicht geöffnet. Lässt sich der Store nicht öffnen, zeigt das Fenster `PersistenceErrorView`; es wird nie auf einen leeren Store ausgewichen. Beim Beenden `backupOnQuit()`.
- **Schreiben:** `PageStore` (`@ModelActor`) über `EnvironmentValues.pageStore`; Schnittstelle nur mit `UUID`s. `PageOperations` registriert Undo/Redo für Anlegen, Umbenennen (Sidebar), Verschieben und Papierkorb.
- **Lesen:** `@Query` in `RootView`, `SidebarView` und `PageDetailView`. `PageTree` baut daraus einen unveränderlichen Baum (`PageNode`), plattformneutral und getestet.
- **Sidebar:** `PageOutlineView` = `NSOutlineView` in `NSViewRepresentable` (ADR-012). Aufklappzustand in `UserDefaults`. Ein Klick in die Sidebar holt den Tastaturfokus dorthin (sonst blieben ↩ und ⌘⌫ im Titelfeld).
- **Fenster:** eine `WindowGroup(id: "main")`. Ausgewählte Seite pro Fenster in `@SceneStorage`. `WindowRouter` übergibt einem neuen Fenster die Startseite und hängt es bei ⌘T bzw. „In neuem Tab öffnen“ als Tab an.
- **Menüleiste:** `QuillCommands` mit `@FocusedValue(\.pageActions)` des aktiven Fensters.

| Kürzel | Befehl |
|---|---|
| ⌘N / ⇧⌘N | Neue Seite / Neue Unterseite der ausgewählten Seite |
| ⌥⌘N / ⌘T | Neues Fenster / Neuer Tab |
| ↩ (Sidebar) | Umbenennen |
| ⌘⌫ (Sidebar) | In den Papierkorb legen (Menüpunkt ohne Kürzel, siehe ADR-012) |
| ⌘Z / ⇧⌘Z | Rückgängig / Wiederholen |
| ↩ (Titel) / ↑ (erste Zeile) | In den Text / zurück in den Titel |
| ⌘B / ⌘I (Editor) | Fett / Kursiv |
| ⇧⌘M (Editor) | Inline-Code |
| ⇧⌘X (Editor) | Durchgestrichen |
| ⌘K (Editor) | Link einfügen oder bearbeiten |
| ⌘O | Schnell öffnen: Suche nach Titel und Volltext (Phase 5) |

⌘K ist bewusst der Link wie in Pages, Mail und Notizen; die Suche liegt deshalb auf ⌘O. ⌘E bleibt frei für den Standard „Auswahl für Suche verwenden“ (HIG), Inline-Code liegt deshalb auf ⇧⌘M. Nicht verwenden: ⇧⌘C („Farben einblenden“).

## Tests

- Unit: Swift Testing pro Modul. `EditorDocument` und Exporter mit Golden Files, Editor-Controller mit Offscreen-Fenster (Tastatureingaben, Undo, Zwischenablage, Formatieren), `EditorPersistenceBridge` gegen In-Memory-Store, `PageStore` mit In-Memory-`ModelContainer`, Backups und Migrationen mit Stores im Temp-Ordner (ADR-010, ADR-011), `PageTree` ohne SwiftData.
- UI: XCUITest, immer über `XCUIApplication.quill()` (ohne Fensterzustand, Store nur im Arbeitsspeicher). Phase 2: Seite anlegen und umbenennen, Unterseite, Papierkorb mit Undo, Tabs. Der Test „Ziehen zum Verschachteln“ ist übersprungen (`XCTSkip`): Synthetische Drags von XCUITest starten in der `NSOutlineView` kein Ziehen; die Logik ist per Unit-Test abgedeckt, das Ziehen selbst wird von Hand geprüft. Phase 3 (`EditorUITests`): Tippen mit Markdown-Kürzeln, Titel ↔ Text, Text bleibt beim Seitenwechsel, Undo im Editor getrennt von der Sidebar, ⌘B und Menü Format, Link-Popover. Die App nutzt dabei per `-QuillPasteboardName` eine eigene Zwischenablage; die allgemeine bleibt unberührt (geprüft über `changeCount`). Später: Slash-Menü, Schnell öffnen (⌘O). Vor dem Lauf darf keine andere Quill-Instanz laufen (z. B. aus ⌘R), sonst kann XCTest sie nicht beenden.
- Darstellung: `EditorSnapshotTests` rendert den Editor hell und dunkel über `cacheDisplay` (keine Bildschirmfotos) und prüft, dass im Dunkelmodus nichts dunkler als der Hintergrund gezeichnet wird; PNGs in `$TMPDIR/QuillEditorSnapshots/`.
- Performance: `EditorBenchmark` im Test-Target, p95 < 16 ms pro Tastendruck bei 1000 Blöcken (Debug-Build).
