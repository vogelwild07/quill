# Architektur

## Überblick

- **App-Target `Quill`** (macOS 26+, Apple Silicon): dünn. Scenes, `ModelContainer`, Menüleiste, Ressourcen.
- **Swift Package `QuillKit`** (macOS + iOS): die gesamte Logik, damit iPhone/iPad später nur ein weiteres dünnes App-Target brauchen.

| Modul | Inhalt | Abhängig von |
|---|---|---|
| `QuillDesign` | Tokens: Typografie, Abstände, Farben | – |
| `QuillModel` | SwiftData-Modelle, `SchemaV1`, Migrationen, `PageStore`, `FractionalIndex` | – |
| `QuillEditor` | `EditorDocument`, TextKit-2-Editor (AppKit/UIKit hinter `#if`) | Model, Design |
| `QuillExport` | Markdown-Export: Dateinamen, Aufbau (`ExportPlan`), Schreiben (ADR-018) | Model, Editor (nur `Document`-Schicht: `MarkdownSerializer`, `EditorBlock`) |
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
│  └─ Quill.entitlements        App Sandbox, user-selected files r/w, Lesezeichen (app-scope) für den Sync-Ordner
├─ Packages/QuillKit/
│  ├─ Sources/{QuillModel,QuillEditor,QuillFeatures,QuillExport,QuillDesign}
│  └─ Tests/                    Swift Testing; `QuillTestFixtures` = gemeinsame `SampleDocuments`
├─ QuillUITests/                XCUITest
└─ docs/                        architecture, decisions, data-model, design, performance, roadmap, product-brief, releases/, images/
```

Bundle-IDs: `io.github.vogelwild07.quill`, `io.github.vogelwild07.quill.UITests`.

## Block-Editor

**Entscheidung (ADR-007, durch den Spike bestätigt):** ein `NSTextView` pro Seite mit TextKit 2. Ein Absatz entspricht einem Block.

Grund: Selektion, Cursorbewegung und Kopieren über Blöcke hinweg, IME, Rechtschreibung, Services und VoiceOver kommen nativ mit. Bei einer TextView pro Block sind genau diese Dinge schwer.

### Abbildung Modell ↔ Text

- Jeder Block ist ein Absatz und endet immer mit `\n`, auch der letzte. Die Auswahl wird vor das letzte `\n` begrenzt.
- Block-ID, Art, Einrückung, Häkchen, Code-Sprache und Listennummer liegen als eigene Attribute (`.quillBlockID` …) auf **jedem** Zeichen des Absatzes.
- Einrückung, Häkchen und Code-Sprache sind gebündelt in `BlockProperties` (ADR-014). Auf die Textattribute bildet sie nur `BlockProperties.textAttributes` / `init(textAttributes:)` ab, auf die Spalten nur `Block.properties`. Regeln je Blockart: `normalized(for:)`.
- `BlockKind` gibt es nur in `QuillModel`; der Editor ergänzt Verhalten per `extension`. Switches über die Blockart ohne `default:`, `BlockKindCoverageTests` prüft jede Art in Renderer, Slash-Menü und Markdown.
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
| Modell | `EditorDocument`, `EditorBlock`, `MarkdownShortcut`, `MarkdownSerializer`, `SlashCommand`, `BlockClipboard` (Format `io.github.vogelwild07.quill.blocks`, Version 2) | neutral |
| Abbildung | `BlockRenderer`, `BlockStyle`, Attribut-Schlüssel | neutral (Fonts über `#if`) |
| Darstellung | `BlockLayoutFragment` zeichnet Bullet, Nummer, Checkbox, Zitatbalken, Code-Hintergrund, Trenner und Bilder (`ImageAttachment` reserviert Platz, `EditorImageCache` hält dekodierte Bilder) | neutral (TextKit 2) |
| Eingabe | `BlockEditorController` (`NSTextViewDelegate`, `NSTextStorageDelegate`) | AppKit, iOS-Gegenstück später |
| Oberfläche | `BlockTextView` (Griff ⋮⋮ mit Kontextmenü und Einfügen-Knopf ＋ bei Hover, Drop mit Mitscrollen, Checkbox-Klick, Zwischenablage), `SlashMenuController` (Glass-Panel), `BlockEditorView` (`NSViewRepresentable`) | AppKit |
| Modell (Inline) | `InlineText`, `InlineSpan`, `InlineMark`, `EditorDocument+Inline` | neutral |
| Persistenz | `EditorPersistenceBridge`: entprellt (≈ 300 ms), Diffs pro Block über `PageStore.applyEdits` nur vom erwarteten Stand aus, sonst Dreiwege-Abgleich je Block (`BlockMerge`) | neutral |
| Seite | `PageEditorSession`, `PageHeaderView` (Icon, Titel) in `QuillFeatures` | AppKit + SwiftUI |

Der Controller ist auf Erweiterungen verteilt: `+Input` (Tastatur, Kürzel, Slash), `+Sync` (Text ↔ Modell, Undo), `+Clipboard`, `+Drag`, `+Formatting` (⌘B … ⌘K), `+Page` (Kopf, Fokus, Neuladen), `+Images` (Bilder laden, einfügen, Hinweis).

### Zwischenablage und Kürzel

- Kopieren schreibt immer vier Darstellungen, auch über den Griff: Klartext (`public.utf8-plain-text`), Markdown (`net.daringfireball.markdown`), RTF (`public.rtf`) und den eigenen Typ `io.github.vogelwild07.quill.blocks` (JSON mit Blockarten). Andere Apps bekommen so lesbares Markdown oder formatierten Text, Quill selbst die Blöcke verlustfrei (`BlockEditorController+Clipboard`).
- Kürzel folgen macOS-Konventionen (⌘B/⌘I, ⌘K Link, ⌘Z/⇧⌘Z, Tab/⇧Tab) und gängigen Markdown-Kürzeln. Das Slash-Menü filtert über deutsche Namen und englische Aliasse („Überschrift“, „h1“, „todo“).

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

### Themes (ADR-024)

- `QuillEditor/Theme/`: `EditorTheme` (Katalog, Paletten aus `ThemeColor`), `EditorThemeState` (aktuelles Theme hinter `Mutex`, aufgelöste Paletten je Variante, Ableitung für „Kontrast erhöhen“), `EditorThemeSettings` (`@Observable`, `UserDefaults`, Notification `didChange`).
- `EditorColor` gibt je Rolle eine dynamische `NSColor` zurück; Textspeicher, Fragmente, Platzhalter, Ziehgriff und Plus-Knopf nutzen nur diese. `placeholder` und `control` leitet `ResolvedPalette` aus der Textfarbe ab. Ein Wechsel: `BlockEditorController+Theme` setzt bei festen Themes `scrollView.appearance`, verwirft die Layout-Fragmente und zeichnet neu. Kein Eingriff in den Text.
- `QuillFeatures/Settings/`: `EditorThemeSetup` (Start, Test-Store ohne `UserDefaults`), `SettingsView` (Szene `Settings` in `QuillApp`). Seitentitel und Platzhalter in `PageDetailView` nehmen die Theme-Farben.

### Fokus-Modus (ADR-027)

- `EditorFocusSettings` (`QuillEditor/Theme/`, `@Observable`, `UserDefaults` `QuillFocusMode`, Notification `didChange`) wie beim Theme; `EditorThemeSetup` liest beides beim Start, Test-Stores ohne `UserDefaults`, Startargument `-QuillTestFocusMode YES`.
- Abdunkeln: `BlockLayoutDelegate.focusedBlocks` hält die Blöcke mit Cursor oder Auswahl (`nil` = nichts abdunkeln). `BlockLayoutFragment.isDimmed` liest das beim Zeichnen, nicht beim Anlegen, weil TextKit Fragmente beim Neu-Layouten wiederverwendet, und zeichnet den Block dann in `EditorColor.drawingDimmed`: Solange das auf diesem Thread läuft (Zähler im Thread-Wörterbuch, verschachtelbar), liefern die dynamischen Theme-Farben ihre abgedunkelte Variante (`ResolvedPalette.dimmed(_:)`, je Textrolle mit eigenem Mindestkontrast; Flächen, Trennlinie und Checkbox-Rahmen `checkboxBorder` mit `dimmedAlpha`); Bilder nehmen `EditorColor.dimmedAlpha`. `BlockEditorController+Focus` gleicht nach Auswahl- und Textänderungen einmal pro Run-Loop-Durchlauf ab und layoutet nur die geänderten Absätze neu; der Kopf bekommt dieselbe Deckkraft über `alphaValue` (`updateHeaderDimming`, auch nach Theme- und Darstellungswechsel; nicht, solange `headerShowsPlaceholder`, das `PageEditorSession` aus dem Titel setzt). Nur solange die Text-View Ersthelfer ist.
- Schreibmaschinen-Scrollen: `BlockTextView` gibt im Fokus-Modus eine halbe Fensterhöhe Platz unter dem Text (`setFrameSize`, merkt sich die von der Text-View verlangte Höhe, damit der Platz nicht doppelt kommt). `centerCaret` misst die Zeile über `enumerateTextSegments` (nie `layoutManager`, das schaltet auf TextKit 1), berücksichtigt die `contentInsets` des Clip-Views und misst nach dem Sprung einmal nach, weil TextKit die Höhe nicht gelayouteter Absätze nur schätzt. Beim Ziehen mit der Maus wird nicht gescrollt; nach dem Loslassen sanft, bei „Bewegung reduzieren“ sofort. Größenänderungen des Clip-Views (`frameDidChangeNotification`) zentrieren neu; den Platz rechnet `setFrameSize`, das AppKit dabei per Autoresizing aufruft. Kein `sizeToFit` beim Zentrieren.

### Erkenntnisse aus dem Spike

- **Fragment-Koordinaten:** Der lokale Ursprung eines `NSTextLayoutFragment` liegt am Textanfang (Padding + Einrückung), nicht am Containerrand. Dekorationen werden in Container-x gerechnet und mit `layoutFragmentFrame.minX` umgerechnet.
- **Attachments:** TextKit 2 reserviert Platz für ein `NSTextAttachment`, zeichnet aber dessen `image(for:…)` nicht zuverlässig. Trenner und Bilder werden deshalb im Fragment gezeichnet (ADR-015).
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

### Bild-Block (ADR-015)

- Bilder sind `Asset`s im Store, verknüpft über `BlockProperties.assetID`. Der Editor bekommt den `PageStore` (`imageStore`), lädt fehlende Bilder nach dem Laden, nach strukturellen Edits und nach Undo, dekodiert sie verkleinert außerhalb des Main Threads und erneuert dann das Layout des Absatzes.
- Einfügen über Slash-Menü (Dateiauswahl), Einsetzen und Ablegen: Dateien werden im Hintergrund gelesen und geprüft (`ImageSource`, nie auf dem Main Thread), danach erscheint der Block mit Platzhalter bis zum Ende des Imports; Unlesbares wird nicht eingefügt. Dauert das Lesen länger als 0,3 s, dreht sich an der Einfügestelle eine kleine Ladeanzeige (`editor.imageLoading`). Import entfernt GPS-Daten und verkleinert Bilder über 20 MB auf 4096 px. Angezeigt wird in natürlicher Größe (DPI).
- Eingesetzte Bild-Blöcke bekommen eine Kopie ihres Assets (`duplicateAsset`), weil ein Asset genau einem Block gehört.

### Erkenntnisse aus Phase 4

- **Inline-Code-Hintergrund:** Über `.backgroundColor` reichte die Fläche einmal in die Zeile darüber (nicht wieder nachstellbar). Jetzt zeichnet `BlockLayoutFragment` sie selbst (`inlineCodeRects`): je Zeile ein Rechteck aus den Schriftmetriken um die Grundlinie, senkrecht auf die Zeile begrenzt. `InlineCodeSnapshotTests` vergleicht den Absatz darüber pixelgenau mit und ohne Inline-Code.
- **Zeichnen außerhalb von `renderingSurfaceBounds`** schneidet TextKit ab; wer dekoriert, muss die Fläche dort aufnehmen.
- **Schriften nur auf dem Main Thread:** `NSFont` lieferte in parallel laufenden Tests sporadisch `nil` (Absturz in `addAttributes`). Tests, die rendern, laufen deshalb auf dem Main Actor.
- **Auswahländerung vor `textDidChange`:** Beim Tippen meldet sich die Auswahl, bevor die Absätze abgeglichen sind; dort nichts aus `paragraphStarts` lesen.
- **Zurücknehmen ohne Undo-Schleife:** Escape nach ＋ nutzt Undo nur, wenn „Neuer Block“ genau oben liegt (Dokument unverändert seit dem Klick); sonst entfernt eine eigene Bearbeitung den Block. Nie mehrere Undo-Schritte in einer Schleife: Ein Schritt aus dem Hintergrund (Import, Duplizieren mit Bild) würde sonst mit zurückgenommen.
- **Asynchron einfügen:** Was erst nach einem `await` eingefügt wird (Bilder lesen, Assets kopieren), nimmt die Einfügemarke von dann, nicht die vom Auslösen.
- **Asset-Kopien:** Gehört ein Asset schon einem anderen Block, bekommt der Block eine Kopie; der Editor kennt weiter die alte ID. Eine vorhandene Kopie mit denselben Daten bleibt deshalb verknüpft, sonst entstünde bei jeder Änderung eine neue.

### Erkenntnisse aus Phase 3

- **SF Symbols einfärben:** `NSColor.set()` färbt ein Symbolbild beim `draw(in:)` nicht ein; es bleibt schwarz und verschwindet im Dunkelmodus. Selbst gezeichnete Elemente deshalb mit Pfaden in Systemfarben zeichnen (Griff ⋮⋮) oder das Symbol über `SymbolConfiguration` färben.
- **Kein ⋮⋮-Symbol:** `grip.vertical` und `circle.grid.2x3` gibt es unter macOS 26 nicht; der Griff sind sechs gezeichnete Punkte.
- **SwiftUI-Textfeld fokussieren** markiert den ganzen Inhalt. Eine Einfügemarke per `TextSelection` muss einen Durchlauf später gesetzt werden.
- **Kopfhöhe:** Der Kopf muss Titel und Icon schon beim ersten Messen kennen, sonst überdeckt ein mehrzeiliger Titel kurz den Text.

## Persistenz und Fenster (Phase 2)

- **Start:** `AppDelegate` ruft `QuillPersistence.open()` vor dem ersten Fenster auf: unter Sperre Store nach `Store/` umziehen (einmalig) und ein vorgemerktes Backup einspielen (`StoreBackup.prepareStore`, ADR-019), Backup vor dem Öffnen (ADR-010), `ModelContainer` mit `QuillMigrationPlan`, danach `markOpened()`. Scheitert das Backup vor einer Migration, wird nicht geöffnet. Lässt sich der Store nicht öffnen, zeigt das Fenster `PersistenceErrorView`; es wird nie auf einen leeren Store ausgewichen. Beim Beenden `backupOnQuit()`.
- **Schreiben:** `PageStore` (`@ModelActor`) über `EnvironmentValues.pageStore`; Schnittstelle nur mit `UUID`s. `PageOperations` registriert Undo/Redo für Anlegen, Umbenennen (Sidebar), Verschieben und Papierkorb.
- **Lesen:** `@Query` in `RootView` (nur Favoriten), `SidebarView` und `PageDetailView`. `PageTree` baut daraus einen unveränderlichen Baum (`PageNode`), plattformneutral und getestet.
- **Reihenfolge:** eine Regel für Seiten, Blöcke und Favoriten, `SiblingOrder` (`sortKey`, dann `createdAt`, dann `id`; ADR-009). `sortedInSiblingOrder` liest den Schlüssel einmal pro Element, weil SwiftData-Getter teuer sind. Blöcke einer Seite lädt `PageStore` gesammelt (`relationshipKeyPathsForPrefetching`).
- **Sidebar:** `PageOutlineView` = `NSOutlineView` in `NSViewRepresentable` (ADR-012). Aufklappzustand in `UserDefaults`. Ein Klick in die Sidebar holt den Tastaturfokus dorthin (sonst blieben ↩ und ⌘⌫ im Titelfeld). Auswahl als Objekt (`PageSelection`), Aktionen als eine Instanz (`PageOutlineActions`), `SidebarView` ist `Equatable` (`==` ohne Main Actor: Objekte nach Identität, Bindings nach Wert): So baut ein Seitenwechsel den Baum nicht neu (`docs/performance.md`). Die Closures der Aktionen setzt `RootView` nur, wenn sich Store oder Undo-Manager ändern, nie in `body`.
- **Fenster:** eine `WindowGroup(id: "main")`. Ausgewählte Seite pro Fenster in `@SceneStorage`. `WindowRouter` übergibt einem neuen Fenster die Startseite und hängt es bei ⌘T bzw. „In neuem Tab öffnen“ als Tab an.
- **Menüleiste:** `QuillCommands` mit `@FocusedValue(\.pageActions)` (Seite) und `@FocusedValue(\.windowActions)` (Fenster, z. B. „Backup wiederherstellen …“) des aktiven Fensters.

## Navigation (Phase 5, ADR-017)

- **Suche:** `PageStore.search` und `recentPages` liefern `SearchHit`s (Seite oder Inhalt mit Block und Fundstelle). `QuickOpenModel` teilt sie in Abschnitte und hält die Auswahl, `QuickOpenView` ist das schwebende Feld über dem Fenster (`RootView`). Inhaltstreffer gehen als `RevealRequest` an `PageDetailView`, die nach dem Laden `BlockEditorController.reveal(blockID:range:)` aufruft.
- **Favoriten:** `PageTree.favorites` (nur Seiten im aktiven Baum) und Gruppenzeilen in `PageOutlineView`; eine favorisierte Seite hat zwei Zeilen, also zwei Items. `SidebarDrop` entscheidet, was ein Drop bewirkt (Seite verschieben, Favorit hinzufügen oder umsortieren).
- **Papierkorb:** `TrashView` liest per `@Query`; Löschen und Leeren über `QuillPersistence` (`\.quillPersistence`), das vorher ein Backup anlegt. Auto-Leeren startet `QuillPersistence.open()`.
- **Backup wiederherstellen:** `BackupRestoreView` (Sheet aus `RootView`, Menü über `WindowActions.restoreBackup`) → `QuillPersistence.requestRestore` → Beenden nach dem Schließen des Sheets. `QuillPersistence.open()` ruft zuerst `StoreBackup.prepareStore()` auf (Tausch von `Store/` in einem Schritt); das Ergebnis holt das erste Fenster per `takeRestoreOutcome()` ab. Bricht der Nutzer das Beenden ab, nimmt `quitWasCancelled()` die Vormerkung zurück (ADR-019).

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
| ⌥⌘0–7 (Editor) | Blockart: Text, Überschrift 1–3, Aufzählung, Nummerierte Liste, To-do, Zitat (ADR-016) |
| ⌘↩ (Editor) | To-dos der Auswahl abhaken |
| ⌥⌘↑ / ⌥⌘↓ (Editor) | Block bzw. ausgewählte Blöcke verschieben |
| ⌘D (Editor) | Block bzw. ausgewählte Blöcke duplizieren |
| Rechtsklick auf ⋮⋮ | Löschen, Duplizieren, Umwandeln in … |
| ⌘O | Schnell öffnen: Suche nach Titel und Volltext (ADR-017) |
| ↑↓ / ↩ / ⌘↩ / ⎋ (Schnell öffnen) | Treffer wählen / öffnen / in neuem Tab öffnen / schließen |
| ⌫ (Papierkorb) | Endgültig löschen (mit Rückfrage) |
| ⇧⌘E | Seite exportieren (Markdown-Ordner, ADR-018) |

⌘K ist bewusst der Link wie in Pages, Mail und Notizen; die Suche liegt deshalb auf ⌘O. ⌘E bleibt frei für den Standard „Auswahl für Suche verwenden“ (HIG), Inline-Code liegt deshalb auf ⇧⌘M. Nicht verwenden: ⇧⌘C („Farben einblenden“), ⌥⌘8 (Zoom der Bedienungshilfen), ⌥⇧↑/↓ (Auswahl absatzweise erweitern).

## Export (Phase 6, ADR-018)

```
PageStore.exportSnapshot  →  MarkdownExporter.plan  →  ExportWriter.write
(Seite + Unterseiten,        (reiner Werttyp: Pfade,     (versteckter Zwischenordner,
 ohne Papierkorb)             Markdown, Bild-IDs)         dann Umbenennen, nie überschreiben)
```

- `PageExport` (QuillFeatures) zeigt den Ordnerdialog mit „Unterseiten einschließen“ und meldet das Ergebnis; Seite › „Exportieren …“ (⇧⌘E) und Kontextmenü der Sidebar.
- Golden Files: `Tests/QuillExportTests/Golden/ExportProject/` aus `SampleDocuments.exportProject()`; neu schreiben mit `QUILL_UPDATE_GOLDEN=1 swift test --filter MarkdownExporterTests`, dann den Diff prüfen.
- UI-Test: `-QuillExportDirectory <Name>` schreibt ohne Dialog in den temporären Ordner der App (Sandbox).

## Mac und iPhone (ADR-028)

QuillKit baut für macOS 26 und iOS 26 (`Scripts/check-ios-build.sh`). Nur-Mac-Teile (Menüs, Fenster, Einstellungsfenster, Seitenbaum mit `NSOutlineView`, Editor-Sitzung mit `NSTextView`) stehen hinter `#if canImport(AppKit)`; `RootView` bleibt ein `NavigationSplitView` für beide Plattformen, damit das iPad später passt. Tests laufen bis vor Phase 13 nur auf dem Mac.

Editor in zwei Schichten (10.3):

```text
QuillEditorCore   Foundation, Observation, Synchronization, QuillModel
  Document/        EditorDocument, EditorBlock, InlineText, Markdown, BlockClipboard, BlockMerge
  Text/            Block-Attribute im Textspeicher
  Persistence/     EditorPersistenceBridge
  Theme/           Katalog, Paletten, PaletteSpec (Kontrast, Fokus-Modus), EditorFocusSettings
  NotificationObservation
QuillEditor       AppKit oder UIKit
  TextKit/         PlatformTypes (EditorColor, Weichen AppKit/UIKit), BlockStyle,
                   BlockLayoutFragment, BlockRenderer, Anhänge (beide Plattformen)
  Theme/           ResolvedPalette (NSColor/UIColor), EditorThemeState, EditorThemeSettings,
                   EditorTheme+Platform (Name, erzwungene Darstellung auf dem Mac)
  Document/        SlashCommand, BlockConversion (lokalisierte Menütitel)
  AppKit/          BlockEditorController, BlockTextView, Slash-Menü (nur Mac)
```

## Sync (ADR-026, ADR-029, ab Phase 11)

`QuillSync` ist das einzige Modul mit Automerge (`AutomergeIsolationTests`) und hängt nur an QuillModel:

```text
QuillSync
  SyncDocument      gemeinsame erste Änderung, neue Akteurs-ID je Sitzung, Konflikte
  PageDocument      [BlockSnapshot] ↔ Map blocks (order, kind, text mit Marks, Felder)
  TreeDocument      [PageRecord] ↔ Map pages, Grabstein statt Entfernen
  TextMarks         RichText ↔ Marks in Unicode-Skalaren
  SyncFolderLayout  Pfade, quill.json (FolderManifest), devices/ (DeviceInfo), <Nr>.changes
  SyncEngine        Abgleich Store ↔ Ordner (Actor): Seiten, dann Seitenbaum
  SyncFileAccess    Lesen/Schreiben per NSFileCoordinator, nie überschreiben, nicht geladene Dateien
  ChunkCheck        Automerge-Daten prüfen, bevor sie übernommen werden
  SyncState         SyncGate („Sync pausieren“), SyncFailure, SyncReport, gelesene Dateien
QuillModel
  PageStore+Sync    Schreibwege des Abgleichs: nur vom erwarteten Stand aus, Seiten nie löschen
QuillFeatures
  Sync/             SyncSettings (Einstellungen, Lesezeichen), SyncController (ein/aus, Backup vorher,
                    Pause, Wiederverbinden, Zeitpunkte), SyncSettingsView, SyncReconnectView, SyncSidebarStatus
  Settings/         Bereiche Darstellung, Sync, Lizenzen (Resources/ThirdPartyLicenses.txt, Scripts/third-party-licenses.py)
```

Ein Abgleich (`SyncEngine.sync`) je Dokument: aus dem Store laden, eigene Dateien nachlesen, die der Store noch nicht kennt, den Stand des Stores als nächste eigene Datei anhängen, dann neue Dateien der anderen Geräte übernehmen und das Ergebnis in den Store schreiben. Hat der Nutzer während des Abgleichs gespeichert, schreibt der Store nichts, und der nächste Abgleich nimmt die Eingabe mit.

`QuillPersistence.sync` hält den einen `SyncController` der App; `AppDelegate` startet nach dem Öffnen die Zeitpunkte (`SyncSchedule`): beim Start, wenn Quill aktiv wird, 2 s nach einer Änderung im Store (`ModelContext.didSave`) und alle 60 s. Ohne eingeschalteten Sync oder pausiert läuft nichts. Ein Abgleich blockiert die App nie; die Sidebar zeigt ab 5 Seiten den Fortschritt und Probleme an. Die Einstellungen des Sync liegen beim echten Store in den Einstellungen des Macs, bei Test-Stores im Arbeitsspeicher oder im Testordner (`SyncSettingsStorage`), weil ein Debug-Build dieselbe Bundle-ID hat. UI-Tests ersetzen die Dateiauswahl durch `-QuillSyncTestFolder <Name>` (nur Debug, nur mit Test-Store).

Für den Handtest gibt es das Schema „Quill Synctest“ mit den Konfigurationen `SynctestA` und `SynctestB` (wie Release, Bundle-IDs `io.github.vogelwild07.quill.synctest.a` und `.b`, Namen „Quill Synctest A“ und „Quill Synctest B“). Jede Variante hat einen eigenen Container mit eigenem Store und eigenen Einstellungen, so laufen zwei „Geräte“ zugleich in einem Benutzerkonto.

Sync über einen gewählten Ordner mit Automerge, je Seite ein Dokument und eines für den Seitenbaum. Der SwiftData-Store bleibt Quelle der App: Seiten öffnen aus dem Store, Automerge braucht nur der Abgleich im Hintergrund. Automerge steht nur in der Sync-Schicht (ein Modul), damit ein Ausstieg auf dieses Modul beschränkt bleibt. Der Spike aus Phase 10.1 liegt unter `Spikes/AutomergeSpike` (Abbildung `[EditorBlock]` ↔ Automerge mit Umrechnung UTF-16 ↔ Unicode-Skalare, Messprogramm, Größenskript) und wird von App und QuillKit nie eingebunden (`SpikeIsolationTests`).

## Tests

- Unit: Swift Testing pro Modul. `EditorDocument` und Exporter mit Golden Files, Editor-Controller mit Offscreen-Fenster (Tastatureingaben, Undo, Zwischenablage, Formatieren), `EditorPersistenceBridge` gegen In-Memory-Store, `PageStore` mit In-Memory-`ModelContainer`, Backups, Migrationen, Umzug und Wiederherstellen mit Stores im Temp-Ordner, nacheinander in `DiskStoreSuites` (ADR-010, ADR-011, ADR-019), `PageTree` ohne SwiftData.
- UI: XCUITest, immer über `XCUIApplication.quill()` (ohne Fensterzustand, Store nur im Arbeitsspeicher). Phase 2: Seite anlegen und umbenennen, Unterseite, Papierkorb mit Undo, Tabs. Der Test „Ziehen zum Verschachteln“ ist übersprungen (`XCTSkip`): Synthetische Drags von XCUITest starten in der `NSOutlineView` kein Ziehen; die Logik ist per Unit-Test abgedeckt, das Ziehen selbst wird von Hand geprüft. Phase 3 (`EditorUITests`): Tippen mit Markdown-Kürzeln, Titel ↔ Text, Text bleibt beim Seitenwechsel, Undo im Editor getrennt von der Sidebar, ⌘B und Menü Format, Link-Popover, ＋ bei Hover öffnet das Slash-Menü im neuen Block (Escape nimmt es zurück), Slash-Menü per Tastatur und Maus über AX-Kennungen (`slash.menu`, `slash.<blockart>`), Schließen bei Fokusverlust, Format › Blockart und ⌘↩ (geprüft über das Markdown der eigenen Zwischenablage), ⌥⌘↓, Kontextmenü am Griff und ⌘D. Die App nutzt dabei per `-QuillPasteboardName` eine eigene Zwischenablage; die allgemeine bleibt unberührt (geprüft über `changeCount`). Phase 4 (`ImageBlockUITests`): Bild per ⌘V mit Undo/Redo, bleibt beim Seitenwechsel, Einsetzen über eine Auswahl als ein Undo-Schritt, Hinweis „Bild wurde verkleinert“ (AX-Gruppe `editor.notice`), Eintrag „Bild“ im Slash-Menü; das Testbild erzeugt die App selbst in ihrer Zwischenablage (`-QuillTestImage <Breite>x<Höhe>|heavy`, nur Debug, ADR-021), weil der Datenschutz das Einsetzen aus einer von einem anderen Prozess gefüllten Zwischenablage sperren kann. Die Dateiauswahl (`NSOpenPanel`) läuft in der Sandbox außerhalb der App und wird von Hand geprüft. Phase 5: Papierkorb (Wiederherstellen mit Undo, Löschen und Leeren mit Rückfrage; das Sheet wird über `window.sheets` und die Knöpfe `action-button-1/2` bedient), Favoriten (Stern, Menü, Kontextmenü, Undo an den alten Platz, Papierkorb), `QuickOpenUITests` (zuletzt bearbeitet, Titel vor Inhalt, Sprung zur Fundstelle, ⌘↩, Klick daneben). Die Sidebar-Zeilen tragen AX-Kennungen am Titelfeld (`sidebar.page`, `sidebar.favorite`, `sidebar.group`), weil die Outline die der Zelle nicht weitergibt; Hilfen `pageRows`/`favoriteRows`. Vor dem Lauf darf keine andere Quill-Instanz laufen (z. B. aus ⌘R), sonst kann XCTest sie nicht beenden. `ReadmeScreenshotUITests` nimmt die Bilder der README auf (hell und dunkel, Demo-Inhalte, Bild per `-QuillTestImage demo`, Fenstergröße per `-QuillWindowSize`, beide nur Debug); er läuft nur über `Scripts/readme-screenshots.sh` (setzt `TEST_RUNNER_QUILL_README_SCREENSHOTS=1`), sonst übersprungen.
- Darstellung: `EditorSnapshotTests` rendert den Editor hell und dunkel über `cacheDisplay` (keine Bildschirmfotos) und prüft, dass im Dunkelmodus nichts dunkler als der Hintergrund gezeichnet wird; PNGs in `$TMPDIR/QuillEditorSnapshots/`.
- Performance (Phase 7.2, `docs/performance.md`): `QuillPerformanceTests` im Package, nur optimiert (`swift test -c release`); App-Messungen per Signposts (`QuillSignposts`) in `PerformanceUITests`, nur im Schema „Quill Profiling“ mit eigenem Bestand (`-QuillSeedPages`). Auswertung und Schwellen: `Scripts/perf-package.py`, `Scripts/perf-ui.py`; `Scripts/check-release-binary.sh` prüft, dass Release keinen Profiling-Code enthält.
- Release (Phase 8, ADR-022): `Scripts/make-release.sh` archiviert ad hoc signiert, prüft das Bundle (Signatur, Architektur, Mindestversion, Entitlements, keine persönlichen Pfade, `check-release-binary.sh --app`) und baut `dist/Quill-<Version>.dmg` mit Prüfsumme. Fenster der .dmg (ADR-025): `Scripts/dmg/` mit Hintergrund (`background.swift` → `background.tiff`, 1× und 2×) und Layout für `dmgbuild` (`settings.py`, feste Version in `requirements.txt`). `BundleIdentifierTests` hält alle Kennungen beim Präfix `io.github.vogelwild07.quill`.
- Bedienungshilfen (Phase 7.3, ADR-021): `AccessibilityAuditUITests` (Audit in 11 Ansichten, rot bei jeder neuen Meldung, Ausnahmen einzeln in `exception(for:in:)`), `AccessibilityUITests` (Beschriftungen, Tab-Schleife, modales Schnell öffnen), `BlockAccessibilityTests` und `MotionTests` im Package.
- Leerzustände (ADR-021): `EmptyStateSnapshotTests` rendert `EmptyStateView`, Speicherhinweis und Fehleransicht hell und dunkel und prüft jede Textzeile auf 4,5:1; `EmptyPageHintTests` und `EmptyPageExportTests` sichern, dass der Hinweis auf leeren Seiten nie im Text, in der Zwischenablage oder im Export landet; `EmptyStateUITests` für den ersten Start.
- Lokalisierung (ADR-021): `LocalizationTests` liest die Quellen von App-Target und Packages mit einem kleinen Lexer und gleicht sie mit `Localizable.xcstrings` und `InfoPlist.xcstrings` ab; `LocalizedTextTests` prüft Pluralformen und lokalisierte Fehler zur Laufzeit.
