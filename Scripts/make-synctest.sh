#!/bin/zsh
# Baut die Testvariante „Quill Synctest“ für den Handtest des Sync mit zwei
# Benutzerkonten (Phase 11.5, docs/synctest.md, ADR-029): Bundle-ID
# io.github.vogelwild07.quill.synctest, eigener Container, nie der echte Store.
# Ad hoc signiert wie das Release, ohne Team. Ergebnis: dist/synctest/Quill Synctest.app
#
# Aufruf: Scripts/make-synctest.sh
set -eu
root=${0:A:h:h}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
out="$root/dist/synctest"

echo "Synctest-Build ($(git -C "$root" rev-parse --short HEAD)) …"
xcodebuild -project "$root/Quill.xcodeproj" -scheme "Quill Synctest" -configuration Synctest \
  -destination 'generic/platform=macOS' -derivedDataPath "$work/derived" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  build > "$work/build.log" 2>&1 || { tail -20 "$work/build.log"; exit 1; }

app="$work/derived/Build/Products/Synctest/Quill Synctest.app"
id=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
[[ $id == io.github.vogelwild07.quill.synctest ]] || { echo "Falsche Bundle-ID: $id"; exit 1; }
rm -rf "$out"
mkdir -p "$out"
ditto "$app" "$out/Quill Synctest.app"
echo "Fertig: dist/synctest/Quill Synctest.app ($id)"
