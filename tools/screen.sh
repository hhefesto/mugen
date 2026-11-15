# tools/screen.sh: sourced by the scenarios that run mugen on its full screen
# (tests/scenarios/{web,handed,waiting}/run; scenarios.sh exports
# SCENARIO_TOOLS, this dir): mugen in a tmux pane of their own, typed into as
# mugen-web types, timed by what has happened rather than by the clock.
S="$PWD/tmux.sock"
export HOME="$PWD" SHELL="$(command -v sh)" TERM=xterm
P=
# MUGEN, with the environment given, on its full screen; its pane once it
# asks for input
screen() {
  tmux -f /dev/null -S "$S" new-session -d -s web -x 120 -y 30 "$1"
  P=$(tmux -S "$S" display-message -p -t web '#{pane_id}')
  for _ in $(seq 150); do tmux -S "$S" capture-pane -p -t "$P" | grep -q "Enter sends" && return; sleep 0.2; done
}
# a line typed as mugen-web's backend types it (Send.hs: the text, then Enter)
web() { tmux -S "$S" send-keys -t "$P" -l -- "$1"; tmux -S "$S" send-keys -t "$P" Enter; }
# until the stand-in for the AI service has had N requests (log/, a file each)
asked() { for _ in $(seq 300); do [ "$(ls log 2> /dev/null | wc -l)" -ge "$1" ] && return; sleep 0.1; done; }
# what the lines under the chat say of TEXT
under() {
  q=$(tmux -S "$S" capture-pane -p -t "$P")
  w=no; h=no
  echo "$q" | grep -q "waiting: .*$2" && w=yes
  echo "$q" | grep -q "handed to mugen: .*$2" && h=yes
  echo "$1: waiting $w, handed $h"
}
bye() {
  web "/quit"
  sleep 2
  tmux -S "$S" kill-server 2> /dev/null
  jq -r '"\(.kind): \(.text)"' "$MUGEN_DIR"/main/*.jsonl
}
