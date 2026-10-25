#!/bin/zsh
# Spike ADR-037: Version 1 aktualisiert sich über Sparkle 2 auf Version 2.
# Aufruf: run-spike.sh <Arbeitsordner> <Installationsordner> [zip|dmg] [ok|manipuliert]
# Schlüssel im Schlüsselbund unter dem Konto „quill-update-spike“ (nur für den Spike).
set -eu
work=$1; install=$2; kind=${3:-zip}; mode=${4:-ok}
here=${0:A:h}
: ${SPARKLE:?SPARKLE auf entpacktes Sparkle-2.x setzen}
export SPARKLE
account=quill-update-spike
port=8765
container=$HOME/Library/Containers/io.github.vogelwild07.quill.updatespike/Data
log=$container/spike.log

"$SPARKLE/bin/generate_keys" --account $account > /dev/null 2>&1 || true
export PUBKEY=$("$SPARKLE/bin/generate_keys" --account $account -p)
export FEED=http://127.0.0.1:$port/appcast.xml

rm -rf "$work"; mkdir -p "$work/v1" "$work/v2" "$work/srv" "$install"
POSTPONE=${POSTPONE_V1:-false} BACKUP_FAILS=${BACKUP_FAILS_V1:-false} "$here/build.sh" 1 "$work/v1"
POSTPONE=false "$here/build.sh" 2 "$work/v2"
if [ $kind = zip ]; then
  archive=UpdateSpike-2.zip
  ditto -c -k --keepParent "$work/v2/UpdateSpike.app" "$work/srv/$archive"
else
  archive=UpdateSpike-2.dmg
  hdiutil create -quiet -fs APFS -volname UpdateSpike -srcfolder "$work/v2/UpdateSpike.app" "$work/srv/$archive"
fi
sig=$("$SPARKLE/bin/sign_update" --account $account "$work/srv/$archive")
if [ $mode = manipuliert ]; then
  # Ein Byte mitten im Archiv ändern, nach dem Signieren.
  size=$(stat -f %z "$work/srv/$archive")
  printf 'X' | dd of="$work/srv/$archive" bs=1 seek=$((size / 2)) conv=notrunc 2>/dev/null
fi
cat > "$work/srv/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>UpdateSpike</title>
<item><title>Version 2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.2</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
<enclosure url="http://127.0.0.1:$port/$archive" type="application/octet-stream" $sig/></item>
</channel></rss>
XML

rm -rf "$install/UpdateSpike.app"; ditto "$work/v1/UpdateSpike.app" "$install/UpdateSpike.app"
if [ -n "${QUARANTINE:-}" ]; then
  # Wie nach einem Download im Browser; $QUARANTINE sind die Flags (0083 neu, 00c3 mit Freigabe).
  xattr -w com.apple.quarantine "$QUARANTINE;$(printf %x $(date +%s));Safari;" "$install/UpdateSpike.app"
fi
rm -f "$log"
python3 -m http.server $port --bind 127.0.0.1 --directory "$work/srv" > "$work/http.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; pkill -f "UpdateSpike.app/Contents/MacOS/UpdateSpike" 2>/dev/null; true' EXIT
sleep 1
open "$install/UpdateSpike.app"
for i in {1..90}; do
  if grep -q "v2 gestartet" "$log" 2>/dev/null && grep -qE "v2 (kein Update|abgebrochen)" "$log"; then break; fi
  if grep -qE "v1 (abgebrochen|Laden gescheitert|kein Update)" "$log" 2>/dev/null; then sleep 3; break; fi
  if grep -q "v1 beende ohne Freigabe" "$log" 2>/dev/null; then sleep 15; break; fi
  sleep 1
done
echo "== Protokoll"; cat "$log"
echo "== installierte Version: $(defaults read "$install/UpdateSpike.app/Contents/Info.plist" CFBundleVersion)"
echo "== Quarantäne: $(xattr -p com.apple.quarantine "$install/UpdateSpike.app" 2>/dev/null || echo keine)"
codesign --verify --deep --strict "$install/UpdateSpike.app" && echo "== Signatur gültig"
