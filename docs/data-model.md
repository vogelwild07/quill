# Datenmodell (SwiftData, CloudKit-tauglich)

## Regeln

- `id: UUID = UUID()` als fachliche ID
- `createdAt` / `updatedAt` an jedem Modell
- Jedes Attribut optional oder mit Default
- Kein `@Attribute(.unique)`
- Alle Beziehungen optional, mit Inverse
- Enums als `String`-Rohwert (`kindRaw`), damit unbekannte Werte späterer Versionen nicht crashen
- Von Anfang an `VersionedSchema` (`SchemaV1`) + `SchemaMigrationPlan`
- Veröffentlichte Versionen sind eingefroren (Fingerabdruck-Test). Neue Version: `SchemaV(n)` + Stufe, `CurrentSchema` umstellen, Test „V(n-1) → V(n)“ in `MigrationTests` (ADR-011)

**Reihenfolge:** CloudKit kennt keine geordneten Beziehungen. Jedes sortierbare Objekt hat einen `sortKey: String` (Fractional Indexing). Verschieben ändert genau ein Objekt → wenige Sync-Konflikte.

## Modelle

```
Workspace
  id, name = "Mein Workspace", createdAt, updatedAt
  pages: [Page]?                         (cascade)

Page
  id, title = "", icon: String?          (Emoji)
  sortKey = "", isFavorite = false, favoriteSortKey: String?
  trashedAt: Date?                       (nil = aktiv; Kinder erben Papierkorb logisch)
  kindRaw = "page"                       ("page" | später "database")
  createdAt, updatedAt
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
- Bilder: `PageStore.importImage` legt ein `Asset` ohne Block an (GPS entfernt, über 20 MB auf 4096 px verkleinert), das Speichern des Blocks verknüpft es. Beim Löschen eines Blocks wird sein Asset gelöst statt mitgelöscht (Undo); `removeOrphanedAssets` löscht beim Start Assets, die seit 30 Tagen keinem Block gehören.

- Eingabe `BlockEdits`: `upserts` (neue oder geänderte `BlockSnapshot`s: `id`, `kindRaw`, `text`, `richText`, `properties`), `deletions` und optional `order` (IDs in gewünschter Reihenfolge). Die `EditorPersistenceBridge` schickt nur Blöcke, die sich gegenüber dem zuletzt gespeicherten Stand geändert haben.
- `updatedAt` ändert sich nur bei Blöcken mit echten Änderungen, `Page.updatedAt` nur, wenn sich überhaupt etwas geändert hat.
- Reihenfolge: Die längste schon richtig sortierte Teilfolge behält ihre `sortKey`s; nur die übrigen Blöcke bekommen neue Schlüssel (`FractionalIndex.keys(count:between:and:)`). Blöcke, die in `order` fehlen (z. B. aus einem anderen Fenster), bleiben unverändert; neue Schlüssel werden so gewählt, dass sie nie mit deren Schlüsseln zusammenfallen.
- Unbekannte `kindRaw`-Werte (spätere Versionen) bleiben erhalten, solange der Block im Editor nicht bearbeitet wird; angezeigt werden sie als Absatz.

## Speicherort und Backups

- Store: `~/Library/Containers/de.vogel.quill/Data/Library/Application Support/Quill/Quill.store` (plus `-wal`, `-shm`, `.Quill_SUPPORT/` für externe Daten, `Quill.store.version`).
- Backups: daneben in `Backups/`, Regeln siehe ADR-010.

### Backup von Hand wiederherstellen

1. Quill beenden.
2. Im Finder den Ordner `…/Application Support/Quill/` öffnen (⇧⌘G, Pfad oben). Versteckte Dateien mit ⇧⌘. einblenden.
3. Die aktuellen Dateien `Quill.store`, `Quill.store-wal`, `Quill.store-shm` und `.Quill_SUPPORT` in einen eigenen Ordner außerhalb verschieben, nicht löschen.
4. Aus `Backups/<Zeitpunkt>_<Anlass>/` die Datei `Quill.store` und, falls vorhanden, `.Quill_SUPPORT` nach `…/Quill/` kopieren.
5. `Quill.store.version` löschen. Beim nächsten Start entsteht dann vorsorglich ein Backup `vor-migration-unbekannt-…`, und eine nötige Migration läuft normal.
6. Quill starten.
