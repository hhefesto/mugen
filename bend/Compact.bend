
import Base
import ./Text.bend as T
import ./Json.bend as J
import ./Tree.bend as R
import ./View.bend as V
import ./Api.bend as A
import ./Memory.bend as M

# Compact: a compaction job run (Memory.ts build): its blocks asked of the
# compactor, patient (an outage only delays it), till a line fits, TRIES lines
# at most, the shortest kept. Each try sends the job's blocks, never a try's
# words or thoughts; one after a line too long adds only where the limit cuts
# it (Tree.bend tr.over). No line (a refusal: its input's doing): its source
# flattened and cut. The hub runs one per job and logs the line it answers.
#
# Every def is prefixed `cp.` (a program's defs share one namespace).

def cp.tries() -> U32:
  5

# A call's end (AskAI.ts End): answered, its text (the replies, each a
# paragraph); else why, and whose doing it was: 0 ours (no key), 1 the
# model's (a refusal or stop reason: `fail`), 2 a stop (`lost`), 3 the
# vendor's (`down`).
type cp.End is Data:
  cp.End{ok: Bool, text: String, stop: U32}

def cp.replies(es: List<&2, A.ap.Entry>) -> List<&2, String>:
  match es:
    case []:
      []
    case A.ap.Entry{+k, t, o} <> rest:
      List.append(&2, String, Bool.pick(List<&2, String>, String.eq(k, "unii"), [t], []), cp.replies(rest))

def cp.end.of(s: A.ap.Step) -> cp.End:
  match s:
    case A.ap.Step{out, uses, es, +stop, +why, after}:
      Bool.pick(cp.End, U32.is_le(stop, 2), cp.End{True{}, T.tx.join(cp.replies(es), "\n\n"), 0},
        cp.End{False{}, Bool.pick(String, U32.is_eq(stop, 4), A.ap.busy.text(), why), Bool.pick(U32, U32.is_eq(stop, 4), 3, Bool.pick(U32, U32.is_eq(stop, 5), 2, 1))})

def cp.end.ok(e: cp.End) -> Bool:
  match e:
    case cp.End{ok, t, s}:
      ok

def cp.end.stop(e: cp.End) -> U32:
  match e:
    case cp.End{ok, t, s}:
      s

def cp.end.text(e: cp.End) -> String:
  match e:
    case cp.End{ok, t, s}:
      t

# asked anew, a minute later, while not answered, but by the model or a stop
# (AskAI.ask patient)
def cp.again(+e: cp.End) -> Bool:
  Bool.and(Bool.not(cp.end.ok(e)), Bool.and(Bool.not(U32.is_eq(cp.end.stop(e), 1)), Bool.not(U32.is_eq(cp.end.stop(e), 2))))

def cp.nap(b: Bool, +cfg: A.ap.Cfg) -> IO(Unit):
  match b:
    case True{}:
      IO.sleep((A.ap.again() * A.ap.cfg.unit(cfg) : U32))
    case False{}:
      IO.pure(Unit, Unit{})

# a patient call of these blocks, no tools (one with none takes no step but
# its own: a pause_turn, no server tool running, ends it as done)
def cp.call.go(n: Nat, again: Bool, +cfg: A.ap.Cfg, +a: A.ap.Ask, +notes: Chan(String), +e: cp.End) -> IO(cp.End):
  match n again:
    case 0n _:
      IO.pure(cp.End, e)
    case 1n+f False{}:
      IO.pure(cp.End, e)
    case 1n+f True{}:
      do IO<cp.End>:
        s : A.ap.Step <- A.ap.step(cfg, a, [A.ap.User{A.ap.ask.blocks(a)}], notes, "")
        +e2 : cp.End = cp.end.of(s)
        Unit <- cp.nap(cp.again(e2), cfg)
        cp.call.go(f, cp.again(e2), cfg, a, notes, e2)

def cp.call(+cfg: A.ap.Cfg, +a: A.ap.Ask, +notes: Chan(String)) -> IO(cp.End):
  cp.call.go(U32.to_nat(4294967295), True{}, cfg, a, notes, cp.End{False{}, "", 0})

# The tries ---------------------------------------------------------------------

def cp.shorter(+a: String, b: Maybe<&2, String>) -> String:
  match b:
    case None{}:
      a
    case Some{+x}:
      Bool.pick(String, U32.is_lt(T.tx.bytes(a), T.tx.bytes(x)), a, x)

# what a job ends with: its line (None: cut by a stop, to build anew)
def cp.best(b: Maybe<&2, String>, +e: cp.End, +text: String) -> Maybe<&2, String>:
  match b:
    case Some{x}:
      Some{x}
    case None{}:
      Bool.pick(Maybe<&2, String>, Bool.and(Bool.not(cp.end.ok(e)), Bool.not(U32.is_eq(cp.end.stop(e), 1))), None{},
        Some{T.tx.cut(T.tx.flat(text), R.tr.node())})

# 0: no line (stop); 1: a line to keep, the last; 2: one too long, to ask again
def cp.verdict(+e: cp.End, +t: U32) -> Nat:
  +line = T.tx.trim(cp.end.text(e))
  Bool.pick(Nat, Bool.or(Bool.not(cp.end.ok(e)), String.is_empty(line)), 0n,
    Bool.pick(Nat, Bool.or(U32.is_le(T.tx.bytes(line), R.tr.node()), U32.is_eq(t, cp.tries())), 1n, 2n))

def cp.with(a: A.ap.Ask, bs: List<&2, V.vw.B>) -> A.ap.Ask:
  match a:
    case A.ap.Ask{p, sy, b, t, se, pa}:
      A.ap.Ask{p, sy, bs, t, se, pa}

# try t ended e, judged v; best: the shortest line so far
def cp.tries.go(n: Nat, v: Nat, +cfg: A.ap.Cfg, +a: A.ap.Ask, +notes: Chan(String), +blocks: List<&2, V.vw.B>, +text: String, +t: U32, +e: cp.End, +best: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match n v:
    case 0n _:
      IO.pure(Maybe<&2, String>, cp.best(best, e, text))
    case 1n+k 0n:
      IO.pure(Maybe<&2, String>, cp.best(best, e, text))
    case 1n+k 1n:
      IO.pure(Maybe<&2, String>, Some{cp.shorter(T.tx.trim(cp.end.text(e)), best)})
    case 1n+k _:
      +line = T.tx.trim(cp.end.text(e))
      +b2 = {Some{cp.shorter(line, best)} : Maybe<&2, String>}
      +t2 = (t + 1 : U32)
      do IO<Maybe<&2, String>>:
        +e2 : cp.End <- cp.call(cfg, cp.with(a, List.append(&2, V.vw.B, blocks, [V.vw.B{R.tr.over(line), False{}}])), notes)
        cp.tries.go(k, cp.verdict(e2, t2), cfg, a, notes, blocks, text, t2, e2, b2)

# a job's line: its blocks asked of the compactor on `pick` with the chat's
# system prompt, no tools
def cp.build(+cfg: A.ap.Cfg, +pick: A.ap.Pick, +system: String, +notes: Chan(String), job: M.me.Job) -> IO(Maybe<&2, String>):
  match job:
    case M.me.Job{l, i, +blocks, +text}:
      +a = {A.ap.Ask{pick, system, blocks, [], 0, True{}} : A.ap.Ask}
      do IO<Maybe<&2, String>>:
        +e : cp.End <- cp.call(cfg, a, notes)
        cp.tries.go(6n, cp.verdict(e, 1), cfg, a, notes, blocks, text, 1, e, None{})
