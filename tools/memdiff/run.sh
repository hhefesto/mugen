#!/usr/bin/env bash
# The differential test: UniiChat's own Memory.ts (harness.ts, under bun) and
# Memory.bend (bend/tests/MemDrive.bend, native) run the same stream
# (gen.ts) and must print the same trace and leave the same files.
#
#   tools/memdiff/run.sh [N [SEED]]
#
# In three segments, each a fresh process loading its directory (so jobs
# running are cut, as by a crash): steps [0, 40%) each side on its own
# directory; [40%, 70%) each on the other's (Bend reads files UniiChat wrote,
# indexing them anew, and UniiChat Bend's); the rest each on its own again
# (each catching up on what the other added). Inside a segment the memory
# also loads anew every 997 steps. After each segment the traces must be equal
# and so must main/, tree/ and view.json (but its "main" and "tree": how far
# UniiChat's own index is built, which mugen leaves at [0, 0]).
#
# UNIICHAT is UniiChat's source (the flake's devShell sets it); BUN and
# MEMDRIVE default to `bun` and run/memdrive; MEMDIFF_DIR to run/memdiff.
set -euo pipefail

N=${1:-5000}
SEED=${2:-1}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
UNIICHAT=${UNIICHAT:?set UNIICHAT to UniiChat\'s source (nix develop sets it)}
BUN=${BUN:-bun}
MEMDRIVE=${MEMDRIVE:-$ROOT/run/memdrive}
WORK=${MEMDIFF_DIR:-$ROOT/run/memdiff}
export TZ=UTC

rm -rf "$WORK"
mkdir -p "$WORK"
"$BUN" "$HERE/gen.ts" "$SEED" "$N" "$WORK/s"

same() {
  local a=$1 b=$2 what=$3
  if ! diff -r "$a/main" "$b/main" > /dev/null || ! diff -r "$a/tree" "$b/tree" > /dev/null; then
    echo "memdiff: $what: the logs differ" >&2
    diff -r "$a/main" "$b/main" | head -c 2000 >&2 || true
    diff -r "$a/tree" "$b/tree" | head -c 2000 >&2 || true
    exit 1
  fi
  if ! cmp -s <(jq -c 'del(.main, .tree)' "$a/view.json") <(jq -c 'del(.main, .tree)' "$b/view.json"); then
    echo "memdiff: $what: view.json differs" >&2
    exit 1
  fi
}

# segment k: steps [from, to), UniiChat on dir ts, Bend on dir bd
seg() {
  local k=$1 from=$2 to=$3 ts=$4 bd=$5
  local t0=$SECONDS
  "$BUN" "$HERE/harness.ts" "$UNIICHAT" "$ts" "$WORK/s" "$from" "$to" > "$WORK/ts.$k" 2> "$WORK/ts.$k.err" &
  local pid=$!
  "$MEMDRIVE" "$bd" "$WORK/s" "$from" "$to" > "$WORK/bd.$k" 2> "$WORK/bd.$k.err"
  wait $pid
  if ! cmp -s "$WORK/ts.$k" "$WORK/bd.$k"; then
    echo "memdiff: segment $k (steps $from-$to): the traces differ (< UniiChat, > mugen):" >&2
    diff "$WORK/ts.$k" "$WORK/bd.$k" | head -20 >&2
    exit 1
  fi
  same "$ts" "$bd" "segment $k (steps $from-$to)"
  echo "memdiff: segment $k, steps $from-$to: $(wc -l < "$WORK/ts.$k") trace lines equal, files equal ($((SECONDS - t0)) s)"
}

X1=$((N * 2 / 5))
X2=$((N * 7 / 10))
seg 1 0 "$X1" "$WORK/a" "$WORK/b"
seg 2 "$X1" "$X2" "$WORK/b" "$WORK/a"
seg 3 "$X2" "$N" "$WORK/a" "$WORK/b"
echo "memdiff: PASS, $N steps (seed $SEED)"
