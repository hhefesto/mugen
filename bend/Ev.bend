import Base
import ./Json.bend as J

# Ev: what the hub hears. One computation, the hub (Hub.bend), owns the
# memory and the chat; every other one (the stdin reader, each compaction,
# the turn's call, each agent's) tells it what happened through its inbox, a
# Chan(ev.Ev), and asks it for what only it knows (a zoom, a spawn) with a
# channel of its own to answer on.
#
# Every def is prefixed `ev.` (a program's defs share one namespace).

# a tool's result: its text, whether it failed
type ev.Out is Data:
  ev.Out{text: String, fail: Bool}

# what a running call is sent: a message to take between its tool calls, or
# its stop
type ev.Say is Data:
  ev.Text{text: String}
  ev.Stop{}

# who: "" for mugen's turn, else an agent's name.
#   Line, Eof       the user typed a line; stdin ended
#   Built           a compaction's line (none: it was cut, to build anew)
#   Entry           a message of a call, to log: a reply, a tool call, its result
#   Show            one only shown, never logged: a thought, a busy note
#   Req             a tool only the hub runs (zoom, date, spawn, tell)
#   End             a call ended: answered, its text; else why, and whose
#                   doing (Compact.bend cp.End); `left` messages sent to it
#                   it never took
#   Goal            a goal check's answer
type ev.Ev is Data:
  ev.Line{text: String}
  ev.Eof{}
  ev.Built{l: U32, i: U32, line: Maybe<&2, String>}
  ev.Entry{who: String, kind: String, text: String}
  ev.Show{who: String, kind: String, text: String}
  ev.Req{who: String, name: String, input: J.Json, reply: Chan(ev.Out)}
  ev.End{who: String, ok: Bool, text: String, stop: U32, left: U32}
  ev.Goal{goal: String, ok: Bool, text: String}

# sent, whatever came of it (a hub gone ends the program anyway)
def ev.send(+c: Chan(ev.Ev), e: ev.Ev) -> IO(Unit):
  IO.bind(Result<&1, &1, ev.Ev, Unit>, Unit, Chan.send(ev.Ev, c, e), r => IO.pure(Unit, Unit{}))
