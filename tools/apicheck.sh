#!/usr/bin/env bash
# Api.bend and Compact.bend against tools/fakeapi.ts, a stand-in for curl:
# each scenario scripts the API's answers, runs bend/tests/ApiCheck.bend on a
# spec, and checks what came of it (and what was sent) with jq.
#
#   tools/apicheck.sh
#
# BUN and APICHECK default to `bun` and run/apicheck; APICHECK_DIR to
# run/apicheck.d.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
BUN=${BUN:-bun}
APICHECK=${APICHECK:-$ROOT/run/apicheck}
WORK=${APICHECK_DIR:-$ROOT/run/apicheck.d}
rm -rf "$WORK"
mkdir -p "$WORK"
printf '#!%s\nexec %s %s "$@"\n' "$(command -v sh)" "$(command -v "$BUN")" "$HERE/fakeapi.ts" > "$WORK/curl"
chmod +x "$WORK/curl"

pass=0
fail=0

# a message as the API answers one
msg() {
  jq -cn --arg stop "$1" --argjson content "$2" --argjson details "${3:-null}" \
    '{id: "msg_x", type: "message", role: "assistant", model: "m", content: $content, stop_reason: $stop, stop_details: $details, usage: {input_tokens: 1, output_tokens: 1}}'
}
err() {
  jq -cn --arg type "$1" --arg m "$2" '{type: "error", error: {type: $type, message: $m}}'
}
TEXT='[{"type": "text", "text": "fine"}]'

# scenario NAME SPEC ANSWERS CHECK: CHECK a jq filter over {got, notes, sent:
# the requests' bodies and argv, in order}, true to pass
scenario() {
  local name=$1 spec=$2 answers=$3 check=$4 d="$WORK/$1"
  mkdir -p "$d"
  echo "$spec" > "$d/spec.json"
  echo "$answers" > "$d/answers.json"
  MUGEN_CURL="$WORK/curl" MUGEN_FAKE="$d/answers.json" MUGEN_FAKE_LOG="$d/log" \
    "$APICHECK" "$d/spec.json" > "$d/out.json"
  jq -s '.' "$d"/log/*.json > "$d/sent.json" 2> /dev/null || echo '[]' > "$d/sent.json"
  if jq -e --slurpfile sent "$d/sent.json" "(. + {sent: \$sent[0]}) | $check" "$d/out.json" > /dev/null; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL $name: $check" >&2
    jq -c . "$d/out.json" >&2
  fi
}

STEP='{"mode": "step", "model": "opus-5.5", "effort": "medium", "system": "sys", "blocks": [["<chat>\n", true], ["a line\n</chat>\n", false], ["Turn: hi", false]]}'
HAIKU='{"mode": "step", "model": "haiku-5.5", "effort": "high", "system": "sys", "blocks": [["", false], ["x", true]], "searches": 3}'
CALL='{"mode": "call", "model": "haiku-5.5", "effort": "high", "system": "sys", "blocks": [["x", false]]}'
TASK='Compaction: compress message 0 into one line\n<input>\nuser: hello\n\n   there\n</input>'
BUILD="{\"mode\": \"build\", \"model\": \"haiku-5.5\", \"effort\": \"high\", \"system\": \"sys\", \"blocks\": [[\"<chat>\\n\", true], [\"</chat>\\n\", false], [\"$TASK\", false]], \"text\": \"user: hello\\n\\n   there\"}"
LONG=$(printf 'x%.0s' $(seq 600))

# the request: the system prompt and the marked block cached, adaptive
# thinking summarized, the effort, Opus's refusal fallback and its beta
scenario body "$STEP" '[{}]' '
  .got.stop == 0 and .got.entries == [["mind", "fake thought", ""], ["unii", "S: <chat> a line </chat> Turn: hi", ""]]
  and (.sent | length) == 1
  and .sent[0].body.system == [{type: "text", text: "sys", cache_control: {type: "ephemeral"}}]
  and .sent[0].body.thinking == {type: "adaptive", display: "summarized"}
  and .sent[0].body.output_config == {effort: "medium"}
  and .sent[0].body.fallbacks == "default"
  and (.sent[0].argv | index("anthropic-beta: server-side-fallback-2026-07-01")) != null
  and (.sent[0].body | has("cache_control") | not)
  and .sent[0].body.messages == [{role: "user", content: [{type: "text", text: "<chat>\n", cache_control: {type: "ephemeral"}}, {type: "text", text: "a line\n</chat>\n"}, {type: "text", text: "Turn: hi"}]}]
  and (.sent[0].argv | map(select(test("sk-ant"))) | length) == 0'
# Haiku: no fallback, no beta; web search; an empty block left out; the last
# block marked, so the top level too
scenario haiku "$HAIKU" '[{}]' '
  .got.stop == 0
  and (.sent[0].body | has("fallbacks") | not)
  and (.sent[0].argv | map(select(startswith("anthropic-beta"))) | length) == 0
  and .sent[0].body.tools == [{type: "web_search_20260209", name: "web_search", max_uses: 3}]
  and .sent[0].body.cache_control == {type: "ephemeral"}
  and .sent[0].body.messages[0].content == [{type: "text", text: "x", cache_control: {type: "ephemeral"}}]'
# overloaded, then answered: asked again after 2 s (2^1), said so
scenario busy "$STEP" "[{\"code\": 529, \"body\": $(err overloaded_error Overloaded)}, {\"body\": $(msg end_turn "$TEXT")}]" '
  .got.stop == 0 and .notes == ["The AI service is busy: asking again in 2 s."] and (.sent | length) == 2'
# a retry-after is waited
scenario after "$STEP" "[{\"code\": 429, \"after\": \"7\", \"body\": $(err rate_limit_error slow)}, {\"body\": $(msg end_turn "$TEXT")}]" '
  .got.stop == 0 and .notes == ["The AI service is busy: asking again in 7 s."]'
# a request refused: down at once, the API's why
scenario bad "$STEP" "[{\"code\": 400, \"body\": $(err invalid_request_error 'messages: bad')}]" '
  .got.stop == 4 and .got.why == "HTTP 400: messages: bad" and .notes == [] and (.sent | length) == 1'
# ... unless the API says to ask again
scenario should "$STEP" "[{\"code\": 400, \"should\": \"true\", \"body\": $(err x y)}, {\"body\": $(msg end_turn "$TEXT")}]" '
  .got.stop == 0 and (.sent | length) == 2'
# ... and a retry status the API says not to
scenario shouldnt "$STEP" "[{\"code\": 503, \"should\": \"false\", \"body\": $(err x 'not now')}]" '
  .got.stop == 4 and .got.why == "HTTP 503: not now"'
# no connection: busy, asked again
scenario curl7 "$STEP" "[{\"exit\": 7}, {\"body\": $(msg end_turn "$TEXT")}]" '
  .got.stop == 0 and (.notes | length) == 1 and (.sent | length) == 2'
# busy TRIES times: down, the user told only that the service is busy
scenario down "$STEP" "[{\"code\": 529, \"body\": $(err overloaded_error Overloaded)}]" '
  .got.stop == 4 and .got.why == "HTTP 529: Overloaded" and (.sent | length) == 8'
scenario down.notes "$STEP" "[{\"code\": 529, \"body\": $(err overloaded_error Overloaded)}]" '
  .notes == ([2, 4, 8, 16, 32, 64, 128] | map("The AI service is busy: asking again in \(.) s."))'
# a refusal, a stop reason: fail, the input'"'"'s doing
scenario refusal "$STEP" "[{\"body\": $(msg refusal '[]' '{"type": "refusal", "category": "cyber", "explanation": "no"}')}]" '
  .got.stop == 6 and .got.why == "stopped: refusal (no)"'
scenario max "$STEP" "[{\"body\": $(msg max_tokens '[{"type": "text", "text": "cut"}]')}]" '
  .got.stop == 6 and .got.why == "stopped: max_tokens"'
# pause_turn: asked again (the agent loop sends the turn back)
scenario pause "$STEP" "[{\"body\": $(msg pause_turn '[{"type": "server_tool_use", "id": "s1", "name": "web_search", "input": {"query": "q"}}]')}]" '
  .got.stop == 2 and .got.entries == [["tool", "web_search {\"query\":\"q\"}", "s1"]]'
# tools: the calls; a run of text blocks one reply; empty text dropped
scenario tools "$STEP" "[{\"body\": $(msg tool_use '[{"type": "text", "text": "a "}, {"type": "text", "text": "b"}, {"type": "text", "text": ""}, {"type": "tool_use", "id": "t1", "name": "shell", "input": {"cmd": "ls"}}]')}]" '
  .got.stop == 1 and .got.entries == [["unii", "a b", ""], ["tool", "shell {\"cmd\":\"ls\"}", "t1"]] and (.got.out | length) == 3'
# a server tool'"'"'s result shown as titles and urls
scenario search "$STEP" "[{\"body\": $(msg end_turn '[{"type": "web_search_tool_result", "tool_use_id": "s1", "content": [{"type": "web_search_result", "title": "T", "url": "https://u"}]}, {"type": "text", "text": "done"}]')}]" '
  .got.entries == [["echo", "T https://u", "s1"], ["unii", "done", ""]]'
# a patient call: down, then a minute later answered
scenario patient "$CALL" "[$(for k in 1 2 3 4 5 6 7 8; do printf '{"code": 529, "body": %s},' "$(err overloaded_error O)"; done){\"body\": $(msg end_turn "$TEXT")}]" '
  .got == {ok: true, text: "fine", stop: 0} and (.sent | length) == 9'
# ... and a refused one ends, the model'"'"'s doing
scenario patient.fail "$CALL" "[{\"body\": $(msg refusal '[]')}]" '
  .got == {ok: false, text: "stopped: refusal", stop: 1} and (.sent | length) == 1'
# a job: its line, the first that fits
scenario build "$BUILD" '[{}]' '
  .got.line == "S: user: hello there" and (.sent | length) == 1
  and (.sent[0].body.messages[0].content | length) == 3'
# a line too long, twice: asked again with the note on the last; then one fits
scenario build.over "$BUILD" "[{\"body\": $(msg end_turn "[{\"type\": \"text\", \"text\": \"$LONG\"}]")}, {\"body\": $(msg end_turn "[{\"type\": \"text\", \"text\": \"${LONG}yy\"}]")}, {\"body\": $(msg end_turn '[{"type": "text", "text": "  short  "}]')}]" '
  .got.line == "short" and (.sent | length) == 3
  and (.sent[1].body.messages[0].content | length) == 4
  and (.sent[1].body.messages[0].content[3].text | startswith("Too long: your last line for this <input> was 600 bytes,"))
  and (.sent[2].body.messages[0].content[3].text | startswith("Too long: your last line for this <input> was 602 bytes,"))
  and (.sent[2].body.messages[0].content | length) == 4'
# always too long: TRIES tries, the shortest kept
scenario build.long "$BUILD" "[{\"body\": $(msg end_turn "[{\"type\": \"text\", \"text\": \"${LONG}aa\"}]")}, {\"body\": $(msg end_turn "[{\"type\": \"text\", \"text\": \"${LONG}\"}]")}, {\"body\": $(msg end_turn "[{\"type\": \"text\", \"text\": \"${LONG}b\"}]")}]" "
  .got.line == \"$LONG\" and (.sent | length) == 5"
# no line (white space): the source flattened and cut
scenario build.empty "$BUILD" "[{\"body\": $(msg end_turn '[{"type": "text", "text": " \n "}]')}]" '
  .got.line == "user: hello there" and (.sent | length) == 1'
# a refusal: the same
scenario build.refused "$BUILD" "[{\"body\": $(msg refusal '[]')}]" '
  .got.line == "user: hello there"'

echo "apicheck: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
