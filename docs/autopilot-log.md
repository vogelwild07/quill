# Autopilot-Log

Seit 2026-10-22 arbeitet Claude die restliche Roadmap der Mac-App allein ab und mergt
selbst, wenn der volle Lauf grün ist und kein Messwert schlechter wird. Hier steht alles,
was gemergt wurde, mit Messwerten, und die Entscheidungen, die der Nutzer prüfen soll.
Neueste Einträge unten.

## Zu prüfende Entscheidungen

Nicht besprochene Entscheidungen, je mit ADR. Häkchen setzt der Nutzer.

- [ ] Regel „Fehlersuche“ in `CLAUDE.md` geändert, nachdem die Ursache der roten Einsetz-Tests
  gefunden war (siehe PR #26).
- [ ] 12.2: Tage aus den Zeitstempeln der Änderungen, im Kalender des Macs, der die Zeitreise
  zeigt; ein Tagesstand enthält alles, worauf seine Änderungen aufbauen; Tage werden beim
  Öffnen gebildet, nicht gespeichert (ADR-031, Abschnitt 12.2).

- [ ] 12.3: Zeitreise als eigenes Fenster je Seite; früherer Stand im Lesemodus (Cursor und
  Markieren per Tastatur gehen, Ändern nicht); „Auswahl zurückholen“ ersetzt noch vorhandene
  Absätze an ihrer Stelle und setzt gelöschte hinter ihren nächsten früheren Nachbarn; eine
  Rückholung lässt sich nur über eine weitere Rückholung rückgängig machen, nicht mit ⌘Z
  (ADR-031, Abschnitt 12.3).

- [ ] 12.4: Frist für gelöschte Bilder pro Mac in den Einstellungen (nicht im Store oder Sync),
  Standard 90 statt bisher 30 Tage, „Immer“ löscht nie; kürzere Frist wirkt erst beim
  nächsten Start; Optionsfelder statt Klappmenü (ADR-031, Abschnitt 12.4).

- [ ] Review Phase 12: Bild-Blöcke ohne aufbewahrtes Bild werden beim Zurückholen
  übersprungen und gemeldet; Zurückholen ist aus, wenn die Seite im Papierkorb liegt; nach
  dem Ausschalten des Sync wird bewusst weiter aufgezeichnet (ADR-031, Abschnitt „Review von
  Phase 12“).

- [ ] 16.1: KI standardmäßig an, wenn Apple Intelligence bereit ist (ein Schalter in
  Einstellungen › KI schaltet alles aus); ohne Apple Intelligence eine Erklärung statt eines
  ausgegrauten Schalters, kein Knopf zu den Systemeinstellungen (Adresse nicht dokumentiert);
  FoundationModels nur im neuen Modul `QuillAI` (ADR-032, Abschnitt 16.1).

- [ ] 16.2: Zusammenfassung in einem Blatt mit „Kopieren“ und „Einfügen“ (an der
  Einfügemarke, ein Schritt für ⌘Z), nicht als eigener Block in der Seite; bis 6.000 Zeichen
  je Anfrage, längere Seiten in Stücken; Verfügbarkeit im Hintergrund geprüft (ADR-032,
  Abschnitt 16.2).

- [ ] 16.3: To-dos nur aus markierten Absätzen, als Vorschau-Liste; „Einfügen“ legt sie als
  To-do-Blöcke unter die Markierung, die Absätze bleiben (nicht ersetzen); Liste per Guided
  Generation statt Text zerlegen; höchstens 50 (ADR-032, Abschnitt 16.3).

## Gemergt

### 12.1 Geschichte aufzeichnen (PR #25, ADR-031)

- `HistoryRecorder` zeichnet jede Speicherung im Editor als Änderung im Sync-Dokument der
  Seite auf, auch ohne Sync; der Abgleich schreibt die Aufzeichnung mit hinaus.
- Zwei Hänger behoben: Beenden ohne offene Arbeit antwortet sofort (`terminateNow`);
  `SyncController` wartet bei `ModelContext.didSave` nicht mehr auf den Main Thread.
- Tests: Package 650 (88 + 7 + 134 + 115 + 30 + 276), UI 46 (1 übersprungen),
  Synctest 13 Fälle; 12 Gegenproben rot wie erwartet.
- Messung siehe `docs/performance.md`, Abschnitt „Geschichte aufzeichnen vorher und nachher“.
- Messung: Package gleich oder besser (editorTyping 1,20 → 1,17 ms, search 44,81 → 44,29 ms).
  App im Wechsel alt/neu gemessen: sidebarReload 174,2 / 153,3 → 152,4 / 153,2 ms, Start und
  sidebarLoad 1–2 % höher innerhalb der Streuung. **Achtung:** sidebarLoad liegt auf beiden
  Ständen inzwischen bei 188–197 ms, nahe der Schwelle 200 ms.
- Nicht getestet: neue Sitzung nach gescheitertem Speichern (Store lässt sich im Test nicht
  zum Scheitern bringen).

### Einsetz-Tests unabhängig von der allgemeinen Zwischenablage (PR #26)

- Ursache der roten Einsetz-Tests gefunden (Roadmap „Später“): `NSTextView` sperrte ⌘V bei
  leerer allgemeiner Zwischenablage, auch mit eigener Test-Zwischenablage. `BlockTextView`
  prüft „Einsetzen“ jetzt gegen die eigene; nur Debug- und Synctest-Builds nutzen eine eigene.
- Beleg: `ImageBlockUITests` bei leerer allgemeiner Zwischenablage auf `main` 3 von 4 rot,
  mit Fix 4 von 4 grün; neuer Unit-Test mit Gegenprobe.
- Regel in `CLAUDE.md` („Fehlersuche“) angepasst: `killall pboard` nur noch, wenn Einsetz-Tests
  trotzdem rot sind.

### 12.2 Stand am Ende eines Tages (PR #27, ADR-031)

- `PageHistory` bildet aus dem Sync-Dokument die Tage mit dem Stand an ihrem Ende; falsche
  Uhren ergeben nie einen Stand, den es nicht gab.
- Tests: Package 658 (93 + 9 + 134 + 115 + 30 + 277), UI 46 (1 übersprungen), Synctest 13 Fälle;
  5 Gegenproben rot (eine erst nach einem zusätzlichen Testfall, Kette über drei Tage).
- Messung: neu `historyDays` 93 ms (Schwelle 250), `historyDayBlocks` 15,5 ms (Schwelle 300);
  bestehende Werte im Wechsel mit `main` gleich oder besser (`docs/performance.md`).

### 12.3 Fenster „Zeitreise …“ (PR #28, ADR-031)

- Seite › „Zeitreise …“ (⌥⌘Y): Tage links, Stand am Tagesende rechts im Lesemodus, markierte
  Absätze zurückholen (über eine eigene `EditorPersistenceBridge`, landet in der Geschichte).
- Nebenbei behoben: Das Öffnen speichert nur noch die Editoren dieser Seite
  (`flushAll(pageID:)`), `HistoryObserver` zählt nur Speicherungen seines eigenen Stores.
  Beides machte parallele Tests unzuverlässig (`SyncTypingTests`, `HistoryObserverTests`).
- Tests: Package 668 (120 + 134 + 282 + 30 + 9 + 93), UI 48 (1 übersprungen), Synctest 13 Fälle;
  11 Gegenproben rot, dazu 2 in UI-Tests (Tastenkürzel, Audit); eine erste Audit-Gegenprobe
  griff nicht (SF Symbol bringt eigene Beschriftung mit) und wurde mit unbeschriftetem Knopf
  wiederholt. Eine Gegenprobe zu `canRestore` griff erst nach einem neuen Unit-Test.
- Einmal rot im UI-Lauf: `EditorUITests.testBoldShortcutAndFormatMenu` (App 20 s nicht
  bereit nach ⌘C, unter Last durch `appstoreagent`); danach 3 Einzelläufe und die ganze Klasse
  grün.
- Messung: im Wechsel mit `main` nicht langsamer. **Achtung:** `sidebarLoad` über 200 ms auf
  allen Ständen, auch 12.1, wegen `appstoreagent` mit 93 % CPU; Nachmessung ohne Last in 12.5.

### 12.4 Frist für gelöschte Bilder (PR #29, ADR-031)

- Einstellungen › Zeitreise › „Gelöschte Bilder aufbewahren“: 30 Tage, 90 Tage (Standard),
  1 Jahr, Immer. Ein zurückgeholter Bild-Block bekommt sein Bild, solange es aufbewahrt wird.
- Test-Stores schreiben die Wahl nie in die Einstellungen des Macs (Debug teilt sie mit der
  echten App; eigener Test mit Gegenprobe).
- Tests: Package 673 (124 + 134 + 283 + 30 + 9 + 93), UI 49 (1 übersprungen), Synctest 13 Fälle;
  6 Gegenproben rot, dazu 1 im UI-Test. Das Klappmenü meldete im Audit eine fehlende Aktion;
  ersetzt durch Optionsfelder statt einer Ausnahme.
- Messung: im Wechsel mit `main` nicht langsamer; `sidebarLoad` weiter über 200 ms auf beiden
  Ständen (`appstoreagent`).

### Review von Phase 12 und Schlussmessung (PR #30, ADR-031)

- Lesemodus dicht: Formatieren, Blockart und Ziehen ändern im Zeitreise-Fenster nichts mehr,
  die Menüs Format und Blockart sind dort aus.
- Zeitreise-Fenster: lädt beim Aktivieren neu, Zurückholen aus bei Seite im Papierkorb,
  Bild-Blöcke ohne Bild übersprungen und gemeldet; Maße als Tokens in `QuillDesign`.
- `saveHistory` schluckt nur noch „Seite fehlt“, andere Fehler gehen nach oben;
  `DocumentLocks.withLock` statt doppeltem Sperrcode; Schlüssel der Speicher-Meldung als
  Konstanten.
- Tests: Package 675 (125 + 135 + 283 + 30 + 9 + 93), UI 49 (1 übersprungen), Synctest 13
  Fälle; 4 Gegenproben rot (2 Package, 2 UI). Formatier- und Zieh-Sperre ohne eigenen Test
  (unter „Später“).
- Schlussmessung gegen den Stand vor Phase 12 (`cb3b6d0`): nichts langsamer
  (`docs/performance.md`). **Achtung:** `sidebarLoad` weiter über 200 ms auf beiden Ständen,
  `appstoreagent` läuft seit über einem Tag mit rund 97 % CPU.
- Phase 12 abgeschlossen.

### 16.1 Grundlage der lokalen KI (PR #31, ADR-032)

- Neues Modul `QuillAI`, einziges mit FoundationModels; nur `SystemLanguageModel` auf dem
  Gerät, Private Cloud Compute nirgends (`AIIsolationTests`).
- Einstellungen › KI: Schalter, oder eine Erklärung, wenn Apple Intelligence fehlt, aus ist
  oder das Modell noch lädt. Test-Modell per `-QuillFakeAI` (nur Debug, nur Test-Store);
  `check-release-binary.sh` prüft, dass es nicht im Release steckt.
- Tests: Package 681 (131 + 135 + 283 + 30 + 9 + 93), UI 51 (1 übersprungen), Synctest 13
  Fälle; 7 Gegenproben rot (eine erste griff nicht und wurde wiederholt), dazu 1 im UI-Test
  und 1 am Release-Check.
- Im vollen Lauf zweimal rot: `SpikeIsolationTests` fand „automerge“ in `AIIsolationTests`
  (Aufruf der Helfer von `AutomergeIsolationTests`, Datei mit Begründung in die Ausnahmen),
  und `AccessibilityUITests` startete nicht („Timed out while enabling automation mode“);
  die Klasse lief danach grün.
- Messung: im Wechsel mit `main` nicht langsamer; `sidebarLoad` weiter auf beiden Ständen über
  200 ms (`appstoreagent`).

### 16.2 Seite zusammenfassen (PR #32, ADR-032)

- Seite › „Zusammenfassen …“ nur mit bereitem Modell; Blatt mit Kopieren und Einfügen,
  lange Seiten in Stücken. Fehler des Modells als `AIError`, das Blatt nennt den Grund.
- Echtes Modell nur auf dem Mac geprüft: 5.891 Zeichen = 1.334 Token bei 8.192 Token
  Kontext, Antwort auf Deutsch; Kommentar „rund 4.000 Token“ korrigiert.
- Das Audit fand eine echte Lücke: Seite ohne Titel hatte in der Sidebar keine Beschreibung
  für VoiceOver (behoben, eigener Commit).
- Tests: Package 688 (135 + 138 + 283 + 30 + 9 + 93), UI 54 (1 übersprungen; zuerst als 55
  gemeldet, verzählt), Synctest 13
  Fälle. Gegenproben: 6 im Package und 1 im UI-Test rot; g1 griff zuerst nicht (Test
  geschärft), g2 kompilierte zuerst nicht (wiederholt). Ohne `breakUndoCoalescing()` vor dem
  Einfügen bleibt der UI-Test grün: Das Blatt nimmt dem Editor schon den Fokus, die Zeile
  bleibt als Absicherung.
- Messung: Package nicht langsamer. `sidebarLoad` im vollen Lauf 200,5 / 202,5 ms gegen
  189,1 / 191,6 auf `main`; derselbe Stand ohne Prüfung der Verfügbarkeit danach gleichauf
  (189,2 / 189,8 mit, 191,0 / 190,3 ohne), Wiederholung im Wechsel mit `main` 191,4 / 192,5
  gegen 191,9 / 185,3. Gewertet als Streuung, nicht als Verschlechterung.

### 16.3 To-dos vorschlagen (PR #33, ADR-032)

- Seite › „To-dos vorschlagen …“: markierte Absätze ans Modell (Guided Generation, Liste),
  Vorschau im Blatt, „Einfügen“ als To-do-Blöcke unter der Markierung, ein Schritt für ⌘Z
  (`BlockEditorController.insertBlocks`, auch von „Duplizieren“ genutzt). Fehlertexte beider
  Blätter jetzt aus `AIProblem`.
- Erster Lauf der Package-Tests rot: Ein Eintrag nur aus „-“ blieb stehen (Zeichen am Ende
  ohne Leerzeichen danach); Regel angepasst.
- Echtes Modell nur auf dem Mac: Notiz mit drei Aufgaben ergab vier deutsche Einträge (der
  Termin zählte mit), Notiz ohne Aufgabe eine leere Liste.
- Tests: Package 694 (135 + 144 + 283 + 30 + 9 + 93), UI 56 (1 übersprungen), Synctest 13
  Fälle. Gegenproben: 8 im Package und 3 im UI-Test rot, alle beim ersten Mal.
- Messung im Wechsel mit `main` (`562c11d`): nicht langsamer.
