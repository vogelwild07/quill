# Roadmap

| Phase | Inhalt | Ergebnis |
|---|---|---|
| 0 Setup | Repo, Xcode-Projekt, `QuillKit`, `.gitignore`, Docs, CLAUDE.md | leere App baut, Tests grün, erster Push |
| 1 Research + Spike | Notion-Verhalten beobachten, Editor-Spike gegen Kriterien | ADR „Editor-Architektur“ |
| 2 Datenmodell + Sidebar | `SchemaV1`, `PageStore`, automatische Backups, Migrationstest, Seitenbaum, Drag & Drop, Tabs, Menüleiste | Seiten anlegen und verschachteln |
| 3 Editor (Text) | Textblöcke, Überschriften, Listen, To-do, Zitat, Inline-Formatierung, Persistenz | Schreiben alltagstauglich |
| 4 Editor (Interaktion) | Slash-Menü, Markdown-Kürzel, Block-Drag & Drop, Code, Trenner, Bild | Editor MVP-komplett |
| 5 Navigation | Schnell öffnen (⌘O), Favoriten, Papierkorb inkl. Auto-Leeren | – |
| 6 Export | Markdown-Exporter (Seite/Baum, `assets/`), Golden-File-Tests | – |
| 7 Feinschliff | Accessibility, Lokalisierung, Performance, Icon, Leerzustände, **„Backup wiederherstellen…“** (Menüpunkt + Tests, Pflicht vor v0.1) | v0.1 |
| 8 Release | GitHub-Release v0.1 | – |

Jede Phase auf eigenem Branch mit PR; auf `main` nur grüne Builds.

**Signing:** Personal Team (gratis) → keine Notarisierung. Ein GitHub-Release startet auf fremden Macs nur über „Trotzdem öffnen“. CloudKit und App Store brauchen später einen bezahlten Developer Account.
