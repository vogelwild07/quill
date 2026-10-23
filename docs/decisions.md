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
- **Zwei Fenster mit derselben Seite (bewusste Vereinfachung):** Nach jeder Speicherung lädt ein anderes Fenster die Seite neu, sofern es selbst keine ungespeicherten Änderungen hat. Sonst gewinnt pro Block die letzte Speicherung. Es gibt kein Zusammenführen innerhalb eines Blocks. Bei markiertem Text (IME) wird nicht neu geladen; das folgt nach dem nächsten eigenen Speichern. *Abgelöst im Review von Phase 11 (ADR-029):* Die Bridge speichert nur noch vom erwarteten Stand aus und führt sonst je Block zusammen (`BlockMerge`).
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
- **Löschen und Undo:** `applyEdits` löst das Asset vor dem Löschen eines Blocks (sonst `cascade`), damit Undo das Bild wiederfindet. Verwaiste Assets löscht `removeOrphanedAssets` beim Start nach 30 Tagen ohne Block (wie der Papierkorb), nach dem Start-Backup. Seit 12.4 wählbar, Standard 90 Tage (ADR-031).
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
- **Umzug (einmalig):** Liegt beim Start noch ein Store direkt in `Quill/` und gibt es `Store/` nicht, entsteht zuerst ein Backup `vor-umzug` (nie rotiert; scheitert es, wird nicht umgezogen und nicht geöffnet). Dann werden die Dateien einzeln nach `.Store-umzug/` verschoben und der Ordner zuletzt in `Store/` umbenannt. Es wird nur verschoben, nie gelöscht, und nie überschrieben; bricht der Umzug ab, macht der nächste Start dort weiter. Gibt es `Store/` schon und liegen trotzdem Store-Dateien im alten Ort oder ein `.Store-umzug/`, wird weder überschrieben noch gemischt: Sie kommen unverändert in ein Backup `beiseitegelegt` (nie rotiert, lässt sich einspielen), und das erste Fenster meldet es.
- **Sperre:** Umzug und Wiederherstellen laufen unter `flock` auf `Store.lock` (`StoreBackup.prepareStore`). Eine zweite Instanz wartet bis 30 s und öffnet sonst nicht. Das System gibt die Sperre beim Prozessende frei, auch nach einem Absturz.
- **Ablauf:** Ablage › „Backup wiederherstellen …“ → Liste (neuestes zuerst, Datum, Anlass, Größe) → Bestätigung → `requestRestore` prüft das Backup und schreibt den Merker → das Sheet schließt, Quill beendet sich (solange ein Sheet offen ist, ignoriert AppKit `terminate`). Bricht der Nutzer das Beenden ab (Rückfrage bei ungespeicherten Änderungen), wird die Vormerkung zurückgenommen und gemeldet. Beim nächsten Start spielt `prepareStore` das Backup ein, **bevor** Backups entstehen und der Container öffnet; das erste Fenster meldet, welches Backup eingespielt wurde und wo der vorherige Stand liegt, oder warum nicht.
- **Prüfen vor dem Beenden** (und noch einmal beim Start): Ordner und `Quill.store` vorhanden, Schema passt zu einer bekannten Version (`isConfiguration(withName:compatibleWithStoreMetadata:)` gegen `QuillMigrationPlan.schemas`; neuere oder fremde Datenbanken werden abgelehnt), `quick_check` **nur lesend** (ein schreibendes Öffnen schriebe den WAL ins Backup zurück), freier Platz mindestens Größe des Backups plus 100 MB. Scheitert etwas, bleibt Quill offen und zeigt den Grund.
- **Austausch:** Merker löschen (lässt er sich nicht löschen, wird nicht getauscht: kein Wiederherstellungs-Loop) → Backup (Store immer mit `-wal`/`-shm`, dazu `.Quill_SUPPORT`) nach `Quill/.restore-staging/` kopieren, prüfen, geprüfte Version und Markierung `.quill-restore` hinein → `Store/` und `.restore-staging/` per `renamex_np(…, RENAME_SWAP)` in **einem** Schritt tauschen (ohne Unterstützung: kein Tausch, Fehler) → alten Stand nach `Backups/<Zeit>_vor-wiederherstellen/` umbenennen, Markierung entfernen. `Store/` enthält jederzeit einen vollständigen Stand. Nach einem Abbruch erkennt der nächste Start an der Markierung in `Store/`, ob schon getauscht wurde: Wenn ja, schließt er ab; wenn nein, verwirft er die Kopie (das Backup liegt unverändert in `Backups/`). Ein Journal gibt es nicht mehr.
- **Rückweg:** „Vor dem Wiederherstellen“ erscheint in der Liste und lässt sich selbst wiederherstellen. Die Rotation behält es 30 Tage, ebenso immer das gerade vorgemerkte Backup (das Backup beim Beenden direkt danach würde sonst ein Backup vom selben Tag verdrängen).
- **Test-Startargumente:** `-QuillInMemoryStore` und `-QuillStoreDirectory` wirken nur aus der Kommandozeile (nie aus gespeicherten Einstellungen wie `defaults write`) und nur in Debug-Builds; sonst könnte ein gespeicherter Wert den echten Store still durch einen leeren ersetzen.
- **Tests:** `StoreRestoreTests` (Austausch, WAL/SHM, Bilder, Schema, Platz, Beschädigung, Merker, Abbruch nach jedem Einzelschritt, altes flaches Format, Rotation), `StoreLayoutTests` (Umzug mit Abbruch nach jedem Schritt, kein Umzug ohne Backup, Beiseitelegen neben vorhandenem `Store/`, Sperre), `TestStoreArgumentTests`, `RestoreQuitCancelledTests`. Suiten mit Stores samt Bildern auf der Platte laufen vorsichtshalber nacheinander (`DiskStoreSuites`): Zweimal las ein Test bei parallelem Lauf Bildbytes, die nur in einer anderen Suite vorkommen (Titel aus dem WAL dabei richtig). Die Ursache ist offen. Geprüft: getrennte Ordner pro Test, kein veränderlicher globaler Zustand in `QuillModel`, in der App nur ein `ModelContainer` (Backup und `quick_check` mit rohem SQLite, Umzug und Tausch vor dem Öffnen). Ein Spike mit eigenem Mini-Modell (externe Speicherung; parallel, lange offene Container, Modelle bauen, Löschen bei offenem Container; gut 2000 Läufe) und 46 Wiederholungen der echten Suiten ohne Serialisierung, auch unter CPU-Last, zeigten keinen Fehler. Die Bild-Assertions nennen bei Fehlschlag Store-Pfad und externe Dateien. Phase 7.2: In 50 Läufen ohne Serialisierung (25 ohne, 25 mit CPU-Last) einmal nachgestellt, ohne Last: `StoreLayoutTests` las Bild-Byte 2 statt 7 (2 kommt nur in `StoreRestoreTests` vor), die Datei in `.Quill_SUPPORT` hatte aber das richtige Byte 7. Die Verwechslung passiert also beim Lesen im Prozess, nicht auf der Platte; die Ursache bleibt offen. Serialisiert unter CPU-Last 25 von 25 Läufen grün; die Serialisierung bleibt. Der UI-Test läuft über drei Starts mit `-QuillStoreDirectory <Name>`: Store und Backups im temporären Ordner der App, nie der echte Store.
**Konsequenzen:**
- Wiederherstellen kostet einen Neustart, dafür ist nie ein Container offen, während Dateien wechseln.
- Die Anleitung „von Hand wiederherstellen“ (`docs/data-model.md`) arbeitet jetzt mit `Store/`.
- Mehrere Instanzen öffnen den Store nach der Vorbereitung weiterhin gleichzeitig; die Sperre schützt nur Umzug und Austausch.

## ADR-020: Performance messen (2026-10-19)

**Kontext:** Phase 7.2 sollte erst messen, dann aufräumen und optimieren. Debug-Builds und der echte Store taugen dafür nicht: Debug ist um ein Vielfaches langsamer, und am echten Store darf nicht getestet werden.

**Entscheidung:**
- Package: `QuillPerformanceTests`, nur optimiert (`swift test -c release`, sonst übersprungen), mit Schwellen in `Performance.limits`; `Scripts/perf-package.py` wiederholt und zeigt Median, Minimum, Maximum.
- App: eigene Konfiguration „Profiling“ (optimiert wie Release, Produkt „Quill Profiling“, Bundle-ID `io.github.vogelwild07.quill.profiling`, also eigener Sandbox-Container und Store). Den Bestand legt `-QuillSeedPages` an, nur unter `QUILL_PROFILING` kompiliert und nur in dieser Bundle-ID; gemessen wird per Signposts (`QuillSignposts`) und `XCTOSSignpostMetric` in `PerformanceUITests`, ausgewertet von `Scripts/perf-ui.py`. `Scripts/check-release-binary.sh` prüft, dass Release keinen Profiling-Code enthält.
- Schwellen: Produktziele fest; neue Messungen max(Baseline × 3, Baseline + 5 ms), nie über einem Ziel. Ausnahmen nur nach Rücksprache (Sidebar beim Start 200 ms, nach ⌘N 180 ms ab Anlegen der Seite; `docs/performance.md`).

**Konsequenzen:**
- Messungen brauchen Netzteil, keine Last und dasselbe Gerät; die Bedingungen stehen in `docs/performance.md`.
- Die Profiling-App ist eine zweite App auf dem Mac mit eigenem Container; ihr Bestand wird bei jedem Messlauf neu angelegt.

## ADR-021: Bedienungshilfen, Leerzustände, Lokalisierung, Icon (2026-10-19)

**Kontext:** Phase 7.3 sollte Quill für v0.1 bedienbar mit VoiceOver und Tastatur machen, leere Ansichten erklären, alle Texte lokalisierbar halten und ein App-Icon liefern. Prüfen ohne Bildschirmfotos (CLAUDE.md), nur über Bedienungshilfen, XCUITest und eigene Renderings.

**Entscheidung:**
- Bedienungshilfen: `AccessibilityAuditUITests` führt `performAccessibilityAudit(for: .all)` in 11 Ansichten aus und ist rot bei jeder neuen Meldung. Ausnahmen nur einzeln mit Begründung im Code, keine Prüfart pauschal: Systemstil von Source-List und Symbolleiste (Entscheidung 1), secondary auf Glas (Hinweise in Schnell öffnen und Slash-Menü) und primary auf dem Glas der Sidebar (Kontrast hängt vom Hintergrund hinter dem Fenster ab), SwiftUI-Hüllgruppen ohne Beschriftung, Touch-Bar-Elemente des Systems, die gedimmte Papierkorb-Zeile hinter dem Sheet „Backup wiederherstellen“. Meldungen ohne Element lassen sich keiner Ursache zuordnen und werden je Ansicht und Prüfart genau erwartet (eine mehr oder weniger ist rot): eine Eltern-Kind-Meldung bei fokussiertem Textfeld (Feld-Editor von AppKit), zwei in „Schnell öffnen“ (zusätzlich `.isModal`, damit VoiceOver im Panel bleibt). Vor jedem Audit wartet der Test, bis sich der Baum der Bedienungshilfen nicht mehr ändert.
- Tastatur: Sidebar →Tab→ Titel →Tab→ Editor →⌃Tab→ Sidebar (Tab rückt im Editor ein); rückwärts mit ⇧, das Symbol nur auf dem Rückweg (⇧Tab im Titel). „Bewegung reduzieren“ über `QuillDesign.Motion`.
- Leerzustände: ein Katalog `EmptyState` mit `EmptyStateView` (Symbol grau, Titel und Erklärung in primary, weil der Systemstil hell nur 3,1:1 erreicht). `EmptyStateSnapshotTests` rendert jeden Fall hell und dunkel und prüft Regeln statt Referenzbildern: jede Textzeile 4,5:1, im Dunkeln nichts dunkler als der Hintergrund. Der Hinweis auf einer leeren Seite wird nur gezeichnet (nie gespeichert, exportiert oder kopiert) und ist für VoiceOver ein Platzhalter.
- Lokalisierung: nur Deutsch. `LocalizationTests` liest App-Target und Packages: kein Prosa-Literal außerhalb lokalisierender APIs (Ausnahmen je Literal mit Begründung; eine Ausnahme, die kein Literal mehr trifft, ist rot), in Packages immer `bundle: .module`, Schlüssel in Code und Katalog decken sich, Ganzzahlen in Sätzen mit Pluralformen, sichtbare Info.plist-Einträge in `InfoPlist.xcstrings`. Die Konfiguration „Profiling“ nimmt `InfoPlist.xcstrings` aus (`EXCLUDED_SOURCE_FILE_NAMES`), sonst hieße die Profiling-App „Quill“.
- Bilder in UI-Tests erzeugt die App selbst (`-QuillTestImage`, nur Debug): Füllt ein anderer Prozess die Zwischenablage, sperrt der Datenschutz („Einsetzen aus anderen Apps“) das Einsetzen. Die eigene Zwischenablage (`-QuillPasteboardName`) gilt wie die Store-Argumente (ADR-019) nur aus der Kommandozeile und nur im Debug-Build, nie aus gespeicherten Einstellungen.
- Icon: `App/Resources/AppIcon.icon` aus Icon Composer, ersetzt `AppIcon.appiconset`. Weißes, leicht geneigtes Blatt mit einer Linie in Koralle auf tiefem Grün, eine Gruppe mit zwei Ebenen; im Dock deutlich anders als Notizen, Pages und Freeform. Entwürfe bleiben lokal (`Design/IconDrafts/`, ignoriert).

**Konsequenzen:**
- Neue UI-Texte brauchen einen Katalogeintrag, sonst ist `LocalizationTests` rot; neue Meldungen der Bedienungshilfen machen den Audit rot.
- Der Audit hängt teils vom Bildschirm ab (Glas, Hell/Dunkel); deshalb prüfen die Snapshot-Tests den Kontrast auf festem Hintergrund zusätzlich.
- „Kontrast erhöhen“ ließ sich offscreen nicht prüfen; im dunklen Modus zeichnet macOS den Icon-Hintergrund selbst dunkel, die eigene Variante für Dunkel greift dort nicht.

## ADR-022: Release ohne Developer ID und Notarisierung (2026-10-19)

**Kontext:** v0.1.0 soll als .dmg auf GitHub erscheinen. Es gibt nur ein Personal Team (gratis), also weder Developer-ID-Zertifikat noch Notarisierung. Auf diesem Mac liegt keine Signier-Identität im Schlüsselbund.

**Entscheidung:**
- Die App wird nur ad hoc signiert (`CODE_SIGN_IDENTITY=-`, ohne Team und Profil), mit Hardened Runtime und App Sandbox. Nutzer bestätigen die Gatekeeper-Meldung selbst über Systemeinstellungen › Datenschutz & Sicherheit › „Dennoch öffnen“ (seit macOS 15 der einzige Weg). Die Anleitung empfiehlt kein `xattr`.
- Nur Apple Silicon (`arm64`), ab macOS 26.0, wie im Projekt festgelegt (CLAUDE.md). Ein Intel-Build ließe sich nicht testen.
- `Scripts/make-release.sh` baut alles aus einer sauberen Arbeitskopie: `xcodebuild archive` (nur das Archiv entfernt Debug-Symbole und damit Pfade wie `/Users/…`), prüft Version, Bundle-ID, Architektur, Mindestversion, Ad-hoc-Signatur ohne Team, Hardened Runtime, Sandbox, kein `get-task-allow`, keine persönlichen Pfade und per `check-release-binary.sh --app` keinen Profiling- oder Testcode (Merkmale des Seeds und des Testbilds, die Namen aller drei Startargumente für UI-Tests, die deshalb samt Konstanten nur in Debug existieren, keine `.xctest`/`PlugIns`; später kam die Lognachricht der Fenstergröße für die README-Bilder hinzu, `-QuillWindowSize`, ebenfalls nur Debug). Danach .dmg mit `Quill.app` und Verknüpfung „Programme“ → `/Applications`, nur lesend eingehängt und geprüft (Inhalt, Signatur, gleicher CDHash wie der Build), dazu `Quill-<Version>.dmg.sha256`. Ausgabe in `dist/` (ignoriert).
- Bundle-ID `io.github.vogelwild07.quill` statt `de.vogel.quill` (ein Namensraum, der zum GitHub-Konto gehört, statt einer fremden Domain), vor dem ersten Release, solange nur ein Store umziehen muss. Alle internen Kennungen (Zwischenablage, Drag, Textattribute, Notification, Logger, Signposts, Profiling, UI-Test-Runner) folgen; `BundleIdentifierTests` hält die alte Kennung aus dem Repo. Der Umzug des eigenen Stores läuft einmal von Hand über „Backup wiederherstellen“ (`docs/data-model.md`): Die Kopie des Backups heißt `…_vor-umzug`, sonst räumt der Start sie neben dem jüngeren Backup vom selben Tag weg (`StoreMoveBackupTests`). Die History wird nicht umgeschrieben.
- Lizenz GPL-3.0-or-later für den Quellcode; das App-Icon ist ausgenommen, alle Rechte vorbehalten. `LICENSE` enthält nur den unveränderten GPL-Text, damit GitHub die Lizenz erkennt; die Wahl „oder später“ steht in der README, der Vorbehalt fürs Icon in `ICON-LICENSE`.

**Konsequenzen:**
- Jede neue Version hat eine neue Ad-hoc-Signatur. Nutzer müssen „Dennoch öffnen“ eventuell erneut bestätigen, und macOS kann fragen, ob Quill auf die Daten im bisherigen Container zugreifen darf.
- Die .dmg ist nicht bitgleich reproduzierbar (Zeitstempel im Image), aber jederzeit aus demselben Commit mit demselben Befehl baubar; die Prüfsumme gilt für die veröffentlichte Datei.
- Developer ID, Notarisierung und Auto-Update stehen unter „Später“.

## ADR-023: Neues App-Icon mit Inhalt und Markenfarbe (2026-10-20)

**Kontext:** Das Icon aus 7.3 (weißes Blatt mit einer Linie auf Grün) war minimalistisch, zeigte aber nicht, was Quill ist. Im dunklen Modus färbte macOS den Hintergrund schwarz und das Blatt grün, obwohl die Datei eine eigene dunkle Füllung enthielt. Drei abstrakte Entwürfe (Eselsohr-Kreis, Ring mit Schreibmarke, Seite mit Giebel) hat der Nutzer verworfen.

**Entscheidung:**
- Motiv aus der App: eine Seite mit Überschrift, Bild-Block und abgehaktem To-do, vier Ebenen mit Liquid Glass auf Seite und Sonne. Markenfarbe Petrol `#0B8F86`, dazu Tinte und Sonnengelb. Eine Fassung in Brombeere `#8C2F63` (weiter weg von Freeform) wurde gebaut und verworfen.
- Dunkle Variante über Farben je Ebene. Eine Füllung für dunkel wirkt nicht: macOS setzt den Hintergrund im dunklen Modus immer selbst (`system-dark` in `Assets.car`).
- Entwürfe und Vorschauen entstehen in `Design/IconDrafts/` (ignoriert), gerendert offline mit `ictool` aus Icon Composer, nie per Bildschirmfoto.

**Konsequenzen:**
- Als reine Silhouette bleibt nur die Seite (ein Rechteck); erkennbar wird das Icon über Farbe und Inhalt. Im einfarbigen Systemstil („klar“) bleiben Bild, Haken und Zeilen sichtbar.
- Das Icon bleibt von der GPL ausgenommen (`ICON-LICENSE`).

**Neues Motiv (2026-10-21, Wahl des Nutzers):** „Slash mit Cursor, Kante“ ersetzt die Seite: weißer Slash (das Zeichen für das Slash-Menü) mit gelber Schreibmarke auf Petrol, darunter eine Kante des Slash in dunklem Petrol ohne Liquid Glass. Die Schreibmarke hat keine Kante, weil sie bei 16 pt sonst doppelt wirkt; schwächer nur in kleinen Größen geht nicht, da `.icon` nicht nach Größe unterscheidet. Farben, Dunkel-Variante je Ebene und Maße in `design.md`. Geprüft mit `ictool` (hell, dunkel, klar, 16 pt @1x und @2x) und im gebauten Bundle (`Assets.car` mit Aqua, DarkAqua und Tintable; Icon über `NSWorkspace` im dunklen Modus, `AppIcon.icns` hell).

## ADR-024: Themes für den Editor (2026-10-20)

**Kontext:** Phase 9.2. Der Editor zeigte nur Systemfarben. Gewünscht waren wenige feste Farbschemata in den Einstellungen, aus den Farben des neuen Icons (ADR-023), mit nachgerechnetem Kontrast und sofortigem Wechsel, gespeichert pro Mac.

**Entscheidung:**
- Sieben Themes in `EditorTheme` (QuillEditor): Standard (Systemfarben, Akzent, Links und Auswahl in Petrol), Quill (Signatur aus Petrol, Tinte und Sonnengelb), Tinte, Kontrast (je hell und dunkel), Sonne (nur hell), Lagune und Abend (nur dunkel). Ein Theme ändert Hintergrund, Text, Überschriften, Links, Zitat und Listenmarker, Zitatbalken, Code, Checkbox, erledigte Aufgaben, Auswahl und Schreibmarke im Editor samt Seitentitel. Sidebar, Symbolleiste und Schriften bleiben im Systemstil. Sonnengelb nur für Flächen (Zitatbalken in dunklen Themes, Auswahl, Checkbox in Abend), nie für Text.
- Feste Themes setzen nur am Editor (`NSScrollView.appearance`) hell oder dunkel; die Sidebar folgt weiter dem System.
- Kontrast: alle Textrollen mindestens 4,5 : 1 zum Hintergrund, zur Codefläche und auf der Auswahl; Häkchen, Checkbox und Zitatbalken 3 : 1. Platzhalter der leeren Seite (4,5 : 1) sowie Ziehgriff, Plus-Knopf und Trennlinie (3 : 1) nehmen abgeleitete Rollen (`placeholder`, `control`) statt Systemfarben, damit sie auch in festen Themes gegen das System reichen; `EditorThemeControlTests` misst sie gezeichnet. Sonnengelb erreicht auf hellen Hintergründen keine 3 : 1; Zitatbalken dort Petrol (Quill) bzw. dunkles Bernstein (Sonne). Mit „Kontrast erhöhen“ leitet `ResolvedPalette` die Textfarben schrittweise Richtung Schwarz bzw. Weiß ab, bis sie 7 : 1 erreichen, und macht die Auswahl durchsichtiger. Kontrastreiche Erscheinungsbilder lassen sich nicht erzeugen (`NSAppearance(named:)` liefert das normale); die Einstellung kommt deshalb aus `NSWorkspace`, nicht aus dem Erscheinungsbild. `EditorThemeContrastTests` prüft alle Themes mit den aufgelösten Farben, eine Gegenprobe mit einem schwachen Theme fällt durch.
- Umsetzung: `EditorColor` liefert je Rolle eine dynamische `NSColor`, die beim Zeichnen das aktuelle Theme liest (`EditorThemeState`, hinter einem `Mutex`, Paletten je Variante zwischengespeichert). Der Textspeicher behält dieselben Farbobjekte; ein Wechsel ändert keinen Text, ist kein Undo-Schritt und löst kein Speichern aus. Jeder Editor beobachtet `EditorThemeSettings.didChange`, verwirft die Layout-Fragmente und zeichnet neu, in allen Fenstern.
- Gespeichert in `UserDefaults` (`QuillEditorTheme`), pro Mac, nicht im Store, in Backups oder im Export (`exportIsTheSameInEveryTheme`). UI-Tests mit Test-Store lesen und schreiben die Wahl nie und starten mit Standard oder `-QuillEditorTheme <id>` (`EditorThemeSetup`).
- Einstellungen (⌘,) › Darstellung: Liste mit kleinen Vorschauen und eine große Vorschau, beide aus den Theme-Farben gezeichnet. Kennungen `settings.theme.<id>`, Vorschau `settings.preview` mit dem Namen des Themes im Label.
- `AccentColor` der App von Tinte auf Petrol: `#08736C` hell, `#0A7A72` dunkel (Weiß darauf 5,7 bzw. 5,2 : 1).

**Konsequenzen:**
- Das Theme gilt prozessweit. Tests, die zeichnen oder das Theme wechseln, laufen mit dem Trait `.renderingLock` (in `QuillTestFixtures`) nacheinander, auch über Suites und Test-Targets hinweg.
- Feste Themes zeigen Rollbalken im Editor mit „Kontrast erhöhen“ ohne deren Systemvariante; alle Theme-Farben samt Platzhalter und Bedienelementen sind abgeleitet.
- Snapshots zeigen die Auswahl grau, weil das Testfenster nicht aktiv ist; im aktiven Fenster gilt die Theme-Farbe.
- Eigene Themes, Import und Export von Themes und eine Schriftgröße stehen unter „Später“.

## ADR-025: Fenster der .dmg mit Hintergrund und Volume-Icon (2026-10-20)

**Kontext:** Die .dmg öffnete ein schlichtes Finder-Fenster mit grauem Laufwerk. Gewünscht war ein gestaltetes Fenster wie bei professionellen Mac-Apps, reproduzierbar per Skript, ohne die Prüfungen von ADR-022 zu ändern.

**Entscheidung:**
- Hintergrund „Tinte und Papier“ (`Scripts/dmg/background.swift`, eigene Gestaltung): Schiefer aus Tinte, angedeutetes Blatt, gepunkteter Pfeil von Quill zu „Programme“, unten ein Band in Petrol mit dem Satz zur Installation, Sonnengelb nur als Akzent. Eine TIFF-Datei mit 1× und 2× (`tiffutil -cathidpicheck`), committet als `Scripts/dmg/background.tiff`.
- Der Hintergrund passt sich nicht an hell und dunkel an; der Finder schreibt die Namen im hellen Modus schwarz, im dunklen weiß. Die Fläche hinter den Namen hat deshalb mittlere Helligkeit (beide Farben mindestens 4,5 : 1); das Zeichenskript bricht sonst ab.
- Layout mit `dmgbuild` (`Scripts/dmg/settings.py`): Fenster 640 × 400 ohne Leisten, Icons 128 pt, Quill links, „Programme“ rechts auf Höhe des Pfeils, Volume-Icon aus `AppIcon.icns`. `dmgbuild` schreibt die `.DS_Store` direkt, ohne Finder und AppleScript, also ohne Freigabe zur Finder-Steuerung und ohne sichtbares Fenster beim Bauen. Version und Prüfsummen fest (`Scripts/dmg/requirements.txt`, `pip --require-hashes`), installiert in `.build/dmgbuild-venv`.
- Kein `hide_extensions`: Es setzt Finder-Informationen am Bundle, und `codesign --strict` lehnt die App dann ab.
- `make-release.sh` prüft zusätzlich Hintergrund und Volume-Icon (byte-gleich), das Attribut für das eigene Volume-Icon und die `.DS_Store`; die bisherigen Prüfungen bleiben.

**Konsequenzen:**
- Release braucht beim ersten Lauf Netz für `pip` (danach aus `.build/`).
- Hintergrund ändern: `swift Scripts/dmg/background.swift Scripts/dmg/background.tiff`, Positionen in `settings.py` mitziehen.

## ADR-026: Sync über einen gewählten Ordner mit Automerge (2026-10-20)

**Status:** entschieden (2026-10-20). Automerge nach dem Spike in Phase 10.1 (`Spikes/AutomergeSpike`); das Kriterium zum Laden wurde nach der Messung neu gefasst, siehe „Spike und Messwerte“.

**Kontext:** Quill soll zwischen Macs und später dem iPhone synchronisieren, ohne CloudKit und ohne eigenen Server, über einen Ordner, den der Nutzer wählt (iCloud Drive, Dropbox, Nextcloud, Syncthing usw.). Bis Phase 13 gibt es kein Developer Program. „Letzte Speicherung pro Block gewinnt“ (ADR-012) reicht für verzögerte Änderungen von mehreren Geräten nicht. Daten dürfen nie still verloren gehen.

**Entscheidung:**
- **Schichten:** Der lokale SwiftData-Store bleibt Quelle der App. Die Sync-Schicht hängt an `PageStore` (einziger Schreiber): Jede lokale Änderung wird zusätzlich als Änderung am CRDT-Dokument der Seite festgehalten; eingehende Änderungen werden zusammengeführt und als Diff über `PageStore.applyEdits` in den Store geschrieben. Ohne eingeschalteten Sync bleibt alles wie bisher.
- **CRDT:** Automerge (`automerge-swift`, MIT, GPL-verträglich), ein Dokument je Seite und eines für den Seitenbaum (Titel, Eltern, `sortKey`, Favorit, Papierkorb). Blöcke als Liste von Maps mit UUID, Art (`kindRaw`), `BlockProperties` und Text mit Marks. Gleichzeitiges Tippen im selben Block wird zusammengeführt.
- **Kriterien** (Apple Silicon, Release-Build), gültig nach dem Spike:
  - Öffnen einer Seite bleibt so schnell wie ohne Sync: Der Editor lädt aus dem SwiftData-Store, nicht aus dem Automerge-Dokument.
  - Abgleich einer Seite im Hintergrund (Datei lesen, Dokument laden, Änderungen anwenden, Blöcke erzeugen, speichern) unter 250 ms, auch im Schwerfall.
  - Der erste Abgleich aller Seiten blockiert die App nicht und zeigt Fortschritt.
  - 1.000 Seiten mit Geschichte zusammen unter 50 MB zusätzlich zum Store.
  - Die App wird höchstens 5 MiB größer (2^20 Bytes je MiB).
- **Abhängigkeit:** `automerge-swift` 0.7.2 exakt (Revision `aa45d17ac92cef2b8ded63b47e65a28dc85e3418`). Der Rust-Kern kommt als vorgebautes `automergeFFI.xcframework`; SwiftPM prüft es gegen die Prüfsumme `10245378e74229b026f689b039d7df3cf17aeed353706d5f420dfd164f283a86` aus dem Paket von automerge-swift. Statisch gelinkt (`staticlib`), kein eingebettetes Framework. Neue Versionen nur bewusst, mit erneuter Messung und Lizenzprüfung.
- **Lizenzen:** `automerge-swift` MIT; Rust-Kern `automerge` 0.7.2 MIT. Die `Cargo.lock` des Kerns nennt 109 Crates, alle unter freien Lizenzen: überwiegend MIT oder Apache-2.0 (wahlweise), dazu BSD-2-Clause, Zlib, 0BSD, Unlicense, BSL-1.0, Unicode-DFS-2016 jeweils als Option oder Zusatz; die 9 uniffi-Crates unter MPL-2.0 (mit GPL-3.0 verträglich, MPL-2.0 Abschnitt 3.3). Keine Crate nur unter einer Copyleft-Lizenz, die mit GPL-3.0-or-later kollidiert. Geprüft über die öffentliche API von crates.io; die Lizenztexte kommen mit dem ersten Release, das Automerge enthält, in die App (Phase 11).
- **Ausstieg, falls Automerge nicht mehr gepflegt wird:**
  - Automerge steht nur in der Sync-Schicht (ein Modul); andere Module sehen keine Automerge-Typen. Ein Wechsel bleibt damit auf dieses Modul beschränkt.
  - Der lokale SwiftData-Store bleibt Quelle der App. Sync ausschalten lässt jeden Store vollständig; Markdown-Export und Backups hängen nicht an Automerge.
  - Das Binärformat von Automerge ist offen beschrieben und hat freie Implementierungen (Rust, JavaScript). Mit der festen Version und dem Quellcode des Kerns bleibt der Ordner lesbar; zur Not bauen wir den Kern selbst (unter „Später“).
  - Wechsel auf ein anderes Format: Alle Seiten mit der letzten funktionierenden Version lesen und neu schreiben. Geht dabei die Geschichte (Zeitreise) verloren, nur nach Rückfrage, und der alte Ordner bleibt unverändert liegen.
  - Anlass zur Prüfung: kein Release seit 12 Monaten, eine offene Sicherheitslücke ohne Fix oder ein Bruch mit der aktuellen Swift- oder Xcode-Version. Dann Alternativen bewerten (eigenes CRDT nur für Blöcke, Yrs/Yjs, Konflikte pro Block ohne Textzusammenführung).
- **Format im Ordner:** Jedes Gerät schreibt nur eigene Dateien, Änderungen nur anhängend; damit sieht kein Sync-Dienst zwei Geräte an derselben Datei, und es entstehen keine Konfliktkopien.

  ```
  Quill/
    quill.json                                   Formatversion, Ordner-ID, verschlüsselt ja/nein
    devices/<Geräte-ID>.json                     Name, zuletzt gesehen
    tree/<Geräte-ID>/<Nr>.changes                Seitenbaum
    tree/<Geräte-ID>/<Nr>.snapshot               Seitenbaum verdichtet
    pages/<Seiten-ID>/<Geräte-ID>/<Nr>.changes   Änderungen je Seite
    pages/<Seiten-ID>/<Geräte-ID>/<Nr>.snapshot  verdichtet, ersetzt alle eigenen Dateien bis zu ihrer Nummer
    assets/<SHA-256>.<Endung>                    Bilder, unveränderlich, nach Inhalt benannt
  ```

  Dateinamen enthalten nur UUIDs, Nummern und Prüfsummen, keine Titel. Eine verdichtete Datei ist der ganze Stand des Dokuments samt Geschichte; sie bekommt die nächste Nummer der Reihe, wird neu angelegt und nie überschrieben (geändert am 2026-10-21 von `snapshot` auf `<Nr>.snapshot`, Entscheidung Nutzer, Umsetzung ADR-029). Erst danach löscht das Gerät seine eigenen Dateien mit kleinerer Nummer; Dateien anderer Geräte löscht es nie.
- **Nie still verwerfen:** Löschen gegen Bearbeiten → der Block bleibt und ist als wiederhergestellt markiert. Zwei Werte für dasselbe Feld (Automerge meldet den Konflikt) → die Seite zeigt beide Fassungen, der Nutzer wählt; bis dahin bleiben beide gespeichert. Unlesbare Dateien (kaputt, neueres Format, falscher Schlüssel) → Quarantäne mit Hinweis, nichts wird gelöscht oder überschrieben. Ein Ordner mit fremden Quill-Daten wird nur nach Rückfrage zusammengeführt.
- **Zugriff:** Mac per Ordnerauswahl und Lesezeichen mit Sandbox-Zugriff (`com.apple.security.files.bookmarks.app-scope`), iPhone über die Dateien-App mit Security-Scoped Bookmark. Lesen und Schreiben über `NSFileCoordinator`, nicht geladene Dateien (iCloud Drive, Datei-Anbieter) werden vorher angefordert. Kein iCloud-Entitlement, deshalb ohne Developer Program möglich.
- **Migration:** neue Schemaversion für Sync-Daten (Geräte-ID, Stand je Seite) mit Test „V1 → V2“ (ADR-011); vorher ein Backup; der Ordner wird erst beschrieben, wenn der Nutzer den Sync einschaltet. Rückweg getestet: Sync ausschalten lässt den lokalen Store unverändert, das Backup aus V1 lässt sich wieder einspielen.
- **Verschlüsselung (Phase 14, optional):** jede Datei mit CryptoKit (ChaCha20-Poly1305), auch Seitenbaum und Bilder. Schlüssel aus einer Passphrase (Schlüsselableitung mit Salz aus `quill.json`), danach nur im Schlüsselbund des Geräts. Der iCloud-Schlüsselbund scheidet aus, weil Mac (ad hoc) und iPhone ohne gemeinsames Team keine Einträge teilen. Beim Einrichten erzeugt Quill einen Wiederherstellungsschlüssel zum Aufschreiben und erklärt klar: Ohne Passphrase und ohne Wiederherstellungsschlüssel ist der Ordner unlesbar; die lokalen Stores der Geräte bleiben erhalten. Größe und Zeitpunkt der Dateien sieht der Anbieter weiterhin.
- **Zeitreise (Phase 12):** aus der Geschichte der Automerge-Dokumente, also mitsynchronisiert. Bilder werden nicht versioniert; ein Bild, auf das nur noch alte Fassungen verweisen, darf nach einer einstellbaren Frist gelöscht werden, die Zeitreise zeigt dann einen Platzhalter.

**Spike und Messwerte (Phase 10.1, 2026-10-20):** Apple M4, 16 GB, macOS 27.0.1, Swift 6.4, Release-Build; Ablauf in `Spikes/AutomergeSpike/README.md`. Seiten erfunden und Zeichen für Zeichen getippt, etwa 8,5 % der Eingaben wieder gelöscht, dazu Formatierung, Einschübe, abgehakte To-dos und geänderte Blockarten. Der Editor speichert 300 ms nach der letzten Eingabe, beim normalen Tippen also etwa einmal pro Wort; „pro Tastendruck“ ist der ungünstigste Fall.

- **Ursprüngliches Kriterium „Laden einer Seite mit Geschichte unter 50 ms“** (Datei lesen, Dokument laden, `[EditorBlock]` erzeugen; Median aus 50 Läufen, kalt = frischer Prozess):

  | Fall | Änderungen | Datei | Median | kalt | nur Automerge |
  |---|---|---|---|---|---|
  | 5.000 Wörter, Commit pro Wort | 5.072 | 51 KB | 28 ms | 33 ms | 16 ms |
  | 5.000 Wörter, Commit pro Tastendruck | 50.920 | 48 KB | 61 ms | 68 ms | 49 ms |
  | 15.000 Wörter, Commit pro Wort | 15.150 | 146 KB | 85 ms | 93 ms | 50 ms |
  | 15.000 Wörter, Commit pro Tastendruck | 153.026 | 135 KB | 194 ms | 213 ms | 159 ms |

  Nur der übliche Fall hielt 50 ms ein. Die Zeit wächst mit der Zahl der Änderungen, kaum mit der Dateigröße.
- **Neufassung:** Das Kriterium hatte angenommen, dass eine Seite zum Öffnen aus Automerge geladen wird. Nach dieser Entscheidung bleibt aber der SwiftData-Store die Quelle der App; Automerge wird nur zum Abgleichen gebraucht, und das läuft im Hintergrund. Für den Nutzer zählt deshalb, dass das Öffnen unverändert schnell bleibt und der Abgleich die App nicht blockiert. Ein eigenes CRDT oder Yrs hätte eigene Spikes gebraucht, ohne absehbaren Vorteil beim Öffnen. Neu gefasst am 2026-10-20 durch den Nutzer (siehe Kriterien oben).
- **Abgleich einer Seite im Hintergrund** (ein anderes Gerät hat 50 Wörter getippt und einen Block angefügt, 51 Änderungen, 7,3 KB; Datei lesen, laden, anwenden, Blöcke erzeugen, speichern; Median aus 20 Läufen): 33 ms, 68 ms, 103 ms, 214 ms (p95 217 ms) für die vier Fälle oben. Hält 250 ms auch im Schwerfall, mit etwa 15 % Reserve. Alle Werte stammen von einem M4 (Mac). In Phase 13 wird der Abgleich auf einem echten iPhone nachgemessen; reißt er dort 250 ms, kommen zuerst seltenere Commits (z. B. höchstens alle 2 s) und eine schnellere eigene Zuordnung zu `[EditorBlock]` zum Einsatz (die Zuordnung braucht heute 12–35 ms der Ladezeit), erst danach andere Wege.
- **1.000 Seiten mit Geschichte** (700 × 500, 250 × 2.000, 50 × 5.000 Wörter): 11,9 MB mit Commit pro Wort, 11,3 MB mit Commit pro Tastendruck; derselbe Inhalt als JSON ohne Geschichte 14,1 MB; größte Seite 53 KB. Eine einzelne Änderung (ein Wort) als Datei etwa 125 Bytes.
- **App-Größe** (zwei Release-Builds wie `make-release.sh`, ohne und mit Automerge und einem Aufruf der APIs der Sync-Schicht beim Start; `measure-app-size.sh`): `.app` 3,77 → 8,63 MiB, also **4,86 MiB mehr** (5,09 MB dezimal); `.dmg` (UDZO) 2,86 → 4,88 MiB, also 2,02 MiB mehr. Zwei Builds byte-gleich. Die Grenze gilt in MiB (Entscheidung des Nutzers); in MB wäre sie um 0,09 MB gerissen.
- **Verhalten** (Tests im Spike): Gleichzeitiges Tippen im selben Block wird zusammengeführt. Zwei Werte für dasselbe Feld meldet Automerge (`getAll`), die Sync-Schicht kann beide zeigen. Löschen gegen Bearbeiten: Automerge entfernt den Block, die Bearbeitung bleibt in der Geschichte lesbar (`textAt`); wiederherstellen muss die Sync-Schicht selbst. Automerge zählt Textpositionen in Unicode-Skalaren, auch nach dem Laden; der Editor zählt in UTF-16, die Sync-Schicht rechnet um. Automerge baut für iOS ohne Warnungen.

**Konsequenzen:**
- Das iPhone gleicht nur im Vordergrund und gelegentlich per Hintergrundaufgabe ab, nicht live. Syncthing auf dem iPhone geht nur über Drittanbieter-Apps und wird nicht versprochen.
- Das Datenmodell bleibt nach den Regeln aus ADR-002 aufgebaut; CloudKit ist nicht mehr geplant. ADR-012 (letzte Speicherung pro Block) gilt weiter für zwei Fenster auf einem Mac.
- Ein Sync-Ordner ist kein Backup: Löschen wird synchronisiert. Die lokalen Backups bleiben.
- Direkter Sync im WLAN steht unter „Später“.
- Der Spike bleibt unter `Spikes/AutomergeSpike`, damit sich die Messwerte nachprüfen lassen; App und QuillKit binden ihn nie ein (`SpikeIsolationTests`). Phase 11 erlaubt dort Automerge selbst, nicht den Spike.
- Die Sync-Schicht muss den Abgleich in den Hintergrund legen und den ersten Abgleich aller Seiten mit Fortschritt zeigen; seltener zu committen (z. B. höchstens alle 2 s) hält die Geschichte kürzer, falls der Schwerfall knapp wird.

## ADR-027: Fokus-Modus mit Schreibmaschinen-Scrollen und abgedunkelter Umgebung (2026-10-20)

**Kontext:** Phase 18.1 der Roadmap, vorgezogen für v0.3.0. Gewünscht: Fokus-Modus mit Schreibmaschinen-Scrollen und abgedunkelter Umgebung, passend zu den Themes (ADR-024).

**Entscheidung:**
- Ein Schalter für beides, im Menü Darstellung (⇧⌘F; ⌘F, ⌥⌘F und ⌃⌘F sind belegt) und unter Einstellungen › Darstellung. Pro Mac in `UserDefaults` (`QuillFocusMode`), nicht im Store, in Backups oder im Export; wirkt sofort in allen Fenstern, ändert keinen Text, kein Undo-Schritt, kein Speichern. UI-Tests mit Test-Store lesen und schreiben die Wahl nie (`-QuillTestFocusMode YES`; anders benannt als der Schlüssel, sonst wirkte das Argument über die Argument-Domain von `UserDefaults` auch ohne Test-Store).
- Abdunkeln: Alle Blöcke außer denen mit Cursor oder Auswahl und der Seitenkopf werden mit geringerer Deckkraft über den Theme-Hintergrund gezeichnet, also in Richtung der Theme-Farbe statt grau. Die Deckkraft berechnet `ResolvedPalette` je Theme und Variante so niedrig wie möglich, solange der Fließtext mindestens 3 : 1 behält (mit „Kontrast erhöhen“ 4,5 : 1). Jede Textrolle bekommt eine eigene abgedunkelte Farbe: Überschrift, Link, Zitat und Listenmarker sowie erledigte To-dos werden so weit wie der Fließtext abgedunkelt, aber nie unter dieselbe Grenze; schwächere Rollen werden dafür weniger abgedunkelt. Flächen und Linien (Code, Zitatbalken, Checkbox samt Rahmen, Trennlinie) und Bilder nehmen die Deckkraft des Fließtexts, ebenso der Kopf; zeigt der Kopf nur den Platzhalter „Ohne Titel“ (Systemfarbe), bleibt er hell. Abgedunkelt wird nur, solange der Text den Fokus hat. Die abgedunkelten Farben gelten nur auf dem Thread, der gerade zeichnet (`EditorThemeState.drawingDimmed`, Zähler im Thread-Wörterbuch).
- Schreibmaschinen-Scrollen: Die Zeile mit dem Cursor bleibt in der Mitte des sichtbaren Bereichs. Unter dem Text kommt eine halbe Fensterhöhe Platz dazu, damit auch die letzte Zeile in die Mitte kann; oben bleibt die Seite am Anfang (Kopf sichtbar), statt Leerraum davor zu setzen. Nicht bei einer Auswahl, nicht bei markiertem Text (IME), nicht während des Ziehens mit der Maus; nach einem Klick sanft (0,25 s), bei „Bewegung reduzieren“ ohne Animation. Nach einer Änderung der Fenstergröße wird neu zentriert.
- Sidebar und Symbolleiste bleiben; kein automatisches Vollbild.

**Konsequenzen:**
- `EditorFocusModeTests` prüft alle Textrollen für alle Themes und Varianten und zeichnet in jedem Theme bei hellem und dunklem System, ohne und mit „Kontrast erhöhen“ (über `EditorThemeSettings.setIncreaseContrast`), Fließtext, Überschrift, Link, Zitat, Listenmarker und erledigte To-dos; dazu Abdunkeln, Flächen, Kopf (Darstellungswechsel, Platzhalter), Thread, Scrollen samt Fenstergröße und Einstellung. Gegenproben fallen durch: schwächerer Mindestkontrast (auch mit „Kontrast erhöhen“), alle Rollen mit der Deckkraft des Fließtexts, eine Deckkraft für den ganzen Block, kein Abdunkeln beim Zeichnen, Trennlinie oder Checkbox-Rahmen nicht als Fläche, Kopf ohne Darstellungswechsel oder mit Platzhalter abgedunkelt, Flag für alle Threads oder nicht verschachtelbar, kein Nachmessen, kein Platz unter dem Text, kein Neuzentrieren nach Größenänderung, Abdunkeln ohne Fokus, Startargument gleich dem Schlüssel.
- Abgeleitete Farben aus Systemfarben müssen dynamisch bleiben: `withAlphaComponent` auf `labelColor` löst sie einmal in der gerade aktuellen Darstellung auf (`ResolvedPalette.faded`).
- Der Kontrast-Audit der UI-Tests läuft ohne Fokus-Modus; abgedunkelter Text liegt bewusst unter 4,5 : 1.

## ADR-028: QuillKit für Mac und iPhone (2026-10-20)

**Kontext:** Phase 10 der Roadmap. Das iPhone (Phase 13) soll dieselbe Logik nutzen wie der Mac, das App-Target bleibt dünn. Bis vor Phase 13 gibt es keinen iOS-Simulator; das Developer Program kommt erst vor Phase 13.

**Entscheidung (10.2, iOS-Build):**
- QuillKit baut für iOS 26, geprüft mit `Scripts/check-ios-build.sh` (generisches iOS-Gerät, eigener temporärer Build-Ordner). Fehler und Compiler-Warnungen zählen wie auf dem Mac; das Skript gehört zu jedem vollen Lauf.
- Nur-Mac-Teile bleiben hinter `#if canImport(AppKit)`, wie bisher im Code: Menübefehle, Fenster (`WindowRouter`, `WindowFocus`, `TestWindowSize`), `QuitGuard`, Einstellungsfenster, Backup wiederherstellen, Export-Dialog, „Schnell öffnen“, Seitenbaum der Sidebar (`NSOutlineView`), Editor-Sitzung. Auf iOS bleibt vorerst das Gerüst aus `NavigationSplitView`, Papierkorb und Leerzustand; Editor und Seitenbaum fürs iPhone kommen in Phase 13.
- Was beide Plattformen brauchen, steht außerhalb dieser Blöcke: `PageFocusTarget` liegt jetzt neben `PageOutlineActions`. Der Seitentitel nimmt auf iOS die Systemfarbe, bis die Themes in 10.3 ohne AppKit auskommen.
- iPad nicht verbauen: `RootView` bleibt ein `NavigationSplitView` für beide Plattformen. Mac-Eigenheiten (Fenster, Menüs, Tastaturfokus über `NSWindow`) stehen nur in Nur-Mac-Blöcken, nie als Annahme im gemeinsamen Code.
- Tests laufen bis vor Phase 13 nur auf dem Mac; auf iOS wird nur gebaut. Der Simulator wird vor Phase 13 installiert.
- Der Automerge-Spike baut auch für iOS (Bibliothek; das Messprogramm nutzt `Process` und läuft nur auf dem Mac).

**Konsequenzen:**
- Neuer Code in QuillKit muss auf beiden Plattformen bauen; ein Nur-Mac-Typ im gemeinsamen Code fällt beim nächsten vollen Lauf auf.
- Gegenproben: Ein Nur-Mac-Typ im gemeinsamen Code (`LaunchNotice` in `RootView`) und eine Compiler-Warnung lassen `check-ios-build.sh` scheitern.

**Entscheidung (10.3, Editor-Kern):**
- Neues Target `QuillEditorCore` nur mit Foundation, Observation, Synchronization und QuillModel: `EditorDocument`, `EditorBlock`, Inline-Text und `RichText`, Markdown (Serialisierung, Kürzel), Format der Zwischenablage, Block-Attribute im Textspeicher, `EditorPersistenceBridge`, `NotificationObservation`, der Theme-Katalog mit Paletten und Varianten, die Kontrastrechnung (`SRGB`) und `PaletteSpec` (Farben je Rolle, Verstärkung bei „Kontrast erhöhen“, Deckkraft im Fokus-Modus) sowie `EditorFocusSettings`. `EditorCoreImportTests` lässt nur diese Importe und nur die Abhängigkeit auf QuillModel zu.
- QuillEditor behält, was Oberfläche oder Plattform braucht: die Weichen zwischen AppKit und UIKit für Farben und Bedienungshilfen gebündelt in `PlatformTypes.swift` (`Platform`, `PlatformColor.dynamic`, `resolved(in:)`); die TextKit-Schicht (`BlockStyle`, `BlockLayoutFragment`, `BlockRenderer`, Anhänge), die schon für AppKit und UIKit baut; `ResolvedPalette`, die aus `PaletteSpec` `NSColor` bzw. `UIColor` anlegt; `EditorThemeState` (Cache, abgedunkeltes Zeichnen je Thread), `EditorThemeSettings` und `EditorColor` für beide Plattformen; Name und erzwungene Darstellung der Themes; `SlashCommand` und `BlockConversion` (lokalisierte Menütitel); den Controller mit `NSTextView` hinter `#if canImport(AppKit)`.
- Zugriff über die Modulgrenze mit `package` statt `public`. Die öffentlichen Typen sind unverändert, liegen aber zum Teil in einem anderen Modul: `EditorDocument`, `EditorTheme`, `EditorFocusSettings` und `EditorPersistenceBridge` kommen aus `QuillEditorCore`, das das Produkt QuillKit mitliefert; wer sie nutzt, importiert den Kern (die App in `QuillApp.swift`). Kein Re-Export, damit sichtbar bleibt, was Plattform braucht und was nicht. Neu öffentlich ist nur `PlatformColor` (`NSColor` bzw. `UIColor`) für `EditorColor` und `EditorThemeColors`. QuillExport hängt nur noch am Kern.
- Der Seitentitel nimmt jetzt auch auf iOS die Theme-Farbe (Übergang aus 10.2 entfernt). Systemfarben des Themes „Standard“ werden für die Kontrastrechnung mit ihren macOS-Werten genähert; auf iOS weichen `systemBackground` und `label` davon ab. Das wird in Phase 13 auf dem Gerät geprüft. Dynamische Farben lösen auf iOS das Ergebnis ihres Providers in den Traits auf (`resolvedColor(with:)`), weil nicht zugesichert ist, dass UIKit verschachtelte dynamische Farben wie `label` nachauflöst; geprüft wird das in Phase 13 im Simulator.

**Konsequenzen (10.3):**
- Darstellung unverändert: Alle 128 PNGs der Snapshot- und Pixeltests sind vor und nach dem Umbau byte-gleich (zwei Ausgangsläufe untereinander ebenfalls). Gegenprobe: ein um 0,5 schwächerer Platzhalter-Kontrast im Kern ändert die Bilder.
- Gegenproben `EditorCoreImportTests`: `import SwiftUI`, mit Tab eingerücktes `import SwiftUI`, `import struct CoreGraphics.CGFloat`, `@preconcurrency import AppKit` und eine Abhängigkeit auf QuillDesign (auch über mehrere Zeilen) fallen auf; ein über mehrere Zeilen umbrochenes Target mit nur QuillModel bleibt grün.

## ADR-029: Sync-Schicht für den Ordner-Sync (2026-10-20)

**Status:** entschieden (Plan von Phase 11, mit dem Nutzer abgestimmt am 2026-10-20); umgesetzt schrittweise in 11.1–11.5.

**Kontext:** ADR-026 legt Automerge und das Ordnerformat fest. Offen waren, wo der Automerge-Stand liegt, wie Backups und Sync zusammenspielen, wie zwei Macs ohne echten Store getestet werden und wie Löschen über Geräte wirkt.

**Entscheidung:**
- **Aus, bis der Nutzer einschaltet.** Ohne Schalter in Einstellungen › Sync fasst die App keinen Ordner an. Kein Startargument schaltet den Sync im Release-Build ein. „Sync pausieren“ stoppt sofort jedes Schreiben in den Ordner (mit Test).
- **Modul:** `QuillSync` ist das einzige Modul mit Automerge und hängt nur an QuillModel. Seine öffentliche Schnittstelle zeigt keine Automerge-Typen (`DocumentVersion` statt Heads, `FieldConflict` statt Werten). `AutomergeIsolationTests` und `SpikeIsolationTests` halten das ein.
- **Automerge-Stand im Store** (neue Schemaversion in 11.2): Backups enthalten damit immer einen zum Inhalt passenden Sync-Stand.
- **Backup einspielen bei eingeschaltetem Sync:** Quill schaltet den Sync vorher aus und fragt, wie es weitergeht (als neues Gerät wieder verbinden oder aus lassen). Sonst würde der Abgleich den alten Stand sofort wieder mit dem neueren aus dem Ordner zusammenführen.
- **Vor dem ersten Einschalten** legt Quill ein Backup an; der Rückweg (Sync aus, Backup einspielen) ist getestet.
- **Löschen über Geräte:** Eine auf einem Gerät gelöschte Seite landet auf den anderen zuerst im Papierkorb, nie direkt endgültig gelöscht. Endgültiges Löschen setzt im Seitenbaum nur einen Grabstein (`deleted`); Seiten werden nie aus dem Baum-Dokument entfernt. Endgültig weg ist eine Seite auf einem Gerät erst nach „Papierkorb leeren“ dort (mit Test in 11.3).
- **Dokumente:**
  - Seite: Map `blocks` von Block-ID auf eine Map mit `kind`, `order` (Schlüssel aus `FractionalIndex`), `text` (Text mit Marks aus `RichText`), `indent`, `checked`, `lang`, `asset`. Eine Map statt einer Liste, damit Verschieben nur `order` ändert und gleichzeitiges Tippen im verschobenen Block erhalten bleibt; verschoben bekommt nur der bewegte Block einen neuen Schlüssel.
  - Seitenbaum: Map `pages` mit Titel, Icon, Eltern, `sortKey`, Favorit, Papierkorb, Grabstein, Art, Anlagedatum.
  - Text wird als Diff geschrieben (`updateText`), Marks nur dort, wo sie abweichen. Unbekannte Blockarten und Marks späterer Versionen bleiben erhalten.
- **Gleiche erste Änderung:** Jedes Dokument beginnt mit derselben Änderung (feste Akteurs-ID, Zeit 0). Legen zwei Geräte dasselbe Dokument unabhängig an, führt Automerge diese Änderung als eine zusammen; sonst gäbe es die Wurzel-Map zweimal und die Inhalte eines Geräts wären unsichtbar.
- **Neue Akteurs-ID je Sitzung:** Jedes geladene Dokument schreibt mit einer neuen Akteurs-ID. Damit erzeugt keine Akteurs-ID zwei verschiedene Änderungen mit derselben Nummer, auch nicht nach einem eingespielten Backup oder einem Absturz zwischen Ordner und Store; Automerge lehnt das sonst ab („duplicate seq“). Kosten: 16 Bytes je Sitzung und Dokument. Die Geräte-ID für die Ordner ist davon getrennt.
- **Konflikte:** Zwei Werte für dasselbe Feld meldet `conflicts()` (Seite: `kind`, `indent`, `checked`, `lang`, `asset`; Baum: `title`, `icon`, `parent`) und doppelte Objekte. Reihenfolge, Favorit und Papierkorb sind keine Konflikte für den Nutzer, weil dort kein Inhalt verloren geht. Der Abgleich schreibt den vorne gezeigten Wert nie zurück; beide Werte bleiben, bis der Nutzer wählt (seit dem Review von Phase 11; die Wahl auf der Seite kommt in 11.6). Die Wahl des Nutzers schreibt den Wert neu und löst den Konflikt auch dann, wenn der gewählte Wert der ist, den Automerge gerade vorne zeigt.
- **Löschen gegen Bearbeiten:** Automerge entfernt einen gelöschten Block trotz gleichzeitiger Bearbeitung. Die Sync-Schicht stellt ihn in 11.3 wieder her und markiert ihn.
- **Test zwischen zwei Macs:** ein Mac mit zwei Benutzerkonten und gemeinsamem Ordner, mit eigener Testvariante (Bundle-ID `io.github.vogelwild07.quill.synctest`, eigener Container in beiden Konten). Seit Fall 14 (nach dem Review): zwei Testvarianten in einem Konto statt zwei Konten, siehe „Testvariante“. Der echte Store wird nie berührt. Automatische Tests nutzen nur Wegwerf-Stores und Wegwerf-Ordner.
- **Lizenztexte** von automerge-swift, dem Rust-Kern und den Crates kommen mit der Oberfläche in 11.4 in die App, vor dem ersten Release mit Automerge.

**Konsequenzen:**
- Gegenproben 11.1 (alle rot):
  - zufällige statt fester erster Akteurs-ID (unabhängig angelegte Dokumente verlieren Inhalte);
  - feste Akteurs-ID beim Laden („duplicate seq“);
  - Konflikt beim gleichen Wert nicht neu geschrieben (der Test löste mit beiden Werten auf, weil der vorne gezeigte Wert von den zufälligen Akteurs-IDs abhängt; seit dem Review von Phase 11 ist genau das gewollt, die Gegenprobe ist umgekehrt);
  - alle Reihenfolge-Schlüssel neu statt nur der verschobene;
  - Marks mit `false` statt entfernt;
  - Grabstein überschreibbar;
  - neueres `quill.json` angenommen;
  - `import Automerge` in der App, Automerge-Typ in der Schnittstelle, Automerge als Abhängigkeit von QuillModel, das Wort Automerge in einem Kommentar in QuillModel.
- Toter Code, den eine Gegenprobe aufgedeckt hat (Behandlung entfernter Marks), ist entfernt; das Verhalten von Automerge dazu hält `removedMarksAreNotReported` fest.

**Umsetzung 11.2 (Schema V2):**
- `SchemaV2` = `SchemaV1` plus `Workspace.syncTree`, `syncDeviceID`, `syncCursors`, `Page.syncDocument`, `Page.isRestored`, `Block.isRestored` (als `BlockProperties.isRestored`, ADR-014). Leichtgewichtige Stufe; Fingerabdruck für V2. Der Probelauf mit eigener Stufe läuft jetzt als `RehearsalSchemaV3`.
- Sync-Einstellungen (Ordner-Lesezeichen, an, pausiert) liegen in den Einstellungen des Macs, nicht im Store; ein eingespieltes Backup schaltet den Sync nie ein.
- **Rückfrage vor jeder Migration** auf ein neues Schema, beim echten Store immer: „Beenden“ ist der Standardknopf (Return), Escape wählt es ebenfalls (lokaler Event-Monitor während der Rückfrage, weil ein Knopf nur ein Tastenkürzel hat); „Umstellen“ hat kein Tastenkürzel und muss angeklickt werden. Gefragt wird nach dem Einspielen eines vorgemerkten Backups, damit „Beenden“ ein eingespieltes V1-Backup für eine ältere Version lässt. Die Frage kommt erst nach dem Start der App (`applicationDidFinishLaunching`): Ein Dialog vorher war in einem ersten Versuch für Bedienungshilfen nicht erreichbar (UI-Test: „has not loaded accessibility“), also auch nicht für VoiceOver. Ohne anstehende Migration öffnet der Store wie bisher vor dem ersten Fenster.
- `BlockProperties` liest fehlende Felder mit Standard, damit ältere Daten (Zwischenablage) lesbar bleiben.
- Gegenproben 11.2 (alle rot): Return auf „Umstellen“ (Unit- und UI-Test), Escape nicht verbraucht (Unit-Test), Escape-Monitor nicht installiert (UI-Test), keine Rückfrage beim echten Store, Rückfrage vor dem Einspielen des Backups (Rückweg), `isRestored` als Pflichtfeld beim Lesen, `isRestored` nicht aus dem Store gelesen. Eine Gegenprobe deckte nebenbei auf, dass der V1-Testbestand mit offener WAL angelegt wurde und „unverändert“ deshalb nicht byte-genau messbar war; er entsteht jetzt per `VACUUM INTO` als eine Datei (15 von 15 Läufen grün).

**Umsetzung 11.3 (Ordnerzugriff und Abgleich):**
- **Abgleich** (`SyncEngine`, Actor in QuillSync) je Dokument: aus dem Store laden; eigene Dateien nachlesen, die der Store noch nicht kennt (Abbruch zwischen Ordner und Store); den Stand des Stores übernehmen und die neuen Änderungen als nächste eigene Datei anhängen; dann neue Dateien der anderen Geräte übernehmen, der Reihe nach bis zur ersten Lücke; das Ergebnis mit Dokument und gelesenen Dateien in einem Schritt in den Store schreiben. Seiten vor dem Seitenbaum, neue Seiten anderer Geräte bekommen ihren Inhalt im selben Abgleich. Fällig sind Seiten mit neuerem `updatedAt` als beim letzten Abgleich oder mit neuen Dateien anderer Geräte.
- **Eingaben während des Abgleichs:** `PageStore.applySyncTree` und `applySyncPage` schreiben nur, wenn der Store noch dem Stand entspricht, von dem der Abgleich ausging; sonst nichts, und der nächste Abgleich nimmt die Eingabe mit. Der Abgleich überschreibt so nie eine Eingabe des Nutzers.
- **Dateien:** Eigene Dateien werden vollständig daneben geschrieben und dann umbenannt; existiert der Name schon, scheitert es, statt zu überschreiben. Die nächste Nummer folgt auf die höchste vorhandene eigene Datei. Lesen und Schreiben über `NSFileCoordinator`. Nicht geladene Dateien (Platzhalter `.name.icloud`, `ubiquitousItemDownloadingStatus`) werden angefordert und nie koordiniert gelesen, weil das bis zum Laden wartet; der nächste Abgleich holt sie.
- **Automerge-Daten prüfen:** automerge-swift 0.7.2 nimmt leere, fremde und abgeschnittene Daten ohne Fehler an (geprüft). Eine halb geladene Datei hätte dann als gelesen gegolten, und ihre Änderungen wären für immer verloren gewesen. `ChunkCheck` prüft deshalb Kennung, Länge und Prüfsumme jedes Blocks (bei komprimierten Blöcken Kennung und Länge). Unlesbares bleibt unverändert liegen, steht im Bericht und wird bei jedem Abgleich erneut versucht.
- **Ordner:** `quill.json` legt Quill nur beim ersten Verbinden mit einem leeren Ordner an. Ein Ordner mit vorhandenen Quill-Daten, auch der eines eigenen zweiten Macs, oder mit anderer Ordner-ID wird erst nach Zustimmung zusammengeführt. Fehlt `quill.json` im verbundenen Ordner, oder stammt es aus einer neueren Version, schreibt Quill nichts.
- **Löschen gegen Bearbeiten:** Verschwindet ein Block durch fremde Änderungen, sucht der Abgleich in der Geschichte die löschende Änderung und vergleicht den Block, wie das löschende Gerät ihn sah, mit dem eigenen Stand. Weicht er ab, kommt der Block mit dem eigenen Stand zurück, markiert als wiederhergestellt (`restored`), und geht als eigene Änderung an die anderen Geräte.
- **Papierkorb gegen Bearbeiten:** Wer eine Seite in den Papierkorb legt, schreibt den Stand ihres Seiten-Dokuments dazu (`trashedVersion`). Ein anderes Gerät, das die Seite seitdem bearbeitet hat, behält sie, markiert als wiederhergestellt. Kennt es den Stand nicht, behält es sie auch, lieber eine Seite zu viel. Für eine hier endgültig gelöschte Seite wird der Stand aus den Dateien im Ordner bis zu den gelesenen Nummern nachgebaut. Eine endgültig gelöschte Seite liegt auf den anderen Geräten im Papierkorb, bis „Papierkorb leeren“ sie dort löscht, und kommt danach nirgends zurück.
- **Konflikte und Baum:** Haben zwei Geräte denselben Wert gesetzt, ist das kein Konflikt für den Nutzer. Über Kreuz verschobene Seiten (Kreis) kommen auf die oberste Ebene: je Kreis die mit der kleinsten ID, auf jedem Gerät dieselbe. Datumswerte stehen als Sekunden seit 2001 im Seitenbaum (wie `Date`), damit sie verlustfrei zurückkommen; seit 1970 rundete es.
- **Bilder:** Datei `assets/<SHA-256>.<Endung>` mit den unveränderten Bytes; der Block nennt sie im Feld `assetFile`. Eine Seite mit einem noch nicht geladenen Bild wartet, sonst verlöre der Block beim Speichern seinen Verweis.
- **Ein und aus** (`SyncController`, `SyncSettings` in QuillFeatures):
  - Einschalten legt zuerst ein Backup `vor-sync` an (nie automatisch gelöscht); scheitert es, bleibt der Sync aus. Dann folgen eine neue Geräte-ID (bei jedem Einschalten) und die Verbindung mit Lesezeichen (`com.apple.security.files.bookmarks.app-scope`) in den Einstellungen des Macs. Den Ordner beschreibt erst der erste Abgleich.
  - Ausschalten lässt Store und Ordner unverändert.
  - „Sync pausieren“ bleibt über Neustarts; `SyncGate` wird vor jedem Schreiben in den Ordner gefragt und stoppt auch einen laufenden Abgleich sofort.
  - Vor dem Einspielen eines Backups schaltet `turnOffForRestore()` den Sync aus und merkt die Rückfrage für den Neustart vor. Wieder verbinden heißt: als neues Gerät. Neuere Stände aus dem Ordner kommen dabei zurück, weil der Abgleich zusammenführt; die Oberfläche (11.4) sagt das.
  - Geänderte Seiten laden offene Editoren neu wie bei Änderungen aus einem anderen Fenster.
- **Noch nicht in 11.3:** Oberfläche, Zeitpunkte des Abgleichs (11.4); Verdichten der eigenen Dateien (vor v0.4.0, umgesetzt, siehe „Verdichten“ unten).
- Gegenproben 11.3 (alle rot):
  - kein Wiederherstellen nach „Löschen gegen Bearbeiten“;
  - Seite und Seitenbaum ohne Vergleich mit dem erwarteten Stand;
  - ohne Prüfung der Automerge-Daten;
  - Anhängen ohne Pausen-Prüfung, Pausieren nur in den Einstellungen (laufender Abgleich schreibt weiter);
  - „Papierkorb gegen Bearbeiten“ ohne Prüfung;
  - endgültig gelöscht ohne Stand;
  - nicht geladene Datei gelesen;
  - fremder Ordner ohne Rückfrage;
  - eigene Dateien nicht nachgelesen (Text doppelt nach Abbruch);
  - Einschalten ohne Backup;
  - Datum seit 1970;
  - Kreis nicht aufgelöst.
  - Zwei Gegenproben waren zuerst grün (Datum, Pausieren während des Abgleichs); die Tests wurden verschärft.

**Umsetzung 11.4 (Oberfläche und Zeitpunkte):**
- **Einstellungen › Sync:** aus mit Erklärung und „Ordner wählen und einschalten …“; an mit Ordner, Status, Fortschritt, „Sync pausieren“ (Schalter, bleibt über Neustarts), „Jetzt abgleichen“, Rückfrage bei einem Ordner mit fremden Quill-Daten, Ergebnis des letzten Abgleichs (zwei Werte für ein Feld, nicht geladene und unlesbare Dateien) und „Sync ausschalten …“ mit Bestätigung. Die Sidebar zeigt den Fortschritt erst ab 5 Seiten, damit der Abgleich einer einzelnen Seite nicht aufflackert, und Probleme; ein Klick öffnet die Einstellungen.
- **Zeitpunkte:** beim Start, wenn Quill aktiv wird, 2 s nach einer Änderung im Store, alle 60 s für die anderen Geräte. Änderungen während eines Abgleichs lösen keinen weiteren aus, sonst stieße jeder Abgleich mit seinen eigenen Schreibvorgängen den nächsten an; sie nimmt spätestens der regelmäßige Abgleich mit. Vor dem Beenden wird nicht abgeglichen, damit Beenden nie wartet.
- **Ordner wechseln, Geschichte bleibt:** Wird der Ordner von vor dem Ausschalten wieder gewählt (gleiche Ordner-ID in `quill.json`), führt Quill zusammen. Mit jedem anderen Ordner vergisst es nur die gelesenen Nummern (`resetSyncCursors`), denn die gehören zum bisherigen Ordner; erst wenn der neue Ordner gebunden wird: ein leerer beim Verbinden, einer mit fremden Daten nach Zustimmung (seit dem Review von Phase 11). Die Automerge-Dokumente im Store bleiben samt Geschichte, sie ist die Grundlage der Zeitreise (Entscheidung Nutzer).
  - **Erste eigene Datei = ganzer Stand:** Steht ein Dokument noch nicht im Ordner (`SyncCursors.inFolder`), ist die erste eigene Datei dafür der ganze Stand samt Geschichte (`save()`), auch mit den Beiträgen anderer Geräte aus dem vorherigen Ordner. Danach folgen wie bisher nur neue Änderungen. Ein Gerät im neuen Ordner kann so auch ältere Stände abrufen.
  - **Dateiname:** Bis zum Verdichten hieß die Datei `<Nr>.changes`, weil der Lesepfad (`applyEncodedChanges`) Änderungen und ganze Stände gleich annimmt (geprüft). Seit dem Verdichten ist sie eine verdichtete Datei `<Nr>.snapshot` (siehe „Verdichten“ unten); Ordner im alten Format bleiben lesbar.
  - **Keine Kopien beim Empfangen:** Ein Dokument, das beim ersten Abgleich mit diesem Ordner nur die gemeinsame erste Änderung enthält, gilt sofort als im Ordner. Wer eine Seite nur empfängt, schreibt also keine Kopie fremder Inhalte.
  - **Verworfen:** Zuerst hatte 11.4 die Dokumente beim Ordnerwechsel gelöscht und neu begonnen. Damit war die Geschichte auch im Store weg, und gemerkte Stände beim Papierkorb passten nicht mehr.
- **Backup einspielen bei eingeschaltetem Sync:** Die Bestätigung sagt, dass der Sync ausgeschaltet wird. Vor dem Vormerken schaltet `turnOffForRestore()` ihn aus (seit dem Review von Phase 11, in `QuillPersistence.requestRestore`); scheitert das Vormerken, läuft er weiter; wird das Beenden abgebrochen, läuft er mit demselben Gerät weiter wie vorher (`cancelTurnOffForRestore()`). Nach dem Neustart fragt das erste Fenster, nach der Meldung zum Backup:
  - „Zusammenführen“ mit dem bisherigen Ordner; neuere Stände aus dem Ordner kommen dabei zurück, das sagt der Text.
  - „Neu beginnen mit neuem Ordner“ nur mit einem leeren Ordner, nicht dem bisherigen (auch nicht unter anderem Pfad, erkannt an der Ordner-ID).
  - „Später“ (Escape): Der Sync bleibt aus.
  - Keine Wahl ist Standard für Return. Der bisherige Ordner wird in keinem Fall überschrieben; Quill hängt dort nur eigene Dateien an (Entscheidung Nutzer).
- **Einstellungen des Sync außerhalb des echten Bereichs:** Ein Debug-Build hat dieselbe Bundle-ID wie die App. Test-Stores speichern Verbindung, Pause und Rückfrage deshalb im Arbeitsspeicher (`-QuillInMemoryStore`) oder als JSON im Testordner (`-QuillStoreDirectory`), nie in den Einstellungen des Macs (`SyncSettingsStorage`). UI-Tests wählen den Ordner mit `-QuillSyncTestFolder <Name>` statt der Dateiauswahl (nur Debug, nur mit Test-Store).
- **Testvariante:** Schema „Quill Synctest“ für den Handtest (Anleitung `docs/synctest.md`). Bis 11.5 eine Variante (`…quill.synctest`) in zwei Benutzerkonten; seit Fall 14 zwei Konfigurationen `SynctestA` und `SynctestB` (wie Release, Bundle-IDs `io.github.vogelwild07.quill.synctest.a` und `.b`, Namen „Quill Synctest A“ und „Quill Synctest B“), die zugleich in einem Konto laufen, weil der Wechsel zwischen zwei Konten für den Handtest zu aufwendig war. Jede hat ihren eigenen Container; der gemeinsame Ordner liegt im Benutzerordner (`~/QuillSyncTest`). `Scripts/make-synctest.sh` baut beide ad hoc signiert nach `dist/synctest/` und bricht ab, wenn eine Kennung nicht stimmt; `BundleIdentifierTests` (`synctestVariantsNeverUseTheRealIdentifier`) verlangt beide Kennungen und verbietet die der echten App.
- **Lizenzen:** Einstellungen › Lizenzen zeigt `ThirdPartyLicenses.txt` unverändert: die MIT-Lizenz von automerge-swift, die Liste der Rust-Pakete im vorgebauten Automerge-Kern mit ihrer Lizenz und alle Lizenztexte, gleiche nur einmal.
  - **Quelle:** automerge-swift liefert keine solche Liste mit; das Release 0.7.2 enthält nur das xcframework und zwei Bibliotheken. Die Datei erzeugt deshalb `Scripts/third-party-licenses.py` mit `cargo`: alle normalen Abhängigkeiten von `uniffi_automerge` für macOS und iOS (75 Pakete, für beide gleich). Pakete nur zum Übersetzen (Makros) sind dabei, lieber eine Lizenz zu viel.
  - **Fehlende Lizenzdateien:** automerge, hexane und uniffi haben im veröffentlichten Paket keine Lizenzdatei; ihr Text kommt aus dem Repo des Projekts, gleiche Version.
  - **MPL-2.0:** uniffi steht unter MPL-2.0 und ist unverändert; die Datei nennt den Ort des Quellcodes.
  - **Test:** `ThirdPartyLicensesTests` prüft, dass die Datei zur festgelegten Version von automerge-swift passt; nach einem Versionswechsel das Skript neu laufen lassen.
  - **Rust nur für diese Analyse**, installiert per rustup ohne Änderung an Shell-Profilen (`--no-modify-path`, Profil `minimal`). Es liegt in `~/.rustup` und `~/.cargo`, dazu die geladenen Quellen der Pakete in `~/.cargo/registry`. Entfernen mit `~/.cargo/bin/rustup self uninstall`; das löscht beide Ordner vollständig.
- Gegenproben 11.4 (alle rot):
  - anderer Ordner: nur neue Änderungen statt des ganzen Stands (neues Gerät dort bekäme nichts, alte Stände fehlten);
  - neuer Ordner ohne Zurücksetzen der gelesenen Nummern;
  - Zurücksetzen löscht auch die Dokumente (alte Stände fehlen im neuen Ordner);
  - ganzer Stand bei jedem Abgleich, ganzer Stand auch für leere Dokumente (Kopien beim Empfangen), `inFolder` geht beim Lesen verloren;
  - bisheriger Ordner wie ein anderer behandelt;
  - „Neu beginnen“ ohne Prüfung auf leeren Ordner und ohne Prüfung auf den bisherigen Ordner;
  - eigene Schreibvorgänge lösen weitere Abgleiche aus;
  - abgebrochenes Beenden ohne Rückweg;
  - Test-Store speichert Sync-Einstellungen nicht im Testordner;
  - Testordner ohne Pfadprüfung;
  - Backup einspielen ohne Ausschalten des Sync (UI-Test: keine Rückfrage nach dem Neustart);
  - Lizenzen für eine andere Version von automerge-swift, Paket fehlt in der Liste.
  - Eine Gegenprobe war zuerst grün (zweiter Aufruf von `syncNow()` wartet nicht auf den laufenden Abgleich); der Test wurde verschärft.
- Handtest 11.5 mit zwei Benutzerkonten: alle 13 Fälle aus `docs/synctest.md` bestanden (2026-10-20, Nutzer).

**Review von Phase 11 (2026-10-20, Befunde zuerst gezeigt, Fixes nach Freigabe des Nutzers):**
- **Tippen während eines Abgleichs** (Befund 1, Datenverlust): Der Editor schrieb seinen Stand ohne Vergleich in den Store und überschrieb so einen Block, den der Sync gerade zusammengeführt hatte; der nächste Abgleich verteilte das Löschen. Jetzt speichert die Bridge nur, wenn der Store noch dem Stand entspricht, von dem sie ausging (`PageStore.applyEdits(_:_:expected:)`). Sonst führt `BlockMerge` je Block zusammen: Was nur eine Seite geändert hat, gilt; Art und jedes Feld von `BlockProperties` getrennt; Text samt Formatierung auf UTF-16-Ebene, solange sich die geänderten Stellen nicht überschneiden (an derselben Stelle zuerst die lokale Eingabe). Geht das nicht, bleibt der lokale Block und die Fassung aus dem Store steht als Kopie dahinter, markiert als wiederhergestellt; gelöscht gegen bearbeitet behält den bearbeiteten Block, markiert. Das Ergebnis bekommt der Editor (`onExternalChange`), der Cursor bleibt hinter dem Getippten. Lehnt der Editor ab (markierter Text), wird nichts gespeichert und später erneut versucht. Gilt auch für zwei Fenster mit derselben Seite (löst die Vereinfachung aus ADR-012 ab). Grenze: Neu laden leert wie bisher die Undo-Liste des Editors.
- **Konflikte blieben nicht stehen** (Befund 2): Jeder Abgleich schrieb den vorne gezeigten Wert zurück und löste den Konflikt still. `set()` schreibt einen gleichen Wert jetzt nie; der Konflikt bleibt bei jedem Abgleich beider Geräte bestehen.
- **Wettlauf beim Ordnerwechsel** (Befund 5): Verbinden wartet, bis ein laufender Abgleich geendet hat, bevor es die Pause aufhebt.
- **Abgelehnter fremder Ordner** (Befund 6): Ein Ordner mit fremden Quill-Daten ohne Zustimmung wird beim Ausschalten nicht zum „bisherigen“; die gelesenen Nummern vergisst Quill erst nach Zustimmung (`confirmFolder`). Wieder mit dem bisherigen Ordner verbunden, führt Quill dort ohne Rückfrage zusammen und schreibt nichts erneut.
- **Reihenfolge beim Backup einspielen** (Befund 7): erst Sync aus, dann vormerken.
- **Status nach dem Ausschalten** (Befund 9): „aus“ statt „pausiert“, wenn ein Abgleich danach noch fertig wird.
- **Tote API** (Befund 10): `PageStore.setRestored` entfernt; die Marke setzen Abgleich und Zusammenführen selbst.
- **Block-Felder vollständig** (ADR-014): `SyncBlockPropertiesTests` schickt jedes Feld aus `SampleDocuments.fullProperties` durch `PageDocument` und über ein zweites Gerät; `BlockMerge.mergedPropertyCount` muss zur Zahl der Felder passen.
- **Farben:** Fehler und Hinweise im Sync und beim Backup als `ProblemLabel` (Warnsymbol in Systemfarben, Text in Primärfarbe) statt `.red`/`.orange`.
- Nicht behoben (Entscheidung Nutzer): ganzer Stand doppelt nach einem verschobenen Abgleich (Befund 8, nichts geht verloren); Smells nur, wo ohnehin berührt (Ordner aus dem Lesezeichen jetzt an einer Stelle, `SyncConnection.folder`). Konflikt-Wahl auf der Seite und die Marke „wiederhergestellt“ in Editor und Sidebar folgen in 11.6, vor v0.4.0.
- Gegenproben Review (alle rot):
  - Speichern ohne Vergleich mit dem erwarteten Stand; Text nie zusammengeführt; Eingabe während des Wartens vergessen; Ablehnung des Editors übergangen; Cursor an der alten Stelle; gelöscht gegen bearbeitet ohne Marke;
  - Konflikt beim gleichen Wert wieder aufgelöst;
  - Verbinden wartet nicht auf den laufenden Abgleich; fremder Ordner ohne Zustimmung wird „bisheriger“; gelesene Nummern schon vor der Zustimmung vergessen; Zustimmung ohne Zurücksetzen;
  - erst vormerken, dann Sync aus; gescheitertes Vormerken ohne Rückweg; Status „pausiert“ nach dem Ausschalten;
  - Feld fehlt in `PageDocument`; Feld fehlt in `BlockMerge`.
  - Drei Gegenproben waren zuerst grün: Cursor (Filter traf keinen Test), Feld im Zusammenführen (der Test zählte nur eine Konstante) und Zustimmung ohne Zurücksetzen (kein Test). Filter korrigiert, Tests neu geschrieben.

**Handtest als UI-Test mit zwei Geräten (2026-10-21, Freigabe des Nutzers):** `SyncTwoAppsUITests` spielt die Fälle aus `docs/synctest.md` mit Synctest A und B nebeneinander durch; `Scripts/test-synctest-ui.sh` baut beide, meldet sie bei Launch Services an und startet jede Testmethode einzeln mit 600 s Grenze. Im normalen UI-Lauf wird die Klasse übersprungen (nur mit `TEST_RUNNER_QUILL_SYNC_UI=1`).
- **Test-Schalter nur in den Testvarianten:** Die Schalter für Wegwerf-Stores, eigene Zwischenablage, Testbild und Testordner gelten unter `DEBUG || QUILL_SYNCTEST`. `QUILL_SYNCTEST` setzt nur `make-synctest.sh`, auf der Kommandozeile für alle Targets samt Paket (die Paket-Targets sehen die Einstellungen des App-Targets nicht). Keine Konfiguration der Projektdatei enthält es (`SynctestVariantTests`), und `check-release-binary.sh` sucht im Release-Build nach den Namen der Synctest-Schalter, dem Ordnernamen, der Bundle-ID und nach Ausnahmen in den Entitlements.
- **Gemeinsamer Ordner trotz Sandbox:** Der Test-Runner läuft selbst in der Sandbox und darf nur in seinem Container schreiben; der Ordner liegt deshalb in dessen temporärem Ordner (`…/io.github.vogelwild07.quill.UITests.xctrunner/Data/tmp/QuillSyncUITests/`). Nur die Testvarianten bekommen dafür eine Ausnahme in eigenen Entitlements (`App/QuillSynctest.entitlements`, `home-relative-path.read-write`, genau dieser Ordner); `-QuillSyncSharedFolder <Name>` nimmt nur einen Namen darin, nie einen Pfad. Die Entitlements der echten App bleiben unverändert (`SynctestVariantTests`). macOS fragt dabei nicht nach dem Zugriff auf Daten anderer Apps (Probelauf).
- **Fall 12 verlässlich:** `-QuillSyncHaltBeforePage <n>` lässt den Abgleich vor dem Schreiben der n-ten Seite in den Store anhalten, bis die App endet (`SyncEngine`, nur unter `DEBUG || QUILL_SYNCTEST`). Der Test wartet auf „3 / 8“ in den Einstellungen und beendet B dann mit ⌘Q; kein Zeitfenster muss getroffen werden.
- **Fall 14 zweimal:** mit der normalen Wartezeit vor dem Speichern (A lädt neu, „BBB “ erscheint während des Tippens) und mit `-QuillSaveDelay 8000` (`EditorPersistenceBridge.testDelay`): Dann fällt der Abgleich sicher in ungespeicherte Eingaben, und die Bridge muss zusammenführen. Ohne diese Wartezeit traf der UI-Test den Weg über `BlockMerge` nicht (Gegenprobe blieb grün).
- **Per Hand bleiben** (Entscheidung Nutzer): Fall 13 (iCloud Drive) und „Neu beginnen …“ aus Fall 11 (Dateiauswahl), beide in Phase 13 mit echtem Mac und iPhone. Den Pfad in der Gruppe „Unlesbare Dateien“ (Fall 9) prüft der Test nicht: XCUITest klappt die Gruppe in den Einstellungen weder per Klick noch per Tastatur auf; geprüft wird der Eintrag.
- Gegenproben (alle rot): `QUILL_SYNCTEST` in der Debug-Konfiguration; Ausnahme in den Entitlements der echten App; Ausnahme der Testvarianten zeigt auf einen anderen Ordner; Release-Prüfung ohne Synctest-Namen; Release-Build mit `QUILL_SYNCTEST` und mit den Synctest-Entitlements (`check-release-binary.sh`); Synctest B mit der Kennung der echten App; Haltepunkt greift nicht (Fall 12); `BlockMerge` übernimmt nur den lokalen Stand (Fall 14 mit Wartezeit, „BBB “ geht verloren). Eine Gegenprobe war zuerst grün (Fall 14 ohne Wartezeit, siehe oben).

**Konflikt-Wahl und Marke „wiederhergestellt“ (11.6, 2026-10-21, Freigabe des Nutzers):** Konflikte bleiben nicht mehr nur eine Zahl in den Einstellungen; der Nutzer wählt je Stelle eine Fassung.
- **Gerät je Fassung:** Jede Sitzung schreibt mit einer Akteurs-ID aus Geräte-ID (16 Byte) und zufälliger Sitzungs-ID (`SyncDocument.write(as:)`). Für jeden strittigen Wert sucht `conflicts(in:)` die Änderung, die ihn geschrieben hat, und liest daraus das Gerät; den Namen nennt `devices/<ID>.json` im Ordner, das eigene Gerät seinen eigenen Namen, sonst „Unbekanntes Gerät“. **Keine Zeit:** Die Zeitstempel der Automerge-Änderungen entstehen beim Anhängen an den Ordner, nicht beim Bearbeiten; nach einer Pause oder ohne Ordner stünde dort die Zeit des Abgleichs. Deshalb nennt das Popover nur das Gerät (Vorgabe Nutzer: Zeit nur, wenn verlässlich).
- **Wählen:** `SyncDocument.resolve` schreibt den gewählten Wert neu, auch wenn er schon angezeigt wird, damit alle Geräte denselben Stand haben; bei doppelten Blöcken oder Seiten bleibt die gewählte Fassung. Die Wahl geht über `SyncEngine.choose` in den nächsten Abgleich: nach den Dateien der anderen Geräte, als eigene Datei im Ordner und in den Store. Ist der Konflikt inzwischen weg (anderes Gerät hat gewählt), fällt die Wahl still weg. Gewählt wird nur bei eingeschaltetem, nicht pausiertem Sync (`SyncController.canChoose`); pausiert sind die Knöpfe aus, mit Hinweis „Zum Wählen Sync fortsetzen.“
- **Oberfläche:** Unter dem Seitentitel „N Stellen mit zwei Fassungen · Wählen …“ mit Popover über alle Konflikte der Seite (auch Titel, Symbol, Ort). Am rechten Rand eines Blocks ein Zeichen (zwei versetzte Quadrate in der Akzentfarbe) mit Popover nur für diesen Block. In Einstellungen › Sync unter der Zahl die Liste der Seiten mit Konflikten; ein Klick springt im vordersten Fenster zur Seite und zum ersten strittigen Block (`PageJumpRouter`), ohne offenes Fenster öffnet sich eines.
- **Marke „wiederhergestellt“:** Block mit Zeichen am Rand (Pfeil zurück, Sekundärfarbe) und Popover mit Erklärung und „Markierung entfernen“ (ein Undo-Schritt, gespeichert und abgeglichen wie jede Änderung). Seite mit Symbol in der Sidebar, Eintrag „Markierung entfernen“ im Kontextmenü und Hinweis unter dem Titel mit „Markierung entfernen“ und „In den Papierkorb“. Die Marke verschwindet nur so, nie von selbst (Entscheidung Nutzer). Dafür gibt es `PageStore.setRestored` wieder (im Review als tote API entfernt, jetzt mit Aufrufer, mit Undo über `PageOperations.clearRestored`).
- **Gerätenamen im Test:** Beide Testvarianten laufen auf einem Mac und hätten denselben Namen; `-QuillSyncDeviceName <Name>` setzt ihn (nur `DEBUG || QUILL_SYNCTEST`, nur mit Test-Store, `SynctestVariantTests`, `check-release-binary.sh`).
- **Konflikte beim Start** (Vorgabe Nutzer vor dem Merge): `SyncController.start()` liest sie nur aus den Sync-Dokumenten im Store (`PageStore.storedSyncDocuments`, ohne `save()`; `SyncEngine.storedConflicts`), auch pausiert; Gerätenamen nur lesend aus `devices/`. Nichts wird in Ordner oder Store geschrieben (`conflictsShowAfterRestartWhilePausedWithoutWriting`, `storedConflictsMatchTheLastSyncWithoutWriting`). Ein schon fertiger Abgleich hat Vorrang. Gewählt wird weiter erst bei laufendem Sync.
- **Grenzen:** Das Zeichen am Block hat keinen Tooltip (Beschriftung für VoiceOver und Popover genügen). Der Bedienungshilfen-Audit sieht die Konflikt-Oberfläche nicht, weil sie zwei Geräte braucht; geprüft wird sie in `SyncTwoAppsUITests` (Fälle 5, 6, 7).

**Verdichten (vor v0.4.0, 2026-10-21, Freigabe des Nutzers):** Jedes Gerät fasst seine eigenen Dateien je Dokument (Seite und Seitenbaum) zu einer verdichteten Datei `<Nr>.snapshot` zusammen (ADR-026).
- **Wann:** Liegen nach der letzten eigenen verdichteten Datei 50 eigene Dateien für ein Dokument im Ordner (`SyncEngine.compactAfter`), schreibt der Abgleich dieses Dokuments den ganzen Stand samt Geschichte (`save()`) als nächste Nummer. Danach löscht er die eigenen Dateien darunter (`SyncFileAccess.delete`, koordiniert, nur im Ordner des eigenen Geräts). Bricht er zwischen Schreiben und Löschen ab, räumt der nächste Abgleich des Dokuments auf. Pausiert wird weder geschrieben noch gelöscht.
- **Erste Datei nach einem Ordnerwechsel (11.4):** gleich eine verdichtete Datei statt `<Nr>.changes` mit ganzem Stand. Alte Ordner mit `000000000001.changes` als ganzem Stand werden weiter gelesen und beim nächsten Verdichten aufgeräumt.
- **Lesen:** Eine verdichtete Datei eines anderen Geräts über der gelesenen Nummer wird zuerst übernommen, danach die nummerierten Dateien. Die Nummer `n` ist immer genau eine Datei, die gelesene Nummer je Gerät bleibt eine Zahl.
  - **Noch nicht geladen:** anfordern, unter „Noch nicht geladen“ melden; liegen die alten Dateien noch lückenlos da, mit ihnen weiter, sonst warten.
  - **Unlesbar:** unter „Unlesbare Dateien“ melden, liegen lassen, bei jedem Abgleich erneut versuchen; mit den alten Dateien weiter, wenn sie lückenlos da sind, sonst bleibt die gelesene Nummer stehen.
  - **Lücke ohne verdichtete Datei** (alte Dateien schon gelöscht, die neue noch nicht übertragen): Quill wartet still; besteht die Lücke länger als eine Stunde (`SyncEngine.gapReportDelay`, Beginn in den gelesenen Nummern im Store), steht sie in Einstellungen › Sync mit Seite (oder Seitenbaum), Gerät und Beginn (`SyncReport.gaps`, Vorgabe Nutzer). Geht es weiter, verschwindet sie.
- **Papierkorb:** Der Stand des Ordners, den dieses Gerät kannte (`folderPageVersion`, für Seiten, die ohne Papierkorb verschwunden sind), liest je Gerät die verdichtete Datei bis zur gelesenen Nummer und die Dateien danach. Hat das Gerät inzwischen weiter verdichtet, ist er unbekannt, und die Seite bleibt auf den anderen Geräten (wie bisher, wenn eine Datei fehlt).
- **Tests:** `SyncCompactionTests` (50 Dateien → eine verdichtete Datei, Gerät mit Stand vorher, mittendrin und neu holen auf, erster Stand bleibt abrufbar; Seitenbaum; altes Format; noch nicht geladen mit und ohne alte Dateien; unlesbar; Lücke nach einer Stunde; Pause; Abbruch zwischen Schreiben und Löschen; fremde Dateien bleiben), `SyncLabelTests`.
- Gegenproben (alle rot): Löschen vor dem Schreiben; Leser löscht die alten Dateien des anderen Geräts (zuerst grün, weil kein Test eine verdichtete Datei neben den alten Dateien las; Test ergänzt); verdichtete Datei trotz Pause; unlesbare und nicht geladene verdichtete Datei übersprungen; erste Datei wieder `.changes`; verdichtete Dateien beim Lesen übergangen; Lücke nie oder sofort gemeldet; `folderPageVersion` ohne verdichtete Dateien; kein Aufräumen nach Abbruch.

**Review von 11.6 und dem Verdichten (2026-10-21, Fixes nach Freigabe des Nutzers):**
- **Nur verdichten, wenn alle eigenen Dateien übernommen sind:** Fehlt dem Store eine eigene Datei (noch nicht geladen, unlesbar, Store hinter dem Ordner nach einem Abbruch oder älteren Backup), bleibt die gelesene eigene Nummer stehen, damit der nächste Abgleich sie nachliest, und es wird weder verdichtet noch unter der letzten verdichteten Datei aufgeräumt. Vorher hätte das Verdichten eigene Dateien gelöscht, die nie übernommen waren. Die erste Datei mit ganzem Stand ist in diesem Fall keine verdichtete.
- **Gelesene Nummern mit genauen Zeitpunkten:** Die Zeitpunkte darin waren auf Sekunden gerundet (ISO 8601); dadurch war jede Seite bei jedem Abgleich fällig. Jetzt genau, alte Daten bleiben lesbar. Damit Konflikte nicht aus dem Bericht fallen, wenn ihre Seite nicht fällig ist, merkt sich die Engine die Konflikte aller Dokumente (beim ersten Abgleich aus dem Store).
- **Lücke beim Warten auf ein Bild:** Der Beginn einer Lücke steht auch dann in den gelesenen Nummern, wenn die Seite auf ein Bild wartet und ihr Abgleich vor dem Speichern endet.
- **Wahl geht nicht verloren:** Die Engine verwirft eine Wahl erst, wenn sie im Ordner steht oder nichts mehr zu entscheiden ist; scheitert das Schreiben, gilt sie beim nächsten Abgleich. Eine Wahl während eines laufenden Abgleichs bleibt aus der Anzeige, auch wenn dessen Bericht den Konflikt noch enthält (`SyncController.remember`).
- **Standards:** Maße der Sync-Hinweise als `QuillDesign.SyncNotice` (`DesignTokenTests`), Name der Randzeichen für VoiceOver über den String-Katalog.
- **UI-Tests auf dem Hauptbildschirm:** `-QuillWindowsOnMainScreen YES` (nur Debug, `TestWindowScreen`, aus `XCUIApplication.quill()`) legt jedes Fenster auf den Bildschirm mit der Menüleiste. Mit zweitem Monitor öffnete das Fenster sonst dort, und der Kontrast-Audit meldete je nach Hintergrund mehr. `check-release-binary.sh` prüft, dass der Name im Release fehlt.
- **Tests:** `ownFilesNotYetReadAreNeverCompactedAway`, `cleanupWaitsUntilAllOwnFilesAreRead`, `firstFileIsNoSnapshotWhileOwnFilesAreMissing`, `missingOwnFilesMakeThePageDue`, `cursorsKeepExactDates`, `gapIsReportedEvenWhileThePageWaitsForAnImage`, `choiceSurvivesAFailedWrite`, `choiceDuringARunningSyncStaysHidden`, `TestWindowScreenTests`, `QuillUITests.testWindowsLieOnTheMainScreen`.
- Gegenproben (alle rot): Verdichten und Aufräumen trotz fehlender eigener Dateien; eigene Nummer rückt trotzdem vor; erste verdichtete Datei trotz Lücke; eigene Dateien machen die Seite nicht fällig; gerundete Zeitpunkte; Konflikte nur fällig gewesener Seiten und nicht aus dem Store; Beginn der Lücke nur nach dem Speichern; Wahl vor dem Schreiben verworfen; Bericht des laufenden Abgleichs überschreibt die Wahl; Zahlen statt Tokens; Name der Randzeichen ohne Katalog; Fenster nicht verschoben; UI-Test ohne das Startargument (Fenster auf dem zweiten Monitor).
- Übrige Befunde unter „Später“ in `docs/roadmap.md`.

**Store hinter dem Ordner (vor v0.4.0, 2026-10-21, Fix nach Freigabe des Nutzers):** Bricht ein Abgleich ab, nachdem er eine eigene Datei in den Ordner geschrieben hat, aber bevor Dokument und gelesene Nummern im Store stehen, enthalten die Blöcke im Store schon Änderungen, die dem Sync-Dokument fehlen. War diese eigene Datei beim nächsten Abgleich noch nicht geladen, verglich der Abgleich die Blöcke mit dem unvollständigen Dokument und legte einen dort neu angelegten Block (im Seitenbaum: eine neue Seite) ein zweites Mal an. Kam die Datei an, standen unter derselben ID zwei gleichzeitige Fassungen, beide vom eigenen Gerät; die Seite zeigte einen Konflikt. Getippter Text heilte sich, weil der nächste Vergleich die doppelte Einfügung wieder entfernt.
- **Fix:** Ist eine eigene Datei einer Seite oder des Seitenbaums noch nicht geladen, wartet dieses Dokument wie auf ein Bild: angefordert, unter „Noch nicht geladen“ gemeldet, nichts geschrieben, die Blöcke im Store bleiben. Bei einer unlesbaren eigenen Datei geht der Abgleich weiter wie bisher (ohne Verdichten), sonst bliebe die Seite für immer stehen; wird die Datei repariert, kann der Konflikt erscheinen und wird gewählt.
- **Bericht:** Konflikte einer Seite, die erst dieser Abgleich über den Seitenbaum anlegt, fehlten bis zum nächsten Abgleich, weil der Filter die Seiten vor dem Seitenbaum las (seit #21). Jetzt danach.
- **Tests:** `SyncStoreBehindFolderTests` (eigene Datei lesbar; noch nicht geladen, mit Warten ohne Schreiben; getippter Text; neue Seite im Seitenbaum; Konflikt auf einer neuen Seite im ersten Bericht). `ownFilesNotYetReadAreNeverCompactedAway` und `firstFileIsNoSnapshotWhileOwnFilesAreMissing` prüfen jetzt eine unlesbare eigene Datei, weil eine noch nicht geladene nichts mehr schreiben lässt.
- Gegenproben (alle rot): Seite wartet nicht; Seitenbaum wartet nicht; Filter vor dem Seitenbaum.

## ADR-030: Vorerst nur die Mac-App (2026-10-21)

**Kontext:** Phase 13 sollte nach Sync und Zeitreise die iPhone-App bringen. Der Nutzer will den vollen Fokus auf die Mac-App legen.

**Entscheidung:**
- Die iPhone-App wird vorerst nicht gebaut; Phase 13 ist pausiert und steht am Ende der Roadmap. Offen beim Wiederaufnehmen: Developer Program und die Messung des Abgleichs auf einem echten iPhone (ADR-026).
- Der Ordner-Sync (ADR-026, ADR-029) bleibt und gilt für mehrere Macs.
- `QuillKit` baut weiter für iOS (`Scripts/check-ios-build.sh` im vollen Lauf, ADR-028), damit der gemeinsame Code kompilierbar bleibt, solange das wenig kostet. Wird es teuer, wird neu entschieden.
- Die Reihenfolge der weiteren Mac-Phasen wird nach Phase 12 festgelegt.

**Konsequenzen:**
- Nur-Mac-Code steht weiter hinter `#if canImport(AppKit)`; neue Logik kommt weiter in `QuillKit`.
- Das Developer Program wird erst nötig, wenn eine Mac-Phase es braucht (z. B. Teilen-Erweiterung mit App Group).

## ADR-031: Zeitreise (2026-10-21, entsteht mit Phase 12)

**Kontext:** Phase 12 soll frühere Stände jeder Seite zeigen und Absätze daraus zurückholen. Die Seiten-Dokumente des Sync (ADR-026) enthalten schon eine Geschichte, aber nur mit einem Stand je Abgleich und nur bei eingeschaltetem Sync.

**Entscheidung (12.1, Geschichte aufzeichnen):**
- Quill zeichnet die Geschichte jeder Seite immer auf, auch ohne Sync, im Sync-Dokument der Seite (`Page.syncDocument`, kein neues Schema). `HistoryRecorder` (in `QuillSync`, ein Actor) übernimmt nach jedem Speichern im Editor die Blöcke aus dem Store als Änderung, entprellt (2 s Pause, spätestens nach 30 s) und vor dem Beenden sofort. Auf dem Main Thread kommt nur die Meldung an (`HistoryObserver`, nur Speicherungen einer `EditorPersistenceBridge`, nicht das Neuladen nach einem Abgleich).
- Je Seite und App-Sitzung schreibt eine Akteurs-ID: Gerät + Sitzung wie beim Abgleich, ohne eingeschalteten Sync nur die Sitzung (die Änderungen nennen dann kein Gerät). Scheitert das Speichern, beginnt eine neue Sitzung.
- Der Abgleich schreibt die Aufzeichnung mit hinaus: Er merkt sich je Seite den Stand des Dokuments beim letzten erfolgreichen Abgleich (`SyncCursors.exported`) und hängt alles danach als nächste eigene Datei an, nicht nur, was er selbst gerade übernommen hat.
- Stehen lokale Änderungen schon in einer eigenen Datei, aber das Dokument noch nicht im Store (Abgleich verschoben oder abgebrochen), zeichnet `HistoryRecorder` dort nichts auf (`SyncCursors.pending`, gespeichert vor dem Schreiben in den Ordner). Sonst enthielte die Aufzeichnung auf dem alten Dokument dieselben Blöcke ein zweites Mal. Das Gleiche gilt für Seiten, die vor 12.1 abgeglichen wurden, bis zu ihrem nächsten Abgleich.
- Abgleich und Aufzeichnung einer Seite sperren einander (`DocumentLocks`), weil beide das Dokument lesen, ändern und zurückschreiben.

**Entscheidung (12.2, Stand am Ende eines Tages):**
- `PageHistory` (in `QuillSync`) bildet aus dem Sync-Dokument der Seite die Tage mit mindestens einer Änderung, je mit dem Stand an ihrem Ende. Kein neues Schema, nichts wird zusätzlich gespeichert: Die Tage entstehen beim Öffnen aus der Geschichte.
- Eine Änderung zählt zu dem Tag, den die Uhr des schreibenden Geräts nennt (Zeitstempel der Automerge-Änderung), im Kalender und in der Zeitzone des Macs, der die Zeitreise zeigt.
- Der Stand eines Tages enthält alle Änderungen bis zu seinem Ende und alles, worauf sie aufbauen. Geht die Uhr eines Geräts falsch, steht dessen Änderung früher oder später da, aber nie ein Stand, den es so nicht gab. Ein Tag ohne neuen Stand fällt weg.
- Alternativen (nicht gewählt, nicht besprochen): Tage aus der Reihenfolge der Geschichte statt aus den Zeitstempeln (robust gegen falsche Uhren, aber ohne Datum nicht als Tage darstellbar); Tagesstände beim Aufzeichnen als eigene Einträge speichern (schnelleres Öffnen, aber neues Schema und doppelte Daten); Zeitzone des schreibenden Geräts (Automerge speichert sie nicht).
- Messung: `historyDays` (Seite mit 100 Blöcken und einem Jahr Geschichte, dreimal am Tag aufgezeichnet) und `historyDayBlocks` (Blöcke eines Tages), Schwellen 250 und 300 ms (`docs/performance.md`).

**Entscheidung (12.3, Fenster „Zeitreise …“):**
- „Seite › Zeitreise …“ (⌥⌘Y) öffnet für die ausgewählte Seite ein eigenes Fenster (`TimeTravelScene`, `WindowGroup` mit der Seiten-ID): links die Tage, neuester zuerst („Heute“, „Gestern“, sonst Datum), rechts der Stand am Ende des gewählten Tages im Block-Editor. Ein zweites ⌥⌘Y für dieselbe Seite holt ihr Fenster nach vorn.
- Der frühere Stand ist nur lesbar, aber markierbar wie sonst auch (Lesemodus `BlockEditorController.isReadOnly`): Cursor, Markieren mit Maus und Tastatur, Kopieren gehen; Tippen, Einsetzen, Ausschneiden, Löschen, Widerrufen, Ziehgriff, ＋ und Slash-Menü nicht.
- „Auswahl zurückholen“ holt alle Absätze, die die Markierung berührt, in die Seite zurück (`EditorDocument.restore`): Einen Absatz, den es noch gibt, ersetzt sein früherer Inhalt an seiner jetzigen Stelle. Einer, den es nicht mehr gibt, kommt hinter den nächsten früheren Vorgänger, den es noch gibt, sonst an den Anfang; den leeren Absatz einer leeren Seite ersetzt er.
- Zurückgeholt wird über eine eigene `EditorPersistenceBridge`, wie jede Bearbeitung (ADR-013): Offene Editoren der Seite laden neu oder führen zusammen, die Rückholung kommt als neue Änderung in die Geschichte und zeigt sich unter „Heute“. Widerrufen lässt sie sich im Editor der Seite nicht, wohl aber mit einer weiteren Rückholung aus „Heute“ vor der Änderung.
- Zum Testen legt die App selbst eine Seite mit drei Tagen Geschichte an (`-QuillSeedTimeTravel`, nur Debug und Test-Store, `TimeTravelSeed`).
- Vor dem Öffnen speichert das Fenster nur die Editoren dieser Seite (`EditorPersistenceBridge.flushAll(pageID:)`), nicht alle. `HistoryObserver` nimmt nur Speicherungen seines eigenen Stores (die Bridge gibt ihn in `didSave` mit). Beides fiel in parallel laufenden Tests auf (`SyncTypingTests`, `HistoryObserverTests`); in der App gibt es nur einen Store, aber offene Editoren anderer Seiten speicherte das Öffnen sonst unnötig mit.

**Entscheidung (12.4, Frist für gelöschte Bilder):**
- Bilder werden nicht versioniert: Frühere Stände enthalten nur die Asset-ID. Ein Bild ohne Block bleibt im Store, bis die gewählte Frist abgelaufen ist; in der Zeit bekommt ein zurückgeholter Bild-Block sein Bild wieder (die Verknüpfung über `BlockProperties.assetID` gibt es schon, ADR-015).
- Einstellungen › Zeitreise › „Gelöschte Bilder aufbewahren“: 30 Tage, 90 Tage (Standard), 1 Jahr, Immer. Optionsfelder statt Klappmenü: vier Werte, alle auf einen Blick, und das Klappmenü im gruppierten Formular meldete im Audit eine fehlende Aktion.
- Pro Mac in `UserDefaults` (`QuillImageRetention`), nicht im Store, nicht im Backup, nicht im Sync, wie Theme und Fokus-Modus. Test-Stores lesen und speichern sie nie (`QuillPersistence.retentionDefaults`), weil Debug-Builds die Einstellungen mit der echten App teilen.
- Aufgeräumt wird wie bisher einmal beim Start nach dem Start-Backup (`removeOrphanedAssets`), jetzt mit der gewählten Frist, bei „Immer“ gar nicht. Eine kürzere Frist wirkt also erst beim nächsten Start, nie sofort.
- Alternativen (nicht gewählt, nicht besprochen): Bilder mitversionieren (jede Fassung bliebe, Store wächst ohne Grenze); Frist an die älteste Geschichte koppeln (Bilder blieben, solange irgendein Tagesstand sie zeigt; genauer, aber das Aufräumen müsste alle Sync-Dokumente lesen); Frist im Store oder im Sync (gälte für alle Macs, braucht Schema bzw. Sync-Format); sofort aufräumen nach dem Ändern der Frist (ein Fehlgriff löschte sofort, ohne frisches Backup); Klappmenü.
- Konsequenz: Mit 90 statt bisher 30 Tagen wächst der Store um gelöschte Bilder der letzten drei Monate. Vor 12.4 gelöschte Bilder, die schon weg sind, kommen nicht zurück.

**Review von Phase 12 (umgesetzt):**
- Lesemodus dicht: Das Fenster nimmt kein Drag&Drop an (ein abgelegtes Bild wurde sonst schon in den Store importiert), das Menü „Format“ samt Blockart ist im Zeitreise-Fenster gesperrt (`FocusedValues.readOnlyEditor`), Tastenkürzel ohne Menü geben einen Ton.
- „Auswahl zurückholen“ ist aus, solange die Seite im Papierkorb liegt. Kehrt man ins Fenster zurück, lädt es die Geschichte neu („Heute“ aktuell, nach Mitternacht der neue Tag).
- Bild-Blöcke, deren Bild nicht mehr aufbewahrt wird, holt die Zeitreise nicht zurück, sondern meldet sie („N Bilder nicht zurückgeholt …“): Ein leerer Bild-Block hülfe niemandem und käme selbst in die Geschichte.
- `saveHistory` meldet nur „Seite fehlt“ als `false`, andere Fehler beim Lesen wirft es weiter. `DocumentLocks.withLock` statt Sperren und Freigeben von Hand an zwei Stellen, Schlüssel von `didSave` als Konstanten, Fenstermaße als Tokens (`QuillDesign.TimeTravel`).
- Nicht umgesetzt, bewusst: Für Seiten mit verschobenem Abgleich (`pending`) oder letztem Abgleich vor 12.1 zeichnet Quill bei ausgeschaltetem Sync weiter nichts auf. Würde Quill dort aufzeichnen, käme die eigene, noch nicht übernommene Datei beim nächsten Einschalten dazu, und Text stünde doppelt da (unter „Später“).
- Alternativen (nicht gewählt, nicht besprochen): Zeitreise als Sheet oder Seitenleiste im Hauptfenster (enger, Seite und früherer Stand nicht nebeneinander); `NSTextView` mit `isEditable = false` (dann ohne Cursor, Markieren nur mit der Maus, für Tastatur und VoiceOver schlecht); frühere Absätze als SwiftUI-Liste statt im Block-Editor (andere Darstellung als die Seite, Formatierung doppelt); ganzen Tag statt Auswahl zurückholen (gröber, überschreibt alles Spätere); Rückholung direkt über `PageStore` statt die Bridge (bräche die Regel, dass nur die Bridge Blöcke schreibt, und offene Editoren bekämen sie nicht mit); Rückholung im Undo des Seiteneditors (das Fenster hat einen eigenen Editor, ein gemeinsamer Undo-Stapel über Fenster wäre neu).

**Konsequenzen:**
- Die Dokumente wachsen mit jeder Aufzeichnung. Die Messung (`docs/performance.md`) zeigt, ob das stört.
- Seiten ohne Speicherung im Editor (z. B. dupliziert, aus einem Backup) haben bis zur ersten Bearbeitung keine eigene Geschichte.
- Eine Aufzeichnung löst wie jede Speicherung im Store einen Abgleich aus, wenn der Sync an ist.
- Beim Beenden zeichnet Quill auf, was noch wartet (nach dem Speichern der Editoren). Wartet nichts, beendet die App sofort, ohne Task: Wer `NSApp.terminate` aus einem Task auf dem Main Actor ruft, blockiert ihn, und ein Task zum Antworten käme nie dran (so hing der Seed der Performance-Tests).
- `SyncController` nimmt `ModelContext.didSave` ohne Queue entgegen und wechselt erst danach auf den Main Actor. Mit `queue: .main` wartete der speichernde Thread des Stores auf den Main Thread, der seinerseits auf den Store wartete: SwiftData führt Aufrufe auf dem Store synchron aus. Die Lücke gab es schon vorher (Abgleich), die häufigeren Speicherungen der Aufzeichnung haben sie im UI-Test Fall 12 sichtbar gemacht (`SyncControllerTests.storeSavesOffTheMainThreadDoNotWaitForIt`).

## ADR-032: Lokale KI (2026-10-22, entsteht mit Phase 16)

**Kontext:** Phase 16 soll Seiten zusammenfassen, Absätze in To-dos umwandeln, Fragen an die eigenen Notizen mit Quellen beantworten und Links vorschlagen. Vorgabe: nur auf dem Gerät, nichts geht ins Netz. Das SDK (macOS 27) bietet neben dem Modell auf dem Gerät (`SystemLanguageModel`) auch `PrivateCloudComputeLanguageModel`, das Anfragen an Apples Server schickt.

**Entscheidung (Plan):**
- Ein eigenes Modul `QuillAI` ist das einzige, das `FoundationModels` importiert, und nutzt nur `SystemLanguageModel`. `AIIsolationTests` prüft beides an den eingecheckten Dateien (kein Import außerhalb von `QuillAI`, kein `PrivateCloudCompute` irgendwo).
- Die Funktionen sprechen das Modell über ein kleines Protokoll an. Unit- und UI-Tests nutzen ein Test-Modell mit festen Antworten (`-QuillFakeAI`, nur Debug), weil das echte Modell nicht auf jedem Mac läuft und nicht immer gleich antwortet.
- Ohne Apple Intelligence (Gerät ungeeignet, ausgeschaltet, Modell lädt noch) sind die Befehle ausgeblendet; Einstellungen › KI erklärt warum.
- Nichts aus einer KI-Antwort landet ohne Zutun des Nutzers in einer Seite: Zusammenfassung und To-dos zeigen erst eine Vorschau, Übernehmen lässt sich mit ⌘Z zurücknehmen.
- Deployment-Ziel bleibt macOS 26.0: Funktionen ab 26.4 (`tokenCount`) nur hinter `#available`, sonst zählt Quill Zeichen.
- Jeder Schritt ergänzt hier seine Entscheidungen mit Alternativen.

**Entscheidung (16.1, Grundlage):**
- Modul `QuillAI` ohne Abhängigkeiten; `QuillFeatures` hängt daran. Schnittstelle nur Quill-Typen (`TextModel`, `AIAvailability`), kein Typ aus FoundationModels nach außen. Je Anfrage eine neue `LanguageModelSession`, damit nichts aus einer früheren Anfrage mitläuft.
- Einstellungen › KI: „KI-Funktionen verwenden“, Standard an, sobald das Modell bereitsteht. Pro Mac in `UserDefaults` (`QuillAIEnabled`), Test-Stores nie (`QuillPersistence.settingsDefaults`, bisher nur für die Frist der Bilder). Ohne Modell kein Schalter, sondern eine Erklärung je Grund (Mac ungeeignet, Apple Intelligence aus, Modell lädt noch, unbekannt); geprüft beim Öffnen der Einstellungen und wenn ihr Fenster wieder aktiv wird.
- `AISettings` entsteht erst beim ersten Zugriff: Die erste Abfrage der Verfügbarkeit kostet 3–7 ms auf dem Main Thread, der Start soll das nicht tragen.
- Test-Modell `-QuillFakeAI <Fall von AIAvailability>` nur im Debug-Build und nur mit Test-Store.
- Alternativen (nicht gewählt, nicht besprochen): Standard aus bis zum Einschalten (wie der Sync; aber hier verlässt nichts den Mac, und die Befehle erscheinen ohnehin nur auf Wunsch des Nutzers); KI-Code direkt in `QuillFeatures` (einfacher, aber dann prüft kein Test mehr, dass nur das Modell auf dem Gerät verwendet wird); Knopf „Systemeinstellungen öffnen“ (die Adresse des Bereichs „Apple Intelligence & Siri“ ist nicht dokumentiert); ausgegrauter Schalter mit Erklärung darunter (Kontrast im Audit zu gering).

**Entscheidung (16.2, Seite zusammenfassen):**
- Seite › „Zusammenfassen …“ (ohne Kürzel) erscheint nur mit bereitem Modell und eingeschalteter KI. Es speichert zuerst die offenen Editoren der Seite (`flushAll(pageID:)`) und fasst die Blöcke aus dem Store zusammen: ein Absatz je Block, ohne Bilder, Trenner und leere Blöcke.
- Bis zu 6.000 Zeichen je Anfrage: Anweisung, Text und Antwort teilen sich das Kontextfenster (4.096 Token unter macOS 26, 8.192 unter 27); gemessen auf diesem Mac mit dem echten Modell: 5.891 Zeichen deutscher Text = 1.334 Token, Antwort auf Deutsch. Längere Seiten gehen in Stücken an Absatzgrenzen ans Modell, die Teilergebnisse werden noch einmal zusammengefasst; nach drei Runden zählt nur noch das erste Stück (Schutz vor einem Modell, das nicht kürzer antwortet).
- Ergebnis in einem Blatt: „Kopieren“ (in die Zwischenablage des Editors, in UI-Tests die eigene), „Einfügen“ nur, wenn der Editor dieser Seite beim Aufruf den Fokus hatte. Eingefügt wird wie getippt an der Einfügemarke, als ein Absatz, als eigener Schritt für ⌘Z. Hinweis im Blatt, dass das Modell auf dem Mac die Zusammenfassung erstellt hat und sie geprüft werden soll.
- Die Verfügbarkeit prüft `AISettings` jetzt außerhalb des Main Threads und ist bis dahin `nil` (Befehl ausgeblendet, Einstellungen mit Fortschritt): Das Menü fragt schon beim Start, die erste Prüfung kostet 3–7 ms.
- Fehler des Modells kommen als `AIError` aus `QuillAI` (zu lang, abgelehnt, Sprache, nicht bereit, sonst), ab macOS 27 aus `LanguageModelError`, davor aus `GenerationError`; das Blatt nennt den Grund.
- Alternativen (nicht gewählt, nicht besprochen): Zusammenfassung als eigener Block oben auf der Seite (über die Bridge, dann ohne ⌘Z im Editor); als Zitat-Block; immer gespeichert in der Seite (Eigenschaft); Fortschritt je Stück; Seite zu lang ablehnen statt in Stücken.

**Entscheidung (16.3, To-dos vorschlagen):**
- Seite › „To-dos vorschlagen …“ (ohne Kürzel, neben „Zusammenfassen …“, gleiche Bedingung) nimmt die Blöcke, die die Markierung im Editor berührt. Ohne Markierung oder ohne Editor im Fokus erklärt das Blatt, was zu tun ist.
- Das Modell gibt eine Liste zurück (geführte Ausgabe, `TextModel.list`), keinen freien Text: So muss Quill keine Zeilen deuten, und „keine Aufgabe“ ist eine leere Liste. Quill entfernt trotzdem Aufzählungszeichen, Nummern und Kästchen, leere und doppelte Einträge und nimmt höchstens 50. Lange Markierungen gehen in denselben Stücken wie beim Zusammenfassen ans Modell, die Listen werden aneinandergehängt.
- Vorschau im Blatt; „Einfügen“ setzt die To-dos als eigene Blöcke unter den letzten markierten Block und wählt sie aus, ein Schritt für ⌘Z („To-dos einfügen“). Die markierten Absätze bleiben unverändert.
- Fehlermeldungen des Modells teilen sich Zusammenfassen und To-dos (`AIProblem`); die Sätze nennen jetzt „diesen Text“ statt „diese Seite“.
- Alternativen (nicht gewählt, nicht besprochen): die markierten Absätze durch die To-dos ersetzen („umwandeln“ wörtlich; verliert den Wortlaut, nur mit ⌘Z zurück); Kästchen je Vorschlag zum Abwählen (mehr Bedienung; Löschen nach dem Einfügen geht genauso); Eintrag im Menü „Format“ (dort stehen Befehle ohne Blatt, die sofort wirken); freie Antwort Zeile für Zeile deuten (unzuverlässig, „keine Aufgabe“ nicht eindeutig); Einrückung des letzten markierten Blocks übernehmen.

**Entscheidung (16.4, Frag deine Notizen):**
- „Ablage › Frag deine Notizen …“ (ohne Kürzel, unter „Schnell öffnen …“, nur mit bereitem Modell und eingeschalteter KI) öffnet ein Blatt mit einem Feld für die Frage. Vorher werden alle offenen Editoren gespeichert.
- Quellen kommen aus der vorhandenen Suche (`PageStore.search`), kein eigener Index und keine Vektoren: Das Modell zieht aus der Frage bis zu fünf Suchbegriffe (`TextModel.list`); findet keiner etwas, sucht Quill nach den Wörtern der Frage ab vier Buchstaben. Seiten mit den meisten Begriffen zuerst, höchstens fünf; Seiten im Papierkorb nie.
- Zusammen höchstens 6.000 Zeichen Text der Quellen (wie ein Stück beim Zusammenfassen), gleich verteilt; ist eine Seite länger, kommt der Ausschnitt um die erste Fundstelle. Das Modell soll nur aus diesen Notizen antworten und sagen, wenn die Antwort nicht darin steht.
- Anweisungen mit dem echten Modell auf diesem Mac verglichen: Ohne den Hinweis, zusammengesetzte Wörter zu zerlegen, kam „Zahnarzttermin“ statt „Zahnarzt“ (die Suche findet Teile von Wörtern, nicht Zusammensetzungen). Ein fester Satz für „nichts gefunden“ kam auch, wenn die Antwort in den Notizen stand; ohne Bedingung erfand das Modell eine Antwort aus der falschen Seite. Gewählt: „Wenn keine Notiz zur Frage passt, sag, dass du dazu nichts gefunden hast“, in drei Fällen je zweimal richtig.
- Das Blatt zeigt die Antwort und darunter alle Seiten, die ans Modell gingen; ein Klick öffnet die Seite und schließt das Blatt. Ohne passende Seite fragt Quill das Modell gar nicht und sagt das.
- Alternativen (nicht gewählt, nicht besprochen): eigener Index mit Einbettungen (mehr Speicher, mehr Code, neue Daten im Store); nur die Wörter der Frage suchen, ohne Modell (Füllwörter wie „wann“ treffen fast jede Seite); vom Modell genannte Quellen statt aller übergebenen (das Modell kann Nummern erfinden); Antwort als neue Seite speichern; eigenes Fenster statt Blatt; Verlauf der Fragen.

**Entscheidung (16.5, Verwandte Seiten):**
- Seite › „Verwandte Seiten …“ (ohne Kürzel, unter „To-dos vorschlagen …“, gleiche Bedingung) speichert zuerst die offenen Editoren der Seite und zeigt in einem Blatt bis zu fünf Seiten zum selben Thema; ein Klick öffnet die Seite und schließt das Blatt. Unter jeder Seite stehen die gemeinsamen Begriffe, damit der Nutzer den Vorschlag einschätzen kann.
- Gleicher Weg wie bei „Frag deine Notizen“, gemeinsamer Code: Das Modell zieht aus Titel und Text der Seite (höchstens 6.000 Zeichen, sonst der Anfang) bis zu fünf Suchbegriffe, die vorhandene Suche findet die Seiten; Seiten mit den meisten Begriffen zuerst, die Seite selbst und der Papierkorb nie. Ohne Titel und Text fragt Quill das Modell nicht.
- Anweisung mit dem echten Modell auf diesem Mac verglichen (drei Notizen, je zweimal): „die wichtigsten Namen und Dinge“ lieferte Orte und Namen („Gardasee“, „Quill“, „Lisa“), „das Thema beschreiben“ eher allgemeine Wörter. Zusammengesetzte Wörter zerlegt das Modell auch mit ausdrücklicher Bitte nicht verlässlich („Urlaubsplanung“ findet „Urlaub“ nicht); hingenommen, weil die übrigen Begriffe meist genügen.
- „Link-Vorschläge“ heißt hier: Vorschläge, welche Seiten zusammengehören. Einen Link in die Seite einfügen kann Quill noch nicht, weil es keine Links auf Seiten gibt (eigenes URL-Schema steht unter „Später“ in der Roadmap).
- Alternativen (nicht gewählt, nicht besprochen): Link einfügen mit neuem URL-Schema (eigener Schritt mit Editor, Export und Sync); Ähnlichkeit ohne Modell über gemeinsame Wörter (braucht Wortlisten und Gewichte, findet Füllwörter); eigener Index mit Einbettungen (wie 16.4 verworfen); Leiste neben dem Editor, die sich bei jedem Seitenwechsel füllt (Modell bei jedem Wechsel, kostet Zeit und Strom); Begründung je Seite vom Modell (mehr Anfragen, kann erfinden).

**Entscheidung (Review von Phase 16):**
- Behoben: Text der KI wird nie bei markiertem Text (IME, tote Tasten) oder im Lesemodus eingefügt; „Einfügen“ erscheint nur, wenn der Editor beim Aufruf bearbeitbar war, und piept sonst statt still nichts zu tun (`BlockEditorController.acceptsInsertion`, `insertTyped`, `focused(in:)`). „Verwandte Seiten“ ohne Treffer zeigt den Leerzustand aus dem Katalog. „Schließen“ bricht eine laufende Frage ab. Fragen über 500 Zeichen lehnt Quill ab, ohne das Modell zu fragen (Frage und Notizen teilen sich das Kontextfenster). Die Verfügbarkeit wird auch beim Aktivieren eines Fensters neu geprüft, so erscheinen die Befehle, wenn das Modell fertig geladen ist, und verschwinden, wenn Apple Intelligence ausgeschaltet wurde. `check-release-binary.sh` sucht auch nach `QuillFakeAI`. „Ohne Titel“, Titel holen und Seite öffnen gibt es je nur einmal.
- Nicht geändert: Unter macOS 27 hat `LanguageModelError` keinen Fall für fehlende Modelldaten, ein solcher Fehler bleibt „gescheitert“. Die vier Blätter bekommen keinen gemeinsamen Rahmen und keine gemeinsame Phase: Inhalt und Knöpfe unterscheiden sich, ein Rahmen würde das verdecken; beim nächsten Blatt neu prüfen. Die Texthilfen bleiben in `PageSummarizer`. ⌘D (Duplizieren) weist jetzt wie die To-dos markierten Text und den Lesemodus ab, das ist gewollt (Editor-Regel). Die Beschriftung für Seiten ohne Titel in der Seitenliste (aus dem Audit) bleibt.
- Ohne eigenen UI-Test: Abbruch während der Arbeit (das Test-Modell antwortet sofort) und das neue Prüfen beim Aktivieren (das Test-Modell hat eine feste Verfügbarkeit je Start).

## ADR-033: Apple-Ökosystem auf dem Mac (2026-10-23, entsteht mit Phase 15)

**Kontext:** Phase 15 bindet Quill an Kurzbefehle, Siri, Spotlight, die Menüleiste, Mitteilungen und den Kalender an. Die iPhone-Teile sind pausiert (ADR-030). Die Teilen-Erweiterung braucht eine App Group und damit das Developer Program; sie bleibt offen, bis der Nutzer das Konto hat. Alle Anbindungen berühren Daten außerhalb des Stores (Spotlight-Index, Mitteilungen, Kalender) oder laufen über das System in die App hinein (Kurzbefehle); Tests dürfen weder den echten Store noch den echten Index, Kalender oder Mitteilungen des Macs berühren.

**Entscheidung (Plan):**
- Jeder Schritt einzeln, Logik in `QuillKit`, im App-Target nur, was das System dort verlangt.
- Was Daten außerhalb des Stores schreibt (Spotlight, Menüleiste mit Kürzel), ist pro Mac abschaltbar und im Zweifel aus, bis der Nutzer es einschaltet. Test-Stores schreiben nie dorthin; Tests nutzen Ersatz-Objekte.
- Kalender und Mitteilungen fragen erst, wenn der Nutzer die Funktion aufruft, nie beim Start.
- Jeder Schritt ergänzt hier seine Entscheidungen mit Alternativen.

**Entscheidung (15.1, Kurzbefehle und Siri):**
- Drei Aktionen: „Neue Seite“ (Titel und Text optional, legt am Ende der obersten Ebene an und öffnet die Seite), „Zu Seite hinzufügen“ (Text an eine gewählte Seite anhängen, im Hintergrund), „Seite öffnen“. Seiten als `PageEntity`, gesucht nur über den Titel (wie Siri einen Namen auflöst), ohne Papierkorb, die zuletzt bearbeiteten als Vorschlag. Siri-Sätze auf Deutsch, je zwei pro Aktion.
- „Zu Seite hinzufügen“ macht aus jeder nicht leeren Zeile einen Block und entfernt Objektzeichen (U+FFFC gehört zu Bildern). Endet die Seite mit einem To-do, einer Aufzählung oder einer Nummerierung, setzen die neuen Blöcke die Liste mit derselben Einrückung fort (so landet „Milch“ in der Einkaufsliste als To-do); sonst Absätze. Leere Blöcke am Ende bleiben am Ende. Vorher werden offene Editoren der Seite gespeichert, sonst fehlte die Liste, die gerade getippt wurde. Geschrieben wird über `PageStore.applyEdits`; ein offener Editor übernimmt die Blöcke wie aus dem Sync.
- Die Aktionen stehen in `QuillFeatures/Intents` und kommen über `AppIntentsPackage` in die App (die Metadaten liest Xcode auch aus dem Package). Die Siri-Sätze stehen im App-Target, denn aus dem Package liest Xcode sie nicht aus. Seitentitel für die Siri-Sätze meldet nur der echte Store (`QuillPersistence.isTestStore`): Debug-Builds haben dieselbe Kennung wie die echte App.
- „Seite öffnen“ geht über `PageJumpRouter.open`: vorderstes Hauptfenster, sonst ein neues. Die Weiterleitung an eine Szene (`TargetContentProvidingIntent`) gibt es auf dem Mac nicht.
- Texte, die das System aus den Metadaten liest (Titel, Beschreibungen, Siri-Sätze), stehen als Ausnahmen in `LocalizationTests`; Fehlermeldungen und die Antwort stehen im Katalog von QuillFeatures.
- Getestet im Package: die Logik (`PageIntentActionsTests`) und die Aktionen selbst ohne das System (`PageIntentsTests`). Ein UI-Test über das System (App Intents Testing, ab macOS 27) erreicht nicht die Test-Instanz: Für die Kennung sind mehrere Quill-Kopien registriert (`/Applications`, DerivedData, Worktrees), das System meldet „nicht vorhanden“. Die Test-Instanz selbst zu registrieren hieße, dass das System bei einem Kurzbefehl den Debug-Build startet, der ohne Testargument den echten Store öffnet; deshalb nicht. Öffnen ohne offenes Fenster und Siri prüft der Nutzer von Hand.
- Alternativen (nicht gewählt, nicht besprochen): Aktionen im App-Target (sicher ausgelesen, aber Logik und Tests getrennt von QuillKit); Liste per Parameter wählen statt fortsetzen (mehr Bedienung bei Siri); immer Absätze anhängen (die Einkaufsliste bekäme keine To-dos); eigenes URL-Schema zum Öffnen (würde bei mehreren Kopien die falsche App, womöglich mit dem echten Store, starten).
