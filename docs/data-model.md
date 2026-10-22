# Datenmodell (SwiftData, CloudKit-tauglich; Sync über Ordner nach ADR-026)

## Regeln

- `id: UUID = UUID()` als fachliche ID
- `createdAt` / `updatedAt` an jedem Modell
- Jedes Attribut optional oder mit Default
- Kein `@Attribute(.unique)`
- Alle Beziehungen optional, mit Inverse
- Enums als `String`-Rohwert (`kindRaw`), damit unbekannte Werte späterer Versionen nicht crashen
- Von Anfang an `VersionedSchema` (`SchemaV1`, seit Phase 11.2 `SchemaV2`) + `SchemaMigrationPlan`
- Veröffentlichte Versionen sind eingefroren (Fingerabdruck-Test). Neue Version: `SchemaV(n)` + Stufe, `CurrentSchema` umstellen, Test „V(n-1) → V(n)“ in `MigrationTests` (ADR-011)

**Reihenfolge:** CloudKit kennt keine geordneten Beziehungen. Jedes sortierbare Objekt hat einen `sortKey: String` (Fractional Indexing). Verschieben ändert genau ein Objekt → wenige Sync-Konflikte.

## Modelle

```
Workspace
  id, name = "Mein Workspace", createdAt, updatedAt
  syncTree: Data? @Attribute(.externalStorage)   (V2: Seitenbaum als Automerge-Dokument)
  syncDeviceID: UUID?                     (V2: Geräte-ID im Sync-Ordner)
  syncCursors: Data?                      (V2: gelesene Dateien im Ordner, je Gerät)
  pages: [Page]?                         (cascade)

Page
  id, title = "", icon: String?          (Emoji)
  sortKey = "", isFavorite = false, favoriteSortKey: String?
  trashedAt: Date?                       (nil = aktiv; Kinder erben Papierkorb logisch)
  kindRaw = "page"                       ("page" | später "database")
  createdAt, updatedAt
  syncDocument: Data? @Attribute(.externalStorage)   (V2: Blöcke als Automerge-Dokument)
  isRestored = false                     (V2: vom Sync wiederhergestellt)
  workspace: Workspace?
  parent: Page?          ⇄ children: [Page]?        (cascade)
  blocks: [Block]?                                   (cascade)
  -- später:
  propertyDefinitions: [PropertyDefinition]?  (Page = Datenbank)
  propertyValues: [PropertyValue]?            (Page = Zeile)
  views: [DatabaseView]?

Block
  id, kindRaw = "paragraph"   (paragraph|heading1-3|bulleted|numbered|todo|quote|code|divider|image)
  sortKey = "", indent = 0    (flache Liste + Einrückungsstufe)
  text = ""                   (Klartext → Suche, Export)
  richText: Data?             (RichText-JSON, nil ohne Formatierung; siehe unten)
  isChecked = false, codeLanguage: String?
  isRestored = false          (V2, Teil von BlockProperties: vom Sync wiederhergestellt)
  createdAt, updatedAt
  page: Page?
  asset: Asset?                                     (cascade)

Asset
  id, data: Data? @Attribute(.externalStorage)    (→ später CKAsset)
  uti = "public.png", pixelWidth = 0, pixelHeight = 0, createdAt, updatedAt
  block: Block?

PropertyDefinition   (später)  id, name, typeRaw, optionsJSON: Data?, sortKey, database: Page?, values: [PropertyValue]?
PropertyValue        (später)  id, valueJSON: Data?, definition: PropertyDefinition?, page: Page?
DatabaseView         (später)  id, name, layoutRaw (table|board|calendar), configJSON: Data?, sortKey, database: Page?
```

`DatabaseView` statt `View`, um Konflikte mit `SwiftUI.View` zu vermeiden.

## Zugriff

- Schreiben über einen `@ModelActor`-Store `PageStore` (`createPage`, `move`, `trash`, `restore`, `applyEdits`).
- Lesen in der UI über `@Query`.
- `richText` ist bewusst kein `NSAttributedString`-Archiv: plattformneutral (iOS), diff-bar, exportierbar.

### Format von `Block.richText`

```json
{"runs":[{"marks":[],"text":"Hallo "},{"link":"https://apple.com","marks":["bold"],"text":"Welt"}],"version":1}
```

- `RichText` in `QuillModel`: `version` (aktuell 1) und `runs` mit `text`, `marks` (sortierte Rohwerte `bold`, `italic`, `code`, `strikethrough`) und optional `link`. Kodiert mit sortierten Schlüsseln: gleicher Inhalt ergibt gleiche Bytes.
- `nil`, solange ein Block keine Formatierung hat. `Block.text` bleibt immer der vollständige Klartext (Suche, Export).
- Unbekannte Marks bleiben beim Lesen und Schreiben erhalten. Passt der Text der Runs nicht zu `Block.text`, gilt `Block.text` ohne Formatierung; unlesbare Daten werden ebenso behandelt.
- Neue Felder nur additiv und optional; ein anderer Aufbau bekommt eine neue `version`.

### Blöcke schreiben: `PageStore.applyEdits`

- Einfache Felder (`indent`, `isChecked`, `codeLanguage`, `assetID`) reisen als `BlockProperties`; `Block.properties` ist die einzige Abbildung auf Spalten und die Beziehung `asset` (ADR-014, ADR-015).
- Bilder: `PageStore.importImage` legt ein `Asset` ohne Block an (GPS entfernt, über 20 MB auf 4096 px verkleinert), das Speichern des Blocks verknüpft es. Beim Löschen eines Blocks wird sein Asset gelöst statt mitgelöscht (Undo); `removeOrphanedAssets` löscht beim Start Assets, die seit der gewählten Frist keinem Block gehören (Einstellungen › Zeitreise, Standard 90 Tage, „Immer“ löscht nie; ADR-031).

- Eingabe `BlockEdits`: `upserts` (neue oder geänderte `BlockSnapshot`s: `id`, `kindRaw`, `text`, `richText`, `properties`), `deletions` und optional `order` (IDs in gewünschter Reihenfolge). Die `EditorPersistenceBridge` schickt nur Blöcke, die sich gegenüber dem zuletzt gespeicherten Stand geändert haben, und zwar über `applyEdits(_:_:expected:)`: geschrieben wird nur, wenn die Seite noch dem Stand entspricht, von dem der Editor ausging; sonst `nil`, und die Bridge führt zusammen (`BlockMerge`, ADR-029 Review).
- `updatedAt` ändert sich nur bei Blöcken mit echten Änderungen, `Page.updatedAt` nur, wenn sich überhaupt etwas geändert hat.
- Reihenfolge: Die längste schon richtig sortierte Teilfolge behält ihre `sortKey`s; nur die übrigen Blöcke bekommen neue Schlüssel (`FractionalIndex.keys(count:between:and:)`). Blöcke, die in `order` fehlen (z. B. aus einem anderen Fenster), bleiben unverändert; neue Schlüssel werden so gewählt, dass sie nie mit deren Schlüsseln zusammenfallen.
- Unbekannte `kindRaw`-Werte (spätere Versionen) bleiben erhalten, solange der Block im Editor nicht bearbeitet wird; angezeigt werden sie als Absatz.

### Schreiben durch den Sync (Phase 11.3, ADR-029)

- `PageStore+Sync`: `applySyncTree` (Seiten anlegen, ändern, in den Papierkorb legen, nie löschen) und `applySyncPage` (Blöcke als `BlockEdits`) speichern zusammen mit dem Sync-Dokument und den gelesenen Dateien in einem Schritt. Beide erwarten den Stand, von dem der Abgleich ausging; weicht der Store ab, schreiben sie nichts.
- `PageSnapshot` ist die Seite als Werttyp (wie `BlockSnapshot`). Bilder aus dem Ordner legt `insertSyncedAsset` unverändert an.
- `Workspace.syncCursors`: JSON mit der letzten übernommenen Datei je Dokument und Gerät und `updatedAt` je Seite beim letzten Abgleich.
- `resetSyncCursors` (seit 11.4) vergisst nur die gelesenen Dateien, nicht die Sync-Dokumente samt Geschichte: vor dem Verbinden mit einem anderen Ordner. Der erste Abgleich schreibt dann jedes Dokument als ganzen Stand in den neuen Ordner (ADR-029).

## Speicherort und Backups

- Store: `~/Library/Containers/io.github.vogelwild07.quill/Data/Library/Application Support/Quill/Store/Quill.store` (plus `-wal`, `-shm`, `.Quill_SUPPORT/` für externe Daten, `Quill.store.version`). Bis Phase 7.1 lagen diese Dateien direkt in `Quill/`; der erste Start einer neueren Version zieht sie nach einem Backup `vor-umzug` um. Gibt es `Store/` schon, kommen Reste im alten Ort in ein Backup `beiseitegelegt` (ADR-019).
- Backups: daneben in `Backups/`, Regeln siehe ADR-010. Vor dem Einschalten des Sync immer ein Backup `vor-sync`; es wird nie automatisch gelöscht (Rückweg, ADR-029).

### Migration auf ein neues Schema (seit Phase 11.2, ADR-029)

Öffnet eine neuere Version einen Store mit älterem Schema (oder ohne `Quill.store.version`), fragt Quill zuerst, nach dem Start der App: „Datenbank umstellen?“ mit „Beenden“ (Standard, Return und Escape) und „Umstellen“ (nur per Klick).

- „Beenden“: Quill endet ohne Backup und ohne Änderung; der Store bleibt byte-gleich.
- „Umstellen“: Backup `vor-migration-<alt>-<neu>` (wird nie automatisch gelöscht), dann die Migration. Scheitert das Backup, öffnet Quill nicht.
- Rückweg: In der neuen Version das Backup „vor Migration“ einspielen; beim Neustart fragt Quill wieder, dort „Beenden“; danach öffnet die ältere Version den Stand aus dem Backup.
- Test-Stores (`-QuillInMemoryStore`, `-QuillStoreDirectory`) fragen nur mit `-QuillAskBeforeMigration YES`; `-QuillSeedSchemaV1 YES` legt im Test-Ordner einen Store im alten Format an (beides nur Debug).

### Backup wiederherstellen

In der App: Ablage › „Backup wiederherstellen …“, Backup wählen, bestätigen. Quill beendet sich und spielt es beim nächsten Start ein; der vorherige Stand bleibt als Backup „Vor dem Wiederherstellen“ (ADR-019).

### Backup von Hand wiederherstellen

Nur falls Quill nicht mehr startet:

1. Quill beenden.
2. Im Finder den Ordner `…/Application Support/Quill/` öffnen (⇧⌘G, Pfad oben). Versteckte Dateien mit ⇧⌘. einblenden.
3. Den Ordner `Store/` als Ganzes in einen eigenen Ordner außerhalb verschieben, nicht löschen.
4. Einen neuen, leeren Ordner `Store/` anlegen und aus `Backups/<Zeitpunkt>_<Anlass>/` die Dateien `Quill.store`, falls vorhanden `Quill.store-wal` und `Quill.store-shm` (immer zusammen) sowie `.Quill_SUPPORT` hineinkopieren.
5. Keine `Quill.store.version` mitkopieren. Beim nächsten Start entsteht dann vorsorglich ein Backup `vor-migration-unbekannt-…`, und eine nötige Migration läuft normal.
6. Quill starten.

### Umzug aus `de.vogel.quill` (einmalig, vor v0.1.0)

Bis Phase 8 hieß die Bundle-ID `de.vogel.quill` (ADR-022). Eine neue Bundle-ID bekommt einen neuen, leeren Sandbox-Container; die App selbst darf den alten nicht lesen. Der Umzug läuft deshalb einmal von Hand über „Backup wiederherstellen“:

1. In der alten Quill eine bleibende Änderung machen, z. B. eine neue Seite „Umzug“ anlegen, dann Quill beenden. Nur nach einer Änderung entsteht beim Beenden ein Backup `<Zeitpunkt>_beenden`, das sicher den aktuellen Stand enthält.
2. Sicherung: Im Finder ⇧⌘G, `~/Library/Containers/de.vogel.quill/Data/Library/Application Support/` öffnen und den Ordner `Quill` mit gedrückter ⌥-Taste nach `~/Documents/` ziehen (kopiert ihn). Den Ordner `Quill-Sicherung-<Datum>` nennen. Den alten Container nicht verändern.
3. Die neue Quill (`io.github.vogelwild07.quill`) einmal starten und wieder beenden. Dabei legt macOS den neuen Container an.
4. In `~/Library/Containers/de.vogel.quill/Data/Library/Application Support/Quill/Backups/` den neuesten Ordner `…_beenden` (Zeit in UTC) als Ganzes nach `~/Library/Containers/io.github.vogelwild07.quill/Data/Library/Application Support/Quill/Backups/` kopieren; fehlt dort `Backups/`, den Ordner anlegen. Fragt macOS, ob der Zugriff auf Daten einer anderen App erlaubt werden soll, **erlauben**, sonst scheitert das Kopieren. Die Kopie dann umbenennen: Endung `_beenden` durch `_vor-umzug` ersetzen (z. B. `2026-10-19T20-15-03Z_vor-umzug`). Sonst räumt der nächste Start sie weg, weil das Backup aus Schritt 3 vom selben Tag jünger ist; Backups `vor-umzug` bleiben immer (`StoreMoveBackupTests`).
5. Die neue Quill starten, Ablage › „Backup wiederherstellen …“, das kopierte Backup („Vor dem Umzug des Speicherorts“) wählen und bestätigen. Quill beendet sich; beim nächsten Start ist der Stand da, der leere Stand bleibt als Backup „Vor dem Wiederherstellen“.
6. Seiten, Bilder, Favoriten und Papierkorb prüfen. Alter Container und Sicherung bleiben unverändert liegen.
