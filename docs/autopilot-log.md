# Autopilot-Log

Seit 2026-10-22 arbeitet Claude die restliche Roadmap der Mac-App allein ab und mergt
selbst, wenn der volle Lauf grün ist und kein Messwert schlechter wird. Hier steht alles,
was gemergt wurde, mit Messwerten, und die Entscheidungen, die der Nutzer prüfen soll.
Neueste Einträge unten.

## Zu prüfende Entscheidungen

Nicht besprochene Entscheidungen, je mit ADR. Häkchen setzt der Nutzer.

- (noch keine)

## Gemergt

### 12.1 Geschichte aufzeichnen (PR #25, ADR-031)

- `HistoryRecorder` zeichnet jede Speicherung im Editor als Änderung im Sync-Dokument der
  Seite auf, auch ohne Sync; der Abgleich schreibt die Aufzeichnung mit hinaus.
- Zwei Hänger behoben: Beenden ohne offene Arbeit antwortet sofort (`terminateNow`);
  `SyncController` wartet bei `ModelContext.didSave` nicht mehr auf den Main Thread.
- Tests: Package 650 (88 + 7 + 134 + 115 + 30 + 276), UI 46 (1 übersprungen),
  Synctest 13 Fälle; 12 Gegenproben rot wie erwartet.
- Messung siehe `docs/performance.md`, Abschnitt „Geschichte aufzeichnen vorher und nachher“.
- Messung: Package gleich oder besser (editorTyping 1,20 → 1,17 ms, search 44,81 → 44,29 ms).
  App im Wechsel alt/neu gemessen: sidebarReload 174,2 / 153,3 → 152,4 / 153,2 ms, Start und
  sidebarLoad 1–2 % höher innerhalb der Streuung. **Achtung:** sidebarLoad liegt auf beiden
  Ständen inzwischen bei 188–197 ms, nahe der Schwelle 200 ms.
- Nicht getestet: neue Sitzung nach gescheitertem Speichern (Store lässt sich im Test nicht
  zum Scheitern bringen).
