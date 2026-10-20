# Roadmap

| Phase | Inhalt | Ergebnis |
|---|---|---|
| 0 Setup | Repo, Xcode-Projekt, `QuillKit`, `.gitignore`, Docs, CLAUDE.md | leere App baut, Tests grün, erster Push |
| 1 Research + Spike | Verhalten beobachten (Kürzel, Slash-Menü, Zwischenablage), Editor-Spike gegen Kriterien | ADR „Editor-Architektur“ |
| 2 Datenmodell + Sidebar | `SchemaV1`, `PageStore`, automatische Backups, Migrationstest, Seitenbaum, Drag & Drop, Tabs, Menüleiste | Seiten anlegen und verschachteln |
| 3 Editor (Text) ✅ | Textblöcke, Überschriften, Listen, To-do, Zitat, Inline-Formatierung (⌘B, ⌘I, ⇧⌘M, ⇧⌘X, ⌘K), Persistenz, Kopf mit Titel im Editor; aus dem Spike übernommen: Slash-Menü, Markdown-Kürzel, Block-Drag, Code, Trenner | Schreiben alltagstauglich |
| 4 Editor (Interaktion) ✅ | Block-Felder in `BlockProperties` (ADR-014), `BlockKind` nur in `QuillModel`, Bild-Block (ADR-015), Einfügen-Knopf ＋ (Escape nimmt den Klick zurück), Slash-Menü mit Abschnitten, Maus und VoiceOver, Kürzel in allen Textblöcken, Format › Blockart (⌥⌘0–7), Abhaken (⌘↩), Blöcke verschieben (⌥⌘↑/↓) und duplizieren (⌘D), Kontextmenü am Griff, Mitscrollen beim Ziehen (ADR-016), Ladeanzeige beim Lesen großer Bilder; gemergt (PR #4) | Editor MVP-komplett |
| 5 Navigation ✅ | Schnell öffnen (⌘O) mit Sprung zur Fundstelle, Favoriten als Abschnitt der Sidebar, Papierkorb mit Vorschau und Auto-Leeren nach 30 Tagen, Backup vor jedem endgültigen Löschen (ADR-017), Review-Fixes; gemergt (PR #5) | Seiten schnell finden |
| 6 Export ✅ | Markdown-Exporter (Seite/Baum, `assets/`), Golden-File-Tests; Ordner per Dialog, ⇧⌘E, YAML-Frontmatter, APFS-sichere Dateinamen, Zwischenordner außerhalb des Ziels (ADR-018), Review-Fixes; gemergt (PR #6) | Seiten als Markdown-Ordner |
| 7 Feinschliff ✅ | Accessibility, Lokalisierung, Performance, Icon, Leerzustände, Aufräumen aus dem Review von Phase 3 (feste Layout-Zahlen im Editor als `QuillDesign`-Tokens, Namen wie `T`/`S` und `longestIncreasingRun`, doppelter Code beim Laden in `EditorPersistenceBridge`) und aus dem Review von Phase 6 (Sortiervergleich `(sortKey, createdAt, id)` an fünf Stellen zusammenfassen, `title`/`untitled` im Export als fertige Namensbasis übergeben), **„Backup wiederherstellen …“** (7.1 ✅, gemergt PR #7: Menüpunkt, Tausch von `Store/` in einem Schritt beim Start, Umzug, Rückweg, ADR-019); 7.2 Aufräumen + Performance ✅, gemergt PR #8 (Messung und Schwellen ADR-020, `docs/performance.md`; Produktziel `sidebarReload` 100 ms verfehlt, für v0.1 akzeptiert, Lösung unter „Später“), darin zusätzlich aus dem Review von PR #7: ein gemeinsames Mapping Slug ↔ Anlass für Backups (`Reason`, `Kind`, `BackupLabel`), Backup-Namen als eigener Typ statt `String`, `restoreBackup` als App-Aktion statt in `PageActions`; offen: Ursache der fremden Bildbytes (in 7.2 einmal in 50 Läufen ohne Serialisierung nachgestellt, ADR-019), solange laufen `DiskStoreSuites` nacheinander; 7.3 Bedienungshilfen, Leerzustände, Lokalisierung, Icon ✅ (Audit rot bei jeder neuen Meldung, `EmptyState`, `LocalizationTests`, `AppIcon.icon`, ADR-021), gemergt PR #9 | v0.1 |
| 8 Release ✅ | GitHub-Release v0.1.0 veröffentlicht (Tag `v0.1.0`, PR #10, neues öffentliches Repo mit bereinigter History, altes als privates Archiv): ad hoc signierte App als .dmg mit Prüfsumme (`Scripts/make-release.sh`, ADR-022), nur Apple Silicon, macOS 26.0, Installationsanleitung, Lizenz GPL-3.0-or-later (Icon ausgenommen), History vor Veröffentlichung geprüft | v0.1.0 |

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
- Eigenes URL-Schema `quill://` für Links auf Seiten (Deep Links).
- „Kontrast erhöhen“ von Hand prüfen (offscreen nicht nachstellbar, ADR-021).
- UI-Tests legen das Fenster immer auf den Hauptbildschirm, damit Messungen (Kontrast-Audit,
  README-Bilder) bei mehreren Monitoren vergleichbar sind. Mit zweitem Monitor meldete der
  Audit zusätzlich den Erklärtext im Sheet „Backup wiederherstellen“, auf einem Bildschirm
  mit neutralem Hintergrund nicht.
- Eigene Variante des Icons für den dunklen Modus in Icon Composer gestalten; bisher
  dunkelt macOS den Hintergrund selbst ab.
- Sidebar aus einer Momentaufnahme des `PageStore` statt aus beobachteten `Page`-Objekten
  bauen. SwiftData meldet nach jeder Store-Änderung `Page.parent` als geändert, dadurch
  läuft `SidebarView.body` dreimal statt einmal (`docs/performance.md`). Danach Schwelle
  `sidebarReload` wieder auf 100 ms.

Aufräumen aus dem Review von PR #8, nicht eingeplant (Urteile, kein Fehler):
- `PageTree.Entry` hat eine zweite Kopie der Reihenfolge-Regel (`siblingOrder`,
  `favoriteOrder`) neben `SiblingOrder` für `Page`; ADR-009 will eine einzige Stelle.
- `StoreBackup.Reason`: drei Switches über fast dieselben Fälle (`kind`, `slug`,
  `Kind.slug`). Prüfen, ob `Reason` auf `Kind` plus Versionsanhang schrumpfen kann.
- `BackupName("")` steht für „unbekannt“ (`StoreBackup+Restore.swift`); besser ein
  Optional. `RestoreOutcome.restored(previous:)` ist noch ein `String`.
- `ExportStrings.fileBase(for:)` und `PageStore.fetchPage(_:)` reichen nur weiter.
- `QuillSignposts.beginSidebarLoadIfNeeded()` läuft als Seiteneffekt in
  `SidebarView.body`; einen Ort außerhalb von `body` suchen, der genauso früh misst.

Aus dem Review von PR #9, nicht eingeplant (Urteile, kein Fehler):
- Lexer in `LocalizationTests`: Raw-Strings `#"…"#`, Regex-Literale `/…/`, verschachtelte
  Blockkommentare und `\` am Zeilenende mehrzeiliger Literale werden nicht richtig
  gelesen; mehrzeilige Literale behalten ihre Einrückung (Abgleich mit dem Katalog);
  Ternary in `Text(c ? "A" : "B")` wird uneinheitlich eingestuft; einzelne
  kleingeschriebene Wörter und Kürzel wie „OK“ gelten nicht als Prosa. Kommt heute im
  Code nicht vor.
- `LocalizationTests.swift` vereint Lexer, Katalog- und Projektdatei-Parser; aufteilen.
- Touch-Bar-Ausnahme im Audit steht doppelt (`sufficientElementDescription`, `action`).
- `TestImage.png(spec:)` parst einen String statt eines kleinen Enum.
- `current!` im Rotor „Überschriften“ (`BlockTextView+Accessibility.swift`) per `map` vermeiden.

Ideen aus Phase 8, nicht eingeplant:
- Developer-ID-Zertifikat (bezahlter Developer Account) und Notarisierung, damit der erste Start ohne „Dennoch öffnen“ klappt und Updates keine neue Bestätigung brauchen.
- Auto-Update (z. B. Sparkle) mit signierten Updates.
- Fenster der .dmg gestalten (Hintergrund, Symbolpositionen).
- Release-Build in CI statt lokal.
- Englische Fassung der Installationsanleitung.

Aus dem Review von PR #10, nicht eingeplant (Urteile, kein Fehler):
- Bundle-ID-Präfix und Mindestversion stehen in `make-release.sh`, `check-release-binary.sh` und `BundleIdentifierTests` zusätzlich zum Projekt; aus dem Build lesen (`xcodebuild -showBuildSettings`).
- `BundleIdentifierTests` und `LocalizationTests` teilen sich `LocalizationTests.root`; eine gemeinsame Hilfe `RepoRoot` statt der Kopplung an eine fremde Testklasse.

Infrastruktur, nicht eingeplant:
- CI-Workflow auf GitHub (macOS-Runner): Build, Package- und App-Tests ohne Warnungen bei jedem PR. Bisher wird nur lokal getestet; PR #5 wurde auf Basis der lokalen Tests gemergt.

## Bekannte Probleme

- Keine offenen. Behoben in Phase 4: Inline-Code-Hintergrund in der Zeile darüber (siehe `architecture.md`, Erkenntnisse aus Phase 4).

**Signing:** Personal Team (gratis) → keine Notarisierung. Das Release ist nur ad hoc signiert und startet auf fremden Macs erst nach „Dennoch öffnen“ in Datenschutz & Sicherheit (ADR-022). CloudKit und App Store brauchen später einen bezahlten Developer Account.
