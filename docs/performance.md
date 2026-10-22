# Performance

Messungen, Schwellen und Baseline (Phase 7.2). Erst messen, dann aufräumen: Jeder
Refactor wird gegen diese Baseline verglichen.

## Regeln

- **Produktziele sind fest:** Tippen und Enter p95 < 16 ms, Laden einer Seite mit
  1000 Blöcken < 300 ms, Suche p95 < 100 ms, Kaltstart < 1 s; Sidebar und
  Seitenwechsel < 100 ms; Export von 1000 Seiten (lesen und planen) < 2 s.
- **Neue Messungen:** Schwelle = max(Baseline × 3, Baseline + 5 ms), nie über einem
  Produktziel.
- Eine gerissene Schwelle wird erst gezeigt und besprochen, dann optimiert.
- Ausnahmen nach den Optimierungen (19.10.2026, so entschieden): Sidebar beim Start
  200 ms (erstes Layout des Fensters, kein Umbau), Neuladen nach ⌘N 180 ms (SwiftData,
  siehe unten; Umbau unter „Später“ in `roadmap.md`). Erst 130 ms; nach dem Review von
  PR #8 misst `sidebarReload` ab dem Anlegen der Seite, seitdem 180 ms.
- Gemessen wird nur optimiert: im Package mit `swift test -c release`, in der App mit
  der Konfiguration „Profiling“.

## Package (`QuillPerformanceTests`)

```sh
python3 Scripts/perf-package.py 3
# einzeln:
swift test --package-path Packages/QuillKit -c release -Xswiftc -enable-testing --filter QuillPerformanceTests
```

- In Debug übersprungen (`.enabled(if: Performance.isOptimized)`), Suiten serialisiert.
- `-enable-testing` braucht es für `@testable import`; es verhindert ein paar
  Optimierungen über Modulgrenzen, die Werte sind also eher zu hoch als zu niedrig.
- Pro Messung ein Aufwärmlauf, dann fünf Läufe; ein Lauf ergibt einen Wert (bei
  mehreren Proben dessen p95), verglichen wird der Median der fünf Läufe. Das Skript
  wiederholt das Ganze und zeigt Median, Minimum und Maximum.

### Baseline Package (19.10.2026, Stand `b2050f5`)

Median über drei Skriptläufe (je Aufwärmlauf + fünf Läufe), in ms.

| Messung | Was | Median | Min | Max | Schwelle |
|---|---|---:|---:|---:|---:|
| `editorLoad` | Editor mit 1000 Blöcken laden, Layout, Zeichnen | 11,95 | 11,40 | 12,25 | 300 (Ziel) |
| `editorTyping` | Tastendruck p95 | 1,09 | 1,05 | 1,11 | 16 (Ziel) |
| `editorEnter` | Enter p95 | 0,94 | 0,93 | 0,95 | 16 (Ziel) |
| `search` | Suche p95, 1000 Seiten × 50 Blöcke | 43,34 | 42,43 | 43,75 | 100 (Ziel) |
| `applyEditsMove` | einen von 1000 Blöcken verschieben, p95 | 59,13 | 58,91 | 63,09 | 178 |
| `applyEditsReverse` | 1000 Blöcke umkehren | 102,85 | 102,79 | 103,41 | 309 |
| `bridgeLoad` | Seite mit 1000 Blöcken aus dem Store, p95 | 106,40 | 105,08 | 116,32 | 300 (Ziel Laden; × 3 wäre 320) |
| `exportPlan` | 1000 Seiten lesen und Markdown planen | 4536,95 | 4471,93 | 4544,79 | 13 611, seit den Optimierungen 2000 (Ziel) |
| `pageTreeBuild` | Seitenbaum aus 5000 Seiten, p95 | 58,09 | 57,59 | 61,68 | 175 |

Gegenprobe: Schwelle `search` auf 1 ms gesetzt → Test rot („44,47 ms, Schwelle 1,0 ms“).

## App (Schema „Quill Profiling“)

```sh
python3 Scripts/perf-ui.py                    # Tests ausführen und auswerten
python3 Scripts/perf-ui.py --result X.xcresult # nur auswerten
Scripts/check-release-binary.sh               # Release ohne Profiling-Code?
```

- Konfiguration „Profiling“: optimiert wie Release, Produktname „Quill Profiling“,
  Bundle-ID `io.github.vogelwild07.quill.profiling`. Damit eigener Sandbox-Container und eigener
  Store; der echte Store ist für diese App nicht erreichbar.
- Das Package baut Xcode dort ohne `DEBUG`: `-QuillInMemoryStore` und
  `-QuillStoreDirectory` wirken nicht. Der Testbestand kommt aus
  `App/ProfilingSeed.swift`, nur unter `QUILL_PROFILING` kompiliert:
  `-QuillSeedPages 1000` leert den Store der Profiling-App, legt 1000 Seiten mit je
  50 Blöcken an (jede 50. mit Bild) und beendet die App. Das passiert einmal vor den
  Messungen und wird nicht mitgemessen.
- `Scripts/check-release-binary.sh` baut Release und sucht im App-Bundle nach
  `QuillSeedPages` und der Profiling-Bundle-ID. Gegenprobe: mit
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS=QUILL_PROFILING` muss es scheitern.
- Signposts (`QuillSignposts`, Subsystem `io.github.vogelwild07.quill`, Points of Interest):
  - `launch`: Start des App-Delegates bis zur ersten gezeichneten Sidebar.
  - `sidebarLoad`: erster Aufbau der Sidebar (Seitenbaum, Laden, Zeichnen).
  - `sidebarReload`: neue Seite (⌘N oder „Neue Seite“) bis zur neu geladenen,
    gezeichneten Sidebar: Speichern, Abfrage, Seitenbaum, Neuladen. Andere Änderungen
    laden die Sidebar auch neu, werden aber nicht gemessen.
  - `pageSwitch`: Klick auf eine Seite bis zum gezeichneten Editor.

  Intervalle enden nach dem nächsten Commit von Core Animation.
- „Kalt“ heißt frischer Prozess, nicht Start nach Neustart des Macs; der Datei-Cache
  des Systems bleibt warm.
- Handtest: Schema „Quill Profiling“ in Instruments öffnen (Product › Profile),
  Vorlage „Time Profiler“ oder „os_signpost“; die vier Intervalle stehen unter
  „Points of Interest“.

### Baseline App (19.10.2026, Stand nach `b2050f5`)

Zwei vollständige Läufe von `Scripts/perf-ui.py`; Median je Lauf über 5 Iterationen
(Seitenwechsel 10), in ms.

| Messung | Lauf 1 | Lauf 2 | Schwelle | |
|---|---:|---:|---:|---|
| Prozessstart bis bedienbar (`ApplicationLaunch`) | 607,6 | 630,2 | 1000 | ok |
| `launch` (Delegate bis gezeichnete Sidebar) | 395,5 | 394,8 | 1000 | ok |
| `sidebarLoad` (1000 Seiten) | 180,9 | 184,1 | 100 | **gerissen** |
| `sidebarReload` nach ⌘N | 130,9 | 158,2 | 100 | **gerissen** |
| `pageSwitch` (50 Blöcke, teils mit Bild) | 96,4 | 96,4 | 100 | knapp ok |

- Per `log stream --signpost` geprüft: ein ⌘N erzeugt genau ein `sidebarReload`.
- Das scheinbare Dauer-Neuladen „beim ersten Start“ war der Seed-Prozess selbst
  (siehe Analyse).
- Gegenproben: Seitenwechsel mit 300 ms Verzögerung → „ZU LANGSAM“ (406,7 ms),
  Exit 1. Ohne Ende des Intervalls → „FEHLT“, Exit 1. Der UI-Test selbst bleibt in
  beiden Fällen grün; maßgeblich ist das Skript.
- Release-Prüfung: ohne Treffer. Gegenprobe mit `QUILL_PROFILING` im Release-Build →
  alle drei Merkmale gefunden, Exit 1.

## Analyse (19.10.2026)

### Neuladen der Sidebar während des Seeds

Mit `log stream --signpost` und `-com.apple.CoreData.SQLDebug 1` getrennt geprüft:

- Seed (11 s): 209 × `sidebarReload` bei rund 110 000 INSERT/UPDATE und 4063 COMMIT.
  Jede gespeicherte Seite meldet `@Query`, die Sidebar lädt neu. Erwartet.
- Erster Start danach (15 s offen): 0 × `sidebarReload`, kein INSERT/UPDATE/DELETE
  (17 SELECT, das Protokoll lief also).
- Unter XCUITest ist `sidebarLoad` langsamer als per `open` gestartet (181 statt
  134 ms), vermutlich wegen der aktiven Bedienungshilfen.

### Speichern beim Löschen

Geprüft, ob „Papierkorb leeren“ und das Löschen eines Teilbaums einmal oder pro Seite
speichern: jeweils ein `save()` pro Aktion, Unterseiten folgen über die Beziehung.
`trash` markiert nur die Wurzel des Teilbaums (`PageStore.trash`),
`deletePermanently` und `emptyTrash` löschen alle Wurzeln und speichern danach einmal
(`PageStore+Navigation.swift`). Vor dem endgültigen Löschen entsteht ein Backup, sofern sich der Store seit dem letzten geändert hat
(`StoreBackup`, Anlass „vor-papierkorb-leeren“). Kein Handlungsbedarf.

### Time Profile (xctrace, Time Profiler + os_signpost, Profiling-Build)

Nur Abtastungen auf dem Main Thread innerhalb der Intervalle, ohne Seed-Prozess. Der
Main Thread rechnet fast durchgehend (größte Lücke 1–12 ms), die Intervalle sind also
CPU-Arbeit, kein Warten.

**Seitenwechsel** (12 Intervalle, Median 94 ms):

| Anteil | Wo |
|---:|---|
| 10 % | `PageStore.blocks(of:)` → `orderedBlocks`: Sortieren von 50 Blöcken, der Vergleich liest pro Aufruf `sortKey`, `createdAt`, `id.uuidString` aus SwiftData |
| 8 % | `SidebarView.body` läuft bei jedem Wechsel neu (Auswahl-Binding) und baut 1000 `PageTree.Entry` |
| 2 % | Editor (`BlockEditorController` laden, Layout) |
| Rest | SwiftUI-Graph, Layout, Commit |

**Neuladen nach ⌘N** (7 Intervalle, Median 135 ms): 28 % SwiftData-Abfragen von
`@Query`, davon zwei über alle aktiven Seiten (`SidebarView.pages` und
`RootView.activePages`; Letztere nur für den Favoriten-Stern, 15 %); 18 %
`SidebarView.body`; 18 % Layout; 18 % Tasks der neu gewählten Seite.

**Aufbau der Sidebar beim Start** (2 Intervalle, Median 178 ms): 40 % erstes Layout
von `NavigationSplitView` (`NSSplitViewController viewDidLoad`), dabei wertet SwiftUI
Views aus: `SidebarView.body` 15 % (davon `@Query`-Abruf 12 %, Einträge 3 %); die
Outline selbst (Zellen) rund 3 %.

### Export: kein quadratisches Wachstum

Lesen (`exportSnapshot`) und Planen getrennt, nacheinander, Release:

| Seiten | Lesen | Planen |
|---:|---:|---:|
| 125 | 566 ms | 2 ms |
| 250 | 1128 ms | 4 ms |
| 500 | 2254 ms | 8 ms |
| 1000 | 4520 ms | 17 ms |
| 2000 | 9087 ms | 33 ms |

Linear, aber 4,5 ms pro Seite. Time Profile: 91 % in der Vergleichsfunktion von
`orderedBlocks` (rund 600 Vergleiche je Seite mit 50 Blöcken, je etwa 7 µs für sechs
SwiftData-Getter und zwei `uuidString`). Dieselbe Funktion bremst `bridgeLoad`
(106 ms für 1000 Blöcke) und den Seitenwechsel.

Das Ziel von 2 s gilt ab der Optimierung als Schwelle (`Performance.limits`); bis dahin
steht dort die Baseline-Schwelle, damit die Refactors vorher und nachher gleich grün
vergleichbar bleiben.

## Optimierungen (19.10.2026)

| Commit | Was |
|---|---|
| `9e0edd0` | Eine Reihenfolge-Regel (`SiblingOrder`) statt Vergleichen an fünf Stellen |
| `bf6a868` | Schlüssel einmal pro Element lesen, nicht pro Vergleich |
| `c0f8ce2` | Blöcke gesammelt laden (`relationshipKeyPathsForPrefetching`), Export mit Teilbaum in einer Abfrage |
| `1826024` | Favoriten-Stern nur über Favoriten, nicht über alle Seiten |
| `40662b9` | Sidebar baut den Seitenbaum beim Seitenwechsel nicht neu |

Gleiche Reihenfolge bei gleichen Schlüsseln: `SiblingOrderTests` gegen den früheren
Vergleich (Zufall mit vielen Gleichständen, über den Store), Export-Golden-Files
unverändert.

**Package** (Release, Median):

| Messung | Baseline | danach |
|---|---:|---:|
| `applyEditsMove` | 59,1 | 14,8 |
| `applyEditsReverse` | 102,9 | 64,0 |
| `bridgeLoad` | 106,4 | 16,0 |
| `exportPlan` | 4537 | 927 |
| übrige | | unverändert im Rauschen |

**App** (Profiling, Median):

| Messung | Baseline | danach | Schwelle |
|---|---:|---:|---:|
| `ApplicationLaunch` | 608 | 561 | 1000 |
| `launch` | 395 | 352 | 1000 |
| `sidebarLoad` | 181 | 171 | 200 |
| `sidebarReload` | 131 | 104 | 130 |
| `pageSwitch` | 96 | 76,5 | 100 |

### Messpunkt `sidebarReload` korrigiert (Review PR #8)

Bis hier begann `sidebarReload` erst nach `reloadData()`: Speichern, Abfrage,
`SidebarView.body`, Seitenbaum und Neuladen fehlten im Wert. Seitdem beginnt das
Intervall beim Anlegen der Seite (`PageOperations.create`) und endet nach dem Zeichnen
der neu geladenen Sidebar. Zwei Läufe ohne Last: Median 140,3 und 140,1 ms, Einzelwerte
134–163 ms. Schwelle 180 ms, so entschieden. Gegenprobe: ohne Beginn beim Anlegen meldet
`Scripts/perf-ui.py` „FEHLT“, Exit 1. Die Werte oben (104 ms) gelten für den alten
Messpunkt.

**Produktziel verfehlt:** `sidebarReload` liegt mit 140 ms über dem Ziel von 100 ms
(Schlusslauf auf dem Endstand: Median 154,6 ms, Einzelwerte 133,6–161,8 ms).
Für v0.1 akzeptiert. Lösung über Weg (a): Sidebar aus einer Momentaufnahme des
`PageStore` bauen (`roadmap.md`, „Später“).

### Warum `SidebarView.body` lief

Per `Self._logChanges()` (SwiftUI-Log „Changed Body Properties“) geprüft:

- Beim Seitenwechsel: `@self changed`. Das Binding der Auswahl trägt den Wert mit,
  die Aktionen waren jedes Mal neue Closures, und auch zwei Bindings auf denselben
  Zustand gelten als verschieden. Lösung: Auswahl als Objekt (`PageSelection`),
  Aktionen als Klasse mit einer Instanz, `SidebarView` ist `Equatable`.
- Nach jeder Store-Änderung zweimal zusätzlich `Page.parent changed`. Laut Stacktrace
  ruft SwiftData selbst `willSet` für `parent` auf, wenn `@Query` aktualisiert
  (`_SwiftData_SwiftUI` → `SwiftData` → `Registrar.willSet`); ein Prefetch von
  `parent` ändert nichts. Deshalb die Ausnahme für `sidebarReload`.

## Themes vorher und nachher (20.10.2026, ADR-024)

Gleiche Messung vor dem Umbau (Stand `ccd7827`) und danach (Branch `phase-9/themes`).
Die Farben im Editor sind jetzt dynamisch und lesen das Theme beim Zeichnen; die
aufgelösten Paletten sind je Variante zwischengespeichert.

| Messung (Median, ms) | vorher | nachher |
|---|---|---|
| editorLoad | 11,94 | 12,13 |
| editorTyping | 1,09 | 1,10 |
| editorEnter | 0,95 | 0,97 |
| bridgeLoad | 16,08 | 16,11 |
| applyEditsMove | 14,97 | 14,88 |
| applyEditsReverse | 63,71 | 63,81 |
| pageTreeBuild | 53,05 | 54,97 |
| search | 43,60 | 44,47 |
| exportPlan | 924,95 | 928,41 |
| App: ApplicationLaunch | 589,8 | 587,8 |
| App: launch | 369,3 | 337,2 |
| App: sidebarLoad | 182,5 | 158,0 |
| App: sidebarReload | 159,9 | 134,2 |
| App: pageSwitch | 87,0 | 81,2 |

Alle Unterschiede im Rauschen (Package bis 3,6 %, App eher schneller), alle Schwellen
eingehalten. Ein Theme-Wechsel verwirft die Layout-Fragmente des Editors einmal; das
ist kein Pfad beim Tippen und wird nicht gemessen.

## Geschichte aufzeichnen vorher und nachher (21./22.10.2026, ADR-031)

Gleiche Messung vor 12.1 (Stand `9bd40ff`) und danach (Branch
`phase-12/geschichte-aufzeichnen`). `HistoryRecorder` läuft erst 2 s nach dem Speichern
und nicht auf dem Main Thread; Tippen und Seitenwechsel sollen davon nichts merken.

| Messung (Median, ms) | vorher | nachher |
|---|---|---|
| editorLoad | 12,86 | 12,70 |
| editorTyping | 1,20 | 1,17 |
| editorEnter | 1,07 | 1,04 |
| bridgeLoad | 17,08 | 16,81 |
| applyEditsMove | 16,03 | 15,15 |
| applyEditsReverse | 69,93 | 67,59 |
| pageTreeBuild | 54,46 | 54,97 |
| search | 44,81 | 44,29 |
| exportPlan | 981,42 | 959,64 |
| App: ApplicationLaunch | 560,7 / 555,8 | 569,2 / 563,0 |
| App: launch | 395,2 / 389,5 | 397,8 / 397,1 |
| App: sidebarLoad | 197,3 / 188,4 | 197,4 / 196,8 |
| App: sidebarReload | 174,2 / 153,3 | 152,4 / 153,2 |
| App: pageSwitch | 59,8 / 57,2 | 59,1 / 57,6 |

Package: drei Läufe je Stand. App: zwei Runden, abwechselnd alter Stand (eigener Worktree)
und neuer Stand, Median je Lauf (Runde 1 / Runde 2). Ein einzelner Lauf allein reichte
nicht: Der erste Lauf auf dem Endstand ergab `sidebarReload` 176,7 ms, weil nur einer von
fünf Werten in der schnellen Gruppe um 105 ms lag (die Werte zerfallen in zwei Gruppen, um
105 und um 150–184 ms). Im Wechsel ist der neue Stand nicht langsamer; `sidebarLoad` und
der Start liegen 1–2 % höher, innerhalb der Streuung der Einzelwerte (Start alt 383–402 ms,
neu 377–403 ms). Am selben Vormittag lag `sidebarLoad` auch auf dem alten Stand bei 197 ms,
nahe der Schwelle von 200 ms. Alle Schwellen eingehalten.

## Tagesstände der Zeitreise (22.10.2026, ADR-031)

12.2 bildet die Tage einer Seite beim Öffnen aus der Geschichte. Zwei neue Messungen mit
Produktziel (Schwelle), Seite mit 100 Blöcken, ein Jahr lang dreimal am Tag aufgezeichnet:

| Messung | Was | Median (ms) | Schwelle |
|---|---|---|---|
| `historyDays` | Dokument laden und 365 Tage bilden | 93,81 / 92,08 | 250 (Zeitreise öffnen) |
| `historyDayBlocks` | Blöcke eines Tages lesen | 15,49 / 15,54 | 300 (wie Laden im Editor) |

Bestehende Messungen abwechselnd auf `main` (`b9955df`) und 12.2, je drei Läufe, zwei
Runden (Runde 1 / Runde 2); 12.2 berührt diese Wege nicht:

| Messung (Median, ms) | `main` | 12.2 |
|---|---|---|
| editorLoad | 13,40 / 13,25 | 13,37 / 13,09 |
| editorTyping | 1,23 / 1,22 | 1,23 / 1,22 |
| editorEnter | 1,09 / 1,08 | 1,07 / 1,08 |
| bridgeLoad | 17,30 / 17,40 | 17,37 / 17,28 |
| applyEditsMove | 16,62 / 15,77 | 15,80 / 15,67 |
| applyEditsReverse | 71,39 / 73,05 | 70,66 / 70,57 |
| pageTreeBuild | 56,49 / 56,26 | 56,24 / 56,12 |
| search | 45,64 / 46,16 | 45,67 / 45,41 |
| exportPlan | 1006,16 / 1004,84 | 992,67 / 991,69 |

Ein Lauf direkt nach dem App-Build lag 3–6 % über der ruhigen Messung vom Morgen, auf
beiden Ständen: Vergleiche deshalb nur im Wechsel.

## Fenster „Zeitreise“ (22.10.2026, ADR-031)

12.3 ändert Szenen und Menü der App und den Editor (Lesemodus). Gemessen im Wechsel mit
`main` (`ffd3ee7`), zwei Runden (Runde 1 / Runde 2), Median je Lauf:

| Messung (ms) | `main` | 12.3 |
|---|---|---|
| editorLoad | 13,52 / 13,37 | 13,41 / 13,41 |
| editorTyping | 1,22 / 1,23 | 1,22 / 1,22 |
| bridgeLoad | 17,25 / 17,38 | 17,28 / 17,47 |
| pageTreeBuild | 57,99 / 57,58 | 58,64 / 59,38 |
| search | 45,65 / 47,07 | 46,18 / 45,96 |
| historyDays | 92,01 / 92,07 | 92,22 / 92,45 |
| App: sidebarLoad | 220,0 / 215,6 | 217,1 / 212,2 |
| App: sidebarReload | 152,0 / 173,1 | 173,7 / 173,1 |
| App: pageSwitch | 58,7 / 58,2 | 59,0 / 58,0 |

12.3 ist nicht langsamer. `sidebarLoad` lag während der ganzen Messung auf allen Ständen über
der Schwelle von 200 ms, auch auf dem Stand nach 12.1 (`b9955df`: 217,7 / 220,4, am Morgen
noch 188–197 ms). Ursache war Last von außen: `appstoreagent` lief die ganze Zeit mit rund
93 % CPU, zeitweise auch `mds`. Die Messung ohne diese Last steht noch aus (siehe Schlussmessung Phase 12).

## Frist für gelöschte Bilder (22.10.2026, ADR-031)

12.4 ändert nur, ob und mit welcher Frist beim Start aufgeräumt wird (außerhalb des Main
Threads). Im Wechsel mit `main` (`4eb2f40`), zwei Runden:

| Messung (ms) | `main` | 12.4 |
|---|---|---|
| editorLoad | 13,31 / 13,14 | 13,25 / 13,34 |
| bridgeLoad | 17,24 / 17,43 | 17,26 / 17,43 |
| pageTreeBuild | 58,24 / 58,08 | 55,25 / 55,41 |
| historyDays | 92,16 / 91,93 | 94,57 / 92,62 |
| App: sidebarLoad | 219,4 / 213,6 | 212,1 / 214,8 |
| App: sidebarReload | 171,7 / 171,5 | 170,6 / 171,5 |
| App: pageSwitch | 58,5 / 58,8 | 58,8 / 58,4 |

Nicht langsamer (`historyDays` +1 % auf einem Pfad, den 12.4 nicht berührt). `sidebarLoad`
weiter auf beiden Ständen über 200 ms, `appstoreagent` lief weiter mit rund 93 % CPU.

## Schlussmessung Phase 12 (22.10.2026, ADR-031)

Stand vor der Phase (`cb3b6d0`) gegen den Stand nach dem Review von Phase 12, im Wechsel,
zwei Runden:

| Messung (ms) | vor Phase 12 | nach Phase 12 |
|---|---|---|
| editorLoad | 13,34 / 13,33 | 13,32 / 13,22 |
| editorTyping | 1,22 / 1,22 | 1,22 / 1,22 |
| bridgeLoad | 17,16 / 17,40 | 17,33 / 17,36 |
| applyEditsReverse | 70,46 / 71,26 | 71,75 / 70,53 |
| pageTreeBuild | 55,41 / 55,50 | 56,16 / 56,15 |
| search | 45,90 / 47,15 | 45,56 / 45,79 |
| exportPlan | 992,88 / 1000,81 | 991,34 / 994,53 |
| historyDays | – | 92,80 / 94,39 |
| historyDayBlocks | – | 15,54 / 15,48 |
| App: sidebarLoad | 221,7 / 216,6 | 220,2 / 210,5 |
| App: sidebarReload | 172,6 / 172,7 | 172,0 / 171,1 |
| App: pageSwitch | 58,5 / 57,9 | 58,3 / 57,5 |

Phase 12 macht nichts langsamer (`pageTreeBuild` +1,3 %, im Rauschen, der Pfad blieb
unberührt). `sidebarLoad` liegt auf beiden Ständen über 200 ms: `appstoreagent` lief auch
während dieser Messung mit rund 97 % CPU. Eine Messung ohne diese Last steht weiter aus;
sie ist kein Grund, Phase 12 zurückzuhalten, weil beide Stände gleich schnell sind.

## Messbedingungen

| | |
|---|---|
| Datum | 19.10.2026 |
| Gerät | Mac mini (Mac16,10), Apple M4, 10 Kerne, 16 GB |
| Strom | Netzteil, Stromsparmodus aus |
| System | macOS 27.0.1 (26A434) |
| Werkzeuge | Xcode 27.1 (27A9275), Swift 6.4 |
| Last | keine weiteren Builds oder Tests während der Messung |
