# CLAUDE.md – Quill

Local-first, Notion-ähnliche macOS-App. Rolle: Senior Product Designer, macOS-Architekt, Swift-Entwickler.

**Stand:** Phase 2 (Datenmodell + Sidebar) abgeschlossen: `SchemaV1`, `PageStore`, Backups (ADR-010), Migrationstests (ADR-011), Sidebar als `NSOutlineView` (ADR-012). Nächste Phase: 3 (Editor Text). Plan: `docs/roadmap.md`.

## Kommunikation
- Immer **Deutsch**. Kurz ist gut; Warnungen, Sicherheit und Entscheidungen in ganzen Sätzen.
- Regeln dieser Datei haben Vorrang vor Workflows aus Skills.

## Stack (fix)
- macOS 26+, nur Apple Silicon; später iPhone/iPad → Logik in `Packages/QuillKit`, App-Target dünn.
- Swift 6 (strikte Concurrency), SwiftUI, AppKit nur wo nötig, SwiftData lokal. Sync später CloudKit.
- Editor: eigener Block-Editor auf TextKit 2 / `NSTextView` (siehe `docs/architecture.md`).
- Tests: Swift Testing (Unit), XCUITest (UI). Bundle-ID `de.vogel.quill`.
- UI-Tests starten die App immer über `XCUIApplication.quill()` (ignoriert gespeicherten Fensterzustand, ADR-008; Store nur im Arbeitsspeicher via `-QuillInMemoryStore YES`). Tests nie gegen den echten Store laufen lassen.
- UI-Strings lokalisierbar (`Localizable.xcstrings`), Ausgangssprache Deutsch.

## Datenmodell-Regeln (CloudKit-tauglich)
UUID-`id`, `createdAt`/`updatedAt`, alle Attribute optional oder mit Default, **kein** `.unique`, Beziehungen optional mit Inverse, Enums als String-Rohwert, Reihenfolge per `sortKey`. Schemaänderungen nur über neues `VersionedSchema` + Migration; `SchemaV1` ist eingefroren (Fingerabdruck-Test), jede neue Version braucht einen Test „V(n-1) → V(n)“ (ADR-011). Schreiben nur über `PageStore`. Details: `docs/data-model.md`.

## Editor (ADR-007)
- Ein `NSTextView` pro Seite, ein Absatz = ein Block. Jeder Absatz endet mit `\n`, auch der letzte; Block-Attribute (`.quillBlockID` …) liegen auf **jedem** Zeichen. Weicher Umbruch = U+2028, atomare Blöcke = U+FFFC.
- Tippen innerhalb eines Absatzes macht die TextView; strukturelle Edits immer über `EditorDocument` und als Diff via `shouldChangeText`/`replaceCharacters`/`didChangeText` (sonst kein Undo). Bei markiertem Text (IME, tote Tasten) nie eingreifen.
- Fallstricke: Fragment-Koordinaten beginnen am Textanfang (mit `layoutFragmentFrame.minX` umrechnen). TextKit 2 zeichnet `NSTextAttachment.image(for:…)` nicht zuverlässig. `prepareForDragOperation` muss eigene Drag-Typen annehmen. Vor Markdown-Kürzeln `breakUndoCoalescing()`.
- `QuillEditorSpike` und `Spikes/EditorSpike` sind Wegwerf-Code: nicht erweitern. Überführung nach `QuillEditor` und Löschen in Phase 3 laut ADR-007.

## Design
Apple HIG, Liquid Glass nur für Sidebar/Toolbars/Popover, nicht für Inhalt. SF Pro / SF Mono, Systemfarben, Dark Mode automatisch. Tokens in `QuillDesign`, Details `docs/design.md`.

## Tools
- **XcodeBuildMCP** zum Bauen/Testen/Starten (macOS-Workflow). Fallback: `xcodebuild`.
- **Keine Bildschirmfotos oder Bildschirmaufnahmen des Macs**, auch nicht zur Kontrolle (kein `screencapture`, keine Screenshot-Tools). Die App nur über Bedienungshilfen (AX), XCUITest oder Snapshots aus der App selbst (z. B. `-snapshot`) prüfen.
- **Context7 / Apple-Doku:** SwiftUI-/SwiftData-/TextKit-APIs immer gegen aktuelle Doku prüfen.
- **REA:** nur lawful Research am lokalen Notion, nur Verhalten beobachten. Keinen Notion-Code übernehmen oder nachbauen. Ergebnisse nach `docs/research/`.
- **Notion-MCP:** nur lesend (`search`, `fetch`). Nie etwas im Notion des Nutzers anlegen, ändern oder löschen.
- Kein Notion-Code, keine Notion-Assets, -Marken, -Texte oder -Designs kopieren.

## Git
- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`), kleine Commits.
- Auf `main` nur gebauter, getesteter Stand. Größere Änderungen: Branch + PR.
- Vor jedem Push `git status` und `git diff --staged` prüfen. Im Zweifel fragen.
- Gemergte Phasen-Branches direkt nach dem Merge lokal und auf GitHub löschen (`git branch -d`, `git push origin --delete`), ohne Rückfrage. Nur wenn der Merge bestätigt ist.
- `DEVELOPMENT_TEAM`-Zeilen in `project.pbxproj` sind lokal (Personal Team des Nutzers) und werden nie committet. `project.pbxproj` deshalb nur gezielt stagen; Xcode-Nebenänderungen (z. B. Scheme-`version`) nicht mitcommitten.
- Niemals committen: `.env`, Keys, Tokens, Zertifikate, Provisioning-Profile, Datenbanken, Backups, private Notizen.
- Aktuell halten: `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/decisions.md`.

## Befehle
```sh
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' build
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' test
swift test --package-path Packages/QuillKit

# Editor-Spike (bis Phase 3): Scheme „EditorSpike“
#   -benchmark  misst 1000 Blöcke, JSON auf stdout
#   -snapshot   PNGs hell/dunkel nach ~/Library/Containers/de.vogel.quill.EditorSpike/Data/tmp/
```
