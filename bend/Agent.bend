
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./View.bend as V
import ./Api.bend as A
import ./Ev.bend as E
import ./Tools.bend as L

# Agent: a call in Unii's own loop (UniiChat's Agent.ts), for Unii's turn or
# an agent: each step sends every item and reads one output; its tool calls
# run in order; messages sent meanwhile (the hub's ev.Text on `says`) follow
# the next results; the call ends at a step with no tools and nothing sent.
# What it says goes to the hub as it comes: thoughts and busy notes shown
# (Show), replies, tool calls and their results logged (Entry), a call just
# before its result (as UniiChat logs them), those left without one at the
# end. The tools the hub owns (zoom, date, spawn, tell) it asks of the hub; the
# rest run here (Tools.bend). Its end goes to the hub (End), with how many
# messages sent to it it never took.
#
# Every def is prefixed `ag.` (a program's defs share one namespace).

# A call's place: settings, the hub's inbox, who it is ("" Unii), whether it
# may spawn and tell (Unii's), its tools' place (its control files too).
type ag.Env is Data:
  ag.Env{cfg: A.ap.Cfg, hub: Chan(E.ev.Ev), who: String, boss: Bool, tools: L.tl.Env}

def ag.cfg(e: ag.Env) -> A.ap.Cfg:
  match e:
    case ag.Env{c, h, w, b, t}:
      c

def ag.hub(e: ag.Env) -> Chan(E.ev.Ev):
  match e:
    case ag.Env{c, h, w, b, t}:
      h

def ag.who(e: ag.Env) -> String:
  match e:
    case ag.Env{c, h, w, b, t}:
      w

def ag.boss(e: ag.Env) -> Bool:
  match e:
    case ag.Env{c, h, w, b, t}:
      b

def ag.tools(e: ag.Env) -> L.tl.Env:
  match e:
    case ag.Env{c, h, w, b, t}:
      t

def ag.ctl(e: ag.Env) -> String:
  match e:
    case ag.Env{c, h, w, b, L.tl.Env{ho, wo, who, sh, ctl, g}}:
      ctl

def ag.busy() -> String:
  "the AI service is busy or unavailable right now"

def ag.log(+env: ag.Env, +kind: String, +text: String) -> IO(Unit):
  E.ev.send(ag.hub(env), E.ev.Entry{ag.who(env), kind, text})

def ag.show(+env: ag.Env, +kind: String, +text: String) -> IO(Unit):
  E.ev.send(ag.hub(env), E.ev.Show{ag.who(env), kind, text})

# Tool calls waiting on their results: id, as logged ("name {json}")
type ag.Pend is Data:
  ag.Pend{id: String, text: String}

def ag.pend.find(ps: List<&2, ag.Pend>, +id: String) -> Maybe<&2, String>:
  match ps:
    case []:
      None{}
    case ag.Pend{+i, +t} <> rest:
      Bool.pick(Maybe<&2, String>, String.eq(i, id), Some{t}, ag.pend.find(rest, id))

def ag.pend.del(ps: List<&2, ag.Pend>, +id: String) -> List<&2, ag.Pend>:
  match ps:
    case []:
      []
    case ag.Pend{+i, +t} <> rest:
      List.append(&2, ag.Pend, Bool.pick(List<&2, ag.Pend>, String.eq(i, id), [], [ag.Pend{i, t}]), ag.pend.del(rest, id))

# a result logged, its call (if waiting) just before it
def ag.result(+env: ag.Env, +call: Maybe<&2, String>, +text: String) -> IO(Unit):
  match call:
    case Some{c}:
      do IO<Unit>:
        Unit <- ag.log(env, "tool", c)
        ag.log(env, "echo", text)
    case None{}:
      ag.log(env, "echo", text)

def ag.entry.go(k: Nat, +env: ag.Env, +kind: String, +text: String, +call: Maybe<&2, String>) -> IO(Unit):
  match k:
    case 0n:
      ag.show(env, "mind", text)
    case 1n:
      IO.pure(Unit, Unit{})
    case 2n:
      ag.result(env, call, text)
    case _:
      ag.log(env, kind, text)

# a step's messages, in order (Server.ts Chat.on): a thought shown; a tool
# call kept till its result; a result logged after its call; a reply logged
def ag.entries(es: List<&2, A.ap.Entry>, +env: ag.Env, +ps: List<&2, ag.Pend>) -> IO(List<&2, ag.Pend>):
  match es:
    case []:
      IO.pure(List<&2, ag.Pend>, ps)
    case A.ap.Entry{+kind, +text, +of} <> rest:
      +mind = String.eq(kind, "mind")
      +call = Bool.and(String.eq(kind, "tool"), Bool.not(String.is_empty(of)))
      +echo = Bool.and(String.eq(kind, "echo"), Bool.not(String.is_empty(of)))
      do IO<List<&2, ag.Pend>>:
        Unit <- ag.entry.go(Bool.pick(Nat, mind, 0n, Bool.pick(Nat, call, 1n, Bool.pick(Nat, echo, 2n, 3n))), env, kind, text, ag.pend.find(ps, of))
        ag.entries(rest, env, Bool.pick(List<&2, ag.Pend>, call, List.append(&2, ag.Pend, ps, [ag.Pend{of, text}]), Bool.pick(List<&2, ag.Pend>, echo, ag.pend.del(ps, of), ps)))

# calls left without a result (the call stopped), logged as they are
def ag.unanswered(ps: List<&2, ag.Pend>, +env: ag.Env) -> IO(Unit):
  match ps:
    case []:
      IO.pure(Unit, Unit{})
    case ag.Pend{i, +t} <> rest:
      IO.bind(Unit, Unit, ag.log(env, "tool", t), u => ag.unanswered(rest, env))

# Tools --------------------------------------------------------------------------

def ag.hub.tool(+name: String, +boss: Bool) -> Bool:
  Bool.or(Bool.or(String.eq(name, "zoom"), String.eq(name, "date")), Bool.and(boss, Bool.or(String.eq(name, "spawn"), String.eq(name, "tell"))))

def ag.is.obj(+j: J.Json) -> Bool:
  match j:
    case J.JObj{kvs}:
      True{}
    case _:
      False{}

def ag.reply.got(m: Maybe<&1, E.ev.Out>) -> E.ev.Out:
  match m:
    case Some{o}:
      o
    case None{}:
      E.ev.Out{"The chat ended.", True{}}

# a tool the hub answers: asked, its answer awaited on a channel of our own
def ag.ask.hub(+env: ag.Env, +name: String, +input: J.Json) -> IO(E.ev.Out):
  do IO<E.ev.Out>:
    +reply : Chan(E.ev.Out) <- Chan.new(E.ev.Out, 1)
    Unit <- E.ev.send(ag.hub(env), E.ev.Req{ag.who(env), name, input, reply})
    m : Maybe<&1, E.ev.Out> <- Chan.recv(E.ev.Out, reply)
    return ag.reply.got(m)

def ag.out.fix(o: E.ev.Out) -> E.ev.Out:
  match o:
    case E.ev.Out{+text, fail}:
      E.ev.Out{Bool.pick(String, String.is_empty(text), "(no output)", text), fail}

# 0 not an object, 1 the hub's, 2 the device's, 3 none such
def ag.use.kind(+name: String, +input: J.Json, +boss: Bool) -> Nat:
  Bool.pick(Nat, Bool.not(ag.is.obj(input)), 0n, Bool.pick(Nat, ag.hub.tool(name, boss), 1n, Bool.pick(Nat, L.tl.is.kit(name), 2n, 3n)))

def ag.use.go(k: Nat, +env: ag.Env, +name: String, +input: J.Json) -> IO(E.ev.Out):
  match k:
    case 0n:
      IO.pure(E.ev.Out, E.ev.Out{"The input is not a JSON object.", True{}})
    case 1n:
      ag.ask.hub(env, name, input)
    case 2n:
      L.tl.kit.run(ag.tools(env), name, input)
    case _:
      IO.pure(E.ev.Out, E.ev.Out{"No tool " ++ name ++ ".", True{}})

# a tool call run (Agent.use): its output, "(no output)" for none
def ag.use(+env: ag.Env, +name: String, +input: J.Json) -> IO(E.ev.Out):
  IO.bind(E.ev.Out, E.ev.Out, ag.use.go(ag.use.kind(name, input, ag.boss(env)), env, name, input), o => IO.pure(E.ev.Out, ag.out.fix(o)))

# Messages sent meanwhile ------------------------------------------------------------

# what came on `says` so far: the texts in order, and whether a stop came
type ag.Got is Data:
  ag.Got{texts: List<&2, String>, stop: Bool}

def ag.drain(n: Nat, r: Poll<&1, &1, Maybe<&1, E.ev.Say>, Unit>, +says: Chan(E.ev.Say), +texts: List<&2, String>, +stop: Bool) -> IO(ag.Got):
  match n r:
    case 1n+f Ready{Some{E.ev.Text{t}}}:
      IO.bind(Poll<&1, &1, Maybe<&1, E.ev.Say>, Unit>, ag.Got, Chan.try_recv(E.ev.Say, says, 0), r2 => ag.drain(f, r2, says, List.append(&2, String, texts, [t]), stop))
    case 1n+f Ready{Some{E.ev.Stop{}}}:
      IO.bind(Poll<&1, &1, Maybe<&1, E.ev.Say>, Unit>, ag.Got, Chan.try_recv(E.ev.Say, says, 0), r2 => ag.drain(f, r2, says, texts, True{}))
    case _ _:
      IO.pure(ag.Got, ag.Got{texts, stop})

def ag.got(+says: Chan(E.ev.Say)) -> IO(ag.Got):
  IO.bind(Poll<&1, &1, Maybe<&1, E.ev.Say>, Unit>, ag.Got, Chan.try_recv(E.ev.Say, says, 0), r => ag.drain(U32.to_nat(65536), r, says, [], False{}))

def ag.parts(ts: List<&2, String>) -> List<&2, V.vw.B>:
  match ts:
    case []:
      []
    case t <> rest:
      V.vw.B{t, False{}} <> ag.parts(rest)

# The loop ---------------------------------------------------------------------------
#
# What comes next: a step; the step's tool calls to run (its replies, the
# results so far); the end.

type ag.Next is Data:
  ag.Step{}
  ag.Run{uses: List<&2, A.ap.Use>, replies: String, backs: List<&2, A.ap.Bk>}
  ag.Done{ok: Bool, text: String, stop: U32}

def ag.replies(es: List<&2, A.ap.Entry>) -> List<&2, String>:
  match es:
    case []:
      []
    case A.ap.Entry{+k, t, o} <> rest:
      List.append(&2, String, Bool.pick(List<&2, String>, String.eq(k, "unii"), [t], []), ag.replies(rest))

# after a step: its end (down, a stop, a failure), again (pause_turn), or its
# tools to run
def ag.after(s: A.ap.Step) -> ag.Next:
  match s:
    case A.ap.Step{out, +uses, +es, +stop, +why, after}:
      Bool.pick(ag.Next, U32.is_eq(stop, 4), ag.Done{False{}, ag.busy(), 3},
        Bool.pick(ag.Next, U32.is_eq(stop, 5), ag.Done{False{}, why, 2},
          Bool.pick(ag.Next, U32.is_eq(stop, 6), ag.Done{False{}, why, 1},
            Bool.pick(ag.Next, U32.is_eq(stop, 2), ag.Step{}, ag.Run{uses, T.tx.join(ag.replies(es), "\n\n"), []}))))

def ag.step.out(s: A.ap.Step) -> List<&2, J.Json>:
  match s:
    case A.ap.Step{out, u, e, st, w, a}:
      out

def ag.step.entries(s: A.ap.Step) -> List<&2, A.ap.Entry>:
  match s:
    case A.ap.Step{o, u, es, st, w, a}:
      es

def ag.step.ends(s: A.ap.Step) -> Bool:
  match s:
    case A.ap.Step{o, u, e, +st, w, a}:
      Bool.or(U32.is_eq(st, 4), Bool.or(U32.is_eq(st, 5), U32.is_eq(st, 6)))

# a step's output joins the items, unless the step failed
def ag.turn(+s: A.ap.Step, +its: List<&2, A.ap.Item>) -> List<&2, A.ap.Item>:
  Bool.pick(List<&2, A.ap.Item>, ag.step.ends(s), its, List.append(&2, A.ap.Item, its, [A.ap.Turn{ag.step.out(s)}]))

# the items after a batch of results: the results, then the messages sent
def ag.more(+its: List<&2, A.ap.Item>, +backs: List<&2, A.ap.Bk>, +texts: List<&2, String>) -> List<&2, A.ap.Item>:
  List.concat(&2, A.ap.Item, [its, Bool.pick(List<&2, A.ap.Item>, List.is_empty(&2, A.ap.Bk, backs), [], [A.ap.Back{backs}]),
    Bool.pick(List<&2, A.ap.Item>, List.is_empty(&2, String, texts), [], [A.ap.User{ag.parts(texts)}])])

# a batch's end: stopped; nothing more (the call answered with the replies);
# or on, with the results and what was sent
def ag.batch(g: ag.Got, +replies: String, +backs: List<&2, A.ap.Bk>) -> ag.Next:
  match g:
    case ag.Got{+texts, stop}:
      Bool.pick(ag.Next, stop, ag.Done{False{}, "stopped", 2},
        Bool.pick(ag.Next, Bool.and(List.is_empty(&2, A.ap.Bk, backs), List.is_empty(&2, String, texts)), ag.Done{True{}, replies, 0}, ag.Step{}))

def ag.got.texts(g: ag.Got) -> List<&2, String>:
  match g:
    case ag.Got{t, s}:
      t

def ag.json.show(+name: String, +input: J.Json) -> String:
  name ++ " " ++ J.js.write(input)

def ag.err(+o: E.ev.Out) -> String:
  match o:
    case E.ev.Out{+t, f}:
      Bool.pick(String, f, "error: " ++ t, t)

def ag.bk(+id: String, o: E.ev.Out) -> A.ap.Bk:
  match o:
    case E.ev.Out{t, f}:
      A.ap.Bk{id, t, f}

def ag.loop(n: Nat, next: ag.Next, +env: ag.Env, +ask: A.ap.Ask, +says: Chan(E.ev.Say), +notes: Chan(String), +its: List<&2, A.ap.Item>, +ps: List<&2, ag.Pend>) -> IO(ag.Next):
  match n next:
    case 0n _:
      IO.pure(ag.Next, ag.Done{False{}, "too many steps", 1})
    case 1n+f ag.Step{}:
      do IO<ag.Next>:
        st : Bool <- A.ap.stopped(ag.ctl(env))
        +s : A.ap.Step <- Bool.pick(IO(A.ap.Step), st, IO.pure(A.ap.Step, A.ap.fail("stopped", 5, 0)), A.ap.step(ag.cfg(env), ask, its, notes, ag.ctl(env)))
        +ps2 : List<&2, ag.Pend> <- ag.entries(ag.step.entries(s), env, ps)
        ag.loop(f, ag.after(s), env, ask, says, notes, ag.turn(s, its), ps2)
    case 1n+f ag.Run{[], +replies, +backs}:
      do IO<ag.Next>:
        +g : ag.Got <- ag.got(says)
        ag.loop(f, ag.batch(g, replies, backs), env, ask, says, notes, ag.more(its, backs, ag.got.texts(g)), ps)
    case 1n+f ag.Run{A.ap.Use{+id, +name, +input} <> rest, +replies, +backs}:
      do IO<ag.Next>:
        +st : Bool <- A.ap.stopped(ag.ctl(env))
        +o : E.ev.Out <- Bool.pick(IO(E.ev.Out), st, IO.pure(E.ev.Out, E.ev.Out{"(stopped)", True{}}), ag.use(env, name, input))
        Unit <- ag.result(env, Some{Maybe.default(&2, String, ag.pend.find(ps, id), ag.json.show(name, input))}, ag.err(o))
        ag.loop(f, Bool.pick(ag.Next, st, ag.Done{False{}, "stopped", 2}, ag.Run{rest, replies, List.append(&2, A.ap.Bk, backs, [ag.bk(id, o)])}), env, ask, says, notes, its, ag.pend.del(ps, id))
    case 1n+f ag.Done{ok, text, stop}:
      do IO<ag.Next>:
        Unit <- ag.unanswered(ps, env)
        return ag.Done{ok, text, stop}

# Running a call -----------------------------------------------------------------------

# the busy notes, shown as they come, till the call closes them
def ag.forward(n: Nat, m: Maybe<&1, String>, +env: ag.Env, +notes: Chan(String)) -> IO(Unit):
  match n m:
    case 1n+f Some{t}:
      do IO<Unit>:
        Unit <- ag.show(env, "mind", t)
        m2 : Maybe<&1, String> <- Chan.recv(String, notes)
        ag.forward(f, m2, env, notes)
    case _ _:
      IO.pure(Unit, Unit{})

def ag.end(+env: ag.Env, +says: Chan(E.ev.Say), +notes: Chan(String), next: ag.Next) -> IO(Unit):
  match next:
    case ag.Done{ok, text, stop}:
      do IO<Unit>:
        g : ag.Got <- ag.got(says)
        Unit <- Chan.close(E.ev.Say, says)
        Unit <- Chan.close(String, notes)
        E.ev.send(ag.hub(env), E.ev.End{ag.who(env), ok, text, stop, U32.from_nat(List.length(&2, String, ag.got.texts(g)))})
    case _:
      E.ev.send(ag.hub(env), E.ev.End{ag.who(env), False{}, "the call ended early", 1, 0})

# a call run to its end, told to the hub; `says` closed as it ends (a message
# sent after that is the hub's to keep)
def ag.run(+env: ag.Env, +ask: A.ap.Ask, +says: Chan(E.ev.Say)) -> IO(Unit):
  do IO<Unit>:
    +notes : Chan(String) <- Chan.new(String, 64)
    Unit <- IO.spawn(Unit, IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, notes), m => ag.forward(U32.to_nat(4294967295), m, env, notes)))
    next : ag.Next <- ag.loop(U32.to_nat(4294967295), ag.Step{}, env, ask, says, notes, [A.ap.User{A.ap.ask.blocks(ask)}], [])
    ag.end(env, says, notes, next)
