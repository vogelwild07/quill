# Automerge-Spike (Phase 10.1, ADR-026)

Misst `automerge-swift` gegen die Kriterien aus ADR-026. Nicht Teil der App:
App und QuillKit binden weder dieses Paket noch Automerge ein
(`SpikeIsolationTests` in QuillKit).

## Inhalt

- `PageCRDT`: eine Seite als Automerge-Dokument nach ADR-026 (Liste von Maps mit
  `id`, `kind`, `text` mit Marks und den Feldern aus `BlockProperties`), gelesen als
  `[EditorBlock]` aus QuillKit. Automerge zählt in Unicode-Skalaren, der Editor in
  UTF-16; `PageCRDT` rechnet um.
- `PageHistorySimulator`: schreibt Seiten wie ein Mensch, Zeichen für Zeichen, mit
  Tippfehlern, die wieder gelöscht werden (etwa 8,5 % aller Eingaben), Formatierung,
  späteren Einschüben, abgehakten To-dos und geänderten Blockarten. Feste Saat,
  erfundene Texte, nie Daten aus einem echten Store.
- `automerge-spike-measure`: Ladezeit und Speicher.
- `measure-app-size.sh`: App-Größe mit und ohne Automerge, in Klonen im
  temporären Ordner.
- Tests: Rundlauf der Abbildung, gleichzeitiges Tippen im selben Block,
  gemeldete Konflikte, Löschen gegen Bearbeiten.

## Ablauf

```sh
cd Spikes/AutomergeSpike
swift test
swift run -c release automerge-spike-measure          # laden, speicher oder alles
./measure-app-size.sh                                 # vom Repo aus, ca. 10 Minuten
```

## Abhängigkeit

`automerge-swift` 0.7.2 (MIT), Revision `aa45d17ac92cef2b8ded63b47e65a28dc85e3418`.
Der Rust-Kern kommt als vorgebautes `automergeFFI.xcframework`
(Prüfsumme `10245378e74229b026f689b039d7df3cf17aeed353706d5f420dfd164f283a86`,
von SwiftPM beim Laden geprüft) und wird statisch gelinkt (`staticlib`).

## Messung vom 2026-10-20

Apple M4, 10 Kerne, 16 GB, macOS 27.0.1, Swift 6.4, Release-Build.

Die Ergebnisse sind noch nicht bewertet; die Entscheidung steht danach in ADR-026.
