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
