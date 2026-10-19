#!/bin/zsh
# Prüft, dass der Release-Build keinen Profiling- und keinen Testcode enthält
# (docs/performance.md, ADR-022): kein „QuillSeedPages“, kein Typ `ProfilingSeed`
# und keine Profiling-Bundle-ID im App-Bundle. Kurze Zeichenketten (bis 15 Byte)
# legt Swift nicht als Text ab; „QuillSeedPages“ steht deshalb in einer
# Lognachricht des Seeds. Ebenso fehlen das Testbild für UI-Tests (`TestImage`,
# nur Debug) und die Fenstergröße für die README-Bilder (`TestWindowSize`, nur
# Debug, Name „QuillWindowSize“ zu kurz), erkannt an ihren Lognachrichten, die
# Namen der drei Startargumente für den Store und die Zwischenablage (nur Debug)
# und Test-Bundles (`.xctest`, `PlugIns/`).
#
# Aufruf: Scripts/check-release-binary.sh [zusätzliche xcodebuild-Einstellungen]
# Die Einstellungen dienen nur der Gegenprobe, z. B.
#   Scripts/check-release-binary.sh 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=QUILL_PROFILING'
# muss scheitern.
# Oder: Scripts/check-release-binary.sh --app <Quill.app> prüft ein fertiges Bundle
# ohne eigenen Build (Scripts/make-release.sh).
set -u
root=${0:A:h:h}

if [ "${1:-}" = "--app" ]; then
  if [ $# -ne 2 ]; then
    echo "Aufruf: Scripts/check-release-binary.sh --app <Quill.app>"
    exit 2
  fi
  app=$2
  if [ ! -x "$app/Contents/MacOS/Quill" ]; then
    echo "Kein App-Bundle mit Binary: $app"
    exit 2
  fi
  derived=$(mktemp -d "${TMPDIR:-/tmp}/QuillReleaseCheck.XXXXXX")
else
  derived=$(mktemp -d "${TMPDIR:-/tmp}/QuillReleaseCheck.XXXXXX")
  log=$derived/build.log
  xcodebuild -project "$root/Quill.xcodeproj" -scheme Quill -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$derived" "$@" build > "$log" 2>&1
  if [ $? -ne 0 ]; then
    echo "Release-Build gescheitert (Log: $log)"
    exit 2
  fi
  app="$derived/Build/Products/Release/Quill.app"
fi

# Mach-O-Dateien ohne Debug-Symbole prüfen, wie ausgeliefert: Die Debug-Verweise
# nennen auch leer kompilierte Quelldateien (ProfilingSeed.swift) beim Namen.
copies="$derived/stripped"
mkdir -p "$copies"
find "$app" -type f | while read -r file; do
  copy="$copies/${file#"$app"/}"
  mkdir -p "${copy:h}"
  cp "$file" "$copy"
  if file -b "$file" | grep -q Mach-O; then
    strip -S -x "$copy" 2>/dev/null
  fi
done
if [ ! -s "$copies/Contents/MacOS/Quill" ]; then
  echo "Binary nicht kopiert, Prüfung nicht möglich ($copies)"
  exit 2
fi

found=0
for marker in QuillSeedPages ProfilingSeed io.github.vogelwild07.quill.profiling \
  "Testbild in eigener Zwischenablage" "Fenstergröße für UI-Tests" QuillInMemoryStore QuillStoreDirectory QuillPasteboardName; do
  # LC_ALL=C: byteweise; mit UTF-8-Locale findet grep in Binärdaten keine Umlaute.
  hits=$(LC_ALL=C grep -r -l -a -F "$marker" "$copies" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "GEFUNDEN: „$marker“ in:"
    echo "$hits" | sed "s|$copies/|  |"
    found=1
  fi
done
bundles=$(find "$app" \( -name '*.xctest' -o -path '*/Contents/PlugIns/*' \) -print)
if [ -n "$bundles" ]; then
  echo "GEFUNDEN: Test-Bundles oder PlugIns:"
  echo "$bundles" | sed "s|$app/|  |"
  found=1
fi

if [ $found -eq 0 ]; then
  echo "OK: Release-Bundle ohne Profiling- und Testcode ($app)"
  rm -rf "$derived"
  exit 0
fi
echo "Release-Bundle enthält Profiling- oder Testcode (Build: $derived)"
exit 1
