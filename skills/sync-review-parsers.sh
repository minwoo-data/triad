#!/usr/bin/env bash
# Single-source the deterministic scripts. Canonical = triad-all/*; triad-codex gets byte-identical
# copies. Run after editing a canonical. (The Claude-only triad skill calls neither script.)
#
# parse-triad.js: output parser for both engines.
# codex-run.sh:   Codex invocation contract; derives its skill name and file naming from its own
#                 directory, so the copy is byte-identical.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

FILES=(parse-triad.js codex-run.sh)

for f in "${FILES[@]}"; do
  cp "$here/triad-all/$f" "$here/triad-codex/$f"
done
chmod +x "$here/triad-all/codex-run.sh" "$here/triad-codex/codex-run.sh"

fail=0
for f in "${FILES[@]}"; do
  if ! diff -q "$here/triad-all/$f" "$here/triad-codex/$f" >/dev/null; then
    echo "DRIFT: triad-codex/$f != triad-all/$f" >&2; fail=1
  fi
done
[ "$fail" = 0 ] && echo "synced + verified: ${FILES[*]} -> triad-codex" || { echo "sync FAILED" >&2; exit 1; }
