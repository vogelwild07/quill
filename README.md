# Quill

Local-first, Notion-ähnliche Produktivitäts-App für macOS: Seiten, Notizen und Aufgaben in einem nativen Block-Editor.

> Status: Release v0.1.0 in Vorbereitung (Phase 8). Phase 7 (Feinschliff) abgeschlossen: Backup wiederherstellen, Aufräumen und Performance (Messung siehe `docs/performance.md`), Bedienungshilfen mit Audit, Leerzustände, vollständige deutsche Lokalisierung und App-Icon. Export einer Seite oder eines Seitenbaums als Markdown-Ordner mit Bildern (⇧⌘E), Schnell öffnen (⌘O), Favoriten, Papierkorb mit Auto-Leeren nach 30 Tagen. Seiten mit Block-Editor: Überschriften, Listen, To-dos, Zitat, Code, Trenner, Bilder, Inline-Formatierung und Links; Slash-Menü, Markdown-Kürzel, Blockart per ⌥⌘0–7, Blöcke ziehen, verschieben und duplizieren; Speichern automatisch.

## Installation

Voraussetzung: Mac mit Apple Silicon, macOS 26 oder neuer. Die .dmg gibt es unter [Releases](../../releases).

Quill ist nur ad hoc signiert und nicht von Apple notarisiert. macOS blockiert deshalb den ersten Start, und du bestätigst ihn einmal selbst:

1. `Quill-<Version>.dmg` laden und öffnen.
2. Quill auf den Ordner „Programme“ im Fenster der .dmg ziehen. Danach die .dmg im Finder auswerfen.
3. Quill im Ordner „Programme“ öffnen. macOS meldet, dass Quill nicht geöffnet werden kann, weil Apple die App nicht auf Schadsoftware prüfen konnte. Die Meldung schließen, ohne Quill in den Papierkorb zu legen.
4. Systemeinstellungen › Datenschutz & Sicherheit öffnen und nach unten scrollen. Im Abschnitt zur Sicherheit steht ein Hinweis zu Quill. „Dennoch öffnen“ klicken und mit Passwort oder Touch ID bestätigen.
5. Quill erneut öffnen und in der Rückfrage das Öffnen bestätigen. Ab jetzt startet Quill normal.

**Nach Updates:** Jede neue Version ist neu signiert. Eventuell musst du Schritt 3 bis 5 wiederholen. macOS kann außerdem fragen, ob Quill auf die Daten der bisherigen Version zugreifen darf. Erlaube das, sonst findet Quill deine Seiten nicht. Deine Daten bleiben bei einem Update erhalten.

**Prüfsumme (optional):** `shasum -a 256 ~/Downloads/Quill-<Version>.dmg` muss mit der Datei `Quill-<Version>.dmg.sha256` im Release übereinstimmen.

## Voraussetzungen zum Bauen

- macOS 26 oder neuer, Apple Silicon
- Xcode 27+ (aktiv via `xcode-select`)
- Optional Signier-Team: `Config/Local.xcconfig.example` nach `Config/Local.xcconfig` kopieren und die eigene Team-ID eintragen. Die Datei wird nicht committet; ohne sie baut Xcode mit „Sign to Run Locally“.

## Bauen und testen

```sh
open Quill.xcodeproj           # Scheme „Quill“, ⌘R
# oder im Terminal:
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' build
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' test
swift test --package-path Packages/QuillKit
```

Release bauen: `Scripts/make-release.sh` erzeugt aus einer sauberen Arbeitskopie die ad hoc signierte, geprüfte App als `dist/Quill-<Version>.dmg` samt `.sha256` (ADR-022).

Darstellung prüfen ohne Bildschirmfotos: `EditorSnapshotTests` und `EmptyStateSnapshotTests` rendern Editor und Leerzustände hell und dunkel und legen PNGs in `$TMPDIR/QuillEditorSnapshots/` ab. Das App-Icon (`App/Resources/AppIcon.icon`) wird in Icon Composer bearbeitet. Performance: `python3 Scripts/perf-package.py 3` (Package, optimiert) und `python3 Scripts/perf-ui.py` (App im Schema „Quill Profiling“); Ziele und Messwerte in `docs/performance.md`. Der letzte Stand des Editor-Spikes aus Phase 1 ist der Git-Tag `editor-spike`.

## Daten und Backups

Die Datenbank liegt in `~/Library/Containers/io.github.vogelwild07.quill/Data/Library/Application Support/Quill/Store/`. Automatische Backups (beim Start höchstens einmal pro Tag, vor jeder Migration, beim Beenden nach Änderungen) liegen daneben in `Backups/` und sind über **Ablage → Backups im Finder zeigen** erreichbar. Wiederherstellen über **Ablage → Backup wiederherstellen …**: Quill beendet sich und spielt das Backup beim nächsten Start ein, der vorherige Stand bleibt als Backup erhalten. Falls Quill nicht mehr startet: [von Hand](docs/data-model.md#backup-von-hand-wiederherstellen).

Startargumente für UI-Tests:
Alle wirken nur aus der Kommandozeile und nur in Debug-Builds (ADR-019, ADR-021).
- `-QuillInMemoryStore YES`: Daten nur im Arbeitsspeicher, keine Backups.
- `-QuillStoreDirectory <Name>`: Datenbank und Backups in einem Unterordner des temporären Ordners der App (UI-Test über Neustarts).
- `-QuillPasteboardName <Name>`: Kopieren und Einsetzen im Editor über eine eigene Zwischenablage statt der allgemeinen.
- `-QuillTestImage <Breite>x<Höhe>|heavy`: Die App legt ein selbst erzeugtes Testbild in diese eigene Zwischenablage (nur Debug).

## Struktur

- `App/` – macOS-App-Target (Scenes, Menüleiste, Ressourcen)
- `Packages/QuillKit/` – gesamte Logik: Model, Editor, Features, Export, Design
- `QuillUITests/` – UI-Tests
- `docs/` – [Architektur](docs/architecture.md), [Entscheidungen](docs/decisions.md), [Datenmodell](docs/data-model.md), [Design](docs/design.md), [Roadmap](docs/roadmap.md), [Product Brief](docs/product-brief.md)

## Lizenz

Der Quellcode steht unter der [GNU General Public License, Version 3 oder jeder späteren Version](LICENSE) (GPL-3.0-or-later).

**Ausgenommen ist das App-Icon** (`App/Resources/AppIcon.icon` und alle daraus erzeugten Bilder): Copyright © 2026 vogelwild07, alle Rechte vorbehalten. Wer Quill verändert und weitergibt, ersetzt das Icon durch ein eigenes.
