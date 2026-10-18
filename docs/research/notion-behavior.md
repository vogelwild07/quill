# Notion – Verhaltensbeobachtungen

Stand: 2026-10-18 · Notion.app 7.39.0 (lokal installiert)

Nur beobachtetes Verhalten und eigene Schlüsse. Kein Code, keine Assets, keine Texte aus Notion.

## Methode und Grenzen

- **Erlaubt:** passive Metadaten (`Info.plist`), Typen auf der Zwischenablage, nachdem der Nutzer selbst kopiert hat.
- **Bewusst nicht gemacht:** Analyse des JavaScript-Bundles oder Binaries (wäre Code-Analyse, kein Verhalten). Tippen oder Ziehen in Notion-Seiten (würde das Notion des Nutzers verändern).
- REA (`observe_native_ui`) setzt ein geöffnetes Analyseziel voraus. Das ist bereits statische Analyse, darum nicht genutzt.

## Beobachtungen

### Metadaten (`Info.plist`)

| Feld | Wert | Schluss für Quill |
|---|---|---|
| `NSPrincipalClass` | `AtomApplication` | Electron-App; nativ fehlen z. B. Services, echte Textsysteme, Systemrechtschreibung pro Feld. Darin kann sich Quill abheben. |
| `CFBundleURLTypes` | `notion` | Quill bekommt eigenes Schema `quill://` (Deep Links auf Seiten, später). |
| `CFBundleDocumentTypes` | Markdown (Viewer) | Quill: Markdown-Import später als Editor-Rolle. |
| `LSMinimumSystemVersion` | 13.0 | – |

### Zwischenablage

_Offen._ Erhebung: Der Nutzer kopiert in Notion Inhalte (siehe unten), danach `swift Scripts/pasteboard-types.swift`. Es werden nur Typnamen und Größen festgehalten, keine Inhalte.

| Kopierter Inhalt | Typen auf der Zwischenablage |
|---|---|
| Ein Wort im Fließtext | _offen_ |
| Mehrere Blöcke (Überschrift, Liste, To-do) | _offen_ |
| Ein ganzer Block über den Griff | _offen_ |

## Eigene Ideen und Entscheidungen (unabhängig von Notion)

- **Kopieren aus Quill** schreibt mehrere Darstellungen: `public.utf8-plain-text`, `net.daringfireball.markdown`, `public.rtf` sowie einen eigenen Typ `de.vogel.quill.blocks` (JSON mit Blockarten). Fremde Apps bekommen damit sinnvolles Markdown bzw. formatierten Text, Quill selbst verlustfrei Blöcke.
- **Shortcuts** folgen macOS-Konventionen (⌘B/I, ⌘K Link, ⌘Z/⇧⌘Z, Tab/⇧Tab) und gängigen Markdown-Kürzeln; nichts Notion-Spezifisches nötig.
- **Slash-Menü:** filtert über deutsche Namen und englische Aliasse („Überschrift“, „h1“, „todo“), damit auch Markdown-Gewohnheiten funktionieren.
