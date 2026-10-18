#!/bin/bash
# Label the parse probes written by `generate.js probes <dir>`: for each, print
# id, runs53, runs32 where runs = (`bash -n` on the RUNCMD probe is rc 0) AND
# (`bash -n` on the same probe with the slot replaced by `;;` is rc != 0) -- i.e.
# the slot is a command position in that bash, so a real removal there would run.
# `;;` is a syntax error ONLY in command position and inert as data/text, so a
# data/argument slot reads as "does not run". Nothing is executed: only `bash -n`.
set -u
dir="$1"
B53="${BETTER_RM_BASH53:-/opt/homebrew/bin/bash}"
B32="${BETTER_RM_BASH32:-/bin/bash}"
poison_dir=$(mktemp -d "${TMPDIR:-/tmp}/heredoc-later-body-XXXXXX")
trap 'rm -rf -- "$poison_dir"' EXIT
runs_in() {
  "$1" -n "$2" 2>/dev/null || { printf 'no'; return; }
  if "$1" -n "$3" 2>/dev/null; then printf 'no'; else printf 'yes'; fi
}
printf 'id\truns53\truns32\n'
for f in "$dir"/*.sh; do
  id=$(basename "$f" .sh)
  poison="$poison_dir/$id.sh"
  sed 's/RUNCMD/;;/' "$f" > "$poison"
  printf '%s\t%s\t%s\n' "$id" "$(runs_in "$B53" "$f" "$poison")" "$(runs_in "$B32" "$f" "$poison")"
done
