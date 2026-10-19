# Quill

Local-first, Notion-ähnliche Produktivitäts-App für macOS: Seiten, Notizen und Aufgaben in einem nativen Block-Editor.

> Status: Phase 7 (Feinschliff) abgeschlossen: Backup wiederherstellen, Aufräumen und Performance (Messung siehe `docs/performance.md`), Bedienungshilfen mit Audit, Leerzustände, vollständige deutsche Lokalisierung und App-Icon; als Nächstes das Release v0.1. Export einer Seite oder eines Seitenbaums als Markdown-Ordner mit Bildern (⇧⌘E), Schnell öffnen (⌘O), Favoriten, Papierkorb mit Auto-Leeren nach 30 Tagen. Seiten mit Block-Editor: Überschriften, Listen, To-dos, Zitat, Code, Trenner, Bilder, Inline-Formatierung und Links; Slash-Menü, Markdown-Kürzel, Blockart per ⌥⌘0–7, Blöcke ziehen, verschieben und duplizieren; Speichern automatisch.

## Voraussetzungen

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

Darstellung prüfen ohne Bildschirmfotos: `EditorSnapshotTests` und `EmptyStateSnapshotTests` rendern Editor und Leerzustände hell und dunkel und legen PNGs in `$TMPDIR/QuillEditorSnapshots/` ab. Das App-Icon (`App/Resources/AppIcon.icon`) wird in Icon Composer bearbeitet. Performance: `python3 Scripts/perf-package.py 3` (Package, optimiert) und `python3 Scripts/perf-ui.py` (App im Schema „Quill Profiling“); Ziele und Messwerte in `docs/performance.md`. Der letzte Stand des Editor-Spikes aus Phase 1 ist der Git-Tag `editor-spike`.

## Daten und Backups

Die Datenbank liegt in `~/Library/Containers/de.vogel.quill/Data/Library/Application Support/Quill/Store/`. Automatische Backups (beim Start höchstens einmal pro Tag, vor jeder Migration, beim Beenden nach Änderungen) liegen daneben in `Backups/` und sind über **Ablage → Backups im Finder zeigen** erreichbar. Wiederherstellen über **Ablage → Backup wiederherstellen …**: Quill beendet sich und spielt das Backup beim nächsten Start ein, der vorherige Stand bleibt als Backup erhalten. Falls Quill nicht mehr startet: [von Hand](docs/data-model.md#backup-von-hand-wiederherstellen).

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

Privat, keine Lizenz. Alle Rechte vorbehalten.
