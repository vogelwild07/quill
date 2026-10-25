# Design

Grundlage: Apple Human Interface Guidelines. Eigene Gestaltung; keine Designs, Assets oder Texte anderer Apps.

## Ästhetik

„Papier unter Glas“: Inhaltsflächen matt, ruhig, typografisch. Liquid Glass nur für Sidebar, Toolbar, Slash-Menü, Popover, das Panel „Schnell öffnen“ (⌘O) und das Fenster der Schnellnotiz; wie durchsichtig, steuert der Regler „Liquid Glass“ (ADR-036). Identität über Typografie, Weißraum und einen eigenen Akzent, nicht über Deko.

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

Darstellung › Fokus-Modus (⇧⌘F) oder Einstellungen › Darstellung. Die Zeile mit dem Cursor bleibt in der Mitte des Fensters; alle anderen Blöcke und der Seitenkopf treten in Richtung Theme-Hintergrund zurück. Abgedunkelter Fließtext hat mindestens 3 : 1, mit „Kontrast erhöhen“ 4,5 : 1 (`ResolvedPalette.dimmedAlpha`, je Theme und Variante berechnet). Überschrift, Link, Zitat, Listenmarker und erledigte To-dos fallen ebenfalls nicht darunter; schwächere Rollen werden dafür weniger abgedunkelt. Mit einer Auswahl bleiben alle berührten Blöcke hell und es wird nicht gescrollt. Liegt der Fokus im Titel oder in der Sidebar, ist nichts abgedunkelt. Ein leerer Titel (Platzhalter „Ohne Titel“) bleibt hell. Sidebar und Symbolleiste bleiben unverändert; sie lassen sich wie gewohnt ausblenden (⌃⌘S). Gespeichert pro Mac, wie das Theme.

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
- Alle Werte als Tokens in `QuillDesign` (`Typography`, `Spacing`, `EditorLayout`, `Radius`, `SyncNotice`, `TimeTravel`)
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

## Sync-Hinweise (11.6, ADR-029)

- **Zeichen am Blockrand:** rechts neben der Textspalte (16 pt, 12 pt Abstand,
  `QuillDesign.blockMarkerSize`/`blockMarkerGap`), nur gezeichnet, klickbar, für VoiceOver
  ein Knopf. Zwei Fassungen: zwei versetzte Quadrate in `EditorColor.accent`.
  Wiederhergestellt: Pfeil zurück in `EditorColor.secondary`. Ein Konflikt geht vor.
  Klick öffnet ein Popover (Wahl je Fassung mit Gerät bzw. Erklärung und „Markierung
  entfernen“).
- **Hinweis unter dem Seitentitel:** matte Fläche (`quaternary` mit 50 % Deckkraft, 8 pt Radius, Maße in `QuillDesign.SyncNotice`), kein Glas,
  weil Inhalt. „N Stellen mit zwei Fassungen · Wählen …“ und bei einer wiederhergestellten
  Seite „Markierung entfernen“ und „In den Papierkorb“.
- **Sidebar:** Symbol `arrow.uturn.backward.circle` am Zeilenende mit Tooltip; Kontextmenü
  „Markierung entfernen“.
- **Einstellungen › Sync:** unter der Zahl der Konflikte die Seiten als Links, Klick springt
  zur Stelle.
- Pausiert sind die Wahlknöpfe aus, mit Hinweis „Zum Wählen Sync fortsetzen.“; eine Marke
  verschwindet nie von selbst.

## Zeitreise (12.3, ADR-031)

- Eigenes Fenster je Seite (900 × 640 pt), links die Tage (`NavigationSplitView`, Spalte
  180–220 pt), rechts der frühere Stand im Block-Editor im Lesemodus: Cursor und Markieren
  gehen, Ändern nicht; Menü „Format“ ist gesperrt, Tastenkürzel ohne Menü geben einen Ton.
- „Auswahl zurückholen“ in der Toolbar (`arrow.uturn.backward`), aktiv nur mit Markierung
  und solange die Seite nicht im Papierkorb liegt.
- Hinweise über dem Stand mit `ProblemLabel` (Zurückholen gescheitert, Bilder nicht mehr
  aufbewahrt), Rand `QuillDesign.TimeTravel.noticePadding`.
- Einstellungen › Zeitreise: Frist für gelöschte Bilder als Optionsfelder (vier Werte).

## Lokale KI

- Einstellungen › KI (`sparkles`): mit bereitem Modell ein Schalter „KI-Funktionen
  verwenden“ mit dem Hinweis, dass nichts ins Netz geht; ohne Modell statt des Schalters
  eine Erklärung mit `info.circle` (ein ausgegrauter Schalter wäre im Audit zu blass).
- Seite › „Zusammenfassen …“ nur mit bereitem Modell und eingeschalteter KI. Blatt mit
  Fortschritt, dann dem Text (auswählbar) und dem Hinweis, dass das Modell auf dem Mac ihn
  erstellt hat und er geprüft werden soll; Knöpfe „Kopieren“ und „Einfügen“ (Standard, nur
  wenn der Editor den Fokus hatte), „Schließen“ mit Escape. Fehler nennen den Grund in einem Satz.
- Seite › „To-dos vorschlagen …“ direkt darunter, gleiche Bedingung. Arbeitet auf den markierten
  Absätzen; ohne Markierung sagt das Blatt, was zu tun ist. Vorschau als Liste mit `square`,
  „Einfügen“ (Standard) legt sie als To-do-Blöcke unter die Markierung, die Absätze bleiben.
- Ablage › „Frag deine Notizen …“ unter „Schnell öffnen …“, gleiche Bedingung. Blatt mit Feld
  (Fokus beim Öffnen, ↩ fragt), Fortschritt, Antwort (auswählbar) und darunter „Quellen“ als
  Links mit `doc.text`; ein Klick öffnet die Seite und schließt das Blatt. Hinweis, dass das
  Modell auf dem Mac nur aus diesen Seiten antwortet.
- Seite › „Verwandte Seiten …“ unter „To-dos vorschlagen …“, gleiche Bedingung. Blatt mit
  Titel der Seite, Fortschritt, dann bis zu fünf Seiten als Links mit `doc.text`, darunter
  in Sekundärfarbe „Gemeinsam: …“ mit den gemeinsamen Begriffen; ein Klick öffnet die Seite
  und schließt das Blatt. Hinweis, dass das Modell auf dem Mac die Seiten anhand gemeinsamer
  Begriffe vorschlägt. Ohne Treffer der Leerzustand „Keine verwandten Seiten“ aus dem Katalog.

## Apple-Ökosystem

- Einstellungen › Spotlight (`magnifyingglass`, nach KI): Schalter „Seiten in Spotlight
  zeigen“, Standard aus, darunter in einem Satz, was in den Suchindex des Macs kommt und dass
  Ausschalten alle Einträge entfernt. Treffer in Spotlight zeigen Titel (oder „Ohne Titel“)
  und Text; ein Klick öffnet die Seite im vordersten Fenster.
- Einstellungen › Schnellnotiz (`square.and.pencil`, nach Spotlight): „Schnellnotiz in der
  Menüleiste“ und, nur damit, „Kürzel ⌃⌥⌘N in allen Apps“, beide Standard aus; ist das
  Kürzel belegt, sagt das ein roter Satz darunter. Symbol in der Menüleiste
  `square.and.pencil` (Vorlage, passt sich der Leiste an).
- Fenster der Schnellnotiz: klein (360 × 220), schwebend, über allen Spaces, holt Quill nicht
  nach vorn. Textfeld mit Fokus, darunter grau „Die erste Zeile wird der Titel der neuen
  Seite.“ (bei einem Fehler rot, der Entwurf bleibt), Knöpfe „Abbrechen“ (Esc) und „Als Seite
  sichern“ (⌘↩, ohne Text gesperrt). Mit aktivem Regler „Liquid Glass“ ist das Fenster
  ganz aus Glas, auch unter der Titelleiste; bei „Wie System“ normale Fensterfläche (ADR-036).
- Erinnerung (Format › Erinnerung …): Blatt 400 pt breit, Überschrift „Erinnerung“, darunter
  grau der Text des To-dos, Datum und Uhrzeit (Vorschlag morgen 9:00), ein Satz, dass eine
  Mitteilung auf diesem Mac erinnert (Fehler rot an derselben Stelle). Am To-do eine Glocke in
  `EditorColor.secondary` am rechten Rand, selbst gezeichnet wie die Zeichen aus 11.6; das
  Popover nennt den Zeitpunkt fett in der Überschrift (normaler Text hielt auf dem Glas den
  Kontrast nicht) und bietet „Erinnerung entfernen“. Mitteilung: Text des To-dos, darunter
  der Seitentitel.
- Tagesseite (Ablage › Heute, ⇧⌘T): Titel wie das lange Datum („Freitag, 23. Oktober 2026“),
  unter der Sammelseite „Tage“, der neueste Tag oben. „Format › Heutige Termine einfügen“
  setzt eine Aufzählung unter den Block an der Einfügemarke: ganztägige Termine zuerst
  („Ganztägig: Geburtstag“), dann nach Beginn („9:00–10:00 Zahnarzt“, Uhrzeit im Format des
  Systems). Fehlt die Einfügemarke, der Zugriff auf den Kalender oder ein Termin, sagt das eine
  Meldung „Heute“ in einem Satz. Rückfrage des Systems: „Quill liest deinen Kalender nur, wenn
  du die heutigen Termine in eine Seite einfügst.“
- Kurzbefehle: Titel und Siri-Sätze auf Deutsch, Antwort von „Zu Seite hinzufügen“ in einem
  Satz mit dem Titel der Seite.
- Text in Bildern (ADR-034): In „Schnell öffnen“ stehen Bilder unter „Inhalt“ wie Treffer im
  Text, der Ausschnitt aus dem erkannten Text mit SF Symbol `photo` davor; Bedienungshilfen
  lesen „Seite, Bild, Ausschnitt“. Enter setzt die Einfügemarke vor das Bild.
- Sprachnotiz (ADR-034): „Format › Sprachnotiz …“ öffnet ein Blatt mit „Aufnehmen“ (SF Symbol
  `mic.fill`) bzw. „Stopp“ (`stop.fill`) links, „Abbrechen“ und „Einfügen“ rechts. Die
  Abschrift steht live darüber, unsichere Wörter in Sekundärfarbe; ein Satz darunter sagt, dass
  die Aufnahme nicht gespeichert wird. Fehler (Mikrofon nicht erlaubt, Sprache nicht
  installiert, kein Mikrofon) stehen als `ProblemLabel` im Blatt. Rückfrage des Systems:
  „Quill nutzt das Mikrofon nur, während du eine Sprachnotiz aufnimmst. Die Aufnahme wird auf
  diesem Mac abgeschrieben und nicht gespeichert.“
- Liquid Glass (ADR-036): Einstellungen › Darstellung unter dem Fokus-Modus, Überschrift
  „Liquid Glass“, Schalter „Wie System“ (Standard an) mit Erklärung, darunter der Regler
  (320 pt) zwischen `circle.dotted` (klar) und `circle.fill` (getönt) mit fünf
  Rasterpunkten, Standard Mitte. Ausgegraut bei „Wie System“ und bei „Transparenz
  reduzieren“, dann darunter grau mit `info.circle` der Hinweis, dass das Glas deckend ist.
  Getönt wird mit der Hintergrundfarbe des Themes; Text auf dem Glas Schwarz bzw. Weiß,
  Nebentext mit 85 % Deckkraft. Knöpfe der Toolbar in eigenen Kapseln (8 × 5 pt Abstand).
  Vorschaubilder (Näherung) in `Design/Vorschau/`.
- Updates (ADR-037): Einstellungen › Allgemein (`gearshape`, erster Bereich, öffnet nach dem
  Start) mit Schalter „Automatisch suchen“ samt Erklärung (einmal am Tag, nur die Liste der
  Versionen, Backup vorher, Menüpunkt) und „Zuletzt geprüft“ (Datum oder „Noch nie“). Menü
  „Quill › Nach Updates suchen …“ unter „Über Quill“; aus, wo Quill nicht suchen kann. Frage
  beim ersten Start als `NSAlert` „Automatisch nach Updates suchen?“, Knöpfe „Nicht suchen“
  (Standard, Return und Escape) und „Automatisch suchen“. Fenster „Update“ (440 pt, kein
  Glas): Titel in `.headline`, ein Satz darunter, Fortschrittsbalken beim Suchen, Laden und
  Prüfen; bei „Quill 0.5.0 ist da.“ der Text der Version in einer Fläche wie die Lizenzen und
  die Knöpfe „Diese Version überspringen“ (links), „Später“ und „Installieren“ (Standard).
  Fehler mit „Update nicht möglich“ und einem Satz, was passiert ist und dass nichts
  installiert wurde. Die Suche im Hintergrund zeigt nur ein gefundenes Update, nie Fehler.
- Präsentieren (ADR-035): „Seite › Präsentieren“ (⌥⌘P) öffnet die Seite im Vollbild ohne
  Titelleiste auf dem Hintergrund des Themes. Die Folie ist der Editor im Lesemodus ohne
  Schreibmarke und ohne ＋/⋮⋮, vergrößert auf die Breite (höchstens 2,5-fach); unten rechts
  „Folie 2 von 5“ in `.callout` und Sekundärfarbe. Esc beendet.

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
| Zeitreise ohne Geschichte | Noch keine Geschichte | – |
| Zeitreise, Geschichte nicht lesbar | Geschichte nicht lesbar | – |
| Verwandte Seiten ohne Treffer | Keine verwandten Seiten | – |

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

`App/Resources/AppIcon.icon` (Icon Composer, ADR-023): ein weißer Slash mit Schreibmarke auf
Petrol (`#0B8F86`, Markenfarbe, Füllung der Datei). Zwei Gruppen:
- **Vorn** (Liquid Glass, zurückhaltend: Glanzlicht, keine Lichtdurchlässigkeit, Schatten 25 %):
  Slash in Weiß, gezeichnete Form mit runden Enden, 15 % der Breite stark, 25° geneigt, leicht
  links der Mitte; rechts daneben die Schreibmarke als senkrechter, runder Balken in Sonnengelb
  `#FFC23A`, 75 % der Slash-Höhe.
- **Kante** (ohne Liquid Glass): eine Kopie des Slash in dunklem Petrol `#065C56`, um 3 % nach
  rechts unten versetzt. Die Schreibmarke hat keine Kante; mit Kante wirkte sie bei 16 pt wie
  ein doppelter Balken.

Bei 16 pt @2x ist die Kante ein sauberer Pixel, bei @1x (ohne Retina) ein leichter Saum. Eine
`.icon`-Datei kann nicht nach Größe unterscheiden, nur nach Erscheinungsbild und Gerät.

Dunkel: Den Hintergrund setzt macOS im dunklen Modus selbst (Schwarz), eine eigene Füllung
für dunkel wird ignoriert. Wirksam sind nur Farben je Ebene (`fill-specializations` der
Ebenen): Slash `#F2F5F5`, Schreibmarke `#FFC74D`, Kante Petrol `#159F95` (auf Schwarz gut
sichtbar).
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
