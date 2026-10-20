#!/bin/zsh
# Einziger Weg, nach GitHub zu pushen (CLAUDE.md › Git). Prüft vorher jeden Commit,
# der noch auf keinem Zweig von origin liegt, auf persönliche Werte:
# - die Team-ID aus Config/Local.xcconfig und jede Zeile `DEVELOPMENT_TEAM = <Wert>`,
# - die Werte aus Config/Local.push-check (E-Mail-Adressen usw., eine pro Zeile,
#   git-ignoriert; Vorlage Config/Local.push-check.example),
# - den eigenen Benutzerpfad ($HOME),
# in Commit-Nachrichten, Dateinamen und Dateiinhalten, auch in Bildern und anderen
# Binärdateien. Autor und Committer müssen die noreply-Adresse aus
# `git config user.email` tragen. Gesucht wird nach Werten, nicht nach dem Wort
# DEVELOPMENT_TEAM. Bei einem Treffer bricht das Skript ab, ohne zu pushen, und
# nennt Commit, Fundstelle und Art des Werts, nie den Wert selbst.
#
# Aufruf:
#   Scripts/push.sh                     aktuellen Zweig pushen (beim ersten Mal mit -u)
#   Scripts/push.sh --tag <Tag>         Tag pushen (samt Nachricht des Tags)
#   Scripts/push.sh --delete <Zweig>    Zweig auf origin löschen (nichts zu prüfen)
#   Scripts/push.sh --check-only [<Rev>]  nur prüfen, nicht pushen (Gegenprobe)
set -eu
setopt pipefail
root=${0:A:h:h}
remote=origin
empty_tree=4b825dc642cb6eb9a060e54bf8d69288fbee4904

fail() { echo "FEHLER: $*" >&2; exit 1 }
git() { command git -C "$root" "$@" }

mode=branch
rev=HEAD
case "${1:-}" in
  "") ;;
  --tag) [ $# -eq 2 ] || fail "Aufruf: Scripts/push.sh --tag <Tag>"; mode=tag; rev=$2
    git rev-parse -q --verify "refs/tags/$rev" > /dev/null || fail "Tag $rev gibt es nicht" ;;
  --delete) [ $# -eq 2 ] || fail "Aufruf: Scripts/push.sh --delete <Zweig>"
    git push "$remote" --delete "$2"; exit 0 ;;
  --check-only) [ $# -le 2 ] || fail "Aufruf: Scripts/push.sh --check-only [<Rev>]"; mode=check; rev=${2:-HEAD} ;;
  *) fail "Aufruf: Scripts/push.sh [--tag <Tag> | --delete <Zweig> | --check-only [<Rev>]]" ;;
esac

if [ $mode != check ] && [ -n "$(git status --porcelain)" ]; then
  fail "Arbeitskopie nicht sauber (git status). Erst committen."
fi

# Gesuchte Werte mit Art (für die Meldung).
labels=() values=()
add() { [ -n "$2" ] && { labels+=("$1"); values+=("$2") }; true }
team=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Za-z0-9]+).*/\1/p' \
  "$root/Config/Local.xcconfig" 2>/dev/null | head -1 || true)
add "Team-ID" "$team"
add "Benutzerpfad" "$HOME"
private=$root/Config/Local.push-check
[ -f "$private" ] || fail "Config/Local.push-check fehlt (Vorlage: Config/Local.push-check.example)"
count=0
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%%\#*}
  line=${line//[[:space:]]/}
  [ -n "$line" ] || continue
  add "Wert aus Config/Local.push-check" "$line"
  count=$((count + 1))
done < "$private"
[ $count -gt 0 ] || fail "Config/Local.push-check enthält keinen Wert (mindestens die private E-Mail-Adresse)"

noreply=$(git config user.email)
[[ $noreply == *@users.noreply.github.com ]] || fail "git config user.email ist keine noreply-Adresse"

hits=()
# Durchsucht eine Datei; $1 nennt die Fundstelle.
scan() {
  local where=$1 file=$2 i
  for i in {1..${#values}}; do
    if grep -q -a -F -- "${values[$i]}" "$file"; then hits+=("$where: ${labels[$i]}"); fi
  done
  if grep -q -a -E 'DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*"?[A-Za-z0-9]{10}' "$file"; then
    hits+=("$where: DEVELOPMENT_TEAM mit Wert")
  fi
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/QuillPush.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

if [ $mode = tag ] && [ "$(git cat-file -t "refs/tags/$rev")" = tag ]; then
  git cat-file tag "refs/tags/$rev" > "$tmp/tag"
  scan "Tag $rev" "$tmp/tag"
fi

commits=(${(f)"$(git rev-list "$rev" --not --remotes="$remote")"})
for commit in $commits; do
  short=$(git rev-parse --short "$commit")
  [ "$(git log -1 --format=%ae "$commit")" = "$noreply" ] || hits+=("Commit $short: Autor nicht $noreply")
  [ "$(git log -1 --format=%ce "$commit")" = "$noreply" ] || hits+=("Commit $short: Committer nicht $noreply")
  git log -1 --format=%B "$commit" > "$tmp/message"
  scan "Commit $short, Nachricht" "$tmp/message"
  parent=$(git rev-parse -q --verify "$commit^1" || echo $empty_tree)
  git diff --name-only -z --diff-filter=ACMR "$parent" "$commit" > "$tmp/files"
  while IFS= read -r -d '' file_path; do
    # Steckt der Wert im Namen, zeigt die Meldung den Namen nicht.
    print -r -- "$file_path" > "$tmp/name"
    before=${#hits}
    scan "Commit $short, Dateiname" "$tmp/name"
    shown=$file_path
    [ ${#hits} -eq $before ] || shown="(Datei mit persönlichem Wert im Namen)"
    git cat-file blob "$commit:$file_path" > "$tmp/blob"
    scan "Commit $short, $shown" "$tmp/blob"
  done < "$tmp/files"
done

if [ ${#hits} -gt 0 ]; then
  print -l -- $hits >&2
  fail "persönliche Werte gefunden, nichts gepusht"
fi
echo "Geprüft: ${#commits} Commit(s) ohne persönliche Werte."

case $mode in
  check) ;;
  tag) git push "$remote" "refs/tags/$rev" ;;
  branch)
    branch=$(git symbolic-ref --short HEAD) || fail "kein Zweig ausgecheckt"
    if git rev-parse -q --verify "@{upstream}" > /dev/null; then
      git push
    else
      git push -u "$remote" "$branch"
    fi ;;
esac
