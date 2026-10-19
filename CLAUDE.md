# CLAUDE.md – Quill

Local-first, Notion-ähnliche macOS-App. Rolle: Senior Product Designer, macOS-Architekt, Swift-Entwickler.

**Stand:** Phase 6 (Export) fertig, gemergt (PR #6, ADR-018, Review-Fixes drin). Nächstes: Phase 7 (Feinschliff). Neue Ideen nur unter „Später“ in `docs/roadmap.md`. Bekannte Probleme + Plan: `docs/roadmap.md`.

## Kommunikation
- Immer **Deutsch**. Kurz ok; Warnungen, Sicherheit, Entscheidungen in ganzen Sätzen.
- Regeln hier vor Skill-Workflows.

## Stack (fix)
- macOS 26+, nur Apple Silicon; später iPhone/iPad → Logik in `Packages/QuillKit`, App-Target dünn.
- Swift 6 (strikte Concurrency), SwiftUI, AppKit nur wo nötig, SwiftData lokal. Sync später CloudKit.
- Editor: eigener Block-Editor auf TextKit 2 / `NSTextView` (siehe `docs/architecture.md`).
- Tests: Swift Testing (Unit), XCUITest (UI). Bundle-ID `de.vogel.quill`.
- UI-Tests starten App immer via `XCUIApplication.quill()` (ignoriert gespeicherten Fensterzustand, ADR-008; Store nur im RAM via `-QuillInMemoryStore YES`). Nie gegen echten Store testen. Kopieren/Einsetzen-Tests nutzen eigene Zwischenablage (`-QuillPasteboardName`), nie allgemeine.
- Build + Tests (App, Package, alle Test-Targets) **ohne Compiler-Warnungen**; neue Warnungen sofort beheben, nicht stummschalten. UI-Testklassen `@MainActor`, `setUp()`/`tearDown()` als `async throws` (`…WithError`-Varianten nonisolated).
- UI-Strings lokalisierbar (`Localizable.xcstrings`), Ausgangssprache Deutsch.

## Datenmodell-Regeln (CloudKit-tauglich)
UUID-`id`, `createdAt`/`updatedAt`, alle Attribute optional oder mit Default, **kein** `.unique`, Beziehungen optional mit Inverse, Enums als String-Rohwert, Reihenfolge per `sortKey`. Schemaänderung nur via neues `VersionedSchema` + Migration; `SchemaV1` eingefroren (Fingerabdruck-Test), jede neue Version braucht Test „V(n-1) → V(n)“ (ADR-011). Schreiben nur via `PageStore`. Details: `docs/data-model.md`.

## Editor (ADR-007)
- Ein `NSTextView` pro Seite, Absatz = Block. Jeder Absatz endet mit `\n`, auch letzter; Block-Attribute (`.quillBlockID` …) auf **jedem** Zeichen. Weicher Umbruch = U+2028, atomare Blöcke = U+FFFC.
- Tippen im Absatz macht TextView; strukturelle Edits immer via `EditorDocument` als Diff via `shouldChangeText`/`replaceCharacters`/`didChangeText` (sonst kein Undo). Bei markiertem Text (IME, tote Tasten) nie eingreifen.
- Fallstricke: Fragment-Koordinaten ab Textanfang (mit `layoutFragmentFrame.minX` umrechnen). TextKit 2 zeichnet `NSTextAttachment.image(for:…)` unzuverlässig. `prepareForDragOperation` muss eigene Drag-Typen annehmen. Vor Markdown-Kürzeln `breakUndoCoalescing()`.
- Neue einfache Block-Felder nur via `BlockProperties` (ADR-014); Textattribute nur `Int`/`Bool`/`String`-Werte, kein Struct (AppKit muss archivieren). `BlockPropertiesRoundTripTests` erzwingt Testwerte pro Feld.
- `BlockKind` nur in `QuillModel`. Switches über Blockart ohne `default:`; neue Arten müssen `BlockKindCoverageTests` bestehen.
- Inline-Formatierung: `.quillMarks` + `.link` im Textspeicher = Quelle, Schrift/Farbe abgeleitet. Gespeichert als `Block.richText` (`RichText`-JSON, `nil` ohne Formatierung). Blöcke schreibt nur `EditorPersistenceBridge` via `PageStore.applyEdits` (ADR-013).
- Speichern darf nie still scheitern: Bridge wiederholt mit Backoff, Seite zeigt `lastError`, Beenden fragt via `QuitGuard`. Neuladen aus anderen Fenstern nie bei markiertem Text.
- Test-Beispieldokumente nur aus `SampleDocuments` (Target `QuillTestFixtures`, Tests/QuillTestFixtures).
- Selbst gezeichnete Elemente nur Systemfarben; SF Symbols nicht mit `NSColor.set()` einfärben (bleibt schwarz). Hell + dunkel per `EditorSnapshotTests` prüfen.

## Design
Apple HIG, Liquid Glass nur Sidebar/Toolbars/Popover, nicht Inhalt. SF Pro / SF Mono, Systemfarben, Dark Mode automatisch. Tokens in `QuillDesign`, Details `docs/design.md`.

## Tools
- **XcodeBuildMCP** für Bauen/Testen/Starten (macOS-Workflow). Fallback: `xcodebuild`.
- **Keine Bildschirmfotos oder -aufnahmen des Macs**, auch nicht zur Kontrolle (kein `screencapture`, keine Screenshot-Tools). App nur via Bedienungshilfen (AX), XCUITest oder App-eigene Snapshots (z. B. `-snapshot`) prüfen.
- **Context7 / Apple-Doku:** SwiftUI-/SwiftData-/TextKit-APIs immer gegen aktuelle Doku prüfen.
- **REA:** nur lawful Research am lokalen Notion, nur Verhalten beobachten. Keinen Notion-Code übernehmen/nachbauen. Ergebnisse nach `docs/research/`.
- **Notion-MCP:** nur lesend (`search`, `fetch`). Nie im Notion des Nutzers anlegen, ändern, löschen.
- Kein Notion-Code, keine Notion-Assets, -Marken, -Texte, -Designs kopieren.

<!-- graphify-rules-start (managed by `graphify init`) -->
## Use Graphify before grep

This repository is indexed by Graphify: a code graph over its call, dependency, and test structure, exposed through a connected Graphify MCP server. Before reaching for grep or reading files, use the Graphify tools your MCP client lists (their exact names and descriptions are in the server's tool list) for what the graph knows and a text search does not:

- find where a symbol, function, or class is defined (instead of grepping for it)
- understand how something works, or where a behavior is handled
- find who calls a function, or what it calls
- see what a change affects (its blast radius) and which tests cover it
- map a file's dependencies and dependents

Fall back to grep or file reads only for what the graph does not model: literal string or comment matches, non-indexed files, or reading a file you have already located. If no Graphify tools are listed, check the MCP server connection.
<!-- graphify-rules-end -->

- Graphify = externer Dienst, liest GitHub-Stand, nicht lokalen Mac. Ungepushte Änderungen fehlen dort → lokal lesen.
- Nur Code + Doku aus diesem Repo. Nie Inhalte aus meinem echten Store, Backups, Notion, Secrets oder Dateien außerhalb Repo. Im Zweifel vorher fragen.

## Git
- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`), kleine Commits.
- Auf `main` nur gebauter, getesteter Stand. Größere Änderungen: Branch + PR.
- Vor jedem Push `git status` + `git diff --staged` prüfen. Im Zweifel fragen.
- Gegenproben (absichtliche Fehler) nie mit `git checkout`/`git restore` zurücksetzen, sondern aus vorher angelegter Dateikopie (Scratchpad). Sonst gehen uncommittete Änderungen verloren.
- Gemergte Phasen-Branches direkt nach Merge lokal + auf GitHub löschen (`git branch -d`, `git push origin --delete`), ohne Rückfrage. Nur wenn Merge bestätigt.
- Signier-Team (Personal Team des Nutzers) nur in `Config/Local.xcconfig` (git-ignoriert, nie committen), nie in `project.pbxproj`. Setzt Xcode dort `DEVELOPMENT_TEAM`, Zeile entfernen. `project.pbxproj` nur gezielt stagen; Xcode-Nebenänderungen (z. B. Scheme-`version`) nicht mitcommitten.
- Niemals committen: `.env`, Keys, Tokens, Zertifikate, Provisioning-Profile, Datenbanken, Backups, private Notizen.
- Aktuell halten: `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/decisions.md`.

## Befehle
```sh
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' build
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' test
swift test --package-path Packages/QuillKit

# Darstellung hell/dunkel als PNG nach $TMPDIR/QuillEditorSnapshots/
swift test --package-path Packages/QuillKit --filter EditorSnapshotTests
```
