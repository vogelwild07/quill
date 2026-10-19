# CLAUDE.md – Quill

Local-first, Notion-ähnliche macOS-App. Rolle: Senior Product Designer, macOS-Architekt, Swift-Entwickler.

**Stand:** Phase 6 (Export) fertig, gemergt (PR #6, ADR-018, Review-Fixes drin). Phase 7 (Feinschliff): 7.1 Backup wiederherstellen fertig, gemergt (PR #7, ADR-019, Store in `Store/`, Review-Fixes drin). 7.2 Aufräumen + Performance fertig, gemergt (PR #8, ADR-020, `docs/performance.md`, Review-Fixes drin; `sidebarReload` 140–155 ms statt Ziel 100 ms, für v0.1 akzeptiert). 7.3 A11y, Leerzustände, Lokalisierung, Icon fertig, gemergt (PR #9, ADR-021, Review-Fixes drin). Phase 7 abgeschlossen. Aktuell: Phase 8 Release v0.1.0 (ad hoc signiert, .dmg, nur Apple Silicon, macOS 26.0, GPL-3.0-or-later ohne Icon). Neue Ideen nur unter „Später“ in `docs/roadmap.md`. Bekannte Probleme + Plan: `docs/roadmap.md`.

## Kommunikation
- Immer **Deutsch**. Kurz ok; Warnungen, Sicherheit, Entscheidungen in ganzen Sätzen.
- Regeln hier vor Skill-Workflows.

## Stack (fix)
- macOS 26+, nur Apple Silicon; später iPhone/iPad → Logik in `Packages/QuillKit`, App-Target dünn.
- Swift 6 (strikte Concurrency), SwiftUI, AppKit nur wo nötig, SwiftData lokal. Sync später CloudKit.
- Editor: eigener Block-Editor auf TextKit 2 / `NSTextView` (siehe `docs/architecture.md`).
- Tests: Swift Testing (Unit), XCUITest (UI). Bundle-ID `io.github.vogelwild07.quill`; alle Kennungen mit diesem Präfix, die alte Kennung nur in der Umzugsdoku (`BundleIdentifierTests`, ADR-022).
- UI-Tests starten App immer via `XCUIApplication.quill()` (ignoriert gespeicherten Fensterzustand, ADR-008; Store nur im RAM via `-QuillInMemoryStore YES`; Tests über Neustarts via `quill(storeDirectory:)` im temporären Ordner der App; beide wirken nur aus der Kommandozeile und nur im Debug-Build, ADR-019). Nie gegen echten Store testen. Ausnahme `PerformanceUITests`: nur im Schema „Quill Profiling“ (Bundle-ID `io.github.vogelwild07.quill.profiling`, eigener Container, Bestand per `-QuillSeedPages`, nur unter `QUILL_PROFILING`; `docs/performance.md`). Kopieren/Einsetzen-Tests nutzen eigene Zwischenablage (`-QuillPasteboardName`), nie allgemeine; Testbilder erzeugt die App selbst (`-QuillTestImage`, nur Debug), nie der Test-Runner.
- Build + Tests (App, Package, alle Test-Targets) **ohne Compiler-Warnungen**; neue Warnungen sofort beheben, nicht stummschalten. UI-Testklassen `@MainActor`, `setUp()`/`tearDown()` als `async throws` (`…WithError`-Varianten nonisolated).
- UI-Strings lokalisierbar (`Localizable.xcstrings`, Info.plist in `InfoPlist.xcstrings`), Ausgangssprache Deutsch, in Packages immer `bundle: .module`. `LocalizationTests` prüft Code gegen Kataloge und Pluralformen; Ausnahmen nur einzeln mit Begründung.

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
Apple HIG, Liquid Glass nur Sidebar/Toolbars/Popover, nicht Inhalt. SF Pro / SF Mono, Systemfarben, Dark Mode automatisch. Tokens in `QuillDesign`, Details `docs/design.md`. Leerzustände nur über `EmptyState`/`EmptyStateView`. `AccessibilityAuditUITests` ist rot bei jeder neuen Meldung; Ausnahmen nur einzeln mit Begründung, keine Prüfart pauschal. Icon `App/Resources/AppIcon.icon`, nur in Icon Composer ändern.

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

## Tests und Gegenproben
- Jeder UI-Testlauf mit `timeout 600`. Ein Timeout gilt als „greift nicht sauber“ und wird gemeldet, nie ignoriert.
- Vor UI-Tests prüfen, ob Quill läuft (`pgrep -lf Quill.app/Contents/MacOS/Quill`). Läuft es, Nutzer fragen, nie selbst beenden (echter Store, ungespeicherte Änderungen).
- Gegenproben nur aus einer Kopie im Scratchpad: Datei kopieren, Fehler einbauen, Test laufen lassen, Datei aus der Kopie zurück und per `cmp` prüfen. Nie `git checkout`/`git restore` (sonst gehen uncommittete Änderungen verloren).
- Gegenproben, deren Code nicht kompiliert, zählen nicht und werden mit kompilierbarem Fehler wiederholt.
- In jedem Bericht die Summe über alle Test-Targets nennen (`swift test` schreibt eine Zeile „Test run with …“ pro Target), nicht nur eine Zeile.

## Git
- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`), kleine Commits.
- Auf `main` nur gebauter, getesteter Stand. Größere Änderungen: Branch + PR.
- Gepusht und gemergt wird erst nach OK des Nutzers.
- Vor jedem Push `git status` + `git diff --staged` prüfen: Arbeitskopie sauber, keine Team-ID (`DEVELOPMENT_TEAM`) im Diff. Im Zweifel fragen.
- Gemergte Phasen-Branches direkt nach Merge lokal + auf GitHub löschen (`git branch -d`, `git push origin --delete`), ohne Rückfrage. Nur wenn Merge bestätigt.
- Signier-Team (Personal Team des Nutzers) nur in `Config/Local.xcconfig` (git-ignoriert, nie committen), nie in `project.pbxproj`. Setzt Xcode dort `DEVELOPMENT_TEAM`, Zeile entfernen. `project.pbxproj` nur gezielt stagen; Xcode-Nebenänderungen (z. B. Scheme-`version`) nicht mitcommitten.
- Release nur via `Scripts/make-release.sh` (ad hoc, ohne Team, nie mit `xattr`-Tipp). Tag, GitHub-Release und Repo-Sichtbarkeit nur nach OK des Nutzers. `dist/` nie committen.
- Niemals committen: `.env`, Keys, Tokens, Zertifikate, Provisioning-Profile, Datenbanken, Backups, private Notizen.
- Aktuell halten: `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/decisions.md`.

## Befehle
```sh
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' build
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' test
swift test --package-path Packages/QuillKit

# Darstellung hell/dunkel als PNG nach $TMPDIR/QuillEditorSnapshots/
swift test --package-path Packages/QuillKit --filter EditorSnapshotTests

# Performance (docs/performance.md): Package optimiert, App im Schema „Quill Profiling“
python3 Scripts/perf-package.py 3
python3 Scripts/perf-ui.py
Scripts/check-release-binary.sh

# Release (ADR-022): ad hoc signierte .dmg + .sha256 nach dist/, nur aus sauberer Arbeitskopie
Scripts/make-release.sh
```
