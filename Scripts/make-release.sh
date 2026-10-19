#!/bin/zsh
# Baut das Release (ADR-022): App ad hoc signiert und geprüft, als .dmg mit
# Verknüpfung zum Ordner „Programme“, dazu die SHA-256-Prüfsumme.
#
# Aufruf: Scripts/make-release.sh [--allow-dirty]
# Ergebnis in dist/: Quill-<Version>.dmg und Quill-<Version>.dmg.sha256.
# Ohne --allow-dirty nur aus einer sauberen Arbeitskopie, damit die .dmg genau
# einem Commit entspricht; mit --allow-dirty (nur zum Ausprobieren) heißt sie
# Quill-<Version>-dirty.dmg und ist nicht für ein Release gedacht. Bitgleich ist
# die .dmg bei einem zweiten Lauf nicht (Zeitstempel im Image); die Prüfsumme
# gilt für die veröffentlichte Datei. Nach einem Fehler bleibt der Arbeitsordner
# mit allen Logs liegen (Pfad in der Meldung).
set -eu
setopt pipefail
root=${0:A:h:h}
dist=$root/dist
bundle_id=io.github.vogelwild07.quill
min_macos=26.0

fail() { echo "FEHLER: $*" >&2; exit 1 }

suffix=
case "${1:-}" in
  "") ;;
  --allow-dirty) [ -n "$(git -C "$root" status --porcelain)" ] && suffix=-dirty ;;
  *) fail "Aufruf: Scripts/make-release.sh [--allow-dirty]" ;;
esac
if [ -z "${1:-}" ] && [ -n "$(git -C "$root" status --porcelain)" ]; then
  fail "Arbeitskopie nicht sauber (git status). Erst committen oder --allow-dirty."
fi
commit=$(git -C "$root" rev-parse --short HEAD) || fail "Commit nicht lesbar"
work=$(mktemp -d "${TMPDIR:-/tmp}/QuillRelease.XXXXXX") || fail "kein Arbeitsordner"
archive=$work/Quill.xcarchive
mnt=$work/mnt
trap '[ -d "$mnt" ] && hdiutil detach -quiet "$mnt" 2>/dev/null; true' EXIT

# 1. Archiv statt einfachem Build: Nur „archive“ entfernt Debug-Symbole und mit
#    ihnen die Pfade der Objektdateien (/Users/…) aus dem Binary. Ohne Team und
#    ohne Profil, nur ad hoc signiert; Config/Local.xcconfig wird überschrieben.
echo "1/4 Release-Build (Commit $commit$suffix, $(xcodebuild -version | head -1)) …"
xcodebuild -project "$root/Quill.xcodeproj" -scheme Quill -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" -derivedDataPath "$work/derived" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  archive > "$work/build.log" 2>&1 || fail "Build gescheitert (Log: $work/build.log)"
# appintentsmetadataprocessor meldet bei jedem Build „Metadata extraction skipped,
# no AppIntents.framework dependency found“: ein Hinweis des Werkzeugs, keine
# Compiler-Warnung; Quill nutzt keine App Intents. Alles andere zählt.
warnings=$(grep -E 'warning: ' "$work/build.log" | grep -v appintentsmetadataprocessor | sort -u || true)
[ -z "$warnings" ] || { echo "$warnings"; fail "Build mit Warnungen (Log: $work/build.log)" }
app=$archive/Products/Applications/Quill.app
binary=$app/Contents/MacOS/Quill
[ -x "$binary" ] || fail "kein Binary im Archiv: $binary"

# 2. App prüfen.
echo "2/4 App prüfen …"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist" || fail "Info.plist: $1 fehlt" }
version=$(plist CFBundleShortVersionString)
[ "$(plist CFBundleIdentifier)" = $bundle_id ] || fail "Bundle-ID ist nicht $bundle_id"
[ "$(plist LSMinimumSystemVersion)" = $min_macos ] || fail "Mindestversion ist nicht macOS $min_macos"
[ "$(lipo -archs "$binary")" = arm64 ] || fail "Binary nicht nur für Apple Silicon: $(lipo -archs "$binary")"
build=$(vtool -show-build "$binary") || fail "vtool gescheitert"
print -r -- "$build" | grep -q "minos $min_macos" || fail "Binary nicht für macOS $min_macos gebaut"
codesign --verify --deep --strict "$app" || fail "Signatur ungültig"
signature=$(codesign -dv "$app" 2>&1) || fail "Signatur nicht lesbar"
print -r -- "$signature" | grep -qx 'Signature=adhoc' || fail "nicht ad hoc signiert"
print -r -- "$signature" | grep -qx 'TeamIdentifier=not set' || fail "Team-ID in der Signatur"
print -r -- "$signature" | grep -q 'flags=.*runtime' || fail "ohne Hardened Runtime"
entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null) || fail "Entitlements nicht lesbar"
print -r -- "$entitlements" | grep -q com.apple.security.app-sandbox || fail "ohne App Sandbox"
if print -r -- "$entitlements" | grep -q get-task-allow; then fail "Debug-Entitlement get-task-allow"; fi
# grep: 0 = gefunden, 1 = nichts gefunden, 2 = Lesefehler (zählt als Fehler).
paths=$(grep -r -l -a -F /Users/ "$app") && found=0 || found=$?
case $found in
  0) echo "$paths"; fail "persönlicher Pfad im Bundle (siehe oben)" ;;
  1) ;;
  *) fail "Bundle nicht lesbar (grep $found)" ;;
esac
"$root/Scripts/check-release-binary.sh" --app "$app" || fail "Profiling- oder Testcode im Bundle"

# 3. .dmg: App und Verknüpfung zu /Applications, Name „Programme“ wie im Finder.
echo "3/4 .dmg bauen …"
name=Quill-$version$suffix
dmg=$dist/$name.dmg
stage=$work/stage
mkdir -p "$stage" "$dist" || fail "Ordner nicht anlegbar"
ditto "$app" "$stage/Quill.app" || fail "App nicht kopiert"
ln -s /Applications "$stage/Programme" || fail "Verknüpfung nicht angelegt"
rm -f "$dmg" "$dmg.sha256" || fail "alte .dmg nicht entfernt"
hdiutil create -volname "Quill $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg" \
  > "$work/hdiutil.log" 2>&1 || fail "hdiutil create gescheitert (Log: $work/hdiutil.log)"
hdiutil verify "$dmg" > "$work/verify.log" 2>&1 || fail "hdiutil verify gescheitert (Log: $work/verify.log)"

# 4. Wie ein Nutzer: Image nur lesend einhängen und Inhalt prüfen.
echo "4/4 .dmg prüfen …"
mkdir -p "$mnt" || fail "Einhängepunkt nicht anlegbar"
diskutil image attach --readOnly --nobrowse --mountPoint "$mnt" "$dmg" > "$work/attach.log" 2>&1 \
  || fail "Einhängen gescheitert (Log: $work/attach.log)"
[ "$(ls "$mnt" | tr '\n' ' ')" = "Programme Quill.app " ] || fail "Inhalt der .dmg: $(ls "$mnt")"
[ "$(readlink "$mnt/Programme")" = /Applications ] || fail "Verknüpfung zeigt nicht auf /Applications"
codesign --verify --deep --strict "$mnt/Quill.app" || fail "Signatur in der .dmg ungültig"
cdhash() { codesign -dv "$1" 2>&1 | grep '^CDHash=' || fail "CDHash nicht lesbar: $1" }
[ "$(cdhash "$mnt/Quill.app")" = "$(cdhash "$app")" ] || fail "App in der .dmg weicht vom Build ab"
hdiutil detach -quiet "$mnt" || fail "Aushängen gescheitert ($mnt)"

(cd "$dist" && shasum -a 256 "$name.dmg" > "$name.dmg.sha256") || fail "Prüfsumme nicht geschrieben"
rm -rf "$work"
echo "OK: $dmg ($(du -h "$dmg" | cut -f1), Commit $commit$suffix)"
echo "SHA-256: $(cut -d' ' -f1 "$dmg.sha256")"
