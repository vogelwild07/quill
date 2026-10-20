# Design

Grundlage: Apple Human Interface Guidelines. Eigene Gestaltung; keine Designs, Assets oder Texte anderer Apps.

## Ästhetik

„Papier unter Glas“: Inhaltsflächen matt, ruhig, typografisch. Liquid Glass nur für Sidebar, Toolbar, Slash-Menü und das Panel „Schnell öffnen“ (⌘O). Identität über Typografie, Weißraum und einen eigenen Akzent, nicht über Deko.

## Farben

Außerhalb des Editors nur semantische Systemfarben. Akzent „Petrol“ im `AccentColor`-Asset: Light `#08736C`, Dark `#0A7A72` (Weiß darauf 5,7 bzw. 5,2 : 1). Die vom Nutzer gewählte Systemakzentfarbe wird respektiert. Dark Mode und erhöhter Kontrast automatisch.

## Themes (ADR-024)

Der Editor zeichnet in einem Theme, gewählt unter Einstellungen (⌘,) › Darstellung. Selbst gezeichnete Elemente nehmen ihre Farbe aus `EditorColor` (Rollen statt fester Werte); Sidebar, Symbolleiste und Schriften bleiben im Systemstil.

| Theme | Hell | Dunkel | Charakter |
|---|---|---|---|
| Standard | ✓ | ✓ | Systemfarben; Links Petrol `#08736C` / `#3DCBBE`, Akzent, Zitatbalken und Auswahl `#0B8F86` / `#3DCBBE` |
| Quill | ✓ | ✓ | Signatur: Hintergrund `#F7FBFA` / `#151D23`, Text Tinte, Überschriften Petrol, Auswahl Sonnengelb, Zitatbalken hell Petrol, dunkel Sonnengelb |
| Tinte | ✓ | ✓ | Blaugrau, zurückhaltend |
| Sonne | ✓ | – | warmes Papier `#FFF8E6`, Zitatbalken dunkles Bernstein `#B07A00` |
| Lagune | – | ✓ | tiefes Petrol `#062E2B` |
| Abend | – | ✓ | warmes Dunkel `#1C1A16`, Checkbox Sonnengelb |
| Kontrast | ✓ | ✓ | Schwarz auf Weiß bzw. Weiß auf Schwarz |

Regeln: jede Textrolle mindestens 4,5 : 1 (zum Hintergrund, zur Codefläche, auf der Auswahl), Platzhalter der leeren Seite 4,5 : 1, Grafik (Zitatbalken, Checkbox, Ziehgriff, Plus-Knopf, Trennlinie) 3 : 1. Mit „Kontrast erhöhen“ Text und Platzhalter 7 : 1, Ziehgriff, Plus und Trennlinie 4,5 : 1 (abgeleitet). Platzhalter und Bedienelemente sind aus der Textfarbe abgeleitet: so zurückhaltend wie möglich, aber über dem Mindestkontrast. Sonnengelb `#FFC23A` nur für Flächen, nie für Text, und nur wo es 3 : 1 erreicht. Feste Themes erzwingen hell bzw. dunkel nur im Editor. Werte in `EditorTheme.swift`, geprüft von `EditorThemeContrastTests` (Rechnung) und `EditorThemeControlTests` (gezeichnet, jedes Theme bei hellem und dunklem System).

## Fokus-Modus (ADR-027)

Darstellung › Fokus-Modus (⇧⌘F) oder Einstellungen › Darstellung. Die Zeile mit dem Cursor bleibt in der Mitte des Fensters; alle anderen Blöcke und der Seitenkopf treten in Richtung Theme-Hintergrund zurück. Abgedunkelter Fließtext hat mindestens 3 : 1, mit „Kontrast erhöhen“ 4,5 : 1 (`ResolvedPalette.dimmedAlpha`, je Theme und Variante berechnet). Überschrift, Link, Zitat, Listenmarker und erledigte To-dos fallen ebenfalls nicht darunter; schwächere Rollen werden dafür weniger abgedunkelt. Mit einer Auswahl bleiben alle berührten Blöcke hell und es wird nicht gescrollt. Liegt der Fokus im Titel oder in der Sidebar, ist nichts abgedunkelt. Sidebar und Symbolleiste bleiben unverändert; sie lassen sich wie gewohnt ausblenden (⌃⌘S). Gespeichert pro Mac, wie das Theme.

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
- Editor-Textkörper max. 720 pt, zentriert, mindestens 56 pt Rand seitlich, 96 pt Rand
  über dem Seitenkopf, 12 pt zwischen Kopf und erstem Block
- 4-pt-Raster; Block-Abstand 4 pt, vor Überschriften 16 pt
- Eckenradien 4 pt (Inline-Code, Checkbox, Bild), 6 pt (Bild-Platzhalter), 8 pt
  (Code-Block, Hinweise)
- Alle Werte als Tokens in `QuillDesign` (`Typography`, `Spacing`, `EditorLayout`, `Radius`)
- Block-Griff nur bei Hover im linken Rand

## Interaktionsprinzipien

- Tastatur zuerst: alles per Shortcut erreichbar
- Keine modalen Dialoge außer „Endgültig löschen“
- Autosave, kein Speichern-Befehl; Undo überall
- Löschen = Papierkorb
- Animationen ≤ 200 ms (Spring), respektieren „Bewegung reduzieren“ (`QuillDesign.Motion`:
  Überblenden statt Gleiten, Hinweise ohne Ausblenden)
- Kontextmenüs überall
- Vollständige Menüleiste: Ablage, Bearbeiten, Format, Darstellung, Seite, Fenster, Hilfe
- Ein Fenster mit System-Tabs (⌘T); Seite optional in neuem Fenster

## Leerzustände

Nach HIG: Symbol, Titel, ein Satz Erklärung, wo es passt ein Knopf. Alle Fälle im Katalog
`EmptyState` (`QuillFeatures/Shared/EmptyState.swift`), angezeigt über `EmptyStateView`:

| Fall | Titel | Knopf |
|---|---|---|
| Keine Auswahl | Keine Seite ausgewählt | Neue Seite |
| Sidebar, Schnell öffnen vor der ersten Seite | Noch keine Seiten | – |
| Seite fehlt | Seite nicht gefunden | – |
| Papierkorb | Der Papierkorb ist leer | – |
| Backups | Noch keine Backups | – |
| Schnell öffnen ohne Treffer | Keine Treffer | – |

Symbol grau; Titel und Erklärung in primary, weil der Systemstil hell nur 3,1:1 erreicht
(WCAG verlangt 4,5:1). Eine leere Seite zeigt im Editor „Leere Seite – mit „/“ wählst du
eine Blockart.“ in der Platzhalterfarbe; der Hinweis ist nur gezeichnet und verschwindet
beim ersten Zeichen.

## Bedienungshilfen

- Jedes Bedienelement hat eine Beschriftung; Listen heißen „Seiten“, „Seiten im
  Papierkorb“, „Backups“; Panels „Schnell öffnen“ (modal) und „Block einfügen“.
- Tab-Schleife: Sidebar →Tab→ Titel →Tab→ Editor →⌃Tab→ Sidebar (Tab allein rückt im
  Editor ein). Rückwärts: Sidebar →⇧Tab→ Editor →⇧⌃Tab→ Titel →⇧Tab→ Symbol →⇧Tab→
  Sidebar; das Symbol liegt nur auf dem Rückweg.
- Kontrast mindestens 4,5:1 auf matten Flächen (geprüft in `EmptyStateSnapshotTests`).
  Ausnahmen im Audit (`AccessibilityAuditUITests`) nur einzeln mit Begründung: Systemstil
  von Source-List und Symbolleiste, Text auf Glas (Sidebar, Hinweise in Schnell öffnen und
  Slash-Menü), gedimmte Zeilen und Kopf des Papierkorbs hinter dem Sheet „Backup
  wiederherstellen“ (Kennungen `trash.row`, `trash.header.title`, `trash.header.subtitle`).

## App-Icon

`App/Resources/AppIcon.icon` (Icon Composer, ADR-023): eine Seite aus Quill mit Überschrift,
Bild-Block (Sonne über Hügeln) und abgehaktem To-do auf Petrol (`#0B8F86`, Markenfarbe).
Vier Ebenen in einer Gruppe, von unten: Seite (Weiß, Liquid Glass), Text (Tinte `#1F2A33`),
Bild und Haken (Petrol), Sonne und Hügel (Sonnengelb `#FFC23A`, Liquid Glass). Hintergrund als
Füllung der Datei. Bei 16 pt bleibt „Seite mit Inhalt“ erkennbar.

Dunkel: Den Hintergrund setzt macOS im dunklen Modus selbst (Schwarz), eine eigene Füllung
für dunkel wird ignoriert. Wirksam sind nur Farben je Ebene (`fill-specializations` der
Ebenen): Seite dunkelgrau `#33373C`, Text `#E6EBEE`, Petrol heller `#3DCBBE`, Gelb `#FFC74D`.
Prüfen offline mit `ictool` aus Icon Composer (`--rendition Default|Dark|ClearLight`) und im
gebauten Bundle über `Assets.car`. Anpassen nur in Icon Composer.

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
