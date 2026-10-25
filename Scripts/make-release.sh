#!/bin/zsh
# Baut das Release (ADR-022): App ad hoc signiert und geprüft, als .dmg mit
# Verknüpfung zum Ordner „Programme“, dazu die SHA-256-Prüfsumme und der signierte
# Appcast für Updates (ADR-037).
#
# Aufruf: Scripts/make-release.sh [--allow-dirty]
# Ergebnis in dist/: Quill-<Version>.dmg, Quill-<Version>.dmg.sha256 und appcast.xml.
# Der Appcast nennt die .dmg unter github.com/vogelwild07/quill/releases/download/
# v<Version>/ und trägt EdDSA-Signaturen für .dmg und Appcast. Den privaten Schlüssel
# liest sign_update aus dem Schlüsselbund (Konto io.github.vogelwild07.quill); fehlt
# er oder passt er nicht zu SUPublicEDKey in App/Info.plist, bricht das Skript vor dem
# Build ab. Werkzeuge aus Sparkle 2.10.0, Prüfsumme fest, zwischengespeichert in .build/.
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
sparkle_version=2.10.0
sparkle_sha256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
key_account=io.github.vogelwild07.quill

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

# 0. Werkzeuge von Sparkle und Schlüssel, vor dem langen Build.
echo "0/5 Sparkle-Werkzeuge und Schlüssel …"
tools=$root/.build/sparkle-$sparkle_version
if [ ! -x "$tools/bin/sign_update" ]; then
  download=$work/sparkle
  mkdir -p "$download" || fail "Ordner nicht anlegbar"
  curl -fsSL --proto '=https' -o "$download/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/Sparkle-$sparkle_version.tar.xz" \
    || fail "Sparkle $sparkle_version nicht geladen"
  [ "$(shasum -a 256 "$download/sparkle.tar.xz" | cut -d' ' -f1)" = $sparkle_sha256 ] || fail "Prüfsumme von Sparkle $sparkle_version stimmt nicht"
  rm -rf "$tools" && mkdir -p "$tools" || fail "Ordner nicht anlegbar: $tools"
  tar -xJf "$download/sparkle.tar.xz" -C "$tools" ./bin || fail "Sparkle nicht entpackt"
fi
public_key=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$root/App/Info.plist") || fail "SUPublicEDKey fehlt in App/Info.plist"
keychain_key=$("$tools/bin/generate_keys" --account $key_account -p 2>/dev/null) \
  || fail "Kein privater Schlüssel im Schlüsselbund (Konto $key_account). Ohne ihn gibt es keine Updates."
[ "$keychain_key" = "$public_key" ] || fail "Schlüssel im Schlüsselbund passt nicht zu SUPublicEDKey in App/Info.plist"

# 1. Archiv statt einfachem Build: Nur „archive“ entfernt Debug-Symbole und mit
#    ihnen die Pfade der Objektdateien (/Users/…) aus dem Binary. Ohne Team und
#    ohne Profil, nur ad hoc signiert; Config/Local.xcconfig wird überschrieben.
echo "1/5 Release-Build (Commit $commit$suffix, $(xcodebuild -version | head -1)) …"
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
echo "2/5 App prüfen …"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Contents/Info.plist" || fail "Info.plist: $1 fehlt" }
version=$(plist CFBundleShortVersionString)
build_number=$(plist CFBundleVersion)
[ "$(plist SUPublicEDKey)" = "$public_key" ] || fail "SUPublicEDKey in der App weicht von App/Info.plist ab"
[ "$(plist SUDefaultsDomain)" = $bundle_id.sparkle ] || fail "SUDefaultsDomain ist nicht $bundle_id.sparkle"
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
# Kein Pfad aus einem Benutzerordner im Bundle. Einzige Ausnahme (ADR-022): Pfade vom
# Build-Rechner der fertig gebauten Rust-Bibliothek von automerge-swift (Cargo-Registry,
# Rust-Toolchain, Build-Ordner). Der eigene Benutzername bricht immer ab.
"$root/Scripts/check-bundle-paths.pl" "$USER" "$app" || fail "persönlicher Pfad im Bundle (siehe oben)"
"$root/Scripts/check-release-binary.sh" --app "$app" || fail "Profiling- oder Testcode im Bundle"

# 3. .dmg: App und Verknüpfung zu /Applications, Name „Programme“ wie im Finder
#    (Verknüpfung aus Scripts/dmg/settings.py).
echo "3/5 .dmg bauen …"
name=Quill-$version$suffix
dmg=$dist/$name.dmg
stage=$work/stage
mkdir -p "$stage" "$dist" || fail "Ordner nicht anlegbar"
ditto "$app" "$stage/Quill.app" || fail "App nicht kopiert"
rm -f "$dmg" "$dmg.sha256" || fail "alte .dmg nicht entfernt"
# Fenster mit Hintergrund, Icon-Positionen und Volume-Icon (Scripts/dmg/): dmgbuild
# schreibt das Layout direkt, ohne Finder und AppleScript. Feste Version mit
# Prüfsummen in einer eigenen Umgebung unter .build/, neu bei geänderten Anforderungen.
venv=$root/.build/dmgbuild-venv
requirements=$root/Scripts/dmg/requirements.txt
wanted=$(shasum -a 256 "$requirements" | cut -d' ' -f1) || fail "requirements.txt nicht lesbar"
if [ "$(cat "$venv/requirements.sha256" 2>/dev/null)" != "$wanted" ]; then
  rm -rf "$venv"
  { python3 -m venv "$venv" && "$venv/bin/pip" install --disable-pip-version-check --require-hashes \
      --only-binary :all: -r "$requirements"; } > "$work/pip.log" 2>&1 \
    || fail "dmgbuild nicht installiert (Log: $work/pip.log)"
  print -r -- "$wanted" > "$venv/requirements.sha256"
fi
volume_icon=$app/Contents/Resources/AppIcon.icns
[ -f "$volume_icon" ] || fail "kein AppIcon.icns in der App"
"$venv/bin/dmgbuild" -s "$root/Scripts/dmg/settings.py" -D app="$stage/Quill.app" \
  -D background="$root/Scripts/dmg/background.tiff" -D icon="$volume_icon" "Quill $version" "$dmg" \
  > "$work/dmgbuild.log" 2>&1 || fail "dmgbuild gescheitert (Log: $work/dmgbuild.log)"
hdiutil verify "$dmg" > "$work/verify.log" 2>&1 || fail "hdiutil verify gescheitert (Log: $work/verify.log)"

# 4. Wie ein Nutzer: Image nur lesend einhängen und Inhalt prüfen.
echo "4/5 .dmg prüfen …"
mkdir -p "$mnt" || fail "Einhängepunkt nicht anlegbar"
diskutil image attach --readOnly --nobrowse --mountPoint "$mnt" "$dmg" > "$work/attach.log" 2>&1 \
  || fail "Einhängen gescheitert (Log: $work/attach.log)"
[ "$(ls "$mnt" | tr '\n' ' ')" = "Programme Quill.app " ] || fail "Inhalt der .dmg: $(ls "$mnt")"
[ "$(readlink "$mnt/Programme")" = /Applications ] || fail "Verknüpfung zeigt nicht auf /Applications"
# Fenster: Hintergrund und Volume-Icon wie gebaut, Layout vorhanden (Scripts/dmg/).
cmp -s "$mnt/.background.tiff" "$root/Scripts/dmg/background.tiff" || fail "Hintergrund fehlt oder weicht ab"
cmp -s "$mnt/.VolumeIcon.icns" "$volume_icon" || fail "Volume-Icon fehlt oder weicht ab"
[[ $(GetFileInfo -a "$mnt") == *C* ]] || fail "Volume ohne eigenes Icon (Attribut C)"
[ -s "$mnt/.DS_Store" ] || fail "kein Fensterlayout (.DS_Store)"
codesign --verify --deep --strict "$mnt/Quill.app" || fail "Signatur in der .dmg ungültig"
# CDHash steht erst ab -dvvv in der Ausgabe. Zuweisung statt Vergleich in [ ]:
# Scheitert das Lesen, bricht set -e hier ab, statt zwei leere Werte zu vergleichen.
cdhash() { codesign -dvvv "$1" 2>&1 | grep '^CDHash=' || fail "CDHash nicht lesbar: $1" }
built_hash=$(cdhash "$app")
dmg_hash=$(cdhash "$mnt/Quill.app")
[ "$dmg_hash" = "$built_hash" ] || fail "App in der .dmg weicht vom Build ab"
hdiutil detach -quiet "$mnt" || fail "Aushängen gescheitert ($mnt)"

(cd "$dist" && shasum -a 256 "$name.dmg" > "$name.dmg.sha256") || fail "Prüfsumme nicht geschrieben"

# 5. Appcast: eine Version, Text aus docs/releases/v<Version>.md ohne Markdown, .dmg und
#    Appcast mit dem Schlüssel aus dem Schlüsselbund signiert, danach beide geprüft.
echo "5/5 Appcast …"
notes=$root/docs/releases/v$version.md
if [ ! -f "$notes" ]; then
  [ -n "$suffix" ] || fail "Release-Text fehlt: docs/releases/v$version.md"
  notes=/dev/null
fi
enclosure=$("$tools/bin/sign_update" --account $key_account "$dmg") || fail ".dmg nicht signiert"
print -r -- "$enclosure" | grep -qE '^sparkle:edSignature="[A-Za-z0-9+/=]+" length="[0-9]+"$' || fail "Unerwartete Ausgabe von sign_update: $enclosure"
appcast=$dist/appcast.xml
rm -f "$appcast"
python3 -I - "$notes" "$version" "$build_number" "$min_macos" "$name.dmg" "$enclosure" > "$appcast" <<'PY' || fail "Appcast nicht geschrieben"
import re, sys
from email.utils import formatdate
from xml.sax.saxutils import escape
notes_path, version, build, min_macos, dmg, enclosure = sys.argv[1:]
text = open(notes_path, encoding="utf-8").read()
text = re.sub(r"^#+\s*", "", text, flags=re.M)
text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
text = text.replace("**", "").replace("`", "").strip()
url = f"https://github.com/vogelwild07/quill/releases/download/v{version}/{dmg}"
print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
<title>Quill</title>
<item>
<title>Quill {escape(version)}</title>
<pubDate>{formatdate(usegmt=True)}</pubDate>
<sparkle:version>{escape(build)}</sparkle:version>
<sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>{escape(min_macos)}</sparkle:minimumSystemVersion>
<description>{escape(text)}</description>
<enclosure url="{escape(url)}" type="application/octet-stream" {enclosure}/>
</item>
</channel>
</rss>""")
PY
"$tools/bin/sign_update" --account $key_account "$appcast" > "$work/sign-appcast.log" 2>&1 || fail "Appcast nicht signiert (Log: $work/sign-appcast.log)"
"$tools/bin/sign_update" --account $key_account --verify "$appcast" > "$work/verify-appcast.log" 2>&1 || fail "Signatur des Appcasts ungültig (Log: $work/verify-appcast.log)"
signature=$(print -r -- "$enclosure" | sed -E 's/^sparkle:edSignature="([^"]+)".*/\1/')
"$tools/bin/sign_update" --account $key_account --verify "$dmg" "$signature" > "$work/verify-dmg.log" 2>&1 || fail "Signatur der .dmg ungültig (Log: $work/verify-dmg.log)"
rm -rf "$work"
echo "OK: $dmg ($(du -h "$dmg" | cut -f1), Commit $commit$suffix)"
echo "SHA-256: $(cut -d' ' -f1 "$dmg.sha256")"
echo "Appcast: $appcast (zum Release v$version hochladen, zusammen mit der .dmg)"
