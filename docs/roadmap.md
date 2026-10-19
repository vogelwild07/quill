# Roadmap

| Phase | Inhalt | Ergebnis |
|---|---|---|
| 0 Setup | Repo, Xcode-Projekt, `QuillKit`, `.gitignore`, Docs, CLAUDE.md | leere App baut, Tests grün, erster Push |
| 1 Research + Spike | Notion-Verhalten beobachten, Editor-Spike gegen Kriterien | ADR „Editor-Architektur“ |
| 2 Datenmodell + Sidebar | `SchemaV1`, `PageStore`, automatische Backups, Migrationstest, Seitenbaum, Drag & Drop, Tabs, Menüleiste | Seiten anlegen und verschachteln |
| 3 Editor (Text) ✅ | Textblöcke, Überschriften, Listen, To-do, Zitat, Inline-Formatierung (⌘B, ⌘I, ⇧⌘M, ⇧⌘X, ⌘K), Persistenz, Kopf mit Titel im Editor; aus dem Spike übernommen: Slash-Menü, Markdown-Kürzel, Block-Drag, Code, Trenner | Schreiben alltagstauglich |
| 4 Editor (Interaktion) ✅ | Block-Felder in `BlockProperties` (ADR-014), `BlockKind` nur in `QuillModel`, Bild-Block (ADR-015), Einfügen-Knopf ＋ (Escape nimmt den Klick zurück), Slash-Menü mit Abschnitten, Maus und VoiceOver, Kürzel in allen Textblöcken, Format › Blockart (⌥⌘0–7), Abhaken (⌘↩), Blöcke verschieben (⌥⌘↑/↓) und duplizieren (⌘D), Kontextmenü am Griff, Mitscrollen beim Ziehen (ADR-016), Ladeanzeige beim Lesen großer Bilder; gemergt (PR #4) | Editor MVP-komplett |
| 5 Navigation ✅ | Schnell öffnen (⌘O) mit Sprung zur Fundstelle, Favoriten als Abschnitt der Sidebar, Papierkorb mit Vorschau und Auto-Leeren nach 30 Tagen, Backup vor jedem endgültigen Löschen (ADR-017), Review-Fixes; gemergt (PR #5) | Seiten schnell finden |
| 6 Export ✅ | Markdown-Exporter (Seite/Baum, `assets/`), Golden-File-Tests; Ordner per Dialog, ⇧⌘E, YAML-Frontmatter, APFS-sichere Dateinamen, Zwischenordner außerhalb des Ziels (ADR-018), Review-Fixes; gemergt (PR #6) | Seiten als Markdown-Ordner |
| 7 Feinschliff | Accessibility, Lokalisierung, Performance, Icon, Leerzustände, Aufräumen aus dem Review von Phase 3 (feste Layout-Zahlen im Editor als `QuillDesign`-Tokens, Namen wie `T`/`S` und `longestIncreasingRun`, doppelter Code beim Laden in `EditorPersistenceBridge`) und aus dem Review von Phase 6 (Sortiervergleich `(sortKey, createdAt, id)` an fünf Stellen zusammenfassen, `title`/`untitled` im Export als fertige Namensbasis übergeben), **„Backup wiederherstellen …“** (7.1 ✅, gemergt PR #7: Menüpunkt, Tausch von `Store/` in einem Schritt beim Start, Umzug, Rückweg, ADR-019); in 7.2 zusätzlich aus dem Review von PR #7: ein gemeinsames Mapping Slug ↔ Anlass für Backups (`Reason`, `Kind`, `BackupLabel`), Backup-Namen als eigener Typ statt `String`, `restoreBackup` als App-Aktion statt in `PageActions`; offen: Ursache der zwei roten Testläufe mit fremden Bildbytes (ADR-019), solange laufen `DiskStoreSuites` nacheinander | v0.1 |
| 8 Release | GitHub-Release v0.1 | – |

Jede Phase auf eigenem Branch mit PR; auf `main` nur grüne Builds.

## Später

Ideen aus Phase 4, nicht eingeplant:
- Kürzel für Code-Blöcke (z. B. ⌥⌘9), falls gewünscht; ⌥⌘8 ist belegt (ADR-016).
- Eigenes Menü „Block“ statt der Blockaktionen im Menü „Format“.
- Blöcke per Ziehen in eine andere Seite der Sidebar verschieben.

Ideen aus Phase 5, nicht eingeplant:
- Seite im Papierkorb lesend öffnen, mit Hinweisbanner und „Wiederherstellen“.
- ⌘↩ in Schnell öffnen: auch im neuen Tab zur Fundstelle springen.
- Unterseiten in den Favoriten aufklappen.

Ideen aus Phase 7, nicht eingeplant:
- Englische Lokalisierung (bisher nur Deutsch).

Infrastruktur, nicht eingeplant:
- CI-Workflow auf GitHub (macOS-Runner): Build, Package- und App-Tests ohne Warnungen bei jedem PR. Bisher wird nur lokal getestet; PR #5 wurde auf Basis der lokalen Tests gemergt.

## Bekannte Probleme

- Keine offenen. Behoben in Phase 4: Inline-Code-Hintergrund in der Zeile darüber (siehe `architecture.md`, Erkenntnisse aus Phase 4).

**Signing:** Personal Team (gratis) → keine Notarisierung. Ein GitHub-Release startet auf fremden Macs nur über „Trotzdem öffnen“. CloudKit und App Store brauchen später einen bezahlten Developer Account.
