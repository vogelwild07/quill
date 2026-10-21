#!/bin/zsh
# Fälle aus docs/synctest.md als UI-Test mit zwei Geräten (SyncTwoAppsUITests,
# ADR-029): baut Synctest A und B (Scripts/make-synctest.sh), meldet sie bei
# Launch Services an und startet jede Testmethode einzeln mit 600 s Grenze.
# Stores und Ordner sind Wegwerf (Test-Stores der Varianten, Ordner im temporären
# Ordner des Test-Runners); die echte App und ihr Store bleiben unberührt.
# Bei Rot oder Timeout bleiben Protokoll und .xcresult in dist/synctest-logs/, dazu
# Stack-Stichproben von A, B und dem Test-Runner (`sample`, nur lesend), genommen
# beim ersten Fehler im Protokoll bzw. beim Timeout.
#
# Aufruf: Scripts/test-synctest-ui.sh [Testmethode …]   (ohne: alle)
set -u
root=${0:A:h:h}
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if pgrep -f "Quill.app/Contents/MacOS/Quill" > /dev/null; then
  echo "Quill läuft. Bitte zuerst beenden; der Test beendet es nie selbst."
  exit 2
fi
if pgrep -f "Quill Synctest [AB].app/Contents/MacOS" > /dev/null; then
  echo "Quill Synctest A oder B läuft. Bitte zuerst beenden."
  exit 2
fi

"$root/Scripts/make-synctest.sh" || exit 1
for variant in A B; do
  "$lsregister" -f "$root/dist/synctest/Quill Synctest $variant.app"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Nicht unter dist/synctest: Das leert make-synctest.sh bei jedem Lauf.
keep="$root/dist/synctest-logs/$(date +%Y%m%d-%H%M%S)"

# Stack-Stichproben (3 s) von A, B und Test-Runner nach $1, einmal je Testmethode.
take_samples() {
  [ -d "$1" ] && return
  mkdir -p "$1"
  local name pid running=()
  for name in "Quill Synctest A" "Quill Synctest B" "QuillUITests-Runner"; do
    for pid in $(pgrep -f "$name.app/Contents/MacOS"); do
      sample $pid 3 -file "$1/$name-$pid.txt" > /dev/null 2>&1 &
      running+=($!)
    done
  done
  # Nur auf die Stichproben warten, nicht auf den Wächter im Hintergrund.
  [ ${#running[@]} -gt 0 ] && wait $running
}

# Wartet auf den ersten Fehler im Protokoll $1 und nimmt dann Stichproben nach $2.
# Endet ohne Stichproben, sobald es $2.stop gibt (Testmethode vorbei).
watch_for_failure() {
  until grep -qE "error: -\[|Failed to |busy for" "$1" 2> /dev/null; do
    [ -e "$2.stop" ] && return
    sleep 1
  done
  take_samples "$2"
}

xcodebuild -project "$root/Quill.xcodeproj" -scheme Quill -destination 'platform=macOS' \
  -derivedDataPath "$work/derived" build-for-testing > "$work/build.log" 2>&1 \
  || { tail -20 "$work/build.log"; exit 1; }

tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then
  tests=(${(f)"$(grep -o 'func test[A-Za-z]*' "$root/QuillUITests/SyncTwoAppsUITests.swift" | sed 's/func //')"})
fi
failed=0
for test in $tests; do
  log="$work/$test.log" samples="$work/$test-samples"
  watch_for_failure "$log" "$samples" &
  watcher=$!
  # Ungepuffert, damit der Wächter den Fehler sieht, solange A und B noch laufen.
  NSUnbufferedIO=YES TEST_RUNNER_QUILL_SYNC_UI=1 perl -e 'alarm shift; exec @ARGV' 600 \
    xcodebuild -project "$root/Quill.xcodeproj" -scheme Quill -destination 'platform=macOS' \
    -derivedDataPath "$work/derived" test-without-building -resultBundlePath "$work/$test.xcresult" \
    -only-testing:"QuillUITests/SyncTwoAppsUITests/$test" > "$log" 2>&1
  code=$?
  # Nimmt der Wächter gerade Stichproben, nicht abbrechen, sondern abwarten.
  touch "$samples.stop"
  wait $watcher 2> /dev/null
  [ $code -eq 142 ] && take_samples "$samples"
  summary=$(grep -oE "Test Case .*(passed|failed) \([0-9.]+ seconds\)" "$log" | tail -1 | grep -oE "(passed|failed) \([0-9.]+ seconds\)")
  if [ $code -eq 142 ]; then
    echo "TIMEOUT $test (600 s)"; failed=1
  elif [ $code -ne 0 ]; then
    echo "ROT     $test: $summary"
    grep -E "error: |XCTAssert|failed -" "$log" | head -5 | sed 's/^/        /'
    failed=1
  else
    echo "GRÜN    $test: $summary"
  fi
  grep -h "SYNC14 " "$log" | sed 's/^.*SYNC14 /        /' | head -1
  if [ $code -ne 0 ]; then
    mkdir -p "$keep"
    mv "$log" "$work/$test.xcresult" "$keep/" 2> /dev/null
    [ -d "$samples" ] && mv "$samples" "$keep/"
    echo "        Protokoll: $keep/$test.*"
  fi
done
pkill -f "Quill Synctest [AB].app/Contents/MacOS" 2>/dev/null
exit $failed
