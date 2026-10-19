# Entscheidungen (ADR-Log)

Format: Kontext → Entscheidung → Konsequenzen. Neueste unten.

## ADR-001: Plattform und Stack (2026-10-18)

**Entscheidung:** macOS 26+, nur Apple Silicon. Swift 6, SwiftUI (AppKit wo nötig), SwiftData lokal. Später CloudKit und iPhone/iPad.
**Konsequenzen:** Liquid Glass und neueste SwiftUI-APIs ohne Fallbacks. Logik in plattformneutralem Package `QuillKit`.

## ADR-002: CloudKit-taugliches Modell ab Tag 1 (2026-10-18)

**Entscheidung:** UUIDs, `createdAt`/`updatedAt`, alle Attribute optional oder mit Default, keine `unique`-Constraints, optionale Beziehungen, Reihenfolge per `sortKey` (Fractional Indexing), `VersionedSchema` von Anfang an.
**Konsequenzen:** Sync später ohne Datenmigration. Eindeutigkeit (z. B. genau ein Workspace) muss im Code sichergestellt werden.

## ADR-003: Ein Workspace im MVP (2026-10-18)

**Entscheidung:** UI kennt genau einen Workspace; das Modell enthält `Workspace` bereits.
**Konsequenzen:** Mehrere Workspaces später ohne Migration.

## ADR-004: Ein Fenster mit System-Tabs (2026-10-18)

**Entscheidung:** `WindowGroup` mit Sidebar + Editor, native Tabs (⌘T), Seite optional in neuem Fenster.
**Konsequenzen:** Navigationszustand pro Fenster (Scene Storage), nicht global.

## ADR-005: Signing mit Personal Team (2026-10-18)

**Entscheidung:** Vorerst kostenloses Personal Team, App Sandbox aktiv.
**Konsequenzen:** Keine Notarisierung, kein CloudKit-Container. Wechsel auf bezahlten Account vor Sync/App Store.

## ADR-006: Markdown-Export als Ordner (2026-10-18)

**Entscheidung:** Export einer Seite oder eines Teilbaums als Ordner: eine `.md` pro Seite, Unterseiten als Unterordner, Bilder in `assets/`, relative Links.

## ADR-007: Block-Editor auf einem NSTextView mit TextKit 2 (2026-10-18)

**Kontext:** Größtes Projektrisiko. Alternativen: ein `NSTextView` pro Block in einem Stack mit eigenem Selektionskoordinator, oder ein Web-Editor. Der Spike in Phase 1 hat den Ansatz mit einer TextView pro Seite gegen 8 Kriterien geprüft (Ergebnisse in `architecture.md`).
**Entscheidung:** Angenommen. Ein `NSTextView` pro Seite mit TextKit 2; ein Absatz entspricht einem Block. Block-Metadaten als Attribute auf jedem Zeichen. Native Edits innerhalb eines Absatzes übernimmt die TextView; strukturelle Edits laufen über `EditorDocument` und werden als Diff in die TextView geschrieben, damit Undo nativ bleibt. Dekoration zeichnen eigene `NSTextLayoutFragment`s.
**Konsequenzen:**
- Selektion, Kopieren über Blöcke, IME, Rechtschreibung, Services und Undo kommen vom System.
- Performance reicht weit: Tippen bei 1000 Blöcken im Median unter 1 ms.
- Marker sind nur gezeichnet. Für VoiceOver braucht es eigene Bedienungshilfen-Angaben (Phase 7).
- Bilder brauchen voraussichtlich einen `NSTextAttachmentViewProvider` (Phase 4).
- Der Controller ist AppKit-spezifisch. Für iOS entsteht später ein `UITextView`-Gegenstück; Modell, Abbildung und Fragmente werden geteilt.
- Eingabe mit markiertem Text ist per Test abgedeckt. Tote Tasten (´e, ^a, ⌥n n) hat der Nutzer am 2026-10-18 manuell geprüft; sie laufen über denselben Pfad wie IME. Ein manueller Test mit japanischer Eingabe steht noch aus.

**Überführung in Phase 3** (Spike → `QuillEditor`, jeweils mit Aufräumen und Tests):

| Spike-Teil | Ziel in `QuillEditor` | Anpassung |
|---|---|---|
| `Document/*` (Modell, Kürzel, Serializer, Slash-Befehle) | bleibt in `Document/` | – |
| `BlockAttributes`, `BlockRenderer` | `TextKit/` | Fonts und Farben hinter `#if` für iOS |
| `BlockLayoutFragment`, `BlockLayoutDelegate` | `TextKit/` | Zeichnen über `CGContext` statt `NSBezierPath`, damit iOS es teilt |
| `DividerAttachment` | `TextKit/` | Bild-Attachment erst in Phase 4 über `NSTextAttachmentViewProvider` |
| `BlockEditorController` | `AppKit/` | aufteilen in Eingabe (Enter, Tab, Backspace, Kürzel), Abgleich Text ↔ Modell und Zwischenablage |
| `BlockTextView`, `BlockEditorView` | `AppKit/` | – |
| `SlashMenu` | `AppKit/` (Panel), Modell neutral | – |
| `BlockEditorControllerTests` mit Harness | `Tests/QuillEditorTests` | – |
| `SpikeBenchmark` | Performance-Test in `QuillEditorTests` | Schwelle p95 < 16 ms bei 1000 Blöcken |
| `SpikeSamples` | Test-Fixtures | – |

Neu in Phase 3: `EditorPersistenceBridge` (Anbindung an `PageStore`) und Inline-Formatierung.

**Löschen:** Ja. Am Ende von Phase 3, im selben PR, sobald die Quill-App den Editor zeigt und alle übernommenen Tests grün sind, werden gelöscht: `Spikes/EditorSpike/`, das Target und Schema `EditorSpike`, das Modul `QuillEditorSpike` samt Produkt und Testtarget. Vorher wird der letzte Spike-Stand mit dem Git-Tag `editor-spike` markiert, damit er auffindbar bleibt.

**Stand Phase 3:** Erledigt. Tag `editor-spike` gesetzt; `QuillEditorSpike` wurde mit Zustimmung des Nutzers schon nach dem ersten Prüfpunkt gelöscht, `Spikes/EditorSpike` samt Target und Scheme am Ende der Phase. `SpikeBenchmark` ist `EditorBenchmark` im Test-Target, `SpikeSamples` ist die Fixture `SampleDocuments` (seit Phase 6 im Target `QuillTestFixtures`), `-snapshot` ersetzt `EditorSnapshotTests`.

## ADR-008: UI-Tests starten ohne gespeicherten Fensterzustand (2026-10-18)

**Kontext:** Nach ⌘R, Schließen des letzten Fensters und hartem Beenden (Xcode-Stop) sichert AppKit den Zustand „0 Fenster“. Unter macOS 27 liegt er im Dienst `com.apple.appkit.restoration_storage`, nicht in `Saved Application State/`. Programmatische Starts durch XCTest stellen diesen Zustand wieder her und öffnen kein Fenster. `testLaunchShowsMainWindow` schlug daher dauerhaft fehl, weil jeder Fehlversuch die App wieder hart beendet. Starts über Finder/Dock öffnen trotzdem ein Fenster; Nutzer sind nicht betroffen. `defaultLaunchBehavior(.presented)` und `restorationBehavior(.disabled)` helfen nicht, weil AppKit vor SwiftUI entscheidet.
**Entscheidung:** Alle UI-Tests starten die App über `XCUIApplication.quill()` mit `-ApplePersistenceIgnoreState YES`.
**Konsequenzen:** Deterministische Teststarts. Fensterwiederherstellung muss bei Bedarf eigens getestet werden. Zeigt ⌘R in Xcode kein Fenster, hilft ⌘N oder ein Klick aufs Dock-Symbol.

## ADR-009: Regeln für Reihenfolge und Papierkorb im PageStore (2026-10-18)

**Kontext:** `sortKey` per Fractional Indexing soll pro Verschieben genau ein Objekt ändern. Durch Fehler oder später durch Sync können Geschwister aber doppelte, leere oder ungültige Schlüssel haben. Außerdem kann eine Seite wiederhergestellt werden, während ihre Elternseite noch im Papierkorb liegt.
**Entscheidung:**
- Sind die Schlüssel der Nachbarn an der Zielposition doppelt oder ungültig, vergibt `PageStore` allen Geschwistern einmalig neue Schlüssel in der bisherigen Reihenfolge (sortiert nach `sortKey`, `createdAt`, `id`). Nur in diesem Reparaturfall ändert sich mehr als ein Objekt.
- Liegt beim Wiederherstellen eine Elternseite noch im Papierkorb, kommt die Seite ans Ende der obersten Ebene, damit sie sichtbar wird.
- Papierkorb-Seiten zählen beim Berechnen von Schlüsseln als Geschwister mit; Wiederherstellen behält so den alten Platz.
**Konsequenzen:** Reihenfolgen heilen sich selbst, ohne Migration. Seltene Reparaturen erzeugen mehrere Änderungen (später mehrere Sync-Datensätze).

## ADR-010: Automatische Backups der Datenbank (2026-10-18)

**Kontext:** Quill ist local-first; ohne Sync gibt es außer Time Machine keine zweite Kopie. Schemamigrationen sind der riskanteste Moment für Datenverlust.
**Entscheidung:** `StoreBackup` (in `QuillModel`) legt Backups unter `Application Support/Quill/Backups/<UTC-Zeitpunkt>_<Anlass>/` an:
- **Wie:** `VACUUM INTO` über eine eigene SQLite-Verbindung, danach `PRAGMA quick_check`. Konsistent auch bei offenem Store und WAL; einfaches Kopieren der Datei wäre das nicht. `.Quill_SUPPORT/` (Daten mit `.externalStorage`) wird mitkopiert. Erst nach erfolgreicher Prüfung wird der Ordner von `.…partial` umbenannt.
- **Wann:** beim Start vor dem Öffnen des Containers, wenn das letzte Backup älter als 24 h ist; **immer vor einer Migration** (zuletzt geöffnete Schema-Version in `Quill.store.version` weicht ab oder fehlt); beim Beenden, wenn Store oder WAL seit dem letzten Backup geändert wurden.
- **Aufbewahrung (11 reguläre Backups, Historie ca. 5 Wochen):**
  - 7 Tages-Backups: je das neueste Backup der letzten 7 Kalendertage, an denen es ein Backup gibt.
  - 4 Wochen-Backups **zusätzlich**: je das neueste Backup der 4 nächstälteren Kalenderwochen (ISO), in denen es kein Tages-Backup gibt. Wochen, die schon ein Tages-Backup haben, zählen nicht mit.
  - Backups vor einer Migration werden nie automatisch gelöscht und zählen nicht zu den 11.
- **Wiederherstellen:** in Phase 2 von Hand (Anleitung in `data-model.md`). Menüpunkt „Backup wiederherstellen…“ mit Tests in Phase 7, Pflicht vor v0.1.
**Konsequenzen:** Speicherbedarf etwa elffacher Store plus Migrations-Backups. Externe Daten werden ohne Snapshot kopiert; ein Bild, das genau während des Backups entsteht, kann im Backup fehlen.

## ADR-011: Migrationstests und eingefrorene Schemas (2026-10-18)

**Kontext:** Eine fehlerhafte Schemaänderung kann Nutzerdaten zerstören. Typische Fehler: `SchemaV1` wird direkt geändert statt eine neue Version anzulegen, oder eine Migrationsstufe verliert Daten. Datenbanken dürfen nicht ins Repo (CLAUDE.md), eine eingefrorene Testdatenbank scheidet also aus.
**Entscheidung:** Drei Arten von Tests in `QuillModelTests`:
- **Fingerabdruck** (`SchemaFingerprintTests`): Entitäten, Attribute (Typ, optional, Optionen) und Beziehungen (Ziel, Kardinalität, Löschregel, Inverse) jeder eingefrorenen Version als lesbarer Text, verglichen mit einem festen Wert im Test. Ein Fehlschlag zeigt genau, was sich geändert hat. Dazu prüft ein Test die CloudKit-Regeln (`id`/`createdAt`/`updatedAt`, kein `.unique`, Beziehungen optional mit Inverse) für jede Version im Plan.
- **Durchlauf** (`MigrationTests`): Ein Store wird zur Laufzeit explizit mit `SchemaV1` befüllt (Baum, Blöcke, Bild, Papierkorb, Favorit), mit dem echten `QuillMigrationPlan` geöffnet und vollständig geprüft.
- **Probelauf V1 → V2**: Eine `SchemaV2` nur im Test, mit einem Feld mit Default und einem Feld, das eine eigene Stufe (`.custom`) aus vorhandenen Daten berechnet. Der Test geht den Weg der App: Backup vor der Migration, Migration, und das Backup bleibt als V1-Store lesbar.
**Regel für neue Versionen:** Fingerabdruck der bisherigen Version einfrieren, `SchemaV(n)` plus Stufe anlegen, `CurrentSchema` umstellen, einen Test „V(n-1) → V(n)“ mit befülltem Store ergänzen. Die Probeversion wird dann durch die nächste echte Version ersetzt.
**Konsequenzen:** Keine Datenbank im Repo. Der Durchlauf erzeugt den Ausgangs-Store mit dem aktuellen Code. Dass dieser Code der ausgelieferten Version entspricht, sichert der Fingerabdruck ab.

## ADR-012: Sidebar als NSOutlineView, Menüleiste und Undo (2026-10-18)

**Kontext:** Der Seitenbaum braucht Ziehen zwischen und auf Zeilen in beliebiger Tiefe, Ausklappen beim Ziehen, Umbenennen in der Zeile, Kontextmenü und Tastatur. In verschachtelten SwiftUI-`List`s auf macOS sind Einfügen zwischen Zeilen und Ablegen auf Zeilen gleichzeitig nicht zuverlässig.
**Entscheidung:**
- **Sidebar als `NSOutlineView`** (Stil `.sourceList`) in einem `NSViewRepresentable` (`PageOutlineView`). Die Logik (Baum, Drop-Position, Zyklen) liegt plattformneutral in `PageTree`. Für iOS kommt später eine eigene Darstellung.
- **„Backups im Finder zeigen“ im Menü Ablage**, nicht im Menü Seite, weil es keine Seitenaktion ist.
- **Kein Menükürzel für „In den Papierkorb legen“:** ⌘⌫ löscht in Textfeldern bis zum Zeilenanfang und würde als Menükürzel die Seite wegwerfen. ⌘⌫ wirkt nur, wenn die Sidebar den Fokus hat.
- **Undo/Redo** für Anlegen, Umbenennen in der Sidebar, Verschieben und Papierkorb (`PageOperations`), damit nichts verloren geht, bevor es in Phase 5 eine Papierkorb-Ansicht gibt. Tippen im Titelfeld nutzt das Undo des Textfelds.
- **Kürzel wie in Apple Notizen:** ⌘N Neue Seite, ⇧⌘N Neue Unterseite, ⌥⌘N Neues Fenster, ⌘T Neuer Tab.
**Konsequenzen:** Mehr AppKit-Code in `QuillFeatures` (hinter `#if canImport(AppKit)`). Bedienungshilfen, Typ-Auswahl und Ausklappen per Pfeiltasten kommen von AppKit.

## ADR-013: Inline-Formatierung, Speichern aus dem Editor und zwei Fenster (2026-10-18)

**Kontext:** Phase 3 bindet den Editor an `PageStore` an. Offen waren das Speicherformat für Formatierung, wann und wie oft gespeichert wird, was bei zwei Fenstern mit derselben Seite passiert und wie Undo von Editor und Sidebar zusammenspielen.
**Entscheidung:**
- **Formatierung:** Marks `bold`, `italic`, `code`, `strikethrough` und ein Link pro Bereich. Im Modell als Spans (`InlineText`), gespeichert als versioniertes JSON in `Block.richText` (Format in `data-model.md`), `nil` ohne Formatierung. Marks sind Strings, damit unbekannte Werte späterer Versionen erhalten bleiben. `Block.text` bleibt maßgeblich: Passt `richText` nicht dazu, gilt der Klartext.
- **Kürzel:** ⌘B, ⌘I, ⇧⌘M (Inline-Code wie in Apple Notizen; ⌘E bleibt „Auswahl für Suche verwenden“, ⇧⌘C ist „Farben einblenden“), ⇧⌘X, ⌘K (Link; Suche deshalb auf ⌘O). Das Menü Format erreicht den Editor über die Responder-Kette.
- **Speichern** über `EditorPersistenceBridge`: Diff gegen den zuletzt gespeicherten Stand, entprellt 300 ms; sofort beim Seitenwechsel, beim Schließen und beim Beenden (`.terminateLater`, alle Editoren speichern, dann Backup). Eine leere neue Seite wird erst nach dem ersten Tippen geschrieben. Schlägt Speichern fehl, bleiben die Änderungen vorgemerkt; die Bridge versucht es selbst erneut (1 s, verdoppelt bis 30 s), und die Seite zeigt „Nicht gespeichert“, bis es gelingt. Scheitert es beim Beenden, fragt Quill „Änderungen konnten nicht gespeichert werden“ mit „Abbrechen“ (Vorgabe) und „Trotzdem beenden“ (`QuitGuard`). Gleichzeitige `flush()`-Aufrufe warten aufeinander; `load()` speichert vorher offene Änderungen anderer Editoren derselben Seite.
- **Zwei Fenster mit derselben Seite (bewusste Vereinfachung):** Nach jeder Speicherung lädt ein anderes Fenster die Seite neu, sofern es selbst keine ungespeicherten Änderungen hat. Sonst gewinnt pro Block die letzte Speicherung. Es gibt kein Zusammenführen innerhalb eines Blocks. Bei markiertem Text (IME) wird nicht neu geladen; das folgt nach dem nächsten eigenen Speichern.
- **Undo:** Jeder Editor hat einen eigenen `UndoManager`. ⌘Z im Text betrifft nur den Text, die Sidebar behält ihr Undo (ADR-012).
- **Kopf im Editor:** Icon und Titel sitzen im oberen Inset der Text-View und scrollen mit dem Text. ↩ im Titel springt in den Text, ↑ in der ersten Zeile zurück.
- **UI-Tests** lenken die Zwischenablage des Editors mit `-QuillPasteboardName` auf ein eigenes `NSPasteboard`, damit die des Nutzers weder gelesen noch überschrieben wird.
**Konsequenzen:**
- Für CloudKit-Sync reicht „letzte Speicherung pro Block gewinnt“ nicht. Dort kommen Änderungen verzögert und von mehreren Geräten; es braucht eine echte Konfliktlösung (mindestens pro Block mit `updatedAt` und sichtbarem Konfliktfall, besser Zusammenführen innerhalb eines Blocks). Das wird vor dem Sync entschieden.
- Undo-Schritte im Editor überleben keinen Seitenwechsel.
- `richText` ist plattformneutral und vom Markdown-Export lesbar; Änderungen am Format brauchen eine neue `version`.

## ADR-014: Block-Felder gebündelt in `BlockProperties` (2026-10-18)

**Kontext:** `indent`, `isChecked` und `codeLanguage` waren an zehn Stellen einzeln aufgezählt (Snapshot, `Block.snapshot`/`apply`, `EditorBlock` samt Codable, Bridge, `BlockStyle`, `BlockRenderer.parse`, `BlockLayoutFragment`, Regeln in `EditorDocument`). Der Bild-Block bringt weitere Felder.
**Entscheidung:**
- `BlockProperties` (`QuillModel`) bündelt die einfachen Felder neben Art und Text. `BlockSnapshot` und `EditorBlock` tragen `properties`; `EditorBlock` reicht die Felder per `@dynamicMemberLookup` durch (`block.indent`).
- `Block.properties` ist die einzige Abbildung auf die SwiftData-Spalten. `SchemaV1` bleibt unverändert (kein Schemawechsel).
- Welche Felder zu welcher Blockart passen, regelt `BlockProperties.normalized(for:)` in `QuillEditor`; `EditorDocument.setKind` nutzt es.
- **Textspeicher: weiter ein Schlüssel pro Feld**, gesetzt und gelesen nur über `BlockProperties.textAttributes` / `init(textAttributes:)`. Ein einzelnes Attribut mit dem Struct als Wert wurde geprüft: Gleichheit nach dem Bridging, Attributläufe und Undo in `NSTextView` funktionieren, aber `NSKeyedArchiver` kann einen Attributstring mit Struct-Wert nicht archivieren. AppKit archiviert Text an Stellen, die wir nicht steuern (Ziehen, Dienste, Pasteboard-Typen der Text-View); dort ginge der Wert verloren oder es käme zu einer Exception. Werte bleiben deshalb `Int`, `Bool`, `String`.
- **Zwischenablage:** Quill-Blöcke als `{"version":2,"blocks":[…]}` (`BlockClipboard`). Version 1 (bloßes Array, flache Felder), unbekannte Versionen und unlesbare Daten werden nicht als Blöcke gelesen; eingesetzt wird dann der Klartext.
- **`BlockKind` nur in `QuillModel`.** `QuillEditor` hatte eine zweite, gleich lautende Definition; jetzt ergänzt es nur Verhalten per `extension` (`isListItem`, `isAtomic` …). Switches über die Blockart in Renderer, Fragment, Serializer und `EditorDocument` haben kein `default:` mehr, damit der Compiler bei einer neuen Art anhält. `BlockKindCoverageTests` prüft per `CaseIterable` Snapshot, Renderer, Slash-Menü (Ausnahmen mit Grund in `notInSlashMenu`, derzeit `.image`) und Markdown.
- `BlockPropertiesRoundTripTests` schickt ein Exemplar mit lauter Nicht-Standardwerten durch Store, Snapshot, Editor, Textspeicher und Zwischenablage und prüft per `Mirror`, dass die Testdaten jedes Feld belegen.
**Konsequenzen:** Ein neues einfaches Feld braucht `BlockProperties`, `Block.properties` (mit neuer Schema-Version, ADR-011), einen Schlüssel in `textAttributes`, ggf. eine Regel in `normalized(for:)` und einen Testwert. Fehlt etwas davon, schlägt der Vollständigkeitstest fehl. Blöcke, die mit einem Build vor Phase 4 kopiert wurden, werden als Klartext eingesetzt.

## ADR-015: Bild-Block, Assets und Aufräumen (2026-10-18)

**Kontext:** Phase 4 bringt Bilder in den Editor. `SchemaV1` hat bereits `Asset` (Daten als `externalStorage`, `Block.asset` 1:1 mit Löschregel `cascade`). Offen waren Darstellung in TextKit 2, Import, Undo nach dem Löschen und Datenschutz.
**Entscheidung:**
- **Darstellung A:** `ImageAttachment` reserviert Platz in der natürlichen Größe (DPI aus den Metadaten wie in Apple-Apps: 144 DPI = 2 Pixel pro Punkt; ohne oder unter 72 DPI ein Pixel = ein Punkt; höchstens Textbreite), das Bild zeichnet `BlockLayoutFragment` aus `EditorImageCache` (wie beim Trenner; TextKit 2 zeichnet Attachment-Bilder nicht zuverlässig). Ein Prüftest (`ImageBlockSnapshotTests`) hat bestätigt: Bild an der reservierten Stelle, auf Textbreite skaliert, Text darüber und darunter, hell und dunkel. Kein `NSTextAttachmentViewProvider`: nur AppKit, schwerer per Snapshot zu prüfen. Bis ein Bild geladen ist, zeigt der Block eine Fläche in `quaternaryFill`; dekodiert wird verkleinert (≤ 2048 px) außerhalb des Main Threads.
- **Verknüpfung:** `BlockProperties.assetID`; die Daten reisen nie durch Snapshots oder die Zwischenablage. `Block.properties` setzt die Beziehung. Gehört ein Asset schon einem anderen Block, bekommt der neue Block eine Kopie, statt es wegzunehmen (Sicherheitsnetz; der Editor kopiert Assets beim Einsetzen selbst über `PageStore.duplicateAsset`, damit seine IDs stimmen).
- **Import** (`ImageImport`, `PageStore.importImage`): Originale bis 20 MB bleiben erhalten (PNG, JPEG, HEIC, GIF; andere Formate wie TIFF werden PNG). Größere Bilder werden auf höchstens 4096 px Kantenlänge heruntergerechnet (JPEG 0,9, mit Transparenz PNG) und nie abgelehnt; der Editor zeigt dezent „Bild wurde verkleinert“ (auch für VoiceOver angesagt).
- **Datenschutz:** GPS-Daten werden beim Import immer entfernt (`kCGImageMetadataShouldExcludeGPS`), Ausrichtung und übrige Metadaten bleiben. Dafür müssen die Metadaten der Quelle ausdrücklich mitgegeben werden, sonst verwirft ImageIO alle (per Test gefunden). Grenze laut SDK: Standortangaben in der MakerNote des Herstellers oder in eigenen XMP-Feldern filtert ImageIO nicht.
- **Löschen und Undo:** `applyEdits` löst das Asset vor dem Löschen eines Blocks (sonst `cascade`), damit Undo das Bild wiederfindet. Verwaiste Assets löscht `removeOrphanedAssets` beim Start nach 30 Tagen ohne Block (wie der Papierkorb), nach dem Start-Backup.
- **Einfügen:** Slash-Menü „Bild“ (Dateiauswahl), Einsetzen (Bilddateien aus dem Finder, sonst Bilddaten, aber nur ohne Text in der Zwischenablage) und Ablegen zwischen Blöcken. Dateien werden im Hintergrund gelesen und kurz geprüft (`ImageImport.isReadable`, nur Kopf und Eigenschaften); Unlesbares kommt gar nicht erst ins Dokument, also auch nicht über Undo zurück, es gibt nur einen Hinweis. Dauert das Lesen länger als 0,3 s, zeigt eine kleine Ladeanzeige an der Einfügestelle (eigene View über dem Text, nicht im Dokument, nicht im Undo). Für die lesbaren Bilder vergibt der Editor die Asset-ID und fügt den Block mit Platzhalter ein (ein Undo-Schritt, eine ersetzte Auswahl inklusive; wurde beim Lesen weitergetippt, an der Einfügemarke von dann). Der Import läuft danach im Hintergrund unter dieser ID (`importImage(_:assetID:linkTo:)` verknüpft einen schon gespeicherten Block). Weil sich der Block danach nicht mehr ändert, bleiben Undo und Redo auch während des Imports korrekt. Scheitert der Import trotzdem (z. B. beim Speichern), wird der Platzhalter entfernt und der Hinweis nennt die Ursache („nicht gelesen“ bzw. „nicht gespeichert“). Ein Asset, das sich nicht laden lässt, wird nicht bei jeder Änderung erneut geladen. Ein einzeln ausgewählter atomarer Block wird als ganzer Block kopiert; ein Bild zusätzlich als PNG (Anzeigegröße) für andere Apps.
**Konsequenzen:**
- Kein Schemawechsel. Bilder stehen als Daten im Store (`.Quill_SUPPORT`) und damit in jedem Backup.
- Ein und dasselbe Bild auf zwei Seiten belegt doppelt Platz (ein Asset pro Block).
- Markdown in der Zwischenablage ist für Bilder `![]()`; Pfade unter `assets/` kommen mit dem Export (Phase 6).
- Beim Verkleinern wird die DPI mitskaliert, damit ein Bild gleich groß erscheint.

## ADR-016: Kurzbefehle und Aktionen für Blöcke (2026-10-18)

**Kontext:** Phase 4 bringt Blockart, Verschieben und Duplizieren auf die Tastatur („Tastatur zuerst“) und ein Kontextmenü an den Griff. Die Tasten dürfen keine Standard-Kürzel von macOS überdecken.
**Entscheidung:**
- **Format › Blockart:** ⌥⌘0–7 in Slash-Menü-Reihenfolge (Text, Überschrift 1–3, Aufzählung, Nummerierte Liste, To-do, Zitat). ⌥⌘8 ist „Zoom ein/aus“ der Bedienungshilfen und erreicht die App dann nicht; Code hat deshalb kein Kürzel (Kürzel „``` “ und Menü bleiben). Liste und Ziffern an einer Stelle: `BlockConversion`.
- **Verschieben:** ⌥⌘↑/↓ statt ⌥⇧↑/↓, das in Textfeldern die Auswahl absatzweise erweitert (`StandardKeyBinding.dict`). Frei laut Standardbelegung; ⌃⌘↓ ist dort Schreibrichtung.
- **Duplizieren** ⌘D, **Abhaken** ⌘↩: in Quill und der Standardbelegung nicht vergeben.
- **Griff:** Klick wählt die Blöcke aus, Ziehen ab 3 pt, Rechtsklick öffnet Löschen, Duplizieren, Umwandeln in … (dieselbe Liste wie Format › Blockart). Für VoiceOver dieselben Aktionen als eigene Aktionen am Griff.
- Alle Aktionen wirken auf die Blöcke der Auswahl (sonst den Block am Cursor bzw. am Griff) und sind ein Undo-Schritt.
**Konsequenzen:**
- Die Menüpunkte liegen im Menü „Format“ und laufen über die Responder-Kette wie die Inline-Formate.
- Markdown-Kürzel greifen in allen Textblöcken außer Code; „## “ in einer Aufzählung macht eine Überschrift daraus.

## ADR-017: Navigation: Suche, Favoriten, Papierkorb (2026-10-19)

**Kontext:** Phase 5 bringt Schnell öffnen (⌘O), Favoriten und einen Papierkorb mit Auto-Leeren. `Page` hat `isFavorite`, `favoriteSortKey` und `trashedAt` schon seit `SchemaV1`; ein neues Schema ist nicht nötig.
**Entscheidung:**
- **Suche** (`PageStore.search`): Titel und Blocktext per `localizedStandardContains` (ohne Groß/klein und Akzente). Titeltreffer zuerst: Titel beginnt mit dem Begriff, dann ein Wort darin, dann irgendwo; bei Gleichstand zuletzt bearbeitet. Danach ein Inhaltstreffer je Seite, aus dem ersten passenden Block nach `sortKey`, mit Ausschnitt (`TextSnippet`, 80 Zeichen, an Wortgrenzen). Seiten im Papierkorb (auch über eine Elternseite) zählen nicht. Höchstens **500 passende Blöcke** werden gelesen (`contentScanLimit`), mit `propertiesToFetch` und vorab geladener Seite: p95 etwa 25–40 ms bei 1000 Seiten × 50 Blöcken (Test < 100 ms). Eine Unterabfrage je Seite brauchte 1,3 s. Bei sehr häufigen Begriffen fehlen deshalb einzelne Inhaltstreffer; die Titeltreffer bleiben vollständig.
- **Schnell öffnen:** schwebendes Feld über dem Fenster (Liquid Glass wie das Slash-Menü), kein eigenes `NSPanel`. Ohne Begriff die zuletzt bearbeiteten Seiten, sonst Abschnitte „Seiten“ (mit Pfad) und „Inhalt“ (mit Ausschnitt); 100 ms Ruhe vor der Suche, veraltete Ergebnisse werden verworfen. ↑↓ wählen, ↩ öffnen, ⌘↩ in neuem Tab, ⎋ oder Klick daneben schließt; der Tastaturfokus bleibt im Suchfeld, solange das Feld offen ist. Inhaltstreffer springen zum Block und wählen die Fundstelle aus (`BlockEditorController.reveal(blockID:range:)`); in einem neuen Tab öffnet nur die Seite. Solange das Feld offen ist, ist „Abhaken“ (⌘↩) deaktiviert, sonst finge der Menüpunkt die Taste ab. Ablage › „Schnell öffnen …“ (⌘O) und „Suchen“ oben in der Sidebar.
- **Favoriten:** eigener Abschnitt im selben `NSOutlineView` (Gruppenzeilen „Favoriten“ und „Seiten“, immer offen), flach, Reihenfolge per `favoriteSortKey` (Fractional Indexing wie ADR-009). Der Abschnitt erscheint mit dem ersten Favoriten und, solange eine Seite gezogen wird, auch leer als Ablageziel (`SidebarSection`). Hinzufügen über den Stern in der Symbolleiste, Menü „Seite“, Kontextmenü oder Ziehen auf „Favoriten“; Umsortieren per Ziehen innerhalb der Favoriten; Favoriten lassen sich nicht in den Baum ziehen (`SidebarDrop`). Kein Kürzel: ⌃⌘D (Wörterbuch) und ⌃⌘F (Vollbild) sind belegt. Undo stellt beim Entfernen den alten Platz wieder her. Favoriten ändern `updatedAt` nicht, damit „Zuletzt bearbeitet“ nur echte Bearbeitungen zeigt. Seiten im Papierkorb verschwinden aus den Favoriten und kommen beim Wiederherstellen zurück (`isFavorite` bleibt).
- **Papierkorb:** Liste im Detailbereich mit Titel, Vorschau (erste Worte, gleiche Ausschnitt-Logik), Pfad und Datum. Wiederherstellen mit Undo (Knopf, Kontextmenü; Doppelklick tut nichts, damit nichts versehentlich zurückkommt); „Endgültig löschen“ und „Papierkorb leeren“ fragen per `alert` nach. Mehrere Seiten werden in einem Schritt gelöscht. Scheitert das Löschen, erscheint ein Hinweis über der Liste statt eines Dialogs (`design.md`). Die Liste bekommt beim Öffnen den Fokus, damit ⌫ wirkt. **Auto-Leeren:** beim Start und danach alle 24 h, was länger als 30 Tage im Papierkorb liegt; Unterseiten gehen mit ihrer Elternseite.
- **Backup vor dem Löschen** (erweitert ADR-010): Vor jedem endgültigen Löschen (von Hand oder automatisch) ein Backup mit Anlass `vor-papierkorb-leeren`, außer der Store ist seit dem letzten Backup gleich welcher Art unverändert (Änderungsdatum von Store und WAL); so liegt auch eine eben angelegte, dann gelöschte Seite in einem Backup. Scheitert das Backup, wird nichts gelöscht. Auto-Leeren legt nur ein Backup an, wenn etwas fällig ist. Diese Backups zählen nicht zu den 11 regulären; sie bleiben 30 Tage, höchstens die neuesten 10.
**Konsequenzen:**
- Endgültig gelöschte Seiten lassen sich nur noch aus einem Backup holen. Ein älterer Undo-Schritt „In den Papierkorb legen“ für eine inzwischen gelöschte Seite scheitert beim Rückgängigmachen und wird nur protokolliert.
- Im Papierkorb lesend öffnen (mit Hinweisbanner) kommt später (Roadmap).
- XCUITest kann die Ziehen-Gesten in der `NSOutlineView` nicht auslösen (siehe Phase 2); Ablegen auf Favoriten ist über `SidebarDrop` per Unit-Test abgedeckt und wird von Hand geprüft.

## ADR-018: Markdown-Export (2026-10-19)

**Kontext:** Phase 6 setzt ADR-006 um. Ziel ist ein beliebiger Ordner per Dialog (iCloud Drive, Obsidian-Vault, Dokumente); Links und Bilder müssen dort ohne Nacharbeit funktionieren.
**Entscheidung:**
- **Ablauf:** Seite › „Exportieren …“ (⇧⌘E) oder Kontextmenü der Sidebar → `NSOpenPanel` für einen Ordner mit Kästchen „Unterseiten einschließen“ (an) → Lesen in einem Schritt auf dem Actor von `PageStore` (`exportSnapshot`, reiner `Sendable`-Werttyp) → `ExportWriter.export` (`@concurrent`, nie auf dem Main Actor): erst die Bilder laden, dann das Markdown aufbauen (`MarkdownExporter.plan`), dann schreiben → Meldung mit Seiten-, Bild- und Fehlbildzahl und „Im Finder zeigen“.
- **Ordner:** immer neu, „<Seite> (Quill JJJJ-MM-TT)“ (lokales Datum); gibt es ihn schon (auch in anderer Schreibweise), „… 2“, „… 3“. Geschrieben wird erst in einen Zwischenordner, dann umbenannt: kein halber Export, nie überschreiben. Der Zwischenordner liegt im temporären Ordner, den das System für das Ziel vorsieht (`.itemReplacementDirectory`, in der Sandbox im Container; geprüft für Dokumente und iCloud Drive), wenn er auf demselben Volume liegt. Sonst entsteht er als `.quill-export-<UUID>` im Ziel; der nächste Export dorthin löscht nur Ordner mit exakt diesem Namen, die älter als eine Stunde sind (jüngere könnten zu einem Export in einem anderen Fenster gehören).
- **Aufbau:** eine `.md` pro Seite, Unterseiten im gleichnamigen Ordner daneben, ein `assets/` ganz oben für alle Bilder (Name: erste 8 Zeichen der Asset-ID plus Endung aus dem UTI). Seiten im Papierkorb fehlen; eine Seite im Papierkorb lässt sich nicht exportieren.
- **Inhalt:** YAML-Frontmatter (`title`, `created`, `updated` als ISO 8601 UTC, `quill-id`), dann `# Titel`, dann die Blöcke über `MarkdownSerializer` (wie beim Kopieren), am Ende „## Unterseiten“ mit relativen `.md`-Links. Bilder als `![](../assets/…)` relativ zur Datei; fehlt ein Asset oder liefert es keine Daten, ein HTML-Kommentar statt eines Links ins Leere.
- **Links:** Ziele mit Leerraum, Klammern oder `<>` in spitzen Klammern (`[Text](<Ohne Titel.md>)`), CommonMark-konform und in Obsidian lesbar; gilt auch für Links im Text und beim Kopieren als Markdown.
- **Dateinamen:** `/ \ : * ? " < > | # ^ [ ] %` werden „-“; Steuer- und Zeilentrennzeichen ein Leerzeichen; führende Punkte „-“ (sonst unsichtbar); Zeichen über 64 Bytes (Buchstabe mit Hunderten Akzenten) „-“, damit das Kürzen nie einen leeren Namen ergibt; leer wird „Ohne Titel“. Höchstens 255 Bytes UTF-8 (APFS), gekürzt nur am Titel und an Zeichengrenzen (Emoji, Umlaute bleiben heil). Gleiche Namen im selben Ordner ohne Unterschied von Groß-/Kleinschreibung und Unicode-Normalform (wie APFS) bekommen „Titel 2“. Eine Seite mit Unterseiten belegt Datei und Ordner zugleich; `assets` ist ganz oben reserviert.
- **Module:** `QuillExport` hängt von `QuillEditor` ab, nutzt aber nur dessen `Document`-Schicht (Serializer, `EditorBlock`), damit Kopieren und Export dasselbe Markdown erzeugen. Texte in den Dateien („Ohne Titel“, „Unterseiten“) kommen lokalisiert aus der App (`ExportStrings`). Die Beispieldokumente liegen dafür im eigenen Target `QuillTestFixtures`, das Editor- und Export-Tests teilen.
**Konsequenzen:**
- Der Export ist eine Momentaufnahme; ein Re-Import kann später über `quill-id` zuordnen.
- Bricht die App beim Export auf ein anderes Volume ab, bleibt bis zum nächsten Export dorthin ein versteckter `.quill-export-<UUID>`-Ordner im Ziel; auf demselben Volume räumt das System seinen temporären Ordner selbst auf.
- Links zwischen Seiten gibt es bisher nur als Unterseiten-Liste; Seitenlinks im Text kämen als relative `.md`-Links dazu.
- Der Ordnerdialog läuft in der Sandbox außerhalb der App und wird von Hand geprüft; der UI-Test schreibt per `-QuillExportDirectory` in den temporären Ordner der App.

## ADR-019: Backup wiederherstellen (2026-10-19)

**Kontext:** Backups (ADR-010) ließen sich bisher nur von Hand im Finder einspielen. Vor v0.1 braucht es einen sicheren Weg in der App. Ein offener `ModelContainer` lässt sich nicht gefahrlos austauschen. Das Review von PR #7 fand, dass ein Austausch Datei für Datei nach einem Abbruch Originale löschen konnte; daher tauscht Quill den ganzen Store-Ordner in einem Schritt.
**Entscheidung:**
- **Speicherort:** Alle Store-Dateien (`Quill.store`, `-wal`, `-shm`, `.Quill_SUPPORT`, `Quill.store.version`) liegen in `Application Support/Quill/Store/`, daneben `Backups/`, die Sperre `Store.lock` und der Merker `Quill.store.restore`. Backup-Ordner bleiben flach (Dateien direkt im Ordner), auch die aus der Zeit vor `Store/`.
- **Umzug (einmalig):** Liegt beim Start noch ein Store direkt in `Quill/` und gibt es `Store/` nicht, entsteht zuerst ein Backup `vor-umzug` (nie rotiert; scheitert es, wird nicht umgezogen und nicht geöffnet). Dann werden die Dateien einzeln nach `.Store-umzug/` verschoben und der Ordner zuletzt in `Store/` umbenannt. Es wird nur verschoben, nie gelöscht, und nie überschrieben; bricht der Umzug ab, macht der nächste Start dort weiter. Gibt es `Store/` schon, bleibt eine Datei im alten Ort unberührt.
- **Sperre:** Umzug und Wiederherstellen laufen unter `flock` auf `Store.lock` (`StoreBackup.prepareStore`). Eine zweite Instanz wartet bis 30 s und öffnet sonst nicht. Das System gibt die Sperre beim Prozessende frei, auch nach einem Absturz.
- **Ablauf:** Ablage › „Backup wiederherstellen …“ → Liste (neuestes zuerst, Datum, Anlass, Größe) → Bestätigung → `requestRestore` prüft das Backup und schreibt den Merker → das Sheet schließt, Quill beendet sich (solange ein Sheet offen ist, ignoriert AppKit `terminate`). Bricht der Nutzer das Beenden ab (Rückfrage bei ungespeicherten Änderungen), wird die Vormerkung zurückgenommen und gemeldet. Beim nächsten Start spielt `prepareStore` das Backup ein, **bevor** Backups entstehen und der Container öffnet; das erste Fenster meldet, welches Backup eingespielt wurde und wo der vorherige Stand liegt, oder warum nicht.
- **Prüfen vor dem Beenden** (und noch einmal beim Start): Ordner und `Quill.store` vorhanden, Schema passt zu einer bekannten Version (`isConfiguration(withName:compatibleWithStoreMetadata:)` gegen `QuillMigrationPlan.schemas`; neuere oder fremde Datenbanken werden abgelehnt), `quick_check` **nur lesend** (ein schreibendes Öffnen schriebe den WAL ins Backup zurück), freier Platz mindestens Größe des Backups plus 100 MB. Scheitert etwas, bleibt Quill offen und zeigt den Grund.
- **Austausch:** Merker löschen (lässt er sich nicht löschen, wird nicht getauscht: kein Wiederherstellungs-Loop) → Backup (Store immer mit `-wal`/`-shm`, dazu `.Quill_SUPPORT`) nach `Quill/.restore-staging/` kopieren, prüfen, geprüfte Version und Markierung `.quill-restore` hinein → `Store/` und `.restore-staging/` per `renamex_np(…, RENAME_SWAP)` in **einem** Schritt tauschen (ohne Unterstützung: kein Tausch, Fehler) → alten Stand nach `Backups/<Zeit>_vor-wiederherstellen/` umbenennen, Markierung entfernen. `Store/` enthält jederzeit einen vollständigen Stand. Nach einem Abbruch erkennt der nächste Start an der Markierung in `Store/`, ob schon getauscht wurde: Wenn ja, schließt er ab; wenn nein, verwirft er die Kopie (das Backup liegt unverändert in `Backups/`). Ein Journal gibt es nicht mehr.
- **Rückweg:** „Vor dem Wiederherstellen“ erscheint in der Liste und lässt sich selbst wiederherstellen. Die Rotation behält es 30 Tage, ebenso immer das gerade vorgemerkte Backup (das Backup beim Beenden direkt danach würde sonst ein Backup vom selben Tag verdrängen).
- **Test-Startargumente:** `-QuillInMemoryStore` und `-QuillStoreDirectory` wirken nur aus der Kommandozeile (nie aus gespeicherten Einstellungen wie `defaults write`) und nur in Debug-Builds; sonst könnte ein gespeicherter Wert den echten Store still durch einen leeren ersetzen.
- **Tests:** `StoreRestoreTests` (Austausch, WAL/SHM, Bilder, Schema, Platz, Beschädigung, Merker, Abbruch nach jedem Einzelschritt, altes flaches Format, Rotation), `StoreLayoutTests` (Umzug mit Abbruch nach jedem Schritt, kein Umzug ohne Backup, Sperre), `TestStoreArgumentTests`, `RestoreQuitCancelledTests`. Suiten mit Stores samt Bildern auf der Platte laufen vorsichtshalber nacheinander (`DiskStoreSuites`): Zweimal las ein Test bei parallelem Lauf Bildbytes, die nur in einer anderen Suite vorkommen (Titel aus dem WAL dabei richtig). Die Ursache ist offen. Geprüft: getrennte Ordner pro Test, kein veränderlicher globaler Zustand in `QuillModel`, in der App nur ein `ModelContainer` (Backup und `quick_check` mit rohem SQLite, Umzug und Tausch vor dem Öffnen). Ein Spike mit eigenem Mini-Modell (externe Speicherung; parallel, lange offene Container, Modelle bauen, Löschen bei offenem Container; gut 2000 Läufe) und 46 Wiederholungen der echten Suiten ohne Serialisierung, auch unter CPU-Last, zeigten keinen Fehler. Die Bild-Assertions nennen bei Fehlschlag Store-Pfad und externe Dateien. Der UI-Test läuft über drei Starts mit `-QuillStoreDirectory <Name>`: Store und Backups im temporären Ordner der App, nie der echte Store.
**Konsequenzen:**
- Wiederherstellen kostet einen Neustart, dafür ist nie ein Container offen, während Dateien wechseln.
- Die Anleitung „von Hand wiederherstellen“ (`docs/data-model.md`) arbeitet jetzt mit `Store/`.
- Mehrere Instanzen öffnen den Store nach der Vorbereitung weiterhin gleichzeitig; die Sperre schützt nur Umzug und Austausch.
