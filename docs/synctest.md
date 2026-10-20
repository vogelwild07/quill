# Handtest Sync mit zwei Benutzerkonten (Phase 11.5)

Zwei Macs, nachgestellt mit einem Mac, zwei Benutzerkonten und einem gemeinsamen Ordner (ADR-029). Getestet wird nur mit **Quill Synctest** (Bundle-ID `io.github.vogelwild07.quill.synctest`): eigener Container, eigener Store, eigene Einstellungen in jedem Konto. Die echte App unter `/Applications/Quill.app` und ihr Store bleiben unberührt; sie muss während des Tests nicht laufen.

Konto **A** ist dein Konto, Konto **B** das Testkonto. Fast User Switching (Kontrollzentrum › Schneller Benutzerwechsel) lässt beide gleichzeitig angemeldet, so laufen beide Apps zur selben Zeit.

## Vorbereitung

1. **App bauen** (Konto A, im Repo): `Scripts/make-synctest.sh` → `dist/synctest/Quill Synctest.app`.
2. **App für beide Konten ablegen:**
   ```sh
   mkdir -p "/Users/Shared/Quill Synctest"
   ditto "dist/synctest/Quill Synctest.app" "/Users/Shared/Quill Synctest/Quill Synctest.app"
   ```
3. **Gemeinsamer Ordner** (Konto A). Die Zugriffsliste erlaubt beiden Konten (Gruppe `staff`) auch in Unterordnern, die das jeweils andere anlegt, Dateien anzulegen:
   ```sh
   mkdir /Users/Shared/QuillSyncTest
   chmod +a "group:staff allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,read,write,append,file_inherit,directory_inherit" /Users/Shared/QuillSyncTest
   ```
4. **Zugriff prüfen:** In A `mkdir /Users/Shared/QuillSyncTest/probe`, in B `touch /Users/Shared/QuillSyncTest/probe/b` – muss ohne Fehler gehen. Danach in A `rm -r /Users/Shared/QuillSyncTest/probe`.
5. In beiden Konten **Quill Synctest** aus `/Users/Shared/Quill Synctest/` starten (beim ersten Mal Rechtsklick › Öffnen). Prüfen: Menü „Quill Synctest“, nicht „Quill“.

Zum Mitschreiben: Fall, OK/Fehler, Beobachtung. Bildschirmfotos brauche ich nicht. Bei einem Fehler hilft die Dateiliste des Ordners (sie enthält nur IDs und Nummern, keine Titel):
```sh
find /Users/Shared/QuillSyncTest/Quill -type f | sed 's|/Users/Shared/QuillSyncTest/||' | sort
```

## Fälle

**1 · Einschalten (A).** Einstellungen › Sync › „Ordner wählen und einschalten …“ › `/Users/Shared/QuillSyncTest`.
Erwartet: Status „Abgeglichen …“; unter Ablage › Backup wiederherstellen … ein Backup „Vor dem Einschalten des Sync“; im Ordner `Quill/quill.json`.

**2 · Zweites Gerät (B).** Vorher in B zwei Seiten anlegen („B eins“, „B zwei“). Dann denselben Ordner wählen.
Erwartet: „Im Ordner liegen schon Quill-Daten …“, nichts geschrieben. Nach „Zusammenführen“ haben A und B alle Seiten beider Konten (A spätestens nach 60 s oder beim Wechsel ins Konto).

**3 · Inhalte.** In A: Seite mit Unterseite, Icon, Favorit, Überschrift, Liste, To-do (abgehakt), Code, fettem Text, Link und einem Bild.
Erwartet in B: alles gleich, Bild sichtbar.

**4 · Gleichzeitiges Tippen.** In A und B „Sync pausieren“ einschalten („pausieren“ und „fortsetzen“ heißt im Folgenden immer dieser Schalter). Im selben Absatz in A am Anfang „AAA“, in B am Ende „BBB“ tippen. Beide fortsetzen.
Erwartet: in beiden „AAA … BBB“, nichts verloren.

**5 · Löschen gegen Bearbeiten.** Beide pausieren. A löscht einen Absatz, B ändert genau diesen Absatz. Beide fortsetzen.
Erwartet: Der Absatz ist in beiden wieder da, mit B's Änderung.

**6 · Zwei Werte für dasselbe Feld.** Beide pausieren. Dieselbe Seite in A „Titel A“, in B „Titel B“ nennen. Fortsetzen.
Erwartet: beide zeigen denselben Titel; Einstellungen › Sync › „Letzter Abgleich“ nennt „Zwei Werte für ein Feld“.

**7 · Papierkorb.** A legt eine Seite in den Papierkorb.
Erwartet: in B im Papierkorb, nicht weg.
Dann: Beide pausieren, A legt eine weitere Seite in den Papierkorb, B bearbeitet genau diese Seite. Fortsetzen.
Erwartet: Die Seite bleibt in beiden außerhalb des Papierkorbs.
Dann: A leert den Papierkorb.
Erwartet: In B liegt die Seite weiter im Papierkorb, bis B ihn leert; danach kommt sie nirgends zurück.

**8 · Pausieren.** A pausiert und bearbeitet mehrere Seiten. Dateiliste (oben) vorher und nachher vergleichen.
Erwartet: keine neue Datei, auch nach Neustart von A (bleibt pausiert). Nach dem Fortsetzen kommen die Änderungen in B an.

**9 · Unlesbare Datei.** A pausiert. In A die höchste Nummer im eigenen Seitenbaum-Ordner suchen (`ls /Users/Shared/QuillSyncTest/Quill/tree/<A-Geräte-ID>/`, A's ID steht in `devices/`) und die nächste als kaputte Datei anlegen, z. B. `printf kaputt > …/000000000007.changes`. B abgleichen lassen.
Erwartet: B meldet unter „Unlesbare Dateien“ genau diesen Pfad, sonst läuft alles weiter. Die Datei **vor dem Fortsetzen von A** wieder löschen, dann A fortsetzen. Erwartet: B übernimmt danach A's Änderungen.

**10 · Fremder Quill-Ordner.** In B den Sync ausschalten und einen zweiten Ordner wählen, in dem schon Quill-Daten eines anderen Bestands liegen (z. B. `/Users/Shared/QuillSyncTest2`, vorher in A mit dem Sync dort einmal befüllt).
Erwartet: Rückfrage, nichts geschrieben; „Sync ausschalten“ lässt beide Ordner unverändert. Danach B wieder mit `/Users/Shared/QuillSyncTest` verbinden: Quill führt zusammen, ohne Rückfrage (bisheriger Ordner).

**11 · Backup einspielen und wiederverbinden (A).** Ablage › Backup wiederherstellen … › „Vor dem Einschalten des Sync“.
Erwartet: Die Bestätigung sagt, dass der Sync ausgeschaltet wird; Quill beendet sich; nach dem Start erst die Meldung zum Backup, dann „Sync nach dem Backup“ mit drei Wahlen. Return löst keine aus, Escape heißt „Später“.
- **Zusammenführen:** neuere Stände aus dem Ordner kommen zurück (so beschrieben).
- Vorher Dateiliste sichern, dann einmal (nach erneutem Einspielen) **„Neu beginnen …“** mit einem leeren Ordner (`/Users/Shared/QuillSyncTest3`, Zugriffsliste wie oben). Erwartet: Dateiliste und Inhalte des bisherigen Ordners unverändert (`shasum` über alle Dateien vorher und nachher). Verbindet B danach mit dem neuen Ordner (Sync aus, Ordner wählen, Zusammenführen), hat B den Stand aus A's Backup.

**12 · Abbruch mitten im Abgleich.** B pausiert. In A 30 Seiten mit Text anlegen (fürs Tempo: neue Seite mit ⌘N, denselben Text jeweils einsetzen). B fortsetzen und während des Abgleichs mit ⌘Q beenden, wieder starten.
Erwartet: Fortschritt unten in der Sidebar (ab 5 Seiten), App bleibt bedienbar; nach dem Neustart alle 30 Seiten da, kein Text doppelt.

**13 · Noch nicht geladene Datei (optional, nur mit iCloud Drive).** Gleicher Test mit einem Ordner in iCloud Drive in beiden Konten ist nicht möglich (zwei Apple-Accounts); stattdessen in A in iCloud Drive einen Ordner wählen, eine Datei per Finder › „Download entfernen“ auslagern und abgleichen.
Erwartet: „Noch nicht geladen“ im letzten Abgleich, danach lädt macOS sie, und der nächste Abgleich nimmt sie.

## Aufräumen

- In beiden Konten Quill Synctest beenden. Löschen nur in den Containern der Testvariante (je Konto): `~/Library/Containers/io.github.vogelwild07.quill.synctest`. **Nie** `~/Library/Containers/io.github.vogelwild07.quill` (echter Store).
- Testordner und App: `rm -r /Users/Shared/QuillSyncTest /Users/Shared/QuillSyncTest2 /Users/Shared/QuillSyncTest3 "/Users/Shared/Quill Synctest"`.
