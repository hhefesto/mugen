
import Base
import ../Sys.bend as S
import ../Text.bend as T
import ../Json.bend as J
import ../View.bend as V
import ../Memory.bend as M
import ../Api.bend as A
import ../Code.bend as C
import ../Compact.bend as P

# Api.bend and Compact.bend against a stand-in for curl (tools/fakeapi.ts):
# `apicheck SPEC.json` runs what the spec says and prints, as one JSON line,
# what came of it, for tools/apicheck.sh to compare. A spec: {"mode": "step"
# (one step), "call" (a patient call) or "build" (a compaction job),
# "model", "effort", "system", "blocks": [[text, mark]...], "text": a job's
# source, "searches": n}. MUGEN_CURL names the curl to run. Waits take a
# millisecond a second. Every def is prefixed `ac.`.

def ac.blocks(xs: List<&2, J.Json>) -> List<&2, V.vw.B>:
  match xs:
    case []:
      []
    case J.JArr{[J.JStr{t}, J.JBool{m}]} <> rest:
      V.vw.B{t, m} <> ac.blocks(rest)
    case x <> rest:
      ac.blocks(rest)

def ac.s(+j: J.Json, +k: String) -> String:
  Maybe.default(&2, String, J.js.str(j, k), "")

def ac.strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case []:
      []
    case x <> t:
      J.JStr{x} <> ac.strs(t)

def ac.entries(es: List<&2, A.ap.Entry>) -> List<&2, J.Json>:
  match es:
    case []:
      []
    case A.ap.Entry{k, t, o} <> rest:
      J.JArr{[J.JStr{k}, J.JStr{t}, J.JStr{o}]} <> ac.entries(rest)

# the notes told, drained (r: the last poll)
def ac.notes(n: Nat, r: Poll<&1, &1, Maybe<&1, String>, Unit>, +c: Chan(String), acc: List<&2, String>) -> IO(List<&2, String>):
  match n r:
    case 1n+k Ready{Some{x}}:
      IO.bind(Poll<&1, &1, Maybe<&1, String>, Unit>, List<&2, String>, Chan.try_recv(String, c, 0), r2 => ac.notes(k, r2, c, x <> acc))
    case _ _:
      IO.pure(List<&2, String>, List.reverse(&2, String, acc))

def ac.say(+what: J.Json, +notes: List<&2, String>) -> IO(Unit):
  IO.print(J.js.write(J.JObj{[J.JKv{"got", what}, J.JKv{"notes", J.JArr{ac.strs(notes)}}]}))

def ac.step.json(s: A.ap.Step) -> J.Json:
  match s:
    case A.ap.Step{out, uses, es, stop, why, after}:
      J.JObj{[J.JKv{"stop", J.js.u32(stop)}, J.JKv{"why", J.JStr{why}}, J.JKv{"entries", J.JArr{ac.entries(es)}}, J.JKv{"out", J.JArr{out}}]}

def ac.end.json(e: P.cp.End) -> J.Json:
  match e:
    case P.cp.End{ok, text, stop}:
      J.JObj{[J.JKv{"ok", J.JBool{ok}}, J.JKv{"text", J.JStr{text}}, J.JKv{"stop", J.js.u32(stop)}]}

def ac.line.json(m: Maybe<&2, String>) -> J.Json:
  match m:
    case Some{x}:
      J.JObj{[J.JKv{"line", J.JStr{x}}]}
    case None{}:
      J.JObj{[J.JKv{"line", J.JNull{}}]}

def ac.mode(+mode: String) -> Nat:
  Bool.pick(Nat, String.eq(mode, "step"), 0n, Bool.pick(Nat, String.eq(mode, "call"), 1n, 2n))

def ac.run(k: Nat, +cfg: A.ap.Cfg, +a: A.ap.Ask, +text: String, +notes: Chan(String)) -> IO(J.Json):
  match k:
    case 0n:
      IO.bind(A.ap.Step, J.Json, A.ap.step(cfg, a, [A.ap.User{A.ap.ask.blocks(a)}], notes, ""), s => IO.pure(J.Json, ac.step.json(s)))
    case 1n:
      IO.bind(P.cp.End, J.Json, P.cp.call(cfg, a, notes), e => IO.pure(J.Json, ac.end.json(e)))
    case _:
      IO.bind(Maybe<&2, String>, J.Json, P.cp.build(cfg, A.ap.ask.pick(a), "system", notes, M.me.Job{0, 0, A.ap.ask.blocks(a), text}), m => IO.pure(J.Json, ac.line.json(m)))

def ac.spec(+curl: String, +j: J.Json) -> IO(Unit):
  +cfg = {A.ap.Cfg{curl, "https://api.anthropic.com/v1/messages", 16000, "web_search_20260209", 1, C.cc.Cfg{0, "claude", "", 1, "/tmp", "/tmp"}, "https://api.openai.com/v1/responses", False{}, "/nonexistent/openai.key"} : A.ap.Cfg}
  +a = {A.ap.Ask{A.ap.Pick{ac.s(j, "model"), ac.s(j, "effort"), "slow"}, ac.s(j, "system"), ac.blocks(J.js.arr(j, "blocks")), [], U32.from_nat(Maybe.default(&2, Nat, J.js.num(j, "searches"), 0n)), True{}} : A.ap.Ask}
  do IO<Unit>:
    +notes : Chan(String) <- Chan.new(String, 64)
    +got : J.Json <- ac.run(ac.mode(ac.s(j, "mode")), cfg, a, ac.s(j, "text"), notes)
    r : Poll<&1, &1, Maybe<&1, String>, Unit> <- Chan.try_recv(String, notes, 0)
    ns : List<&2, String> <- ac.notes(64n, r, notes, [])
    ac.say(got, ns)

def main() -> IO(Unit):
  do IO<Unit>:
    argv : List<String> <- IO.args()
    path : String = Maybe.default(&1, String, List.get(&1, String, argv, 1n), "spec.json")
    curl : String <- S.mu.env("MUGEN_CURL", "curl")
    text : String <- S.mu.must(String, "read spec", S.mu.read_file(path))
    ac.spec(curl, Maybe.default(&2, J.Json, J.js.read(text), J.JNull{}))
