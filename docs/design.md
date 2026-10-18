# Design

Grundlage: Apple Human Interface Guidelines. Quill ist kein Notion-Klon und übernimmt keine Notion-Designs oder -Assets.

## Ästhetik

„Papier unter Glas“: Inhaltsflächen matt, ruhig, typografisch. Liquid Glass nur für Sidebar, Toolbar, Slash-Menü und das Panel „Schnell öffnen“ (⌘O). Identität über Typografie, Weißraum und einen eigenen Akzent, nicht über Deko.

## Farben

Nur semantische Systemfarben: `labelColor`, `secondaryLabelColor`, `tertiaryLabelColor`, `separatorColor`, `textBackgroundColor`, `quaternarySystemFill` (Code, Hover).

Akzent „Tinte“ im `AccentColor`-Asset: Light `#3346D3`, Dark `#8A97FF`. Die vom Nutzer gewählte Systemakzentfarbe wird respektiert. Dark Mode und erhöhter Kontrast automatisch.

## Typografie

| Token | Schrift | Größe/Gewicht | Zeilenhöhe |
|---|---|---|---|
| pageTitle | SF Pro Display | 32 Bold | 1.15 |
| h1 / h2 / h3 | SF Pro | 26 Bold / 21 Semibold / 17 Semibold | 1.25 |
| body | SF Pro Text | 15 Regular | 1.5 |
| code | SF Mono | 13 Regular | 1.45 |
| secondary | SF Pro | 12 | – |

Skalierung über eigenen Faktor (⌘+ / ⌘−).

## Layout

- Sidebar 220–320 pt (`NavigationSplitView`)
- Editor-Textkörper max. 720 pt, zentriert, 96 pt Rand oben
- 4-pt-Raster; Block-Abstand 4 pt, vor Überschriften 16 pt
- Block-Griff nur bei Hover im linken Rand

## Interaktionsprinzipien

- Tastatur zuerst: alles per Shortcut erreichbar
- Keine modalen Dialoge außer „Endgültig löschen“
- Autosave, kein Speichern-Befehl; Undo überall
- Löschen = Papierkorb
- Animationen ≤ 200 ms (Spring), respektieren „Bewegung reduzieren“
- Kontextmenüs überall
- Vollständige Menüleiste: Ablage, Bearbeiten, Format, Darstellung, Seite, Fenster, Hilfe
- Ein Fenster mit System-Tabs (⌘T); Seite optional in neuem Fenster

## Wireframes

### Hauptfenster

```
┌─────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  ⟨sidebar⟩   ‹ ›   📝 Projekte / Quill            ☆   ⋯   ⌕     │ ← Glass-Toolbar
├────────────────────┬────────────────────────────────────────────────────┤
│ ⌕ Suchen      ⌘O   │                                                    │
│                    │        📝 Quill                                    │
│ FAVORITEN          │        ─────────────────────────────               │
│  ★ Inbox           │        Text …                                      │
│  ★ Wochenplan      │                                                    │
│                    │                                                    │
│ SEITEN             │                                                    │
│  ▾ 📁 Projekte     │                                                    │
│     ▸ 📝 Quill     │                                                    │
│     ▸ 📝 Reise     │                                                    │
│  ▸ 📓 Journal      │                                                    │
│  ＋ Neue Seite     │                                                    │
│                    │                                                    │
│ 🗑 Papierkorb      │                                                    │
└────────────────────┴────────────────────────────────────────────────────┘
   Glass-Sidebar                  matte Inhaltsfläche
```

### Editor (Hover über Block)

```
            📝 Quill
            Eine Notizen-App für den Mac.

            ## Ziele
     ⋮⋮ ＋   ☐ Block-Editor-Spike abschließen        ← Griff + Einfügen bei Hover
            ☑ Datenmodell entwerfen
            • Schnell
                ◦ Start < 1 s                         ← Tab = Einrückung
            ┃ Zitat mit Akzentbalken
            ┌──────────────────────────────┐
            │ let quill = "local-first"    │ Swift ▾
            └──────────────────────────────┘
            ─────────────────────────────────
            ▭ [ Bild, skaliert auf Textbreite ]
```

### Slash-Menü

```
            /üb█
            ┌──────────────────────────────┐
            │ GRUNDBLÖCKE                  │
            │ ▸ H1  Überschrift 1     #    │
            │   H2  Überschrift 2     ##   │
            │   H3  Überschrift 3     ###  │
            ├──────────────────────────────┤
            │ ↑↓ wählen  ↩ einfügen  ⎋     │
            └──────────────────────────────┘
```

### Schnell öffnen ⌘O

```
        ┌────────────────────────────────────────────┐
        │ ⌕  reise█                                  │
        ├────────────────────────────────────────────┤
        │ SEITEN                                     │
        │ ▸ 📝 Reise nach Lissabon    Projekte       │
        │   📝 Reisekosten            Finanzen       │
        │ INHALT                                     │
        │   „…Flug für die Reise buchen…“  Inbox     │
        ├────────────────────────────────────────────┤
        │ ↩ öffnen   ⌘↩ in neuem Tab   ⎋ schließen   │
        └────────────────────────────────────────────┘
```
