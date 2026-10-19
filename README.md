# Quill

Local-first, Notion-ähnliche Produktivitäts-App für macOS: Seiten, Notizen und Aufgaben in einem nativen Block-Editor.

> Status: Phase 5 (Navigation) abgeschlossen; als Nächstes Phase 6 (Export). Schnell öffnen (⌘O), Favoriten, Papierkorb mit Auto-Leeren nach 30 Tagen. Seiten mit Block-Editor: Überschriften, Listen, To-dos, Zitat, Code, Trenner, Bilder, Inline-Formatierung und Links; Slash-Menü, Markdown-Kürzel, Blockart per ⌥⌘0–7, Blöcke ziehen, verschieben und duplizieren; Speichern automatisch.

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

Darstellung prüfen ohne Bildschirmfotos: `EditorSnapshotTests` rendert den Editor hell und dunkel und legt PNGs in `$TMPDIR/QuillEditorSnapshots/` ab. Der Performance-Test misst Tippen bei 1000 Blöcken (p95 < 16 ms). Der letzte Stand des Editor-Spikes aus Phase 1 ist der Git-Tag `editor-spike`.

## Daten und Backups

Die Datenbank liegt in `~/Library/Containers/de.vogel.quill/Data/Library/Application Support/Quill/`. Automatische Backups (beim Start höchstens einmal pro Tag, vor jeder Migration, beim Beenden nach Änderungen) liegen daneben in `Backups/` und sind über **Ablage → Backups im Finder zeigen** erreichbar. Wiederherstellen von Hand: [Datenmodell](docs/data-model.md#backup-von-hand-wiederherstellen).

Startargumente für UI-Tests:
- `-QuillInMemoryStore YES`: Daten nur im Arbeitsspeicher, keine Backups.
- `-QuillPasteboardName <Name>`: Kopieren und Einsetzen im Editor über eine eigene Zwischenablage statt der allgemeinen.

## Struktur

- `App/` – macOS-App-Target (Scenes, Menüleiste, Ressourcen)
- `Packages/QuillKit/` – gesamte Logik: Model, Editor, Features, Export, Design
- `QuillUITests/` – UI-Tests
- `docs/` – [Architektur](docs/architecture.md), [Entscheidungen](docs/decisions.md), [Datenmodell](docs/data-model.md), [Design](docs/design.md), [Roadmap](docs/roadmap.md), [Product Brief](docs/product-brief.md)

## Lizenz

Privat, keine Lizenz. Alle Rechte vorbehalten.
