# Entscheidungen (ADR-Log)

Format: Kontext → Entscheidung → Konsequenzen. Neueste unten.

## ADR-001: Plattform und Stack (2026-10-18)

**Entscheidung:** macOS 26+, nur Apple Silicon. Swift 6, SwiftUI (AppKit wo nötig), SwiftData lokal. Später CloudKit und iPhone/iPad.
**Konsequenzen:** Liquid Glass und neueste SwiftUI-APIs ohne Fallbacks. Logik in plattformneutralem Package `QuillKit`.

## ADR-002: CloudKit-taugliches Modell ab Tag 1 (2026-10-18)

**Entscheidung:** UUIDs, `createdAt`/`updatedAt`, alle Attribute optional oder mit Default, keine `unique`-Constraints, optionale Beziehungen, Reihenfolge per `sortKey` (Fractional Indexing), `VersionedSchema` von Anfang an.
**Konsequenzen:** Sync später ohne Datenmigration. Eindeutigkeit (z. B. genau ein Workspace) muss im Code sichergestellt werden.

## ADR-003: Ein Workspace im MVP (2026-10-18)

**Entscheidung:** UI kennt genau einen Workspace; das Modell enthält `Workspace` bereits.
**Konsequenzen:** Mehrere Workspaces später ohne Migration.

## ADR-004: Ein Fenster mit System-Tabs (2026-10-18)

**Entscheidung:** `WindowGroup` mit Sidebar + Editor, native Tabs (⌘T), Seite optional in neuem Fenster.
**Konsequenzen:** Navigationszustand pro Fenster (Scene Storage), nicht global.

## ADR-005: Signing mit Personal Team (2026-10-18)

**Entscheidung:** Vorerst kostenloses Personal Team, App Sandbox aktiv.
**Konsequenzen:** Keine Notarisierung, kein CloudKit-Container. Wechsel auf bezahlten Account vor Sync/App Store.

## ADR-006: Markdown-Export als Ordner (2026-10-18)

**Entscheidung:** Export einer Seite oder eines Teilbaums als Ordner: eine `.md` pro Seite, Unterseiten als Unterordner, Bilder in `assets/`, relative Links.

## ADR-007: Block-Editor auf einem NSTextView mit TextKit 2 (vorläufig, 2026-10-18)

**Kontext:** Größtes Projektrisiko.
**Entscheidung:** Vorläufig ein `NSTextView` pro Seite; Absatz = Block. Validierung im Spike (Phase 1), siehe `architecture.md`.
**Status:** offen bis Spike-Ergebnis.
