# UpdateSpike (ADR-037)

Prüft, ob sich eine ad hoc signierte Sandbox-App mit Sparkle 2 aktualisiert. Nicht Teil
der App (`SpikeIsolationTests`). Eigene Kennung `io.github.vogelwild07.quill.updatespike`.

```sh
# Sparkle 2.x von GitHub laden (Prüfsumme gegen die Release-Angabe prüfen) und entpacken
SPARKLE=<Ordner mit Sparkle.framework und bin/> \
  Spikes/UpdateSpike/run-spike.sh <Arbeitsordner> <Installationsordner> [zip|dmg] [ok|manipuliert]
```

Schalter (Umgebung): `QUARANTINE=00c3` (v1 mit Quarantäne), `POSTPONE_V1=true` (v1 gibt die
Installation nie frei), `OWN_DRIVER=true` (eigene Oberfläche wie in Quill) mit
`BACKUP_FAILS_V1=true` (Backup scheitert), `LOCAL_ATS=false` (ohne `NSAllowsLocalNetworking`).
Der Schlüssel liegt im Schlüsselbund unter dem Konto `quill-update-spike`; nach dem Spike mit
`security delete-generic-password -a quill-update-spike -s https://sparkle-project.org` löschen.
Ergebnisse in ADR-037.
