# Roadmap

| Phase | Inhalt | Ergebnis |
|---|---|---|
| 0 Setup | Repo, Xcode-Projekt, `QuillKit`, `.gitignore`, Docs, CLAUDE.md | leere App baut, Tests grün, erster Push |
| 1 Research + Spike | Notion-Verhalten beobachten, Editor-Spike gegen Kriterien | ADR „Editor-Architektur“ |
| 2 Datenmodell + Sidebar | `SchemaV1`, `PageStore`, automatische Backups, Migrationstest, Seitenbaum, Drag & Drop, Tabs, Menüleiste | Seiten anlegen und verschachteln |
| 3 Editor (Text) ✅ | Textblöcke, Überschriften, Listen, To-do, Zitat, Inline-Formatierung (⌘B, ⌘I, ⇧⌘M, ⇧⌘X, ⌘K), Persistenz, Kopf mit Titel im Editor; aus dem Spike übernommen: Slash-Menü, Markdown-Kürzel, Block-Drag, Code, Trenner | Schreiben alltagstauglich |
| 4 Editor (Interaktion) | Block-Felder gebündelt in `BlockProperties` ✅ (ADR-014), `BlockKind` nur in `QuillModel` ✅, Bild-Block ✅ (ADR-015, manueller Test und UI-Test offen). Dann Einfügen-Knopf ＋ neben dem Griff bei Hover (`design.md`), Feinschliff Slash-Menü, Kürzel und Block-Drag | Editor MVP-komplett |
| 5 Navigation | Schnell öffnen (⌘O), Favoriten, Papierkorb inkl. Auto-Leeren | – |
| 6 Export | Markdown-Exporter (Seite/Baum, `assets/`), Golden-File-Tests | – |
| 7 Feinschliff | Accessibility, Lokalisierung, Performance, Icon, Leerzustände, Aufräumen aus dem Review von Phase 3 (feste Layout-Zahlen im Editor als `QuillDesign`-Tokens, Namen wie `T`/`S` und `longestIncreasingRun`, doppelter Code beim Laden in `EditorPersistenceBridge`), **„Backup wiederherstellen…“** (Menüpunkt + Tests, Pflicht vor v0.1) | v0.1 |
| 8 Release | GitHub-Release v0.1 | – |

Jede Phase auf eigenem Branch mit PR; auf `main` nur grüne Builds.

## Bekannte Probleme

- **Inline-Code-Hintergrund in der Zeile darüber (Phase 4):** Der graue Hintergrund von Inline-Code (`.backgroundColor`, `quaternarySystemFill`) reichte einmal nach oben in die vorherige Zeile, hinter „```“. Gesehen am 2026-10-18 im Dunkelmodus-Snapshot von `EditorSnapshotTests` (Fixture `SampleDocuments.welcome`, Fenster 640 × 820, über `cacheDisplay` gerendert), beim ersten Lauf nach einer Änderung der Fixture; Inline-Code stand im Absatz direkt unter einem zweizeiligen Absatz. In drei weiteren Läufen und beim manuellen Test in der App nicht wieder aufgetreten. Vermutung: Hintergrund wird vor dem endgültigen Layout gezeichnet oder umfasst den Absatzabstand. Prüfen, ggf. Hintergrund im `BlockLayoutFragment` selbst zeichnen.

**Signing:** Personal Team (gratis) → keine Notarisierung. Ein GitHub-Release startet auf fremden Macs nur über „Trotzdem öffnen“. CloudKit und App Store brauchen später einen bezahlten Developer Account.
