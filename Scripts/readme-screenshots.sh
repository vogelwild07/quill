#!/bin/zsh
# Nimmt die Bilder für die README auf (docs/images/quill-hell.png und
# quill-dunkel.png): `ReadmeScreenshotUITests` startet die Debug-App mit einem
# Store nur im Arbeitsspeicher, tippt Demo-Inhalte und nimmt das Fenster auf.
#
# Die Aufnahme liest Bildschirmpixel, Liquid Glass zeigt den Hintergrund hinter
# dem Fenster. Vorher deshalb ein neutrales Schreibtischbild einstellen, andere
# Fenster ausblenden und „Nicht stören“ einschalten; danach die Bilder ansehen.
#
# Aufruf: Scripts/readme-screenshots.sh
# Zeitlimit 600 s; nach einem Fehler bleibt der Arbeitsordner mit Log liegen.
set -eu
setopt pipefail
root=${0:A:h:h}
images=$root/docs/images

fail() { echo "FEHLER: $*" >&2; exit 1 }

# Eine laufende Quill arbeitet mit dem echten Store; nie beenden.
if pgrep -lf 'Quill.app/Contents/MacOS/Quill' > /dev/null; then
  fail "Quill läuft. Bitte selbst beenden, dann erneut starten."
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/QuillReadme.XXXXXX") || fail "kein Arbeitsordner"
result=$work/Screenshots.xcresult
echo "UI-Test läuft (Log: $work/test.log) …"
# perl alarm: Zeitlimit ohne coreutils; Abbruch meldet Exit-Code 142.
code=0
TEST_RUNNER_QUILL_README_SCREENSHOTS=1 perl -e 'alarm shift; exec @ARGV' 600 \
  xcodebuild -project "$root/Quill.xcodeproj" -scheme Quill -destination 'platform=macOS' \
  -derivedDataPath "$work/derived" -resultBundlePath "$result" \
  -only-testing:QuillUITests/ReadmeScreenshotUITests test > "$work/test.log" 2>&1 || code=$?
if [ $code -eq 142 ]; then
  # Nur Prozesse aus dem eigenen Build-Ordner, nie eine andere Quill.
  pkill -f "$work/derived/" || true
  fail "Zeitlimit von 600 s überschritten (Log: $work/test.log)"
fi
[ $code -eq 0 ] || fail "UI-Test gescheitert (Log: $work/test.log)"
grep -q 'Executed 2 tests, with 0 failures' "$work/test.log" \
  || fail "nicht beide Aufnahmen gelaufen (übersprungen?), Log: $work/test.log"

xcrun xcresulttool export attachments --path "$result" --output-path "$work/attachments" \
  > /dev/null || fail "Anhänge nicht exportiert"
mkdir -p "$images"
for name in quill-hell quill-dunkel; do
  # manifest.json: je Test eine Liste von Anhängen mit Dateiname und Anzeigename.
  file=$(python3 -I - "$work/attachments/manifest.json" "$name" <<'EOF'
import json, sys
manifest, name = sys.argv[1], sys.argv[2]
for test in json.load(open(manifest)):
    for attachment in test["attachments"]:
        if attachment["suggestedHumanReadableName"].startswith(name):
            print(attachment["exportedFileName"])
EOF
  )
  [ $(print -r -- "$file" | grep -c .) -eq 1 ] || fail "Anhang „$name“ nicht eindeutig: $file"
  cp "$work/attachments/$file" "$images/$name.png" || fail "$name.png nicht kopiert"
  echo "$images/$name.png ($(sips -g pixelWidth -g pixelHeight "$images/$name.png" | awk '/pixel/ {printf "%s ", $2}'))"
done
rm -rf "$work"
echo "OK: Bilder ansehen, bevor sie committet werden."
