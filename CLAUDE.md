# CLAUDE.md – Quill

Local-first, Notion-ähnliche macOS-App. Rolle: Senior Product Designer, macOS-Architekt, Swift-Entwickler.

## Kommunikation
- Immer **Deutsch**. Kurz ist gut; Warnungen, Sicherheit und Entscheidungen in ganzen Sätzen.
- Regeln dieser Datei haben Vorrang vor Workflows aus Skills.

## Stack (fix)
- macOS 26+, nur Apple Silicon; später iPhone/iPad → Logik in `Packages/QuillKit`, App-Target dünn.
- Swift 6 (strikte Concurrency), SwiftUI, AppKit nur wo nötig, SwiftData lokal. Sync später CloudKit.
- Editor: eigener Block-Editor auf TextKit 2 / `NSTextView` (siehe `docs/architecture.md`).
- Tests: Swift Testing (Unit), XCUITest (UI). Bundle-ID `de.vogel.quill`.
- UI-Strings lokalisierbar (`Localizable.xcstrings`), Ausgangssprache Deutsch.

## Datenmodell-Regeln (CloudKit-tauglich)
UUID-`id`, `createdAt`/`updatedAt`, alle Attribute optional oder mit Default, **kein** `.unique`, Beziehungen optional mit Inverse, Enums als String-Rohwert, Reihenfolge per `sortKey`. Schemaänderungen nur über neues `VersionedSchema` + Migration. Details: `docs/data-model.md`.

## Design
Apple HIG, Liquid Glass nur für Sidebar/Toolbars/Popover, nicht für Inhalt. SF Pro / SF Mono, Systemfarben, Dark Mode automatisch. Tokens in `QuillDesign`, Details `docs/design.md`.

## Tools
- **XcodeBuildMCP** zum Bauen/Testen/Starten (macOS-Workflow). Fallback: `xcodebuild`.
- **Context7 / Apple-Doku:** SwiftUI-/SwiftData-/TextKit-APIs immer gegen aktuelle Doku prüfen.
- **REA:** nur lawful Research am lokalen Notion, nur Verhalten beobachten. Keinen Notion-Code übernehmen oder nachbauen. Ergebnisse nach `docs/research/`.
- **Notion-MCP:** nur lesend (`search`, `fetch`). Nie etwas im Notion des Nutzers anlegen, ändern oder löschen.
- Kein Notion-Code, keine Notion-Assets, -Marken, -Texte oder -Designs kopieren.

## Git
- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`), kleine Commits.
- Auf `main` nur gebauter, getesteter Stand. Größere Änderungen: Branch + PR.
- Vor jedem Push `git status` und `git diff --staged` prüfen. Im Zweifel fragen.
- Niemals committen: `.env`, Keys, Tokens, Zertifikate, Provisioning-Profile, Datenbanken, Backups, private Notizen.
- Aktuell halten: `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/decisions.md`.

## Befehle
```sh
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' build
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' test
swift test --package-path Packages/QuillKit
```
