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
- **Aufbewahrung:** je das neueste Backup der letzten 7 Tage mit Backup, dazu je das neueste der 4 Wochen davor. Backups vor einer Migration werden nie automatisch gelöscht.
- **Wiederherstellen:** in Phase 2 von Hand (Anleitung in `data-model.md`). Menüpunkt „Backup wiederherstellen…“ mit Tests in Phase 7, Pflicht vor v0.1.
**Konsequenzen:** Speicherbedarf etwa elffacher Store plus Migrations-Backups. Externe Daten werden ohne Snapshot kopiert; ein Bild, das genau während des Backups entsteht, kann im Backup fehlen.
