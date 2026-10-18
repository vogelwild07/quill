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

Erhebung am 2026-10-18: Der Nutzer hat in Notion kopiert, danach `swift Scripts/pasteboard-types.swift`. Festgehalten sind nur Typnamen und Größen, keine Inhalte.

| Kopierter Inhalt | Typen auf der Zwischenablage |
|---|---|
| Ein Wort im Fließtext | `public.utf8-plain-text`, `org.chromium.internal.source-rfh-token`, `org.chromium.source-url` (1 Eintrag). Kein HTML, kein RTF. |
| Mehrere Blöcke (Überschrift, Liste, To-do) | `public.html` (354 B), `public.utf8-plain-text` (152 B), `org.chromium.web-custom-data` (≈ 25 KB), dazu die beiden Chromium-Metadaten (1 Eintrag). Kein RTF, kein Markdown-Typ. |
| Ein ganzer Block über den Griff | `public.html` (77 B), `org.chromium.web-custom-data` (308 B), dazu die beiden Chromium-Metadaten (1 Eintrag). **Kein Klartext.** |

**Schlüsse (Beobachtung → eigene Folgerung):**

- Notion schreibt nur Formate, die Chromium von sich aus kennt: Klartext, HTML und einen eigenen Container (`org.chromium.web-custom-data`). Den Inhalt des Containers haben wir nicht angesehen; er enthält vermutlich das interne Blockformat.
- Ein über den Griff kopierter Block hat **keinen Klartext**. In nativen Apps, die nur Text annehmen (Terminal, Textfelder), kommt dann nichts an.
- Es gibt weder RTF noch einen Markdown-Typ. Markdown entsteht in Notion erst beim Einfügen aus dem Klartext.
- Für Quill heißt das: Immer alle vier Formate schreiben, also Klartext, Markdown, RTF und `de.vogel.quill.blocks`, auch beim Kopieren über den Griff. Beim Einfügen aus Notion `public.html` auswerten (Überschriften, Listen), mit Fallback auf Klartext. Den Chromium-Container ignorieren.

## Eigene Ideen und Entscheidungen (unabhängig von Notion)

- **Kopieren aus Quill** schreibt mehrere Darstellungen: `public.utf8-plain-text`, `net.daringfireball.markdown`, `public.rtf` sowie einen eigenen Typ `de.vogel.quill.blocks` (JSON mit Blockarten). Fremde Apps bekommen damit sinnvolles Markdown bzw. formatierten Text, Quill selbst verlustfrei Blöcke.
- **Shortcuts** folgen macOS-Konventionen (⌘B/I, ⌘K Link, ⌘Z/⇧⌘Z, Tab/⇧Tab) und gängigen Markdown-Kürzeln; nichts Notion-Spezifisches nötig.
- **Slash-Menü:** filtert über deutsche Namen und englische Aliasse („Überschrift“, „h1“, „todo“), damit auch Markdown-Gewohnheiten funktionieren.
