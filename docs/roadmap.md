# Roadmap

| Phase | Inhalt | Ergebnis |
|---|---|---|
| 0 Setup | Repo, Xcode-Projekt, `QuillKit`, `.gitignore`, Docs, CLAUDE.md | leere App baut, Tests grün, erster Push |
| 1 Research + Spike | Notion-Verhalten beobachten, Editor-Spike gegen Kriterien | ADR „Editor-Architektur“ |
| 2 Datenmodell + Sidebar | `SchemaV1`, `PageStore`, automatische Backups, Migrationstest, Seitenbaum, Drag & Drop, Tabs, Menüleiste | Seiten anlegen und verschachteln |
| 3 Editor (Text) ✅ | Textblöcke, Überschriften, Listen, To-do, Zitat, Inline-Formatierung (⌘B, ⌘I, ⇧⌘M, ⇧⌘X, ⌘K), Persistenz, Kopf mit Titel im Editor; aus dem Spike übernommen: Slash-Menü, Markdown-Kürzel, Block-Drag, Code, Trenner | Schreiben alltagstauglich |
| 4 Editor (Interaktion) ✅ | Block-Felder in `BlockProperties` (ADR-014), `BlockKind` nur in `QuillModel`, Bild-Block (ADR-015), Einfügen-Knopf ＋ (Escape nimmt den Klick zurück), Slash-Menü mit Abschnitten, Maus und VoiceOver, Kürzel in allen Textblöcken, Format › Blockart (⌥⌘0–7), Abhaken (⌘↩), Blöcke verschieben (⌥⌘↑/↓) und duplizieren (⌘D), Kontextmenü am Griff, Mitscrollen beim Ziehen (ADR-016); inhaltlich fertig, PR nach Handtest | Editor MVP-komplett |
| 5 Navigation | Schnell öffnen (⌘O), Favoriten, Papierkorb inkl. Auto-Leeren | – |
| 6 Export | Markdown-Exporter (Seite/Baum, `assets/`), Golden-File-Tests | – |
| 7 Feinschliff | Accessibility, Lokalisierung, Performance, Icon, Leerzustände, Aufräumen aus dem Review von Phase 3 (feste Layout-Zahlen im Editor als `QuillDesign`-Tokens, Namen wie `T`/`S` und `longestIncreasingRun`, doppelter Code beim Laden in `EditorPersistenceBridge`), **„Backup wiederherstellen…“** (Menüpunkt + Tests, Pflicht vor v0.1) | v0.1 |
| 8 Release | GitHub-Release v0.1 | – |

Jede Phase auf eigenem Branch mit PR; auf `main` nur grüne Builds.

## Später

Ideen aus Phase 4, nicht eingeplant:
- Kürzel für Code-Blöcke (z. B. ⌥⌘9), falls gewünscht; ⌥⌘8 ist belegt (ADR-016).
- Eigenes Menü „Block“ statt der Blockaktionen im Menü „Format“.
- Blöcke per Ziehen in eine andere Seite der Sidebar verschieben.

## Bekannte Probleme

- Keine offenen. Behoben in Phase 4: Inline-Code-Hintergrund in der Zeile darüber (siehe `architecture.md`, Erkenntnisse aus Phase 4).

**Signing:** Personal Team (gratis) → keine Notarisierung. Ein GitHub-Release startet auf fremden Macs nur über „Trotzdem öffnen“. CloudKit und App Store brauchen später einen bezahlten Developer Account.
