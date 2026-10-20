# Handtest Sync mit zwei Testvarianten (Phase 11.5)

Zwei Macs, nachgestellt mit zwei Testvarianten der App in einem Benutzerkonto und einem gemeinsamen Ordner (ADR-029). Getestet wird nur mit **Quill Synctest A** (Bundle-ID `io.github.vogelwild07.quill.synctest.a`) und **Quill Synctest B** (`io.github.vogelwild07.quill.synctest.b`): Jede hat ihren eigenen Container mit eigenem Store und eigenen Einstellungen, beide laufen gleichzeitig. Die echte App unter `/Applications/Quill.app` und ihr Store bleiben unberührt; sie muss während des Tests nicht laufen. `BundleIdentifierTests` stellt sicher, dass keine Variante die Kennung der echten App hat, und `Scripts/make-synctest.sh` prüft die Kennung jedes Builds.

**A** und **B** heißen im Folgenden die beiden Apps. Am Menü erkennst du, welche vorne ist („Quill Synctest A“ oder „Quill Synctest B“).

## Vorbereitung

1. **Apps bauen** (im Repo): `Scripts/make-synctest.sh` → `dist/synctest/Quill Synctest A.app` und `dist/synctest/Quill Synctest B.app`.
2. **Gemeinsamer Ordner** in deinem Benutzerordner: `mkdir ~/QuillSyncTest`.
3. Beide Apps aus `dist/synctest/` starten, zum Beispiel mit `open "dist/synctest/Quill Synctest A.app" "dist/synctest/Quill Synctest B.app"`. Prüfen: Menü „Quill Synctest A“ bzw. „Quill Synctest B“, nie „Quill“.

Zum Mitschreiben: Fall, OK/Fehler, Beobachtung. Bildschirmfotos brauche ich nicht. Bei einem Fehler hilft die Dateiliste des Ordners (sie enthält nur IDs und Nummern, keine Titel):
```sh
find ~/QuillSyncTest/Quill -type f | sed "s|$HOME/QuillSyncTest/||" | sort
```

## Fälle

**1 · Einschalten (A).** Einstellungen › Sync › „Ordner wählen und einschalten …“ › `~/QuillSyncTest`.
Erwartet: Status „Abgeglichen …“; unter Ablage › Backup wiederherstellen … ein Backup „Vor dem Einschalten des Sync“; im Ordner `Quill/quill.json`.

**2 · Zweites Gerät (B).** Vorher in B zwei Seiten anlegen („B eins“, „B zwei“). Dann denselben Ordner wählen.
Erwartet: „Im Ordner liegen schon Quill-Daten …“, nichts geschrieben. Nach „Zusammenführen“ haben A und B alle Seiten beider Apps (A spätestens nach 60 s oder beim Wechsel in die App).

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

**9 · Unlesbare Datei.** A pausiert. In A die höchste Nummer im eigenen Seitenbaum-Ordner suchen (`ls ~/QuillSyncTest/Quill/tree/<A-Geräte-ID>/`, A's ID steht in `devices/`) und die nächste als kaputte Datei anlegen, z. B. `printf kaputt > …/000000000007.changes`. B abgleichen lassen.
Erwartet: B meldet unter „Unlesbare Dateien“ genau diesen Pfad, sonst läuft alles weiter. Die Datei **vor dem Fortsetzen von A** wieder löschen, dann A fortsetzen. Erwartet: B übernimmt danach A's Änderungen.

**10 · Fremder Quill-Ordner.** In B den Sync ausschalten und einen zweiten Ordner wählen, in dem schon Quill-Daten eines anderen Bestands liegen (z. B. `~/QuillSyncTest2`, vorher in A mit dem Sync dort einmal befüllt).
Erwartet: Rückfrage, nichts geschrieben; „Sync ausschalten“ lässt beide Ordner unverändert. Danach B wieder mit `~/QuillSyncTest` verbinden: Quill führt zusammen, ohne Rückfrage (bisheriger Ordner).

**11 · Backup einspielen und wiederverbinden (A).** Ablage › Backup wiederherstellen … › „Vor dem Einschalten des Sync“.
Erwartet: Die Bestätigung sagt, dass der Sync ausgeschaltet wird; Quill beendet sich; nach dem Start erst die Meldung zum Backup, dann „Sync nach dem Backup“ mit drei Wahlen. Return löst keine aus, Escape heißt „Später“.
- **Zusammenführen:** neuere Stände aus dem Ordner kommen zurück (so beschrieben).
- Vorher Dateiliste sichern, dann einmal (nach erneutem Einspielen) **„Neu beginnen …“** mit einem leeren Ordner (`~/QuillSyncTest3`). Erwartet: Dateiliste und Inhalte des bisherigen Ordners unverändert (`shasum` über alle Dateien vorher und nachher). Verbindet B danach mit dem neuen Ordner (Sync aus, Ordner wählen, Zusammenführen), hat B den Stand aus A's Backup.

**12 · Abbruch mitten im Abgleich.** B pausiert. In A 30 Seiten mit Text anlegen (fürs Tempo: neue Seite mit ⌘N, denselben Text jeweils einsetzen). B fortsetzen und während des Abgleichs mit ⌘Q beenden, wieder starten.
Erwartet: Fortschritt unten in der Sidebar (ab 5 Seiten), App bleibt bedienbar; nach dem Neustart alle 30 Seiten da, kein Text doppelt.

**13 · Noch nicht geladene Datei (optional, nur mit iCloud Drive).** In A einen Ordner in iCloud Drive wählen, eine Datei per Finder › „Download entfernen“ auslagern und abgleichen.
Erwartet: „Noch nicht geladen“ im letzten Abgleich, danach lädt macOS sie, und der nächste Abgleich nimmt sie.

**14 · Tippen im selben Block ohne Pause.** In A und B dieselbe Seite öffnen, beide **nicht** pausiert. In B einen Absatz „Mitte“ anlegen und warten, bis er in A ankommt. Dann in A ans Ende des Absatzes klicken und langsam weitertippen („ eins zwei drei vier …“, etwa eine Minute lang, mit kurzen Pausen). Währenddessen in B an den Anfang desselben Absatzes „BBB “ schreiben und B einmal mit „Jetzt abgleichen“ abgleichen lassen.
Erwartet: In A erscheint „BBB “ vorne, während du tippst; der Cursor bleibt hinter deinem Text, und nichts von dem, was du getippt hast, fehlt. Nach dem nächsten Abgleich beider steht in A und B „BBB Mitte eins zwei drei …“. Kein Absatz doppelt; erscheint doch eine Kopie mit Marke „wiederhergestellt“ (erst ab 11.6 sichtbar), bitte notieren, wann.

## Aufräumen

- Beide Apps beenden. Löschen nur in den Containern der Testvarianten: `~/Library/Containers/io.github.vogelwild07.quill.synctest.a` und `~/Library/Containers/io.github.vogelwild07.quill.synctest.b`. **Nie** `~/Library/Containers/io.github.vogelwild07.quill` (echter Store).
- Testordner: `rm -r ~/QuillSyncTest ~/QuillSyncTest2 ~/QuillSyncTest3`.
