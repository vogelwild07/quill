#!/bin/zsh
# Baut die beiden Testvarianten „Quill Synctest A“ und „Quill Synctest B“ für den
# Handtest des Sync in einem Benutzerkonto (docs/synctest.md, ADR-029): Bundle-IDs
# io.github.vogelwild07.quill.synctest.a und .b, je ein eigener Container, nie der
# echte Store. Ad hoc signiert wie das Release, ohne Team.
# Ergebnis: dist/synctest/Quill Synctest A.app und dist/synctest/Quill Synctest B.app
#
# Aufruf: Scripts/make-synctest.sh
set -eu
root=${0:A:h:h}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
out="$root/dist/synctest"
real=io.github.vogelwild07.quill

echo "Synctest-Build ($(git -C "$root" rev-parse --short HEAD)) …"
rm -rf "$out"
mkdir -p "$out"
for variant in A B; do
  lower=${variant:l}
  xcodebuild -project "$root/Quill.xcodeproj" -scheme "Quill Synctest" -configuration "Synctest$variant" \
    -destination 'generic/platform=macOS' -derivedDataPath "$work/derived" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    build > "$work/build-$variant.log" 2>&1 || { tail -20 "$work/build-$variant.log"; exit 1; }

  app="$work/derived/Build/Products/Synctest$variant/Quill Synctest $variant.app"
  id=$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")
  # Nie die Kennung der echten App: sonst teilte die Variante deren Container.
  [[ $id != "$real" && $id == "$real.synctest.$lower" ]] || { echo "Falsche Bundle-ID: $id"; exit 1; }
  ditto "$app" "$out/Quill Synctest $variant.app"
  echo "Fertig: dist/synctest/Quill Synctest $variant.app ($id)"
done
