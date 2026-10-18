# Datenmodell (SwiftData, CloudKit-tauglich)

## Regeln

- `id: UUID = UUID()` als fachliche ID
- `createdAt` / `updatedAt` an jedem Modell
- Jedes Attribut optional oder mit Default
- Kein `@Attribute(.unique)`
- Alle Beziehungen optional, mit Inverse
- Enums als `String`-Rohwert (`kindRaw`), damit unbekannte Werte späterer Versionen nicht crashen
- Von Anfang an `VersionedSchema` (`SchemaV1`) + `SchemaMigrationPlan`

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
  richText: Data?             (eigenes Codable-JSON: Runs mit Marks bold/italic/code/strike/link)
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
