# Quill

Local-first, Notion-ähnliche Produktivitäts-App für macOS: Seiten, Notizen und Aufgaben in einem nativen Block-Editor.

> Status: Phase 0 (Setup). Noch keine nutzbare App.

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

## Struktur

- `App/` – macOS-App-Target (Scenes, Menüleiste, Ressourcen)
- `Packages/QuillKit/` – gesamte Logik: Model, Editor, Features, Export, Design
- `QuillUITests/` – UI-Tests
- `docs/` – [Architektur](docs/architecture.md), [Entscheidungen](docs/decisions.md), [Datenmodell](docs/data-model.md), [Design](docs/design.md), [Roadmap](docs/roadmap.md), [Product Brief](docs/product-brief.md)

## Lizenz

Privat, keine Lizenz. Alle Rechte vorbehalten.
