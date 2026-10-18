# Quill

Local-first, Notion-ähnliche Produktivitäts-App für macOS: Seiten, Notizen und Aufgaben in einem nativen Block-Editor.

> Status: Phase 2 (Datenmodell + Sidebar) abgeschlossen. Seiten anlegen, verschachteln, verschieben, Tabs. Der Editor folgt in Phase 3.

## Voraussetzungen

- macOS 26 oder neuer, Apple Silicon
- Xcode 27+ (aktiv via `xcode-select`)

## Bauen und testen

```sh
open Quill.xcodeproj           # Scheme „Quill“, ⌘R
# oder im Terminal:
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' build
xcodebuild -project Quill.xcodeproj -scheme Quill -destination 'platform=macOS' test
swift test --package-path Packages/QuillKit
```

Editor-Spike (Wegwerf-Prototyp aus Phase 1): Scheme „EditorSpike“, ⌘R. Mit `-benchmark` misst er 1000 Blöcke und gibt JSON aus, mit `-snapshot` schreibt er Bilder (hell und dunkel) in den temporären Ordner der App.

## Daten und Backups

Die Datenbank liegt in `~/Library/Containers/de.vogel.quill/Data/Library/Application Support/Quill/`. Automatische Backups (beim Start höchstens einmal pro Tag, vor jeder Migration, beim Beenden nach Änderungen) liegen daneben in `Backups/` und sind über **Ablage → Backups im Finder zeigen** erreichbar. Wiederherstellen von Hand: [Datenmodell](docs/data-model.md#backup-von-hand-wiederherstellen).

Startargument `-QuillInMemoryStore YES`: Daten nur im Arbeitsspeicher, keine Backups (UI-Tests).

## Struktur

- `App/` – macOS-App-Target (Scenes, Menüleiste, Ressourcen)
- `Packages/QuillKit/` – gesamte Logik: Model, Editor, Features, Export, Design
- `QuillUITests/` – UI-Tests
- `Spikes/EditorSpike/` – Wegwerf-Target des Editor-Spikes (wird in Phase 3 entfernt)
- `docs/` – [Architektur](docs/architecture.md), [Entscheidungen](docs/decisions.md), [Datenmodell](docs/data-model.md), [Design](docs/design.md), [Roadmap](docs/roadmap.md), [Product Brief](docs/product-brief.md)

## Lizenz

Privat, keine Lizenz. Alle Rechte vorbehalten.
