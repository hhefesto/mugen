
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./View.bend as V
import ./Api.bend as A
import ./Ev.bend as E
import ./Tools.bend as L
import ./Code.bend as C
import ./Mcp.bend as Q

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

def ag.json.show(+name: String, +input: J.Json) -> String:
  name ++ " " ++ J.js.write(input)

# a tool call run (Agent.use): its output, "(no output)" for none; its start
# shown (as "run", the call as it will be logged: the screen's running tool)
def ag.use(+env: ag.Env, +name: String, +input: J.Json) -> IO(E.ev.Out):
  do IO<E.ev.Out>:
    Unit <- ag.show(env, "run", ag.json.show(name, input))
    o : E.ev.Out <- ag.use.go(ag.use.kind(name, input, ag.boss(env)), env, name, input)
    return ag.out.fix(o)

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

# a call run to its end on the API, told to the hub; `says` closed as it ends
# (a message sent after that is the hub's to keep)
def ag.api.run(+env: ag.Env, +ask: A.ap.Ask, +says: Chan(E.ev.Say)) -> IO(Unit):
  do IO<Unit>:
    +notes : Chan(String) <- Chan.new(String, 64)
    Unit <- IO.spawn(Unit, IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, notes), m => ag.forward(U32.to_nat(4294967295), m, env, notes)))
    next : ag.Next <- ag.loop(U32.to_nat(4294967295), ag.Step{}, env, ask, says, notes, [A.ap.User{A.ap.ask.blocks(ask)}], [])
    ag.end(env, says, notes, next)

# Claude Code's call ---------------------------------------------------------------
#
# The call on Claude Code (Code.bend): it runs the loop itself. We serve it
# our tools (MCP: its requests read from ctl.cc.mcp.in, our answers appended
# to ctl.cc.mcp.out), read its events as they come (ctl.cc.out), and hand it
# the hub's messages on its stdin (the FIFO ctl.cc.in), each with an id it
# says back as it takes it. A message is held till it can follow tool
# results (written as a tool call is answered, it comes with the results)
# or, the turn answered, starts the next turn of the same process; a turn
# that failed ends the call, and what it held is left for the next. A tool
# call is logged as it is served, its result after it; Claude Code's own
# tools' (web search) from its events. The events are read before MCP's
# requests, so what an output says comes before its calls. The call ends
# once a result came and nothing is held or untaken: its stdin closed,
# Claude Code exits, and its wrapper's last line ends the reading.

# what the call hears: a line of its events (k 0) or of MCP's (1); a message
# from the hub; a reader's end (0 the files', 2 the hub's)
type ag.Cv is Data:
  ag.CLine{k: U32, line: String}
  ag.CSay{say: E.ev.Say}
  ag.CEnd{k: Nat}

def ag.cv.send(+c: Chan(ag.Cv), e: ag.Cv) -> IO(Unit):
  IO.bind(Result<&1, &1, ag.Cv, Unit>, Unit, Chan.send(ag.Cv, c, e), r => IO.pure(Unit, Unit{}))

# lines sent on as they are; true when the wrapper's last line came
def ag.tail.lines(ls: List<&2, String>, +k: U32, +ch: Chan(ag.Cv)) -> IO(Bool):
  match ls:
    case []:
      IO.pure(Bool, False{})
    case +l <> t:
      Bool.pick(IO(Bool), C.cc.is.gone(l), IO.bind(Unit, Bool, ag.cv.send(ch, ag.CLine{k, l}), u => IO.pure(Bool, True{})),
        IO.bind(Unit, Bool, ag.cv.send(ch, ag.CLine{k, l}), u => ag.tail.lines(t, k, ch)))

def ag.shut(q: Poll<&1, &1, Maybe<&1, Unit>, Unit>) -> Bool:
  match q:
    case Ready{None{}}:
      True{}
    case _:
      False{}

# The events' file and MCP's followed from their start, polled at their end,
# their lines to ch (k 0, 1): the events' read first, MCP's only once they
# are caught up. mcp: r is MCP's read (else the events'), `other` the other
# file; c0, c1 their lines cut short; stop: the wrapper's last line came, or
# quit closed.
def ag.tail(fuel: Nat, mcp: Bool, stop: Bool, +ch: Chan(ag.Cv), +quit: Chan(Unit), +c0: String, +c1: String, other: File, r: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match fuel mcp stop r:
    case 1n+f False{} False{} Tuple{file, Done{SCon{h, t}}}:
      +fed = C.cc.feed(SCon{h, t}, c0, [])
      do IO<Unit>:
        last : Bool <- ag.tail.lines(C.cc.fed.lines(fed), 0, ch)
        r2 : File & Result<&1, &1, U32 & String, String> <- File.read(file, 65536)
        ag.tail(f, False{}, last, ch, quit, C.cc.fed.cur(fed), c1, other, r2)
    case 1n+f False{} False{} Tuple{file, Done{SNil{}}}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(other, 65536), r2 => ag.tail(f, True{}, False{}, ch, quit, c0, c1, file, r2))
    case 1n+f True{} False{} Tuple{file, Done{SCon{h, t}}}:
      +fed = C.cc.feed(SCon{h, t}, c1, [])
      do IO<Unit>:
        x : Bool <- ag.tail.lines(C.cc.fed.lines(fed), 1, ch)
        r2 : File & Result<&1, &1, U32 & String, String> <- File.read(other, 65536)
        ag.tail(f, False{}, False{}, ch, quit, c0, C.cc.fed.cur(fed), file, r2)
    case 1n+f True{} False{} Tuple{file, Done{SNil{}}}:
      do IO<Unit>:
        q : Poll<&1, &1, Maybe<&1, Unit>, Unit> <- Chan.try_recv(Unit, quit, 0)
        Unit <- IO.sleep(40)
        r2 : File & Result<&1, &1, U32 & String, String> <- File.read(other, 65536)
        ag.tail(f, False{}, ag.shut(q), ch, quit, c0, c1, file, r2)
    case _ _ _ Tuple{file, _}:
      do IO<Unit>:
        Unit <- File.close(file)
        Unit <- File.close(other)
        ag.cv.send(ch, ag.CEnd{0n})

def ag.tail.open(+ch: Chan(ag.Cv), +quit: Chan(Unit), a: Result<&1, &1, U32 & String, File>, b: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match a b:
    case Done{fo} Done{fm}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(fo, 65536), r => ag.tail(U32.to_nat(4294967295), False{}, False{}, ch, quit, "", "", fm, r))
    case Done{fo} Fail{e}:
      IO.bind(Unit, Unit, File.close(fo), u => ag.cv.send(ch, ag.CEnd{0n}))
    case Fail{e} Done{fm}:
      IO.bind(Unit, Unit, File.close(fm), u => ag.cv.send(ch, ag.CEnd{0n}))
    case _ _:
      ag.cv.send(ch, ag.CEnd{0n})

def ag.tail.start(+ch: Chan(ag.Cv), +quit: Chan(Unit), +ctl: String) -> IO(Unit):
  do IO<Unit>:
    a : Result<&1, &1, U32 & String, File> <- File.open(ctl ++ ".cc.out", "r")
    b : Result<&1, &1, U32 & String, File> <- File.open(ctl ++ ".cc.mcp.in", "r")
    ag.tail.open(ch, quit, a, b)

# Claude Code's stdin, held: each text written, the FIFO closed once texts
# closes (its end of file for Claude Code)
def ag.hold(fuel: Nat, m: Maybe<&1, String>, +texts: Chan(String), r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match fuel m r:
    case 1n+f Some{t} Tuple{file, w}:
      do IO<Unit>:
        r2 : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, t)
        m2 : Maybe<&1, String> <- Chan.recv(String, texts)
        ag.hold(f, m2, texts, r2)
    case _ _ Tuple{file, w}:
      File.close(file)

def ag.hold.open(+texts: Chan(String), r: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match r:
    case Done{file}:
      do IO<Unit>:
        r2 : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, "")
        m : Maybe<&1, String> <- Chan.recv(String, texts)
        ag.hold(U32.to_nat(4294967295), m, texts, r2)
    case Fail{e}:
      IO.pure(Unit, Unit{})

# the hub's messages, passed on, till it is closed
def ag.fwd(fuel: Nat, m: Maybe<&1, E.ev.Say>, +says: Chan(E.ev.Say), +ch: Chan(ag.Cv)) -> IO(Unit):
  match fuel m:
    case 1n+f Some{x}:
      do IO<Unit>:
        Unit <- ag.cv.send(ch, ag.CSay{x})
        m2 : Maybe<&1, E.ev.Say> <- Chan.recv(E.ev.Say, says)
        ag.fwd(f, m2, says, ch)
    case _ _:
      ag.cv.send(ch, ag.CEnd{2n})

# What the call knows: its own message's id, and whether it was taken; the
# ids of the hub's messages sent and not taken yet; those held; the replies
# of the latest output, and its message's id; Claude Code's own tools' calls
# waiting on results; the last result; whether stdin is open; whether a stop
# came; the hub's messages that came after stdin closed.
type ag.Cs is Data:
  ag.Cs{id: String, first: Bool, sent: List<&2, String>, held: List<&2, String>, last: List<&2, String>, msg: String, ps: List<&2, ag.Pend>, res: Maybe<&2, C.cc.Res>, open: Bool, stop: Bool, left: U32}

def ag.cs.sent(s: ag.Cs) -> List<&2, String>:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      se

def ag.cs.held(s: ag.Cs) -> List<&2, String>:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      h

def ag.cs.last(s: ag.Cs) -> List<&2, String>:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      l

def ag.cs.ps(s: ag.Cs) -> List<&2, ag.Pend>:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      p

def ag.cs.res(s: ag.Cs) -> Maybe<&2, C.cc.Res>:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      r

def ag.cs.open(s: ag.Cs) -> Bool:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      o

def ag.cs.stop(s: ag.Cs) -> Bool:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      st

def ag.cs.left(s: ag.Cs) -> U32:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      le

def ag.strs.del(xs: List<&2, String>, +x: String) -> List<&2, String>:
  match xs:
    case []:
      []
    case +y <> t:
      List.append(&2, String, Bool.pick(List<&2, String>, String.eq(x, y), [], [y]), ag.strs.del(t, x))

# every message taken: its own and the hub's sent
def ag.cc.taken(s: ag.Cs) -> Bool:
  match s:
    case ag.Cs{i, f, +se, h, l, m, p, r, o, st, le}:
      Bool.and(f, List.is_empty(&2, String, se))

# Events --------------------------------------------------------------------------

# an output's messages (Api.bend ap.entries) as the API path logs them, but
# our MCP tools' calls, logged as they are served
def ag.cc.mine(es: List<&2, A.ap.Entry>) -> List<&2, A.ap.Entry>:
  match es:
    case []:
      []
    case A.ap.Entry{+k, +t, +o} <> rest:
      List.append(&2, A.ap.Entry, Bool.pick(List<&2, A.ap.Entry>, Bool.and(String.eq(k, "tool"), String.starts_with(t, "mcp__mugen__")), [], [A.ap.Entry{k, t, o}]), ag.cc.mine(rest))

def ag.cc.texts(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case []:
      []
    case +x <> t:
      List.append(&2, String, Bool.pick(List<&2, String>, String.eq(C.cc.ty(x), "text"), [C.cc.s(x, "text")], []), ag.cc.texts(t))

# a tool result's text: its content as text, or its text blocks joined
def ag.cc.result.text(+c: Maybe<&2, J.Json>) -> String:
  match c:
    case Some{J.JStr{s}}:
      s
    case Some{J.JArr{xs}}:
      T.tx.join(ag.cc.texts(xs), "\n")
    case _:
      ""

# the results of Claude Code's own tools' calls (those waiting), as echoes
def ag.cc.echoes(bs: List<&2, J.Json>, +ps: List<&2, ag.Pend>) -> List<&2, A.ap.Entry>:
  match bs:
    case []:
      []
    case +b <> t:
      +id = C.cc.s(b, "tool_use_id")
      +mine = Bool.and(String.eq(C.cc.ty(b), "tool_result"), Maybe.is_some(&2, String, ag.pend.find(ps, id)))
      +fail = Maybe.default(&2, Bool, J.js.bool(b, "is_error"), False{})
      +text = A.ap.or.none(L.tl.clip(T.tx.trim(ag.cc.result.text(J.js.field(b, "content")))))
      List.append(&2, A.ap.Entry, Bool.pick(List<&2, A.ap.Entry>, mine, [A.ap.Entry{"echo", Bool.pick(String, fail, "error: " ++ text, text), id}], []), ag.cc.echoes(t, ps))

def ag.cc.with.out(s: ag.Cs, +msg: String, +replies: List<&2, String>, +ps: List<&2, ag.Pend>) -> ag.Cs:
  match s:
    case ag.Cs{i, f, se, h, +l, +m, p, r, o, st, le}:
      ag.Cs{i, f, se, h, List.append(&2, String, Bool.pick(List<&2, String>, String.eq(m, msg), l, []), replies), msg, ps, r, o, st, le}

# an output of Claude Code's: its messages logged and shown, its replies kept
def ag.cc.assistant(+env: ag.Env, +s: ag.Cs, +j: J.Json) -> IO(ag.Cs):
  +es = ag.cc.mine(A.ap.entries(A.ap.out(C.cc.blocks(j))))
  do IO<ag.Cs>:
    +ps : List<&2, ag.Pend> <- ag.entries(es, env, ag.cs.ps(s))
    return ag.cc.with.out(s, C.cc.s(C.cc.message(j), "id"), ag.replies(es), ps)

def ag.cc.with.taken(s: ag.Cs, +uuid: String, +ps: List<&2, ag.Pend>) -> ag.Cs:
  match s:
    case ag.Cs{+i, +f, +se, h, l, m, p, r, o, st, le}:
      ag.Cs{i, Bool.or(f, String.eq(i, uuid)), ag.strs.del(se, uuid), h, l, m, ps, r, o, st, le}

# a user event: one of ours taken (its id said back), or tool results
def ag.cc.user(+env: ag.Env, +s: ag.Cs, +j: J.Json) -> IO(ag.Cs):
  do IO<ag.Cs>:
    +ps : List<&2, ag.Pend> <- ag.entries(ag.cc.echoes(C.cc.blocks(j), ag.cs.ps(s)), env, ag.cs.ps(s))
    return ag.cc.with.taken(s, C.cc.s(j, "uuid"), ps)

# the held messages onto stdin, each with an id of its own: sent
def ag.cc.flush.go(hs: List<&2, String>, +texts: Chan(String), +sent: List<&2, String>) -> IO(List<&2, String>):
  match hs:
    case []:
      IO.pure(List<&2, String>, sent)
    case t <> rest:
      do IO<List<&2, String>>:
        +u : String <- C.cc.uuid()
        r : Result<&1, &1, String, Unit> <- Chan.send(String, texts, C.cc.say(t, u))
        ag.cc.flush.go(rest, texts, List.append(&2, String, sent, [u]))

def ag.cc.flush(+texts: Chan(String), s: ag.Cs) -> IO(ag.Cs):
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      IO.bind(List<&2, String>, ag.Cs, ag.cc.flush.go(h, texts, se), se2 => IO.pure(ag.Cs, ag.Cs{i, f, se2, [], l, m, p, r, o, st, le}))

def ag.cc.flush.if(b: Bool, +texts: Chan(String), +s: ag.Cs) -> IO(ag.Cs):
  match b:
    case True{}:
      ag.cc.flush(texts, s)
    case False{}:
      IO.pure(ag.Cs, s)

def ag.cc.close.if(b: Bool, +texts: Chan(String)) -> IO(Unit):
  match b:
    case True{}:
      Chan.close(String, texts)
    case False{}:
      IO.pure(Unit, Unit{})

def ag.cc.pid(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Done{t}:
      U32.from_nat(Maybe.default(&2, Nat, Nat.read(T.tx.trim(t)), 0n))
    case Fail{e}:
      0

# Claude Code's group killed, its stdin closed, and (the wrapper killed with
# it) the last line ours
def ag.cc.halt(+env: ag.Env, +texts: Chan(String)) -> IO(Unit):
  +ctl = ag.ctl(env)
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- S.mu.read_file(ctl ++ ".cc.pid")
    +pid : U32 = ag.cc.pid(r)
    k : U32 <- Bool.pick(IO(U32), U32.is_eq(pid, 0), IO.pure(U32, 0), S.mu.kill(pid, 1, 15))
    Unit <- Chan.close(String, texts)
    a : Result<&1, &1, U32 & String, Nat> <- S.mu.append(ctl ++ ".cc.out", C.cc.gone("-1"), 0)
    return Unit{}

def ag.cc.halt.if(b: Bool, +env: ag.Env, +texts: Chan(String)) -> IO(Unit):
  match b:
    case True{}:
      ag.cc.halt(env, texts)
    case False{}:
      IO.pure(Unit, Unit{})

def ag.cc.with.res(s: ag.Cs, +res: C.cc.Res, +open: Bool) -> ag.Cs:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      ag.Cs{i, f, se, h, l, m, p, Some{res}, open, st, le}

# a result: its tokens shown. Answered, the messages held go on as the next
# turn; else, every message taken, stdin is closed. A turn that failed (a
# refusal, an error) ends the call, at once if a message sent was not taken.
def ag.cc.result(+env: ag.Env, +texts: Chan(String), +s: ag.Cs, +j: J.Json) -> IO(ag.Cs):
  +res = C.cc.res.of(j)
  +fine = C.cc.res.fine(res)
  +held = Bool.not(List.is_empty(&2, String, ag.cs.held(s)))
  +taken = ag.cc.taken(s)
  do IO<ag.Cs>:
    Unit <- ag.show(env, "usage", C.cc.usage(Maybe.default(&2, J.Json, J.js.field(j, "usage"), J.JObj{[]})))
    +s2 : ag.Cs <- ag.cc.flush.if(Bool.and(fine, held), texts, s)
    Unit <- ag.cc.close.if(Bool.or(Bool.not(fine), Bool.and(taken, Bool.not(held))), texts)
    Unit <- ag.cc.halt.if(Bool.and(Bool.not(fine), Bool.not(taken)), env, texts)
    return ag.cc.with.res(s2, res, Bool.and(ag.cs.open(s), Bool.and(fine, Bool.or(held, Bool.not(taken)))))

# a retry Claude Code waits on, told as a busy note
def ag.cc.retry(+env: ag.Env, +s: ag.Cs, +j: J.Json) -> IO(ag.Cs):
  +secs = Nat.div(C.cc.n(j, "retry_delay_ms"), 1000n)
  IO.bind(Unit, ag.Cs, ag.show(env, "mind", "The AI service is busy: asking again in " ++ Nat.show(secs) ++ " s."), u => IO.pure(ag.Cs, s))

# 0 an output, 1 a user event, 2 a result, 3 a retry, 4 the plan's limits,
# 5 else
def ag.cc.kind(+j: J.Json) -> Nat:
  +ty = C.cc.ty(j)
  Bool.pick(Nat, String.eq(ty, "assistant"), 0n, Bool.pick(Nat, String.eq(ty, "user"), 1n, Bool.pick(Nat, String.eq(ty, "result"), 2n,
    Bool.pick(Nat, Bool.and(String.eq(ty, "system"), String.eq(C.cc.s(j, "subtype"), "api_retry")), 3n,
      Bool.pick(Nat, String.eq(ty, "rate_limit_event"), 4n, 5n)))))

def ag.cc.event.go(k: Nat, +env: ag.Env, +texts: Chan(String), +s: ag.Cs, +j: J.Json) -> IO(ag.Cs):
  match k:
    case 0n:
      ag.cc.assistant(env, s, j)
    case 1n:
      ag.cc.user(env, s, j)
    case 2n:
      ag.cc.result(env, texts, s, j)
    case 3n:
      ag.cc.retry(env, s, j)
    case 4n:
      IO.bind(Unit, ag.Cs, C.cc.limits.keep(A.ap.cfg.cc(ag.cfg(env)), J.js.field(j, "rate_limit_info")), u => IO.pure(ag.Cs, s))
    case _:
      IO.pure(ag.Cs, s)

def ag.cc.event(+env: ag.Env, +texts: Chan(String), +s: ag.Cs, +line: String) -> IO(ag.Cs):
  +j = Maybe.default(&2, J.Json, J.js.read(line), J.JObj{[]})
  ag.cc.event.go(ag.cc.kind(j), env, texts, s, j)

# MCP ---------------------------------------------------------------------------------

# an answer appended to ctl.cc.mcp.out, the relay's to pass on
def ag.cc.answer(+env: ag.Env, +text: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(text), IO.pure(Unit, Unit{}),
    IO.bind(Result<&1, &1, U32 & String, Nat>, Unit, S.mu.append(ag.ctl(env) ++ ".cc.mcp.out", text, 0), r => IO.pure(Unit, Unit{})))

def ag.cc.out(o: E.ev.Out) -> J.Json:
  match o:
    case E.ev.Out{t, f}:
      Q.mc.out(t, f)

# a tool the call offers
def ag.listed(ds: List<&2, J.Json>, +name: String) -> Bool:
  match ds:
    case []:
      False{}
    case +d <> t:
      Bool.or(String.eq(Maybe.default(&2, String, J.js.str(d, "name"), ""), name), ag.listed(t, name))

def ag.cc.out.of(has: Bool, stopped: Bool, +env: ag.Env, +name: String, +input: J.Json) -> IO(E.ev.Out):
  match has stopped:
    case False{} _:
      IO.pure(E.ev.Out, E.ev.Out{"No tool " ++ name ++ ".", True{}})
    case True{} True{}:
      IO.pure(E.ev.Out, E.ev.Out{"(stopped)", True{}})
    case True{} False{}:
      ag.use(env, name, input)

def ag.ask.tools(a: A.ap.Ask) -> List<&2, J.Json>:
  match a:
    case A.ap.Ask{p, sy, b, t, se, pa}:
      t

# a tool call run as the API path runs one (only a tool the call offers),
# logged as it is served
def ag.cc.call(+env: ag.Env, +ask: A.ap.Ask, +m: J.Json) -> IO(String):
  +name = Q.mc.bare(Q.mc.name(m))
  +input = Q.mc.input(m)
  do IO<String>:
    st : Bool <- A.ap.stopped(ag.ctl(env))
    +o : E.ev.Out <- ag.cc.out.of(ag.listed(ag.ask.tools(ask), name), st, env, name, input)
    Unit <- ag.result(env, Some{ag.json.show(name, input)}, ag.err(o))
    return Q.mc.answer(Q.mc.id(m), ag.cc.out(o))

def ag.ask.searches(a: A.ap.Ask) -> U32:
  match a:
    case A.ap.Ask{p, sy, b, t, se, pa}:
      se

# a request's answer (not a tool call's): "" for a notification
def ag.cc.mcp.go(k: Nat, +ask: A.ap.Ask, +m: J.Json) -> String:
  match k:
    case 0n:
      ""
    case 1n:
      Q.mc.answer(Q.mc.id(m), Q.mc.init(Q.mc.params(m)))
    case 2n:
      Q.mc.answer(Q.mc.id(m), Q.mc.listed(ag.ask.tools(ask)))
    case 4n:
      Q.mc.answer(Q.mc.id(m), J.JObj{[]})
    case _:
      Q.mc.none(Q.mc.id(m), Q.mc.s(m, "method"))

# a tool call run, then what is held sent (so it comes with the results),
# then the answer; any other request answered at once
def ag.cc.mcp.on(call: Bool, k: Nat, +env: ag.Env, +ask: A.ap.Ask, +texts: Chan(String), +s: ag.Cs, +m: J.Json) -> IO(ag.Cs):
  match call:
    case True{}:
      do IO<ag.Cs>:
        +a : String <- ag.cc.call(env, ask, m)
        +s2 : ag.Cs <- ag.cc.flush(texts, s)
        Unit <- ag.cc.answer(env, a)
        return s2
    case False{}:
      IO.bind(Unit, ag.Cs, ag.cc.answer(env, ag.cc.mcp.go(k, ask, m)), u => IO.pure(ag.Cs, s))

def ag.cc.mcp(+env: ag.Env, +ask: A.ap.Ask, +texts: Chan(String), +s: ag.Cs, +line: String) -> IO(ag.Cs):
  +m = Maybe.default(&2, J.Json, J.js.read(line), J.JObj{[]})
  +k = Q.mc.kind(m)
  ag.cc.mcp.on(Nat.is_eq(k, 3n), k, env, ask, texts, s, m)

# The hub's messages ----------------------------------------------------------------

# a message held (or, stdin closed, left)
def ag.cc.text.on(open: Bool, s: ag.Cs, +t: String) -> ag.Cs:
  match open s:
    case True{} ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      ag.Cs{i, f, se, List.append(&2, String, h, [t]), l, m, p, r, o, st, le}
    case False{} ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      ag.Cs{i, f, se, h, l, m, p, r, o, st, (le + 1 : U32)}

def ag.cc.text(+s: ag.Cs, +t: String) -> IO(ag.Cs):
  IO.pure(ag.Cs, ag.cc.text.on(ag.cs.open(s), s, t))

def ag.cc.with.stop(s: ag.Cs) -> ag.Cs:
  match s:
    case ag.Cs{i, f, se, h, l, m, p, r, o, st, le}:
      ag.Cs{i, f, se, h, l, m, p, r, False{}, True{}, le}

# a stop: the call halted
def ag.cc.stop(+env: ag.Env, +texts: Chan(String), +s: ag.Cs) -> IO(ag.Cs):
  IO.bind(Unit, ag.Cs, ag.cc.halt(env, texts), u => IO.pure(ag.Cs, ag.cc.with.stop(s)))

# The loop ----------------------------------------------------------------------------

def ag.cc.line.go(k: Nat, +env: ag.Env, +ask: A.ap.Ask, +texts: Chan(String), +s: ag.Cs, +line: String) -> IO(ag.Cs):
  match k:
    case 0n:
      ag.cc.event(env, texts, s, line)
    case _:
      ag.cc.mcp(env, ask, texts, s, line)

def ag.cc.on(x: ag.Cv, +env: ag.Env, +ask: A.ap.Ask, +texts: Chan(String), +s: ag.Cs) -> IO(ag.Cs):
  match x:
    case ag.CLine{k, line}:
      ag.cc.line.go(U32.to_nat(k), env, ask, texts, s, line)
    case ag.CSay{E.ev.Text{t}}:
      ag.cc.text(s, t)
    case ag.CSay{E.ev.Stop{}}:
      ag.cc.stop(env, texts, s)
    case _:
      IO.pure(ag.Cs, s)

# the call's events, one at a time, till the files' end
def ag.cc.loop(n: Nat, m: Maybe<&1, ag.Cv>, +env: ag.Env, +ask: A.ap.Ask, +ch: Chan(ag.Cv), +texts: Chan(String), +s: ag.Cs) -> IO(ag.Cs):
  match n m:
    case 1n+f Some{ag.CEnd{0n}}:
      IO.pure(ag.Cs, s)
    case 1n+f Some{x}:
      do IO<ag.Cs>:
        +s2 : ag.Cs <- ag.cc.on(x, env, ask, texts, s)
        m2 : Maybe<&1, ag.Cv> <- Chan.recv(ag.Cv, ch)
        ag.cc.loop(f, m2, env, ask, ch, texts, s2)
    case _ _:
      IO.pure(ag.Cs, s)

# after the files' end: the hub's messages still coming counted (left), till
# the hub's reader ends (need: how many readers have yet to)
def ag.cc.drain(n: Nat, need: Nat, m: Maybe<&1, ag.Cv>, +ch: Chan(ag.Cv), +left: U32) -> IO(U32):
  match n need m:
    case 1n+f 1n Some{ag.CEnd{e}}:
      IO.pure(U32, left)
    case 1n+f 1n+k Some{ag.CEnd{e}}:
      IO.bind(Maybe<&1, ag.Cv>, U32, Chan.recv(ag.Cv, ch), m2 => ag.cc.drain(f, k, m2, ch, left))
    case 1n+f 1n+k Some{ag.CSay{E.ev.Text{t}}}:
      IO.bind(Maybe<&1, ag.Cv>, U32, Chan.recv(ag.Cv, ch), m2 => ag.cc.drain(f, 1n+k, m2, ch, (left + 1 : U32)))
    case 1n+f 1n+k Some{x}:
      IO.bind(Maybe<&1, ag.Cv>, U32, Chan.recv(ag.Cv, ch), m2 => ag.cc.drain(f, 1n+k, m2, ch, left))
    case _ _ _:
      IO.pure(U32, left)

# how the call ended: stopped; answered (its last output's replies), or
# stopped by the model (a refusal, a stop reason); else the AI service's
# doing (no result: busy)
def ag.cc.done.of(r: Maybe<&2, C.cc.Res>, +replies: String) -> ag.Next:
  match r:
    case Some{C.cc.Res{g, +ok, +status, +stop, +why}}:
      Bool.pick(ag.Next, Bool.and(ok, C.cc.fine(stop)), ag.Done{True{}, replies, 0},
        Bool.pick(ag.Next, ok, ag.Done{False{}, "stopped: " ++ stop, 1},
          Bool.pick(ag.Next, A.ap.passing(status, ""), ag.Done{False{}, ag.busy(), 3}, ag.Done{False{}, A.ap.cc.why(status, why), 3})))
    case None{}:
      ag.Done{False{}, ag.busy(), 3}

def ag.cc.done(+s: ag.Cs) -> ag.Next:
  Bool.pick(ag.Next, ag.cs.stop(s), ag.Done{False{}, "stopped", 2}, ag.cc.done.of(ag.cs.res(s), T.tx.join(ag.cs.last(s), "\n\n")))

# Claude Code's complaint, shown when it ended with no result
def ag.cc.said(+env: ag.Env, +err: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(err), IO.pure(Unit, Unit{}), ag.show(env, "mind", "claude: " ++ String.take(err, 2000n)))

def ag.cc.err(+env: ag.Env, +s: ag.Cs) -> IO(Unit):
  Bool.pick(IO(Unit), Bool.or(Maybe.is_some(&2, C.cc.Res, ag.cs.res(s)), ag.cs.stop(s)), IO.pure(Unit, Unit{}),
    IO.bind(Result<&1, &1, U32 & String, String>, Unit, S.mu.read_file(ag.ctl(env) ++ ".cc.err"), r => ag.cc.said(env, T.tx.trim(L.tl.text.of(r)))))

def ag.end.cc(+env: ag.Env, next: ag.Next, +left: U32) -> IO(Unit):
  match next:
    case ag.Done{ok, text, stop}:
      E.ev.send(ag.hub(env), E.ev.End{ag.who(env), ok, text, stop, left})
    case _:
      E.ev.send(ag.hub(env), E.ev.End{ag.who(env), False{}, "the call ended early", 1, 0})

# the end: stdin, the readers and `says` closed; left, what the call never
# took (sent and not taken, held, and what came once stdin closed)
def ag.cc.end(+env: ag.Env, +says: Chan(E.ev.Say), +ch: Chan(ag.Cv), +texts: Chan(String), +quit: Chan(Unit), +s: ag.Cs) -> IO(Unit):
  +next = ag.cc.done(s)
  do IO<Unit>:
    Unit <- Chan.close(String, texts)
    Unit <- Chan.close(Unit, quit)
    Unit <- Chan.close(E.ev.Say, says)
    m : Maybe<&1, ag.Cv> <- Chan.recv(ag.Cv, ch)
    +more : U32 <- ag.cc.drain(U32.to_nat(4294967295), 1n, m, ch, 0)
    Unit <- ag.unanswered(ag.cs.ps(s), env)
    Unit <- ag.cc.err(env, s)
    +n : U32 = (U32.from_nat(List.length(&2, String, ag.cs.sent(s))) + U32.from_nat(List.length(&2, String, ag.cs.held(s))) : U32)
    ag.end.cc(env, next, (n + (ag.cs.left(s) + more : U32) : U32))

# Starting ----------------------------------------------------------------------------

# the call's files made fresh: its system prompt, its events', its errors',
# its MCP files empty, its stdin a new FIFO
def ag.cc.files(+ctl: String, +system: String) -> IO(Unit):
  do IO<Unit>:
    a : Result<&1, &1, U32 & String, Unit> <- S.mu.save(ctl ++ ".cc.system", system, 0)
    b : Result<&1, &1, U32 & String, Unit> <- S.mu.save(ctl ++ ".cc.out", "", 0)
    c : Result<&1, &1, U32 & String, Unit> <- S.mu.save(ctl ++ ".cc.err", "", 0)
    d : Result<&1, &1, U32 & String, Unit> <- S.mu.save(ctl ++ ".cc.mcp.in", "", 0)
    e : Result<&1, &1, U32 & String, Unit> <- S.mu.save(ctl ++ ".cc.mcp.out", "", 0)
    g : Result<&1, &1, U32 & String, Unit> <- S.mu.unlink(ctl ++ ".cc.in")
    o : S.mu.Out <- S.mu.run("mkfifo", [ctl ++ ".cc.in"], "", 4096, 10000)
    return Unit{}

def ag.cc.name(+who: String) -> String:
  Bool.pick(String, String.is_empty(who), "main", who)

def ag.out.status(o: S.mu.Out) -> U32:
  match o:
    case S.mu.Out{st, out, err}:
      st

def ag.cc.let.go(r: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match r:
    case Done{file}:
      File.close(file)
    case Fail{e}:
      IO.pure(Unit, Unit{})

# a start that failed: our own last line, and Claude Code's stdin let go
def ag.cc.failed(bad: Bool, +ctl: String) -> IO(Unit):
  match bad:
    case True{}:
      do IO<Unit>:
        a : Result<&1, &1, U32 & String, Nat> <- S.mu.append(ctl ++ ".cc.out", C.cc.gone("127"), 0)
        r : Result<&1, &1, U32 & String, File> <- File.open(ctl ++ ".cc.in", "r")
        ag.cc.let.go(r)
    case False{}:
      IO.pure(Unit, Unit{})

# A call run on Claude Code to its end, told to the hub, as ag.api.run's
def ag.cc.run(+env: ag.Env, +ask: A.ap.Ask, +says: Chan(E.ev.Say)) -> IO(Unit):
  +cc = A.ap.cfg.cc(ag.cfg(env))
  +ctl = ag.ctl(env)
  +cwd = L.tl.env.cwd(ag.tools(env))
  +keep = C.cc.keeps(cc, True{})
  +p = A.ap.ask.pick(ask)
  do IO<Unit>:
    Unit <- ag.cc.files(ctl, A.ap.ask.system(ask))
    mk : Result<&1, &1, U32 & String, Unit> <- S.mu.mkdirs(cwd)
    +u : String <- C.cc.uuid()
    +sid : String = Bool.pick(String, keep, u, "")
    +debug : String <- Bool.pick(IO(String), keep, C.cc.debug.file(cc, ag.cc.name(ag.who(env)), u), IO.pure(String, ""))
    +tools : String = Bool.pick(String, U32.is_eq(ag.ask.searches(ask), 0), "", "WebSearch")
    +run : C.cc.Run = C.cc.Run{A.ap.pick.id(p), A.ap.pick.effort(p), ctl ++ ".cc.system", tools, C.cc.mcp(ctl), sid, debug, False{}}
    o : S.mu.Out <- C.cc.start(cc, ctl, cwd, C.cc.args(cc, run))
    Unit <- ag.cc.failed(Bool.not(U32.is_eq(ag.out.status(o), 0)), ctl)
    +ch : Chan(ag.Cv) <- Chan.new(ag.Cv, 4096)
    +texts : Chan(String) <- Chan.new(String, 256)
    +quit : Chan(Unit) <- Chan.new(Unit, 1)
    Unit <- IO.spawn(Unit, ag.tail.start(ch, quit, ctl))
    Unit <- IO.spawn(Unit, IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(ctl ++ ".cc.in", "w"), r => ag.hold.open(texts, r)))
    Unit <- IO.spawn(Unit, IO.bind(Maybe<&1, E.ev.Say>, Unit, Chan.recv(E.ev.Say, says), m => ag.fwd(U32.to_nat(4294967295), m, says, ch)))
    +first : String <- C.cc.uuid()
    r : Result<&1, &1, String, Unit> <- Chan.send(String, texts, C.cc.user(C.cc.parts(A.ap.ask.blocks(ask), False{}), first))
    +s0 : ag.Cs = ag.Cs{first, False{}, [], [], [], "", [], None{}, True{}, False{}, 0}
    m : Maybe<&1, ag.Cv> <- Chan.recv(ag.Cv, ch)
    +s : ag.Cs <- ag.cc.loop(U32.to_nat(4294967295), m, env, ask, ch, texts, s0)
    ag.cc.end(env, says, ch, texts, quit, s)

def ag.wire(on: Bool, +env: ag.Env, +ask: A.ap.Ask, +says: Chan(E.ev.Say)) -> IO(Unit):
  match on:
    case True{}:
      ag.cc.run(env, ask, says)
    case False{}:
      ag.api.run(env, ask, says)

# a call run to its end, told to the hub, on its wire
def ag.run(+env: ag.Env, +ask: A.ap.Ask, +says: Chan(E.ev.Say)) -> IO(Unit):
  ag.wire(C.cc.on(A.ap.cfg.cc(ag.cfg(env))), env, ask, says)
