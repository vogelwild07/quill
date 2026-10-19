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
  200 ms (erstes Layout des Fensters, kein Umbau), Neuladen nach ⌘N 130 ms (SwiftData,
  siehe unten; Umbau unter „Später“ in `roadmap.md`).
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
| `exportPlan` | 1000 Seiten lesen und Markdown planen | 4536,95 | 4471,93 | 4544,79 | 13 611 |
| `pageTreeBuild` | Seitenbaum aus 5000 Seiten, p95 | 58,09 | 57,59 | 61,68 | 175 |

Gegenprobe: Schwelle `search` auf 1 ms gesetzt → Test rot („44,47 ms, Schwelle 1,0 ms“).

## App (Schema „Quill Profiling“)

```sh
python3 Scripts/perf-ui.py                    # Tests ausführen und auswerten
python3 Scripts/perf-ui.py --result X.xcresult # nur auswerten
Scripts/check-release-binary.sh               # Release ohne Profiling-Code?
```

- Konfiguration „Profiling“: optimiert wie Release, Produktname „Quill Profiling“,
  Bundle-ID `de.vogel.quill.profiling`. Damit eigener Sandbox-Container und eigener
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
- Signposts (`QuillSignposts`, Subsystem `de.vogel.quill`, Points of Interest):
  - `launch`: Start des App-Delegates bis zur ersten gezeichneten Sidebar.
  - `sidebarLoad`: erster Aufbau der Sidebar (Seitenbaum, Laden, Zeichnen).
  - `sidebarReload`: jedes weitere Neuladen der Sidebar.
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

## Messbedingungen

| | |
|---|---|
| Datum | 19.10.2026 |
| Gerät | Mac mini (Mac16,10), Apple M4, 10 Kerne, 16 GB |
| Strom | Netzteil, Stromsparmodus aus |
| System | macOS 27.0.1 (26A434) |
| Werkzeuge | Xcode 27.1 (27A9275), Swift 6.4 |
| Last | keine weiteren Builds oder Tests während der Messung |
