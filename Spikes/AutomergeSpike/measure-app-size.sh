#!/bin/zsh
# Misst, um wie viel die App mit Automerge größer wird (Kriterium aus ADR-026:
# höchstens 5 MB mehr für die .app, die .dmg wird mit genannt).
#
# Aufruf: Spikes/AutomergeSpike/measure-app-size.sh
# Arbeitet nur in einem Klon des aktuellen Commits im temporären Ordner; das Repo
# bleibt unverändert. Baut die App zweimal wie Scripts/make-release.sh (Release,
# ad hoc): einmal unverändert, einmal mit automerge-swift in QuillFeatures und
# einem Aufruf beim Start, der die APIs der späteren Sync-Schicht benutzt (sonst
# entfernt der Linker den Code). Die .dmg entsteht in beiden Fällen gleich mit
# `hdiutil` (UDZO wie in Scripts/dmg/settings.py), ohne gestaltetes Fenster.
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/QuillSpikeSize.XXXXXX")
fail() { print -u2 "Fehler: $1"; exit 1 }

build() {
  local name=$1 clone=$2
  xcodebuild -project "$clone/Quill.xcodeproj" -scheme Quill -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$work/$name.xcarchive" -derivedDataPath "$work/derived-$name" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    archive > "$work/$name.log" 2>&1 || fail "Build $name gescheitert (Log: $work/$name.log)"
  local app=$work/$name.xcarchive/Products/Applications/Quill.app
  mkdir "$work/stage-$name"
  ditto "$app" "$work/stage-$name/Quill.app"
  hdiutil create -quiet -format UDZO -fs APFS -volname Quill -srcfolder "$work/stage-$name" "$work/$name.dmg" \
    || fail "hdiutil $name gescheitert"
}

bytes() { find "$1" -type f -print0 | xargs -0 stat -f %z | awk '{s+=$1} END {print s}' }

print "Klone $(git -C "$root" rev-parse --short HEAD) nach $work …"
git clone -q --no-hardlinks "$root" "$work/base"
git clone -q --no-hardlinks "$root" "$work/automerge"

# Variante mit Automerge: Abhängigkeit in QuillKit, Aufruf beim Start der App.
kit=$work/automerge/Packages/QuillKit
python3 -I - "$kit/Package.swift" "$work/automerge/App/QuillApp.swift" <<'EOF'
import sys
package, app = sys.argv[1], sys.argv[2]
s = open(package).read()
s = s.replace('    targets: [\n', '    dependencies: [\n        .package(url: "https://github.com/automerge/automerge-swift.git", exact: "0.7.2"),\n    ],\n    targets: [\n', 1)
old = 'dependencies: ["QuillModel", "QuillEditor", "QuillExport", "QuillDesign"],'
assert s.count(old) == 1, "QuillFeatures-Abhängigkeiten nicht gefunden"
s = s.replace(old, 'dependencies: ["QuillModel", "QuillEditor", "QuillExport", "QuillDesign", .product(name: "Automerge", package: "automerge-swift")],')
open(package, "w").write(s)
a = open(app).read()
old = '    let persistence = Result { try QuillPersistence.open() }'
assert a.count(old) == 1, "AppDelegate nicht gefunden"
a = a.replace(old, '    private let automergeProbe: Int = AutomergeProbe.run()\n' + old)
open(app, "w").write(a)
EOF
cat > "$kit/Sources/QuillFeatures/AutomergeProbe.swift" <<'EOF'
import Automerge
import Foundation

/// Nur für die Größenmessung des Spikes: benutzt die APIs der späteren Sync-Schicht.
public enum AutomergeProbe {
    public static func run() -> Int {
        do {
            let doc = Document()
            let list = try doc.putObject(obj: .ROOT, key: "blocks", ty: .List)
            let map = try doc.insertObject(obj: list, index: 0, ty: .Map)
            try doc.put(obj: map, key: "kind", value: .String("paragraph"))
            let text = try doc.putObject(obj: map, key: "text", ty: .Text)
            try doc.spliceText(obj: text, start: 0, delete: 0, value: "Hallo")
            try doc.updateText(obj: text, value: "Hallo Welt")
            try doc.mark(obj: text, start: 0, end: 5, expand: .after, name: "bold", value: .Boolean(true))
            doc.commitWith()
            let heads = doc.heads()
            let other = doc.fork()
            try other.spliceText(obj: text, start: 0, delete: 0, value: "! ")
            other.commitWith()
            let changes = try other.encodeChangesSince(heads: heads)
            try doc.applyEncodedChanges(encoded: changes)
            let patches = try doc.mergeWithPatches(other: other)
            let loaded = try Document(doc.save())
            let state = SyncState()
            _ = doc.generateSyncMessage(state: state)
            return try loaded.text(obj: text).count + loaded.marks(obj: text).count + patches.count
                + doc.getAll(obj: map, key: "kind").count + doc.textAt(obj: text, heads: heads).count
                + doc.difference(since: heads).count
        } catch {
            return -1
        }
    }
}
EOF

print "Baue ohne Automerge …"
build base "$work/base"
print "Baue mit Automerge …"
build automerge "$work/automerge"

resolved=$work/automerge/Quill.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
grep -q '"version" : "0.7.2"' "$resolved" || fail "automerge-swift nicht in Version 0.7.2 aufgelöst"
binary=Contents/MacOS/Quill
for name in base automerge; do
  app=$work/$name.xcarchive/Products/Applications/Quill.app
  eval "app_$name=$(bytes "$app")"
  eval "bin_$name=$(stat -f %z "$app/$binary")"
  eval "dmg_$name=$(stat -f %z "$work/$name.dmg")"
done
# MiB (2^20 Bytes) und MB (10^6 Bytes, wie der Finder zählt): Die Grenze von 5 MB
# liegt je nach Einheit verschieden.
mb() { awk -v b="$1" 'BEGIN {printf "%.2f MiB (%.2f MB)", b / 1048576, b / 1000000}' }
print
print "| | ohne Automerge | mit Automerge | Unterschied |"
print "|---|---|---|---|"
print "| .app | $(mb $app_base) | $(mb $app_automerge) | $(mb $((app_automerge - app_base))) |"
print "| Binary | $(mb $bin_base) | $(mb $bin_automerge) | $(mb $((bin_automerge - bin_base))) |"
print "| .dmg (UDZO) | $(mb $dmg_base) | $(mb $dmg_automerge) | $(mb $((dmg_automerge - dmg_base))) |"
print
print "Eingebettete Frameworks mit Automerge: $(ls "$work/automerge.xcarchive/Products/Applications/Quill.app/Contents/Frameworks" 2>/dev/null | tr '\n' ' ' || true)"
print "Arbeitsordner (Logs): $work"
