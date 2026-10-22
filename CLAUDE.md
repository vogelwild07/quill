# CLAUDE.md – Quill

Local-first Notizen- und Seiten-App für macOS. Rolle: Senior Product Designer, macOS-Architekt, Swift-Entwickler.

**Stand:** Phase 6 (Export) fertig, gemergt (PR #6, ADR-018, Review-Fixes drin). Phase 7 (Feinschliff): 7.1 Backup wiederherstellen fertig, gemergt (PR #7, ADR-019, Store in `Store/`, Review-Fixes drin). 7.2 Aufräumen + Performance fertig, gemergt (PR #8, ADR-020, `docs/performance.md`, Review-Fixes drin; `sidebarReload` 140–155 ms statt Ziel 100 ms, für v0.1 akzeptiert). 7.3 A11y, Leerzustände, Lokalisierung, Icon fertig, gemergt (PR #9, ADR-021, Review-Fixes drin). Phase 7 abgeschlossen. Phase 8: v0.1.0 veröffentlicht (Tag `v0.1.0`, GitHub-Release mit ad hoc signierter .dmg, nur Apple Silicon, macOS 26.0; Lizenz GPL-3.0-or-later, Icon ausgenommen via `ICON-LICENSE`; ADR-022). Phase 9: 9.1 neues App-Icon fertig, gemergt (PR #4, ADR-023). 9.2 Themes für den Editor fertig, gemergt (PR #5, ADR-024, Review-Fixes drin). v0.2.0 veröffentlicht (Tag `v0.2.0`, Release-Text `docs/releases/v0.2.0.md`). Nächste Roadmap Phasen 10–18 (iPhone, Ordner-Sync nach ADR-026, neue Funktionen); 18.1 Fokus-Modus fertig, gemergt (PR #10, ADR-027, Review-Fixes drin). v0.3.0 veröffentlicht (Tag `v0.3.0`, Fokus-Modus + Fenster der .dmg nach ADR-025, Release-Text `docs/releases/v0.3.0.md`). Phase 10: 10.1 Spike Automerge fertig (`Spikes/AutomergeSpike`, ADR-026 entschieden, Branch `phase-10/spike-automerge`), gemergt (PR #11). 10.2 iOS-Build fertig, gemergt (PR #12, ADR-028, `Scripts/check-ios-build.sh`). 10.3 Editor-Kern `QuillEditorCore` fertig, gemergt (PR #13, ADR-028, Review-Fixes drin). Phase 10 abgeschlossen. Phase 11 (Ordner-Sync Mac ↔ Mac, Plan ADR-029): 11.1 Sync-Modul `QuillSync` fertig, gemergt (PR #14). 11.2 Schema V2 mit Rückfrage vor der Migration fertig, gemergt (PR #15). 11.3 Ordnerzugriff und Abgleich fertig, gemergt (PR #16, `SyncEngine`, `SyncController`). 11.4 Oberfläche des Sync fertig, gemergt (PR #17; Ordnerwechsel behält die Geschichte, Lizenzen der Rust-Pakete). 11.5 Handtest mit zwei Benutzerkonten nach `docs/synctest.md` bestanden (alle 13 Fälle, 2026-10-20). Code-Review von Phase 11 mit Fixes gemergt (PR #18, ADR-029). Fälle aus `docs/synctest.md` als UI-Test mit zwei Testvarianten (Branch `phase-11/synctest-zwei-varianten`). 11.6 Konflikt-Wahl (Gerät je Fassung, keine Zeit, Konflikte beim Start aus dem Store) und Marke „wiederhergestellt“ fertig, gemergt (PR #20, ADR-029). Verdichten zu `<Nr>.snapshot` (ab 50 eigenen Dateien, Lücken nach einer Stunde gemeldet) fertig, gemergt (PR #21, ADR-026, ADR-029, Review-Fixes drin). Doppelter Block nach Store hinter dem Ordner behoben, gemergt (PR #22, ADR-029). Hänger beim Tippen untersucht: `SyncTypingTests` rot durch `flushAll` aus einem anderen Test (behoben), Fall 14 ohne Hänger in Quill nachweisbar, `test-synctest-ui.sh` behält bei Rot Protokoll, `.xcresult` und Stack-Stichproben in `dist/synctest-logs/`, gemergt (PR #23). Neues App-Icon „Slash mit Cursor, Kante“ gemergt (PR #24, ADR-023). iPhone-App pausiert (ADR-030). Phase 12 Zeitreise (ADR-031): 12.1 Geschichte aufzeichnen fertig, gemergt (PR #25, `HistoryRecorder`, auch ohne Sync). 12.2 Tagesstände fertig, gemergt (PR #27, `PageHistory`). 12.3 Fenster „Zeitreise …“ (⌥⌘Y, Lesemodus, Auswahl zurückholen) fertig, gemergt (PR #28). 12.4 Frist für gelöschte Bilder fertig, gemergt (PR #29). Review-Fixes und Schlussmessung (PR #30). Phase 12 abgeschlossen. Autopilot seit 2026-10-22: Log in `docs/autopilot-log.md`. Phase 16 Lokale KI (ADR-032): 16.1 Grundlage (PR #31), 16.2 Seite zusammenfassen (PR #32) gemergt. UI-Tests legen Fenster auf den Hauptbildschirm (`-QuillWindowsOnMainScreen`, nur Debug). Developer Program erst, wenn eine Phase es braucht, bis dahin alles ohne. Neue Ideen nur unter „Später“ in `docs/roadmap.md`. Bekannte Probleme + Plan: `docs/roadmap.md`.

## Kommunikation
- Immer **Deutsch**. Kurz ok; Warnungen, Sicherheit, Entscheidungen in ganzen Sätzen.
- Regeln hier vor Skill-Workflows.

## Stack (fix)
- macOS 26+, nur Apple Silicon. iPhone-App pausiert (ADR-030), voller Fokus auf die Mac-App; Logik trotzdem in `Packages/QuillKit`, App-Target dünn, QuillKit baut weiter für iOS.
- Swift 6 (strikte Concurrency), SwiftUI, AppKit nur wo nötig, SwiftData lokal. Sync über einen gewählten Ordner mit Automerge, kein CloudKit (ADR-026, ADR-029); Automerge nur in `QuillSync` (`AutomergeIsolationTests`), Sync aus bis der Nutzer einschaltet, Tests nur mit Wegwerf-Stores und -Ordnern.
- Editor: eigener Block-Editor auf TextKit 2 / `NSTextView` (siehe `docs/architecture.md`). Kern ohne AppKit, UIKit und SwiftUI in `QuillEditorCore` (Dokument, Speichern, Theme-Rechnung; `EditorCoreImportTests`, ADR-028); Plattformfarben, TextKit-Schicht und Controller in `QuillEditor`.
- Tests: Swift Testing (Unit), XCUITest (UI). Bundle-ID `io.github.vogelwild07.quill`; alle Kennungen mit diesem Präfix, die alte Kennung nur in der Umzugsdoku (`BundleIdentifierTests`, ADR-022).
- UI-Tests starten App immer via `XCUIApplication.quill()` (ignoriert gespeicherten Fensterzustand, ADR-008; Fenster auf dem Hauptbildschirm, `TestWindowScreen`; Store nur im RAM via `-QuillInMemoryStore YES`; Tests über Neustarts via `quill(storeDirectory:)` im temporären Ordner der App; beide wirken nur aus der Kommandozeile und nur im Debug-Build, ADR-019). Nie gegen echten Store testen. Ausnahme `PerformanceUITests`: nur im Schema „Quill Profiling“ (Bundle-ID `io.github.vogelwild07.quill.profiling`, eigener Container, Bestand per `-QuillSeedPages`, nur unter `QUILL_PROFILING`; `docs/performance.md`). Kopieren/Einsetzen-Tests nutzen eigene Zwischenablage (`-QuillPasteboardName`), nie allgemeine; Testbilder erzeugt die App selbst (`-QuillTestImage`, nur Debug), nie der Test-Runner. Sync-Tests wählen den Ordner per `-QuillSyncTestFolder` und den Gerätenamen per `-QuillSyncDeviceName` (nur Debug, nur Test-Store); Test-Stores speichern Sync-Einstellungen nie in denen des Macs. Handtest des Sync nur mit den Testvarianten „Quill Synctest A“ und „B“ (Schema „Quill Synctest“, Konfigurationen `SynctestA`/`SynctestB`, `io.github.vogelwild07.quill.synctest.a`/`.b`, je eigener Container, nie die Kennung der echten App, `BundleIdentifierTests`; `Scripts/make-synctest.sh`, Anleitung `docs/synctest.md`). Test-Schalter dort nur unter `QUILL_SYNCTEST`, das allein `make-synctest.sh` setzt (nie in einer Konfiguration der Projektdatei, `SynctestVariantTests`, `check-release-binary.sh`); Ordner-Ausnahme nur in `App/QuillSynctest.entitlements`, die Entitlements der echten App bleiben unverändert. UI-Test mit zwei Geräten: `SyncTwoAppsUITests` über `Scripts/test-synctest-ui.sh` (im normalen UI-Lauf übersprungen).
- Build + Tests (App, Package, alle Test-Targets) **ohne Compiler-Warnungen**; QuillKit baut auch für iOS ohne Warnungen (`Scripts/check-ios-build.sh`, Teil jedes vollen Laufs; Nur-Mac-Code steht hinter `#if canImport(AppKit)`, nicht `#if os(macOS)`, ADR-028); neue Warnungen sofort beheben, nicht stummschalten. UI-Testklassen `@MainActor`, `setUp()`/`tearDown()` als `async throws` (`…WithError`-Varianten nonisolated).
- UI-Strings lokalisierbar (`Localizable.xcstrings`, Info.plist in `InfoPlist.xcstrings`), Ausgangssprache Deutsch, in Packages immer `bundle: .module`. `LocalizationTests` prüft Code gegen Kataloge und Pluralformen; Ausnahmen nur einzeln mit Begründung.

## Datenmodell-Regeln (CloudKit-tauglich)
UUID-`id`, `createdAt`/`updatedAt`, alle Attribute optional oder mit Default, **kein** `.unique`, Beziehungen optional mit Inverse, Enums als String-Rohwert, Reihenfolge per `sortKey`. Schemaänderung nur via neues `VersionedSchema` + Migration; `SchemaV1` und `SchemaV2` eingefroren (Fingerabdruck-Test), jede neue Version braucht Test „V(n-1) → V(n)“ (ADR-011). Migration des echten Stores nur nach Rückfrage in der App („Beenden“ Standard) und erst nach Freigabe des Nutzers (ADR-029). Schreiben nur via `PageStore`. Details: `docs/data-model.md`.

## Editor (ADR-007)
- Ein `NSTextView` pro Seite, Absatz = Block. Jeder Absatz endet mit `\n`, auch letzter; Block-Attribute (`.quillBlockID` …) auf **jedem** Zeichen. Weicher Umbruch = U+2028, atomare Blöcke = U+FFFC.
- Tippen im Absatz macht TextView; strukturelle Edits immer via `EditorDocument` als Diff via `shouldChangeText`/`replaceCharacters`/`didChangeText` (sonst kein Undo). Bei markiertem Text (IME, tote Tasten) nie eingreifen.
- Fallstricke: Fragment-Koordinaten ab Textanfang (mit `layoutFragmentFrame.minX` umrechnen). TextKit 2 zeichnet `NSTextAttachment.image(for:…)` unzuverlässig. `prepareForDragOperation` muss eigene Drag-Typen annehmen. Vor Markdown-Kürzeln `breakUndoCoalescing()`.
- Neue einfache Block-Felder nur via `BlockProperties` (ADR-014); Textattribute nur `Int`/`Bool`/`String`-Werte, kein Struct (AppKit muss archivieren). `BlockPropertiesRoundTripTests` erzwingt Testwerte pro Feld.
- `BlockKind` nur in `QuillModel`. Switches über Blockart ohne `default:`; neue Arten müssen `BlockKindCoverageTests` bestehen.
- Inline-Formatierung: `.quillMarks` + `.link` im Textspeicher = Quelle, Schrift/Farbe abgeleitet. Gespeichert als `Block.richText` (`RichText`-JSON, `nil` ohne Formatierung). Blöcke schreibt nur `EditorPersistenceBridge` via `PageStore.applyEdits` (ADR-013), nur vom erwarteten Stand aus; weicht der Store ab (Sync, anderes Fenster), führt `BlockMerge` je Block zusammen, nie still überschreiben.
- Speichern darf nie still scheitern: Bridge wiederholt mit Backoff, Seite zeigt `lastError`, Beenden fragt via `QuitGuard`. Neuladen aus anderen Fenstern nie bei markiertem Text.
- Test-Beispieldokumente nur aus `SampleDocuments` (Target `QuillTestFixtures`, Tests/QuillTestFixtures).
- Selbst gezeichnete Elemente nur Farben aus `EditorColor` (Theme-Rollen, ADR-024) oder Systemfarben; SF Symbols nicht mit `NSColor.set()` einfärben (bleibt schwarz). Hell + dunkel per `EditorSnapshotTests` prüfen. Tests, die zeichnen oder das Theme wechseln, mit Trait `.renderingLock` aus `QuillTestFixtures` (Theme gilt prozessweit, auch über Test-Targets).

## Design
Apple HIG, Liquid Glass nur Sidebar/Toolbars/Popover, nicht Inhalt. SF Pro / SF Mono, Systemfarben, Dark Mode automatisch. Tokens in `QuillDesign`, Details `docs/design.md`. Leerzustände nur über `EmptyState`/`EmptyStateView`. `AccessibilityAuditUITests` ist rot bei jeder neuen Meldung; Ausnahmen nur einzeln mit Begründung, keine Prüfart pauschal. Icon `App/Resources/AppIcon.icon`, nur in Icon Composer ändern.

## Tools
- **XcodeBuildMCP** für Bauen/Testen/Starten (macOS-Workflow). Fallback: `xcodebuild`.
- **Keine Bildschirmfotos oder -aufnahmen des Macs**, auch nicht zur Kontrolle (kein `screencapture`, keine Screenshot-Tools). App nur via Bedienungshilfen (AX), XCUITest oder App-eigene Snapshots (z. B. `-snapshot`) prüfen. Einzige Ausnahme: `Scripts/readme-screenshots.sh` (README-Bilder per XCUITest-Fensteraufnahme), nur nach ausdrücklichem OK des Nutzers für genau diesen Lauf, nachdem er Schreibtischbild, Fenster und „Nicht stören“ vorbereitet hat; Bilder danach auf fremde Inhalte prüfen.
- **Context7 / Apple-Doku:** SwiftUI-/SwiftData-/TextKit-APIs immer gegen aktuelle Doku prüfen.
- **REA:** nur rechtmäßige Recherche an lokal installierten Apps, nur Verhalten beobachten. Keinen fremden Code übernehmen oder nachbauen.
- **Verbundene Konten (MCP):** nur lesend. Konkrete Regeln je Konto in `CLAUDE.local.md`.
- Eigene Texte, Designs und Assets; keine Formulierungen, Designs, Assets, Marken oder Code anderer Apps.

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
- Nur Code + Doku aus diesem Repo. Nie Inhalte aus meinem echten Store, Backups, verbundenen Konten, Secrets oder Dateien außerhalb Repo. Im Zweifel vorher fragen.

## Tests und Gegenproben
- Jeder UI-Testlauf mit `timeout 600`. Ein Timeout gilt als „greift nicht sauber“ und wird gemeldet, nie ignoriert.
- Vor UI-Tests prüfen, ob Quill läuft (`pgrep -lf Quill.app/Contents/MacOS/Quill`). Läuft es, Nutzer fragen, nie selbst beenden (echter Store, ungespeicherte Änderungen).
- Ausnahme: übrig gebliebene Test-Instanzen (z. B. nach einem Timeout) selbst beenden, nur wenn alle drei gelten: Debug-Build in DerivedData (Pfad `~/Library/Developer/Xcode/DerivedData/…/Build/Products/Debug/Quill.app`), Startargument genau `-QuillInMemoryStore YES` (wirkt nur im Debug-Build, ADR-019), kein `-QuillStoreDirectory`. Vorher die volle Befehlszeile prüfen (`ps -o command= -p <PID>`). Sonst nie beenden, sondern Nutzer fragen, besonders bei `/Applications/Quill.app`.
- Gegenproben nur aus einer Kopie im Scratchpad: Datei kopieren, Fehler einbauen, Test laufen lassen, Datei aus der Kopie zurück und per `cmp` prüfen. Nie `git checkout`/`git restore` (sonst gehen uncommittete Änderungen verloren).
- Isolationstests nach dem Committen neuer Dateien erneut laufen lassen, vor dem Push (mindestens `swift test --filter QuillFeaturesTests`): `SpikeIsolationTests` und `BundleIdentifierTests` lesen nur eingecheckte Dateien (`git ls-files`), ein Lauf davor sieht neue Dateien nicht.
- Gegenproben, deren Code nicht kompiliert, zählen nicht und werden mit kompilierbarem Fehler wiederholt.
- Voller Lauf = Package-Tests, `Scripts/check-ios-build.sh`, App-Build ohne Warnungen, Release-Build der Tests (`swift build -c release -Xswiftc -enable-testing --build-tests --package-path Packages/QuillKit`), `python3 Scripts/perf-package.py 3`, `Scripts/check-release-binary.sh`, alle UI-Klassen und `Scripts/test-synctest-ui.sh`. Schlägt einer davon fehl (auch Release-Build oder perf-package), ist der Lauf rot.
- In jedem Bericht die Summe über alle Test-Targets nennen (`swift test` schreibt eine Zeile „Test run with …“ pro Target), nicht nur eine Zeile; jeden Test nur einmal zählen: Package-Tests, die der App-Lauf (`xcodebuild test`) noch einmal ausführt, nicht dazuzählen.

## Fehlersuche
- Rote Einsetz-Tests (z. B. `ImageBlockUITests`, Fall 3 in `SyncTwoAppsUITests`) lagen bis 2026-10-22 an einer leeren allgemeinen Zwischenablage: `NSTextView` sperrte ⌘V danach, auch mit eigener Test-Zwischenablage. Seitdem prüft `BlockTextView` „Einsetzen“ gegen die eigene (`ownClipboardDecidesWhetherPasteIsEnabled`). Sind Einsetz-Tests trotzdem auch auf `main` rot, zuerst `killall pboard` (PID vorher und nachher prüfen), dann die Ursache suchen.

## Git
- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`), kleine Commits.
- Auf `main` nur gebauter, getesteter Stand. Größere Änderungen: Branch + PR.
- Gepusht und gemergt wird erst nach OK des Nutzers.
- Jeder Push nur über `Scripts/push.sh` (aktueller Branch, `--tag <Tag>`, `--delete <Branch>`), nie direkt `git push`. Das Skript prüft alle noch nicht gepushten Commits nach Werten (Team-ID aus `Config/Local.xcconfig`, private Werte aus `Config/Local.push-check`, Benutzerpfad, Autor/Committer nur noreply) und bricht bei einem Treffer oder unsauberer Arbeitskopie ohne Push ab. Treffer nie umgehen, sondern melden und den Nutzer fragen.
- Merges nach `main` nur lokal: `git switch main && git pull --ff-only && git merge --no-ff <Branch> -m "Merge pull request #<Nr> from vogelwild07/<Branch>"`, dann `Scripts/push.sh`; GitHub markiert den PR dadurch als gemergt. Identität immer `vogelwild07 <201217023+vogelwild07@users.noreply.github.com>` (vorher `git config user.name` und `user.email` prüfen). Nie über die GitHub-Weboberfläche oder `gh pr merge`: Beides trägt die private E-Mail des Nutzers ein.
- Gemergte Phasen-Branches direkt nach Merge lokal + auf GitHub löschen (`git branch -d`, `Scripts/push.sh --delete <Branch>`), ohne Rückfrage. Nur wenn Merge bestätigt.
- Signier-Team (Personal Team des Nutzers) nur in `Config/Local.xcconfig` (git-ignoriert, nie committen), nie in `project.pbxproj`. Setzt Xcode dort `DEVELOPMENT_TEAM`, Zeile entfernen. `project.pbxproj` nur gezielt stagen; Xcode-Nebenänderungen (z. B. Scheme-`version`) nicht mitcommitten.
- Release nur via `Scripts/make-release.sh` (ad hoc, ohne Team, nie mit `xattr`-Tipp). Tag, GitHub-Release und Repo-Sichtbarkeit nur nach OK des Nutzers. `dist/` nie committen. Mit jedem Release steigt `CURRENT_PROJECT_VERSION` um 1 (alle Konfigurationen in `project.pbxproj`, zusammen mit `MARKETING_VERSION` im chore-Commit der Version).
- Persönliche Regeln (Ort des echten Stores, Sicherungen) stehen in `CLAUDE.local.md` (ignoriert, nie committen).
- Niemals committen: `.env`, Keys, Tokens, Zertifikate, Provisioning-Profile, Datenbanken, Backups, private Notizen.
- Aktuell halten: `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/decisions.md`.

## Befehle
```sh
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' build
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' test
swift test --package-path Packages/QuillKit

# QuillKit für iOS bauen, ohne Fehler und Warnungen (ADR-028)
Scripts/check-ios-build.sh

# Darstellung hell/dunkel als PNG nach $TMPDIR/QuillEditorSnapshots/
swift test --package-path Packages/QuillKit --filter EditorSnapshotTests

# Performance (docs/performance.md): Package optimiert, App im Schema „Quill Profiling“
python3 Scripts/perf-package.py 3
python3 Scripts/perf-ui.py
Scripts/check-release-binary.sh

# Lizenzen der Rust-Pakete im Automerge-Kern neu erzeugen (braucht cargo, ADR-029)
python3 Scripts/third-party-licenses.py

# Release (ADR-022): ad hoc signierte .dmg + .sha256 nach dist/, nur aus sauberer Arbeitskopie
Scripts/make-release.sh

# Testvarianten A und B für den Handtest des Sync (docs/synctest.md): ad hoc signiert nach dist/synctest/
Scripts/make-synctest.sh
# Fälle aus docs/synctest.md als UI-Test mit A und B (je Testmethode 600 s Grenze)
Scripts/test-synctest-ui.sh
```
