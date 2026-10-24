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
| 9 Icon und Themes ✅ | 9.1 neues App-Icon als Markenzeichen mit eigener Dunkel-Variante je Ebene (ADR-023) ✅, gemergt PR #4; 9.2 sieben Themes für den Editor unter Einstellungen › Darstellung, Akzent Petrol (ADR-024) ✅, gemergt PR #5; GitHub-Release v0.2.0 (Tag `v0.2.0`) | v0.2.0 |
| 10 Architektur Mac + iPhone ✅ | 10.1 Spike Automerge ✅ (`Spikes/AutomergeSpike`, gemergt PR #11): Format entschieden, Messwerte in ADR-026; Laden < 50 ms nur im üblichen Fall gehalten, deshalb neu gefasst (Öffnen unverändert, Abgleich im Hintergrund < 250 ms auch im Schwerfall, erster Abgleich mit Fortschritt); 1.000 Seiten 11,9 MB; App 4,86 MiB größer (Grenze 5 MiB). 10.2 QuillKit baut auch für iOS 26 ✅ (ADR-028, `Scripts/check-ios-build.sh` ohne Fehler und Warnungen, gemergt PR #12; Nur-Mac-Teile hinter `#if canImport(AppKit)`); 10.3 Editor-Kern (`EditorDocument`, Block-Attribute, Layout) getrennt von AppKit ✅ (Target `QuillEditorCore` mit Dokument, Block-Attributen, Speichern und Theme-Rechnung; das Layout (`BlockStyle`, `BlockLayoutFragment`) bleibt in QuillEditor, baut dort aber für AppKit und UIKit; Farben auf beiden Plattformen, Snapshots byte-gleich, ADR-028, Review-Fixes; gemergt PR #13). iPad nicht verbauen (`NavigationSplitView`, Größenklassen, `Commands`) | Format entschieden, Package baut für beide Plattformen |
| 11 Ordner-Sync (Mac) ✅ | Plan in ADR-029 (Sync aus bis zum Einschalten, „Sync pausieren“, Automerge-Stand im Store, Backup vor dem ersten Einschalten, gelöschte Seiten auf anderen Geräten zuerst im Papierkorb, Test mit zwei Benutzerkonten und Testvariante `…quill.synctest`, ab Fall 14 zwei Varianten `…synctest.a`/`.b` in einem Konto). 11.1 Sync-Modul `QuillSync` mit Seiten- und Baum-Dokument und Ordnerformat ✅ (gemergt PR #14); 11.2 Schema V2 und Migration mit Rückfrage („Beenden“ als Standard) ✅ (gemergt PR #15); 11.3 Ordnerzugriff und Abgleich mit Tests für alle Fälle aus ADR-026 ✅ (gemergt PR #16; Verdichten der eigenen Dateien zu `<Nr>.snapshot` ✅ vor v0.4.0, ADR-029); 11.4 Oberfläche mit Lizenztexten, Zeitpunkte des Abgleichs, Rückfrage beim Backup-Einspielen, beim Wiederverbinden danach Wahl zwischen „Zusammenführen“ und „Neu beginnen mit neuem Ordner“ (der alte Ordner wird nie überschrieben) ✅ (gemergt PR #17; erste Datei je Dokument seit dem Verdichten als `<Nr>.snapshot`); 11.5 Handtest mit zwei Benutzerkonten ✅ (alle 13 Fälle bestanden, 2026-10-20; Anleitung `docs/synctest.md`, App per `Scripts/make-synctest.sh`); Review von Phase 11 mit Fixes (Tippen während eines Abgleichs per Dreiwege-Abgleich je Block, Konflikte bleiben bis zur Wahl, Ordnerwechsel, Backup-Reihenfolge; ADR-029), danach Fall 14 (Tippen ohne Pause) und die Fälle 1–12 als UI-Test mit zwei Testvarianten (`SyncTwoAppsUITests`, `Scripts/test-synctest-ui.sh`; per Hand bleiben Fall 13 und „Neu beginnen“ aus Fall 11, in Phase 13); 11.6 Konflikt-Wahl auf der Seite (je Fassung mit Gerät, Liste in Einstellungen › Sync) und Marke „wiederhergestellt“ in Editor und Sidebar ✅ (gemergt PR #20, ADR-029); Verdichten zu `<Nr>.snapshot` mit Meldung von Lücken nach einer Stunde ✅ (gemergt PR #21, Review-Fixes drin). Sync-Schicht über `PageStore` mit Automerge, Format im Ordner nach ADR-026 (jedes Gerät schreibt nur eigene Dateien, Bilder nach Inhalt benannt), Konflikte sichtbar statt verworfen, Quarantäne für unlesbare Dateien; neue Schemaversion mit Test „V1 → V2“, Backup vor der Migration, Rückweg getestet; Ordner per Lesezeichen (`bookmarks.app-scope`); getestet Mac ↔ Mac, ohne Developer Program | v0.4.0 (Beta zum Einschalten), veröffentlicht |
| 12 Zeitreise ✅ | Plan in ADR-031 (wächst mit jedem Schritt). 12.1 Geschichte immer aufzeichnen, auch ohne Sync, außerhalb des Main Threads (`HistoryRecorder`, Abgleich schreibt sie mit hinaus) ✅; 12.2 Stand am Ende eines Tages (`PageHistory`, Tage aus den Zeitstempeln der Änderungen, Stand samt allem, worauf er aufbaut) ✅; 12.3 eigenes Fenster „Zeitreise …“ (⌥⌘Y): Tage links, Seite rechts nur lesbar, markierte Absätze zurückholen (`TimeTravelScene`, Lesemodus des Editors, Rückholung über die Bridge) ✅; 12.4 Bilder nicht versioniert, verwaiste Bilder im Store nach wählbarer Frist löschen (30 Tage, 90 Tage Standard, 1 Jahr, immer aufbewahren; Einstellungen › Zeitreise; ADR-015) ✅; 12.5 Tests, Messung (`perf-package`, `perf-ui` vorher und nachher, keine Verschlechterung), Doku ✅; Review von Phase 12 mit Fixes ✅ | v0.4.0 |
| 14 Verschlüsselung (offen) | optional Ende-zu-Ende für den Sync-Ordner (CryptoKit, ChaCha20-Poly1305), Schlüssel aus Passphrase, nur im Schlüsselbund des Geräts; beim Einrichten Wiederherstellungsschlüssel und klarer Hinweis, dass ohne Passphrase und Wiederherstellungsschlüssel der Ordner unlesbar ist | offen, bis der Nutzer sie einplant |
| 15 Apple-Ökosystem ✅ (Teilen-Erweiterung ⏸) | Teile für das iPhone pausiert mit Phase 13 (ADR-030). App Intents und Siri („Neue Seite“, „Zur Einkaufsliste hinzufügen“), Spotlight, Schnellnotiz (Mac: Menüleiste mit globalem Kürzel; iPhone: Kontrollzentrum, Aktionstaste, Widget), Teilen-Erweiterung (braucht App Group, also Developer Program), To-dos mit Erinnerungen, Tagesseite mit heutigen Terminen. Plan in ADR-033 (Mac, ohne Teilen-Erweiterung): 15.1 Kurzbefehle und Siri (Neue Seite, Zu Seite hinzufügen mit Fortsetzen der Liste, Seite öffnen) ✅; 15.2 Spotlight (Titel und Text im Index, Schalter in den Einstellungen, Standard aus) ✅; 15.3 Schnellnotiz in der Menüleiste mit globalem Kürzel (Standard aus, neue Seite aus erster Zeile als Titel) ✅; 15.4 To-dos mit Erinnerung (Mitteilung auf diesem Mac, Glocke am To-do, nur auf diesem Mac) ✅; 15.5 Tagesseite mit heutigen Terminen (Kalender nur auf Klick): „Ablage › Heute“ (⇧⌘T) öffnet die Seite des Tages unter der Sammelseite „Tage“, „Format › Heutige Termine einfügen“ setzt die Termine als Liste an die Einfügemarke ✅; 15.6 Review, Schlussmessung gegen den Stand vor Phase 15 (`16f978f`) ✅. Phase 15 abgeschlossen (ohne Teilen-Erweiterung); Teilen-Erweiterung pausiert, bis das Developer Program da ist | v0.4.0 |
| 16 Lokale KI ✅ | Plan in ADR-032 (wächst mit jedem Schritt). Nur `SystemLanguageModel` auf dem Gerät, nie Private Cloud Compute, nichts ins Netz. 16.1 Grundlage: Modul `QuillAI` (einziges mit FoundationModels, `AIIsolationTests`), Verfügbarkeit, Einstellungen › KI mit Erklärung, wenn Apple Intelligence fehlt, Befehle dann ausgeblendet, Test-Modell für Tests (`-QuillFakeAI`, nur Debug) ✅; 16.2 Seite zusammenfassen (Blatt mit Kopieren/Einfügen, lange Seiten in Stücken) ✅; 16.3 markierte Absätze in To-dos umwandeln (mit Vorschau, ⌘Z) ✅; 16.4 „Frag deine Notizen“ mit Quellen aus der vorhandenen Suche (Suchbegriffe vom Modell, höchstens 5 Seiten und 6.000 Zeichen, Quellen anklickbar) ✅; 16.5 Link-Vorschläge (verwandte Seiten: Blatt mit bis zu 5 Seiten aus Suchbegriffen des Modells und der vorhandenen Suche, gemeinsame Begriffe sichtbar, Klick öffnet, kein Einfügen von Links) ✅; 16.6 Tests, Messung vorher und nachher, Review, Doku (Review über PR #31–#35 nach Standards und ADR-032, Befunde behoben, Schlussmessung gegen den Stand vor Phase 16) ✅. Phase 16 abgeschlossen | v0.4.0 |
| 17 Erfassen ohne Tippen ✅ | Sprachnotizen mit Abschrift auf dem Gerät (durchsuchbar), Text in Bildern per Vision durchsuchbar. Plan in ADR-034 (alles auf dem Gerät, nichts ins Netz, kein Modell-Download durch Quill, kein neues Feld im Schema): 17.1 Text in Bildern durchsuchbar (Vision erkennt den Text der Bilder im Hintergrund, nur im Speicher; „Schnell öffnen“ (⌘O) findet Bilder und springt zum Bild) ✅; 17.2 Sprachnotiz (Blatt mit Aufnahme, Abschrift live auf dem Gerät mit `SpeechAnalyzer`, „Einfügen“ setzt den Text als einen Absatz unter den Block an der Einfügemarke, die Aufnahme wird nicht gespeichert) ✅; 17.3 Review, Schlussmessung gegen den Stand vor Phase 17 (`7bd23f4`) ✅ | v0.4.0 |
| 18 Schreiben und Lesen ✅ | 18.1 Fokus-Modus ✅ (Schreibmaschinen-Scrollen, Umgebung abgedunkelt passend zum Theme, ADR-027, PR #10), veröffentlicht in v0.3.0 zusammen mit dem neuen Fenster der .dmg (ADR-025); 18.2 Präsentieren, Plan in ADR-035: „Seite › Präsentieren“ (⌥⌘P) zeigt die Seite im Vollbild als Folien, getrennt an den Überschriften der obersten Ebene, erste Folie mit dem Titel; Lesemodus, vergrößert, Pfeiltasten und Esc; nichts wird gespeichert ✅ (PR #46, Review-Fixes und Schlussmessung PR #47) | v0.3.0 / v0.4.0 |
| 13 iPhone-App ⏸ | **Pausiert (ADR-030), voller Fokus auf die Mac-App.** Offen beim Wiederaufnehmen: Developer Program (Anmeldung durch den Nutzer), Abgleich auf einem echten iPhone nachmessen. Inhalt: Developer Program vorher (Anmeldung durch den Nutzer); Sidebar, Editor auf `UITextView` mit Tastaturleiste, Slash-Menü, Blöcke ziehen, Bilder per `PhotosPicker`; Themes und Icon; Ordner über die Dateien-App; im Simulator prüfen: Kontrast des Themes „Standard“ mit den Systemfarben von iOS und dass Theme-Farben aus Systemfarben (`label`, `systemBackground`) bei Wechsel hell/dunkel und „Kontrast erhöhen“ richtig auflösen (ADR-028); Abgleich auf einem echten iPhone nachmessen (Kriterium < 250 ms auch im Schwerfall, ADR-026; reißt er es, zuerst seltener committen und die Zuordnung zu `[EditorBlock]` optimieren); TestFlight | pausiert |

Reihenfolge: 18.1 zuerst (v0.3.0 bekommt etwas Sichtbares), dann 10 → 11 → 12. Das Sync-Format wird schon in Phase 10 festgelegt, weil es Datenmodell, Speicher und Zeitreise bestimmt; die Zeitreise folgt direkt auf den Sync, weil die Geschichte dann schon vorliegt. Seit 2026-10-21 nur die Mac-App (ADR-030): Der Ordner-Sync gilt für mehrere Macs, die iPhone-App (13) ist pausiert, `QuillKit` baut weiter für iOS, solange das wenig kostet. Reihenfolge der Mac-Phasen nach 12 (festgelegt 2026-10-22 im Autopilot): 16 lokale KI → 15 Apple-Ökosystem ohne Teilen-Erweiterung (braucht das Developer Program) → 17 Erfassen ohne Tippen → 18.2 Präsentieren. Phase 14 Verschlüsselung bleibt offen, bis der Nutzer sie einplant. Developer Program erst, wenn eine Phase es braucht (z. B. Teilen-Erweiterung). Alles außer Phase 14 und den pausierten Teilen (iPhone-App, Teilen-Erweiterung) ist in v0.4.0 veröffentlicht. Danach v1.0: Feinschliff, App Store (optional Mac; GPL-Ausnahme für den App Store vor dem ersten fremden Beitrag klären).

Jede Phase auf eigenem Branch mit PR; auf `main` nur grüne Builds.

## Später

Aus dem Release v0.4.0 (2026-10-24, ADR-022):
- Automerge im Release selbst aus dem Quellcode bauen, damit keine Pfade fremder Build-Rechner im Binary stehen (braucht cargo im Release-Build).

Aus Phase 15.4 (2026-10-23, ADR-033):
- Zeitpunkt der Erinnerung als Feld des To-dos (synct auf andere Macs, steht im Backup); braucht Schema V3 mit Migration nach Freigabe des Nutzers und eine Erweiterung des Sync-Formats. Bis dahin gilt eine Erinnerung nur auf dem Mac, auf dem sie geplant wurde.

Aus der Planung von Phase 12 (2026-10-21):
- Zeitreise mit Zwischenständen innerhalb eines Tages, z. B. vor jeder Pause von mehr als einer Stunde; Phase 12 zeigt zuerst nur den Stand am Tagesende.

Aus dem Review von Phase 12 (2026-10-22):
- Geschichte auch für Seiten aufzeichnen, deren Abgleich abgebrochen war oder die zuletzt vor 12.1 abgeglichen wurden, wenn der Sync danach ausgeschaltet bleibt: Bis zum nächsten Abgleich zeichnet Quill dort nichts auf (ADR-031). Lösung bräuchte das Lesen der eigenen, noch nicht übernommenen Datei aus dem Ordner bei ausgeschaltetem Sync.
- Zeitreise-Fenster: Ablegen per Drag&Drop im Lesemodus hat keinen eigenen Test (`NSDraggingInfo` lässt sich im Unit-Test nur mit großem Aufwand nachbilden).

Aus dem Automerge-Spike (Phase 10.1, ADR-026):
- Rust-Kern von Automerge selbst bauen, auf Größe optimiert (`opt-level="z"`, LTO): App vermutlich kleiner als 4,86 MiB mehr, kein fremder Binärcode mehr; braucht Rust-Toolchain und eigenes Build-Skript, Ersparnis nicht gemessen.

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
- Sidebar aus einer Momentaufnahme des `PageStore` statt aus beobachteten `Page`-Objekten
  bauen. SwiftData meldet nach jeder Store-Änderung `Page.parent` als geändert, dadurch
  läuft `SidebarView.body` dreimal statt einmal (`docs/performance.md`). Danach Schwelle
  `sidebarReload` wieder auf 100 ms.

Bei Phase 13 (aus dem Review von Phase 11):
- Undo-Liste bleibt erhalten, wenn fremde Änderungen (Sync, anderes Fenster) in die offene
  Seite übernommen werden. Bisher leert das Neuladen sie (`BlockEditorController.load`).

Aus den UI-Läufen von Phase 11 (2026-10-21):
- ~~Untersuchen, warum die Einsetz-Tests nach vielen UI-Läufen scheitern.~~ Ursache am
  2026-10-22 gefunden: `NSTextView` gibt „Einsetzen“ nur frei, wenn die allgemeine
  Zwischenablage etwas Lesbares enthält; war sie leer, sperrte das ⌘V auch mit eigener
  Test-Zwischenablage. `killall pboard` und Neustarts halfen nur, wenn danach wieder etwas
  in der allgemeinen lag. Behoben in `BlockTextView.validateUserInterfaceItem`.

Aus dem Review von 11.6 und dem Verdichten (2026-10-21), nicht eingeplant:
- Ist die neueste verdichtete Datei eines Geräts noch nicht geladen, nimmt Quill keine ältere,
  schon geladene verdichtete Datei, sondern nur die `.changes`-Dateien danach.
- `storedConflicts` setzt nebenbei die Geräte-ID der Engine (`device`); ohne Seiteneffekt lösen.
- `SyncTwoAppsUITests.testTypingWithoutPause` (Fall 14) ist selten rot beim Tippen in A
  (Zeile 394), bisher nur unter zusätzlicher Last: 2 von 30 Läufen (2026-10-21), einmal im
  vollen Synctest-Lauf direkt nach allen UI-Klassen („process main thread busy for 30.0s“),
  einmal während Stack-Stichproben liefen („Timed out while synthesizing event“). Ohne Last
  20 von 20 einzeln und der volle Synctest-Lauf grün. In den Stichproben des zweiten Rots
  (alle 5 s, je 2 s) wartet der Main Thread von A und B im Run Loop, ab dem Fehlschlag
  durchgehend; ein 30-s-Block hätte mindestens fünf Stichproben getroffen. Vermutung: XCTest
  stellt das Ereignis unter Last nicht zu, kein Hänger in Quill; nicht belegt. Seit
  `test-synctest-ui.sh` bei Rot Protokoll, `.xcresult` und Stichproben von A, B und Test-Runner
  in `dist/synctest-logs/` behält, beim nächsten Rot dort nachsehen.
- Urteile, kein Fehler:
  - Name der Blockart steht in `ConflictLabel` und `BlockTextView+Accessibility` doppelt.
  - Feldnamen der Konflikte (`"kind"`, `"title"` …) als Strings an drei Stellen; ein Enum
    `ConflictField`.
  - Seite für den Sprung holen steht dreimal (Einstellungen › Sync, Lücken, Seitenkopf).
  - `blockText` und `pageTitle` reisen immer zusammen durch die Konfliktansichten; ein Typ.
  - `SyncController.localDeviceName` reicht nur weiter.
  - `rewrite` endet mit `fatalError`; ohne unerreichbaren Zweig formulieren.
  - `device(of:)` liest die Geräte-ID aus der Hex-Beschreibung der Automerge-Actor-ID.

Ideen aus der Roadmap 10–18, nicht eingeplant:
- iPad-App (Architektur aus Phase 10 lässt sie zu).
- Direkter Sync im WLAN ohne Ordner (braucht Berechtigung „Lokales Netzwerk“).

Ideen aus Phase 9, nicht eingeplant:
- Eigene Themes anlegen und bearbeiten.
- Themes importieren und exportieren.
- Schriftgröße im Editor einstellen.
- Feste Themes mit „Kontrast erhöhen“: Rollbalken im Editor bleiben im normalen Kontrast,
  weil sich kontrastreiche Erscheinungsbilder nicht erzwingen lassen (ADR-024).

Aufräumen aus dem Review von PR #5 (Themes), nicht eingeplant (Urteile, kein Fehler):
- `SettingsView`: feste Zahlen (Breite, Schriftgröße, Abstände, Radien) als Tokens nach
  `QuillDesign`.
- Zuordnung „dunkel + Kontrast → Variante“ steht in `EditorThemeVariant.init` und
  `EditorTheme.colors(dark:increaseContrast:)`, „Erscheinung → hell/dunkel“ an drei Stellen;
  auf eine Stelle bringen (z. B. `EditorThemeVariant(dark:highContrast:)`).
- Die Farbrollen stehen in `EditorColorRole`, `EditorPalette`, `ResolvedPalette`, `EditorColor`
  und `EditorThemeColors`; eine neue Rolle braucht viele Änderungen. `EditorThemeColors` könnte
  `ResolvedPalette` sein.
- `PageHeaderView` und `ThemeColorsReader` bauen bei jedem `body` eine neue `ResolvedPalette`
  und umgehen den Cache in `EditorThemeState`.
- Standard mit „Kontrast erhöhen“: Systemfarben (`labelColor`) bleiben unverändert; der Test
  rechnet mit Näherungen statt mit den echten kontrastreichen Systemfarben. Belegen, sobald
  sich die kontrastreiche Variante im Test auflösen lässt.

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
- Release-Build in CI statt lokal.
- Englische Fassung der Installationsanleitung.

Aus dem Review von PR #10, nicht eingeplant (Urteile, kein Fehler):
- Bundle-ID-Präfix und Mindestversion stehen in `make-release.sh`, `check-release-binary.sh` und `BundleIdentifierTests` zusätzlich zum Projekt; aus dem Build lesen (`xcodebuild -showBuildSettings`).
- `BundleIdentifierTests` und `LocalizationTests` teilen sich `LocalizationTests.root`; eine gemeinsame Hilfe `RepoRoot` statt der Kopplung an eine fremde Testklasse.

Aufräumen aus dem Review von PR #10 (Fokus-Modus), nicht eingeplant (Urteile, kein Fehler):
- `EditorThemeState`: Palette suchen oder anlegen steht in `color` und `dimmedAlpha` doppelt; ein `palette(for:)` im Lock.
- `EditorThemeSetup`: Auslesen von `-QuillEditorTheme` und `-QuillTestFocusMode` mit derselben Kette; Hilfe `value(after:)`.
- Toggle-Binding für den Fokus-Modus steht in `QuillCommands` und `SettingsView`.
- `Rendered` in `EditorFocusModeTests` ist fast wörtlich aus `EditorThemeControlTests` kopiert; nach `QuillTestFixtures`. `"hell"`/`"dunkel"` steht mehrfach.
- `BlockLayoutFragment.isDimmed` castet bei jedem Zeichnen den Delegate (bei Bildern zweimal).
- `-QuillEditorTheme` heißt wie der Defaults-Schlüssel `QuillEditorTheme` und wirkt deshalb über die Argument-Domain auch ohne Test-Store (wie vorher `-QuillFocusMode`); umbenennen.

Infrastruktur, nicht eingeplant:
- CI-Workflow auf GitHub (macOS-Runner): Build, Package- und App-Tests ohne Warnungen bei jedem PR. Bisher wird nur lokal getestet; PR #5 wurde auf Basis der lokalen Tests gemergt.

## Bekannte Probleme

- Keine offenen. Behoben in Phase 4: Inline-Code-Hintergrund in der Zeile darüber (siehe `architecture.md`, Erkenntnisse aus Phase 4).

**Signing:** Personal Team (gratis) → keine Notarisierung. Das Release ist nur ad hoc signiert und startet auf fremden Macs erst nach „Dennoch öffnen“ in Datenschutz & Sicherheit (ADR-022). Sync läuft über einen Ordner ohne CloudKit (ADR-026). iPhone-Verteilung, App Group (Widgets, Teilen-Erweiterung) und App Store brauchen den bezahlten Developer Account; Anmeldung vor Phase 13.
