#!/bin/zsh
# Baut QuillKit für iOS (Phase 10.2, ADR-028): Fehler und Compiler-Warnungen zählen
# wie auf dem Mac. Tests auf iOS gibt es erst mit dem Simulator vor Phase 13.
#
# Aufruf: Scripts/check-ios-build.sh
# Baut in einen eigenen temporären Ordner, nicht in die DerivedData von Xcode. Nach
# einem Fehler bleibt der Ordner mit dem Log liegen (Pfad in der Meldung).
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/QuillIOSBuild.XXXXXX")
log=$work/build.log
fail() { print -u2 "Fehler: $1"; exit 1 }

print "QuillKit für iOS bauen ($(xcodebuild -version | head -1)) …"
(cd "$root/Packages/QuillKit" && xcodebuild -scheme QuillKit -destination 'generic/platform=iOS' \
  -derivedDataPath "$work/derived" build) > "$log" 2>&1 \
  || { grep -E ': error: ' "$log" | sort -u | head -20; fail "iOS-Build gescheitert (Log: $log)" }
# Wie in make-release.sh: Der Hinweis von appintentsmetadataprocessor ist keine
# Compiler-Warnung. Alles andere zählt.
warnings=$(grep -E 'warning: ' "$log" | grep -v appintentsmetadataprocessor | sort -u || true)
[ -z "$warnings" ] || { print -r -- "$warnings"; fail "iOS-Build mit Warnungen (Log: $log)" }
grep -q 'BUILD SUCCEEDED' "$log" || fail "kein BUILD SUCCEEDED im Log ($log)"
rm -rf "$work"
print "OK: QuillKit baut für iOS ohne Warnungen."
