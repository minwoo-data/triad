#!/usr/bin/env bash
# Single-source the deterministic scripts and the output contract. Canonical = triad-all/*;
# triad-codex gets byte-identical copies. (The Claude-only triad skill uses none of them.)
#
#   bash skills/sync-review-parsers.sh           report drift, then write the copies
#   bash skills/sync-review-parsers.sh --check   report drift only; exit 1 if any copy differs
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mode=sync; [ "${1:-}" = --check ] && mode=check
FILES=(parse-triad.js codex-run.sh templates/output-contract.md)

drift=0
for f in "${FILES[@]}"; do
  if ! cmp -s "$here/triad-all/$f" "$here/triad-codex/$f" 2>/dev/null; then
    echo "DRIFT: triad-codex/$f differs from triad-all/$f" >&2; drift=1
  fi
done
if [ "$mode" = check ]; then
  [ "$drift" = 0 ] && echo "in sync: ${FILES[*]}" || exit 1
  exit 0
fi
for f in "${FILES[@]}"; do
  mkdir -p "$(dirname "$here/triad-codex/$f")"
  cp "$here/triad-all/$f" "$here/triad-codex/$f.sync.$$" && mv -f "$here/triad-codex/$f.sync.$$" "$here/triad-codex/$f"
done
chmod +x "$here/triad-all/codex-run.sh" "$here/triad-codex/codex-run.sh"
echo "synced ${FILES[*]} -> triad-codex$([ "$drift" = 0 ] && echo ' (no drift found)' || echo ' (drift above was overwritten)')"
