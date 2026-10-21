#!/usr/bin/env bash
# mugen's scenarios: each tests/scenarios/NAME is a run in pipe mode
# against a stand-in for its wire, its stdout compared with NAME/expect
# (NAME/expect.claude instead, if a scenario has one for that wire). WIRE
# picks the wire: claude (the default: tools/fakeclaude.ts stands in for
# Claude Code's CLI) or api (tools/fakeapi.ts for curl); both play the same
# scripts. A scenario has `input` (stdin: a line a message) or `run` (a
# script feeding stdin, for what needs time between lines); `chat.json`,
# `agent.json`, `goal.json` (the fake's scripts for a turn's, an agent's, a
# goal check's calls; @HOST@ is this device's name); and may have `check`
# (a script run in the scenario's dir, its data dir as $1, that fails if the
# store is wrong). Output is masked: the device's name as @HOST@, the work
# dir as @WORK@, the data dir as @DIR@, a shell's time as "in T s", the
# agents' names as @AGENT1@, @AGENT2@, ...
#
#   tools/scenarios.sh [NAME...]
#
# BUN and MUGEN default to `bun` and run/mugen; SCENARIOS_DIR to
# run/scenarios.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
BUN=${BUN:-bun}
MUGEN=${MUGEN:-$ROOT/run/mugen}
WORK=${SCENARIOS_DIR:-$ROOT/run/scenarios}
CASES=${CASES:-$ROOT/tests/scenarios}
HOST=$(uname -n)
rm -rf "$WORK"
mkdir -p "$WORK"
WIRE=${WIRE:-claude}
printf '#!%s\nexec %s %s "$@"\n' "$(command -v sh)" "$(command -v "$BUN")" "$HERE/fakeapi.ts" > "$WORK/curl"
printf '#!%s\nexec %s %s "$@"\n' "$(command -v sh)" "$(command -v "$BUN")" "$HERE/fakeclaude.ts" > "$WORK/claude"
chmod +x "$WORK/curl" "$WORK/claude"

pass=0
fail=0
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  names=($(ls "$CASES"))
fi
for name in "${names[@]}"; do
  src="$CASES/$name"
  w="$WORK/$name"
  mkdir -p "$w"
  for f in chat agent goal; do
    if [ -f "$src/$f.json" ]; then
      sed "s/@HOST@/$HOST/g" "$src/$f.json" > "$w/$f.json"
      export MUGEN_FAKE_$(echo $f | tr a-z A-Z)="$w/$f.json"
    else
      unset MUGEN_FAKE_$(echo $f | tr a-z A-Z)
    fi
  done
  export MUGEN_DIR="$w/d" MUGEN_CURL="$WORK/curl" MUGEN_CLAUDE="$WORK/claude" MUGEN_WIRE="$WIRE" MUGEN_FAKE_LOG="$w/log" MUGEN_SYNC=0 MUGEN_UNIT=1 MUGEN=$MUGEN
  if [ -x "$src/run" ]; then
    (cd "$w" && "$src/run") > "$w/raw" 2> "$w/err" || true
  else
    timeout 120 "$MUGEN" < "$src/input" > "$w/raw" 2> "$w/err" || true
  fi
  # the agents' names (random) as @AGENT1@, ... in the order they were made
  masks=()
  k=0
  for f in $(ls -tr "$w/d/docs/agent" 2> /dev/null); do
    k=$((k + 1))
    masks+=(-e "s/${f%.jsonl}/@AGENT$k@/g")
  done
  sed -e "s#$w/d/work#@WORK@#g" -e "s#$w/d#@DIR@#g" -e "s/$HOST/@HOST@/g" -e 's/ in [0-9]*\.[0-9] s)/ in T s)/g' "${masks[@]}" "$w/raw" > "$w/out"
  ok=1
  expect="$src/expect"
  if [ -f "$src/expect.$WIRE" ]; then
    expect="$src/expect.$WIRE"
  fi
  if ! diff -u "$expect" "$w/out" > "$w/diff"; then
    ok=0
  fi
  if [ $ok -eq 1 ] && [ -x "$src/check" ] && ! (cd "$w" && "$src/check" "$w/d") > "$w/check.out" 2>&1; then
    ok=0
    cat "$w/check.out" >> "$w/diff"
  fi
  if [ $ok -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL $name" >&2
    head -40 "$w/diff" >&2
  fi
done
echo "scenarios ($WIRE): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
