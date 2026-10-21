
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./Clock.bend as C
import ./IMap.bend as I
import ./Tree.bend as R
import ./View.bend as V
import ./Store.bend as St
import ./Memory.bend as M
import ./Api.bend as A
import ./Compact.bend as P
import ./Ev.bend as E
import ./Tools.bend as L
import ./Agent.bend as G
import ./Prompts.bend as Pr
import ./Term.bend as Tm
import ./Export.bend as X

# Hub: the chat (UniiChat's Server.ts Chat, for one user in one process). One
# computation owns the memory and all of the chat's state; everything else
# tells it what happened on its inbox (Ev.bend), and it answers, logs, prints
# and starts what comes next, one event at a time.
#
# One turn at a time. A message is logged as it comes; the running call takes
# it between tool calls if it goes whole beside its view, else the next call
# does. A call waits till every message before it is summarized (settle); its
# blocks are the view to its first message, the devices, the agents at work,
# then "Turn: the user's new message:" and the messages. A turn that ends well
# with a goal set asks whether it is met; unmet, the user's nudge goes on. An
# agent's report is a message of its own that starts a turn. What runs (the
# turn, the agents) is kept in view.json, and a start goes on with it, told so.
#
# Every def is prefixed `hb.` (a program's defs share one namespace).

def hb.turn.name() -> String:
  "Unii's turn"

def hb.searches() -> U32:
  10

# Settings: the API's, the data dir, the work dir, this device's name, the
# user's shell, their instructions (MUGEN_RULES' text), the compactor,
# whether this is a terminal (stdin and stdout), the jobs at once, fsync.
type hb.Cfg is Data:
  hb.Cfg{api: A.ap.Cfg, dir: String, work: String, host: String, shell: String, rules: String, compactor: A.ap.Pick, tty: Bool, jobs: U32, sync: U32, home: String, acct: String}

# a message logged: its pages [id, end)
type hb.Msg is Data:
  hb.Msg{id: U32, end: U32}

# an agent: its name, its effort ("" the chat's), its call's channel if one
# runs, whether a stop cut it, its replies so far, the view its calls get, its
# log's length
type hb.Ag is Data:
  hb.Ag{name: String, effort: String, says: Maybe<&2, Chan(E.ev.Say)>, stop: Bool, replies: List<&2, String>, view: List<&2, V.vw.B>, n: U32}

# the turn: none; waiting on summaries; its call running; its goal check
type hb.T is Data:
  hb.Idle{}
  hb.Settle{}
  hb.Call{says: Chan(E.ev.Say)}
  hb.Check{goal: String}

# a spawn or tell waiting on summaries
type hb.W is Data:
  hb.W{who: String, name: String, input: J.Json, reply: Chan(E.ev.Out)}

# The state: settings, the memory, the inbox, a channel nobody reads (the
# compactions' busy notes go there), the chat's pick; the turn, the messages
# waiting for it, those its call took, why it was stopped ("" not); the
# agents; the requests waiting; stdin ended; leaving; the status last shown.
# What the terminal shows besides the chat: the mode (0 auto: Unii runs its
# tools as it needs them; 1 plan: it reads and proposes, changing nothing),
# and whether a prompt is due (shown once the hub is idle).
type hb.Ui is Data:
  hb.Ui{mode: U32, due: Bool}

type hb.S is Data:
  hb.S{cfg: hb.Cfg, mem: M.me.Mem, inbox: Chan(E.ev.Ev), junk: Chan(String), pick: A.ap.Pick, turn: hb.T, wait: List<&2, hb.Msg>, sent: List<&2, hb.Msg>, halt: String, agents: List<&2, hb.Ag>, reqs: List<&2, hb.W>, eof: Bool, quit: Bool, shown: String, ui: hb.Ui}

# Fields ---------------------------------------------------------------------

def hb.cfg(s: hb.S) -> hb.Cfg:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      c

def hb.mem(s: hb.S) -> M.me.Mem:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      m

def hb.inbox(s: hb.S) -> Chan(E.ev.Ev):
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      ib

def hb.junk(s: hb.S) -> Chan(String):
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      jk

def hb.pick(s: hb.S) -> A.ap.Pick:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      pk

def hb.turn(s: hb.S) -> hb.T:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      tu

def hb.wait(s: hb.S) -> List<&2, hb.Msg>:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      wa

def hb.halt(s: hb.S) -> String:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      ha

def hb.agents(s: hb.S) -> List<&2, hb.Ag>:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      ag

def hb.reqs(s: hb.S) -> List<&2, hb.W>:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      rq

def hb.with.mem(s: hb.S, m2: M.me.Mem) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m2, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}

def hb.with.pick(s: hb.S, pk2: A.ap.Pick) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk2, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}

def hb.with.turn(s: hb.S, tu2: hb.T) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu2, wa, se, ha, ag, rq, eo, qu, sh, ui}

def hb.with.wait(s: hb.S, wa2: List<&2, hb.Msg>) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu, wa2, se, ha, ag, rq, eo, qu, sh, ui}

def hb.with.sent(s: hb.S, se2: List<&2, hb.Msg>) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu, wa, se2, ha, ag, rq, eo, qu, sh, ui}

def hb.sent(s: hb.S) -> List<&2, hb.Msg>:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      se

def hb.with.halt(s: hb.S, ha2: String) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu, wa, se, ha2, ag, rq, eo, qu, sh, ui}

def hb.with.agents(s: hb.S, ag2: List<&2, hb.Ag>) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag2, rq, eo, qu, sh, ui}

def hb.with.reqs(s: hb.S, rq2: List<&2, hb.W>) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq2, eo, qu, sh, ui}

def hb.eof(s: hb.S) -> Bool:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      eo

def hb.with.eof(s: hb.S) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, True{}, qu, sh, ui}

def hb.quit(s: hb.S) -> Bool:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      qu

def hb.with.quit(s: hb.S) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, True{}, sh, ui}

def hb.shown(s: hb.S) -> String:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      sh

def hb.with.shown(s: hb.S, sh2: String) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh2, ui}

def hb.ui(s: hb.S) -> hb.Ui:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      ui

def hb.with.ui(s: hb.S, ui2: hb.Ui) -> hb.S:
  match s:
    case hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui}:
      hb.S{c, m, ib, jk, pk, tu, wa, se, ha, ag, rq, eo, qu, sh, ui2}

def hb.ui.mode(u: hb.Ui) -> U32:
  match u:
    case hb.Ui{m, d}:
      m

def hb.ui.due(u: hb.Ui) -> Bool:
  match u:
    case hb.Ui{m, d}:
      d

def hb.with.mode(+s: hb.S, +m: U32) -> hb.S:
  hb.with.ui(s, hb.Ui{m, hb.ui.due(hb.ui(s))})

def hb.with.due(+s: hb.S, +d: Bool) -> hb.S:
  hb.with.ui(s, hb.Ui{hb.ui.mode(hb.ui(s)), d})

# plan mode: Unii reads and proposes, changing nothing
def hb.plan(+s: hb.S) -> Bool:
  U32.is_eq(hb.ui.mode(hb.ui(s)), 1)

def hb.cfg.api(c: hb.Cfg) -> A.ap.Cfg:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      a

def hb.cfg.dir(c: hb.Cfg) -> String:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      d

def hb.cfg.work(c: hb.Cfg) -> String:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      w

def hb.cfg.host(c: hb.Cfg) -> String:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      h

def hb.cfg.shell(c: hb.Cfg) -> String:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      sh

def hb.cfg.rules(c: hb.Cfg) -> String:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      r

def hb.cfg.compactor(c: hb.Cfg) -> A.ap.Pick:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      cp

def hb.cfg.tty(c: hb.Cfg) -> Bool:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      t

def hb.cfg.home(c: hb.Cfg) -> String:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      ho

def hb.cfg.acct(c: hb.Cfg) -> String:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      ac

def hb.dir(+s: hb.S) -> String:
  hb.cfg.dir(hb.cfg(s))

def hb.tty(+s: hb.S) -> Bool:
  hb.cfg.tty(hb.cfg(s))

# run/<who>: a call's control files (Tools.bend tl.Env)
def hb.ctl(+s: hb.S, +who: String) -> String:
  hb.dir(s) ++ "/run/" ++ Bool.pick(String, String.is_empty(who), "main", who)

# the system prompt with the user's instructions (Tools.system)
def hb.system(+s: hb.S, +head: String) -> String:
  head ++ "\n\n" ++ hb.cfg.rules(hb.cfg(s))

def hb.sub() -> String:
  Pr.pr.sub.head() ++ "\n\n" ++ Pr.pr.view.doc() ++ "\n\n" ++ Pr.pr.devices()

# Time ---------------------------------------------------------------------------

type hb.When is Data:
  hb.When{now: Nat, day: U32}

def hb.when() -> IO(hb.When):
  do IO<hb.When>:
    +now : Nat <- S.mu.wall()
    tz : U32 <- S.mu.tzoff(now)
    return hb.When{now, C.ck.local_day(now, tz)}

# Printing -------------------------------------------------------------------------

def hb.print(+s: hb.S, +who: String, +kind: String, +text: String) -> IO(Unit):
  Bool.pick(IO(Unit), Bool.and(hb.tty(s), Bool.and(String.eq(kind, "user"), String.is_empty(who))), IO.pure(Unit, Unit{}),
    Bool.pick(IO(Unit), String.eq(kind, "usage"), Bool.pick(IO(Unit), hb.tty(s), IO.print(Tm.tm.status(True{}, Tm.tm.who(who) ++ text)), IO.pure(Unit, Unit{})),
      IO.print(Tm.tm.render(hb.tty(s), who, kind, text))))

# Compactions -----------------------------------------------------------------------

# a job run: its line told to the hub
def hb.compact(+c: hb.Cfg, +inbox: Chan(E.ev.Ev), +junk: Chan(String), +system: String, j: M.me.Job) -> IO(Unit):
  match j:
    case M.me.Job{+l, +i, b, t}:
      do IO<Unit>:
        line : Maybe<&2, String> <- P.cp.build(hb.cfg.api(c), hb.cfg.compactor(c), system, junk, M.me.Job{l, i, b, t})
        E.ev.send(inbox, E.ev.Built{l, i, line})

def hb.jobs(js: List<&2, M.me.Job>, +s: hb.S) -> IO(Unit):
  match js:
    case []:
      IO.pure(Unit, Unit{})
    case j <> t:
      do IO<Unit>:
        Unit <- IO.spawn(Unit, hb.compact(hb.cfg(s), hb.inbox(s), hb.junk(s), hb.system(s, Pr.pr.master()), j))
        hb.jobs(t, s)

def hb.mem.jobs(+s: hb.S, r: M.me.Mem & List<&2, M.me.Job>) -> IO(hb.S):
  match r:
    case (m, js):
      IO.bind(Unit, hb.S, hb.jobs(js, s), u => IO.pure(hb.S, hb.with.mem(s, m)))

def hb.when.day(w: hb.When) -> U32:
  match w:
    case hb.When{n, d}:
      d

# a compaction's line in, the jobs it starts started
def hb.built(+s: hb.S, +l: U32, +i: U32, line: Maybe<&2, String>) -> IO(hb.S):
  match line:
    case Some{x}:
      do IO<hb.S>:
        w : hb.When <- hb.when()
        r : M.me.Mem & List<&2, M.me.Job> <- M.me.done.job(hb.mem(s), hb.when.day(w), l, i, x)
        hb.mem.jobs(s, r)
    case None{}:
      do IO<hb.S>:
        w : hb.When <- hb.when()
        r : M.me.Mem & List<&2, M.me.Job> <- M.me.pump(M.me.unbusy(hb.mem(s), R.tr.slot(l, i)), hb.when.day(w))
        r2 : M.me.Mem & List<&2, M.me.Job> <- M.me.built.fin(r)
        hb.mem.jobs(s, r2)

def hb.when.now(w: hb.When) -> Nat:
  match w:
    case hb.When{n, d}:
      n

# Logging --------------------------------------------------------------------------

# a message logged, and where it went
type hb.P is Data:
  hb.P{s: hb.S, msg: hb.Msg}

def hb.p.s(p: hb.P) -> hb.S:
  match p:
    case hb.P{s, m}:
      s

def hb.p.msg(p: hb.P) -> hb.Msg:
  match p:
    case hb.P{s, m}:
      m

def hb.first.i(rs: List<&2, St.st.Root>, +d: U32) -> U32:
  match rs:
    case []:
      d
    case r <> t:
      St.st.root.i(r)

def hb.pushed(+s: hb.S, r: M.me.Mem & (List<&2, St.st.Root> & List<&2, M.me.Job>)) -> IO(hb.P):
  match r:
    case (+m, (rs, js)):
      do IO<hb.P>:
        Unit <- hb.jobs(js, s)
        return hb.P{hb.with.mem(s, m), hb.Msg{hb.first.i(rs, M.me.count(m)), M.me.count(m)}}

# to the chat (in pages), printed
def hb.push(+s: hb.S, +kind: String, +text: String) -> IO(hb.P):
  do IO<hb.P>:
    Unit <- hb.print(s, "", kind, text)
    +w : hb.When <- hb.when()
    r : M.me.Mem & (List<&2, St.st.Root> & List<&2, M.me.Job>) <- M.me.push(hb.mem(s), hb.when.now(w), hb.when.day(w), [M.me.msg(kind, text)])
    hb.pushed(s, r)

# a note in the chat, why work ended as it did
def hb.note(+s: hb.S, +text: String) -> IO(hb.S):
  IO.bind(hb.P, hb.S, hb.push(s, "note", text), p => IO.pure(hb.S, hb.p.s(p)))

# Agents' logs -------------------------------------------------------------------------

def hb.ag.name(a: hb.Ag) -> String:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      n

def hb.ag.n(a: hb.Ag) -> U32:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      k

def hb.ag.find(as: List<&2, hb.Ag>, +name: String) -> Maybe<&2, hb.Ag>:
  match as:
    case []:
      None{}
    case +a <> rest:
      Bool.pick(Maybe<&2, hb.Ag>, String.eq(hb.ag.name(a), name), Some{a}, hb.ag.find(rest, name))

def hb.ag.set(as: List<&2, hb.Ag>, +a: hb.Ag) -> List<&2, hb.Ag>:
  match as:
    case []:
      [a]
    case +b <> +rest:
      Bool.pick(List<&2, hb.Ag>, String.eq(hb.ag.name(b), hb.ag.name(a)), a <> rest, b <> hb.ag.set(rest, a))

def hb.ag.count(a: hb.Ag, +k: U32) -> hb.Ag:
  match a:
    case hb.Ag{n, e, sa, st, r, v, c}:
      hb.Ag{n, e, sa, st, r, v, k}

# an entry in an agent's log, printed
def hb.alog(+s: hb.S, +a: hb.Ag, +kind: String, +text: String) -> IO(hb.S):
  +name = hb.ag.name(a)
  +k = hb.ag.n(a)
  do IO<hb.S>:
    Unit <- hb.print(s, name, kind, text)
    w : hb.When <- hb.when()
    Unit <- St.st.agent.append(hb.dir(s), name, M.me.agent.root(k, kind, text, hb.when.now(w)))
    return hb.with.agents(s, hb.ag.set(hb.agents(s), hb.ag.count(a, (k + 1 : U32))))

def hb.alog.by(+s: hb.S, m: Maybe<&2, hb.Ag>, +kind: String, +text: String) -> IO(hb.S):
  match m:
    case Some{a}:
      hb.alog(s, a, kind, text)
    case None{}:
      IO.pure(hb.S, s)

# Turns ------------------------------------------------------------------------------

def hb.busy(+t: hb.T) -> Bool:
  match t:
    case hb.Idle{}:
      False{}
    case _:
      True{}

def hb.ag.running(a: hb.Ag) -> Bool:
  match a:
    case hb.Ag{n, e, Some{c}, st, r, v, k}:
      True{}
    case _:
      False{}

def hb.working(as: List<&2, hb.Ag>) -> List<&2, String>:
  match as:
    case []:
      []
    case +a <> rest:
      List.append(&2, String, Bool.pick(List<&2, String>, hb.ag.running(a), [hb.ag.name(a)], []), hb.working(rest))

# what runs: Unii's turn, the agents at work (Chat.running)
def hb.running(+s: hb.S) -> List<&2, String>:
  List.append(&2, String, Bool.pick(List<&2, String>, hb.busy(hb.turn(s)), [hb.turn.name()], []), hb.working(hb.agents(s)))

# the agents at work now, at the start of each call's message (Tools.at_work)
def hb.at.work(+s: hb.S) -> String:
  +names = hb.working(hb.agents(s))
  "Agents at work now: " ++ Bool.pick(String, List.is_empty(&2, String, names), "none.", T.tx.join(names, ", ") ++ ".") ++ "\n\n"

def hb.devices(+s: hb.S) -> String:
  L.tl.devices(hb.cfg.host(hb.cfg(s)), hb.cfg.work(hb.cfg(s)))

def hb.tools.env(+s: hb.S, +who: String) -> L.tl.Env:
  +c = hb.cfg(s)
  L.tl.Env{hb.cfg.host(c), hb.cfg.work(c), Bool.pick(String, String.is_empty(who), "main", who), hb.cfg.shell(c), hb.ctl(s, who), hb.dir(s) ++ "/run/groups"}

def hb.env(+s: hb.S, +who: String) -> G.ag.Env:
  G.ag.Env{hb.cfg.api(hb.cfg(s)), hb.inbox(s), who, String.is_empty(who), hb.tools.env(s, who)}

# a call's control files made fresh: no stop asked, no pid
def hb.fresh(+ctl: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Unit> <- S.mu.unlink(ctl ++ ".stop")
    r2 : Result<&1, &1, U32 & String, Unit> <- S.mu.unlink(ctl ++ ".pid")
    r3 : Result<&1, &1, U32 & String, Unit> <- S.mu.unlink(ctl ++ ".cc.pid")
    return Unit{}

# the view to message `end`, in blocks (Memory.view)
def hb.view(+s: hb.S, +end: U32) -> List<&2, V.vw.B>:
  V.vw.blocks(M.me.nodes(hb.mem(s)), V.vw.parts(M.me.view(hb.mem(s))), end)

def hb.msg.end(m: hb.Msg) -> U32:
  match m:
    case hb.Msg{i, e}:
      e

def hb.msg.id(m: hb.Msg) -> U32:
  match m:
    case hb.Msg{i, e}:
      i

def hb.say.if(b: Bool, +s: hb.S, +a: U32, +e: U32) -> IO(String):
  match b:
    case True{}:
      M.me.say(hb.mem(s), a, e)
    case False{}:
      IO.pure(String, "")

# the texts of the messages from `from` on (Chat.call's says)
def hb.says(ms: List<&2, hb.Msg>, +s: hb.S, +from: U32) -> IO(List<&2, String>):
  match ms:
    case []:
      IO.pure(List<&2, String>, [])
    case hb.Msg{+i, +e} <> rest:
      +keep = U32.is_gt(e, from)
      do IO<List<&2, String>>:
        +t : String <- hb.say.if(keep, s, U32.max(i, from), e)
        ts : List<&2, String> <- hb.says(rest, s, from)
        return List.append(&2, String, Bool.pick(List<&2, String>, keep, [t], []), ts)

# what a turn in plan mode is told, after the agents at work
def hb.plan.note() -> String:
  "Plan mode: the user wants a plan, not changes. Read what you need (zoom, read, date, web search), then answer with a plan. shell, write, edit, spawn and tell are off until the user switches back to auto mode.\n\n"

def hb.turn.ask(+s: hb.S, +from: U32, +text: String) -> A.ap.Ask:
  +plan = hb.plan(s)
  A.ap.Ask{hb.pick(s), hb.system(s, Pr.pr.master()),
    List.concat(&2, V.vw.B, [hb.view(s, from), [V.vw.B{hb.devices(s), False{}}, V.vw.B{hb.at.work(s), False{}}],
      Bool.pick(List<&2, V.vw.B>, plan, [V.vw.B{hb.plan.note(), False{}}], []), [V.vw.B{Pr.pr.head() ++ text, True{}}]]),
    Bool.pick(List<&2, J.Json>, plan, L.tl.plan(), L.tl.main()), hb.searches(), False{}}

# the turn's call started on the messages waiting, from message `from`
def hb.call(+s: hb.S, +from: U32) -> IO(hb.S):
  +msgs = hb.wait(s)
  do IO<hb.S>:
    texts : List<&2, String> <- hb.says(msgs, s, from)
    +says : Chan(E.ev.Say) <- Chan.new(E.ev.Say, 256)
    Unit <- hb.fresh(hb.ctl(s, ""))
    Unit <- IO.spawn(Unit, G.ag.run(hb.env(s, ""), hb.turn.ask(s, from, T.tx.join(texts, "\n\n")), says))
    return hb.with.shown(hb.with.halt(hb.with.sent(hb.with.wait(hb.with.turn(s, hb.Call{says}), []), msgs), ""), "")

def hb.wait.first(ws: List<&2, hb.Msg>, +d: U32) -> U32:
  match ws:
    case []:
      d
    case hb.Msg{i, e} <> t:
      i

def hb.first(+s: hb.S) -> U32:
  M.me.first(M.me.ready.of(hb.mem(s)), M.me.count(hb.mem(s)), 0n)

def hb.summing(+s: hb.S, +from: U32) -> IO(hb.S):
  +text = "summarizing " ++ U32.show((from - hb.first(s) : U32)) ++ " messages before the turn"
  Bool.pick(IO(hb.S), Bool.or(Bool.not(hb.tty(s)), String.eq(hb.shown(s), text)), IO.pure(hb.S, s),
    IO.bind(Unit, hb.S, IO.print(Tm.tm.status(True{}, text)), u => IO.pure(hb.S, hb.with.shown(s, text))))

# a turn waiting on summaries: its call once every message before its first
# whole one is built (Chat.call's settle)
def hb.settle(+s: hb.S) -> IO(hb.S):
  do IO<hb.S>:
    +from : U32 <- M.me.whole(hb.mem(s), hb.wait.first(hb.wait(s), M.me.count(hb.mem(s))))
    Bool.pick(IO(hb.S), U32.is_ge(hb.first(s), from), hb.call(s, from), hb.summing(s, from))

def hb.queue(+s: hb.S, +msg: hb.Msg) -> hb.S:
  hb.with.wait(s, List.append(&2, hb.Msg, hb.wait(s), [msg]))

def hb.sent.ok(+s: hb.S, +msg: hb.Msg, r: Result<&1, &1, E.ev.Say, Unit>) -> hb.S:
  match r:
    case Done{u}:
      hb.with.sent(s, List.append(&2, hb.Msg, hb.sent(s), [msg]))
    case Fail{x}:
      hb.queue(s, msg)

def hb.send.call(+s: hb.S, +says: Chan(E.ev.Say), +msg: hb.Msg) -> IO(hb.S):
  do IO<hb.S>:
    t : String <- M.me.say(hb.mem(s), hb.msg.id(msg), hb.msg.end(msg))
    r : Result<&1, &1, E.ev.Say, Unit> <- Chan.send(E.ev.Say, says, E.ev.Text{t})
    return hb.sent.ok(s, msg, r)

def hb.take.on(t: hb.T, +s: hb.S, +msg: hb.Msg) -> IO(hb.S):
  match t:
    case hb.Call{+says}:
      do IO<hb.S>:
        +w : U32 <- M.me.whole(hb.mem(s), hb.msg.id(msg))
        Bool.pick(IO(hb.S), U32.is_eq(w, hb.msg.id(msg)), hb.send.call(s, says, msg), IO.pure(hb.S, hb.queue(s, msg)))
    case _:
      IO.pure(hb.S, hb.queue(s, msg))

# a message logged, to the running call if it goes whole beside its view,
# else waiting for the next (Chat.take)
def hb.take(+s: hb.S, +msg: hb.Msg) -> IO(hb.S):
  hb.take.on(hb.turn(s), s, msg)

# the turn ends: its stop's note, if any; nothing waits
def hb.rest(+s: hb.S) -> IO(hb.S):
  +s2 = hb.with.wait(hb.with.sent(hb.with.turn(s, hb.Idle{}), []), [])
  Bool.pick(IO(hb.S), String.is_empty(hb.halt(s)), IO.pure(hb.S, s2), IO.bind(hb.S, hb.S, hb.note(s2, hb.halt(s)), s3 => IO.pure(hb.S, hb.with.halt(s3, ""))))

# after a call or a check: on while messages wait (and no stop came)
def hb.go.on(+s: hb.S) -> IO(hb.S):
  Bool.pick(IO(hb.S), Bool.and(String.is_empty(hb.halt(s)), Bool.not(List.is_empty(&2, hb.Msg, hb.wait(s)))), IO.pure(hb.S, hb.with.turn(s, hb.Settle{})), hb.rest(s))

def hb.chop(+text: String) -> String:
  Bool.pick(String, String.ends_with(text, "."), String.reverse(String.drop(String.reverse(text), 1n)), text)

def hb.goal(+s: hb.S) -> Maybe<&2, String>:
  M.me.kept.goal(M.me.kept(hb.mem(s)))

def hb.line.of(+i: U32, m: Maybe<&2, St.st.Root>) -> String:
  match m:
    case Some{+r}:
      R.tr.line(R.tr.P{0, i}, St.st.root.kind(r) ++ ": " ++ St.st.root.text(r)) ++ "\n"
    case None{}:
      ""

# the user's goal, asked of the chat's model without tools, on the chat as it
# is now (Chat.check): the view to the messages whole, those as lines, the goal
def hb.lines(n: Nat, +s: hb.S, +i: U32, acc: List<&2, String>) -> IO(List<&2, String>):
  match n:
    case 0n:
      IO.pure(List<&2, String>, List.reverse(&2, String, acc))
    case 1n+f:
      do IO<List<&2, String>>:
        m : Maybe<&2, St.st.Root> <- St.st.message(hb.dir(s), i)
        hb.lines(f, s, (i + 1 : U32), hb.line.of(i, m) <> acc)

def hb.goal.ev(+goal: String, e: P.cp.End) -> E.ev.Ev:
  match e:
    case P.cp.End{ok, text, stop}:
      E.ev.Goal{goal, ok, text}

def hb.goal.run(+c: A.ap.Cfg, +inbox: Chan(E.ev.Ev), +junk: Chan(String), +ctl: String, +a: A.ap.Ask, +goal: String) -> IO(Unit):
  do IO<Unit>:
    s : A.ap.Step <- A.ap.step(c, a, [A.ap.User{A.ap.ask.blocks(a)}], junk, ctl)
    E.ev.send(inbox, hb.goal.ev(goal, P.cp.end.of(s)))

def hb.check(+s: hb.S, +goal: String) -> IO(hb.S):
  do IO<hb.S>:
    +at : U32 <- M.me.whole(hb.mem(s), 0)
    tail : List<&2, String> <- hb.lines(U32.to_nat((M.me.count(hb.mem(s)) - at : U32)), s, at, [])
    +a : A.ap.Ask = A.ap.Ask{hb.pick(s), Pr.pr.goal(), List.append(&2, V.vw.B, hb.view(s, at), [V.vw.B{T.tx.concat(tail) ++ Pr.pr.goal.ask() ++ goal, True{}}]), [], 0, False{}}
    Unit <- hb.fresh(hb.ctl(s, ""))
    Unit <- IO.spawn(Unit, hb.goal.run(hb.cfg.api(hb.cfg(s)), hb.inbox(s), hb.junk(s), hb.ctl(s, ""), a, goal))
    return hb.with.turn(s, hb.Check{goal})

def hb.requeue(+sent: List<&2, hb.Msg>, +left: U32, +wait: List<&2, hb.Msg>) -> List<&2, hb.Msg>:
  List.append(&2, hb.Msg, List.drop(&2, hb.Msg, sent, Nat.sub(List.length(&2, hb.Msg, sent), U32.to_nat(left))), wait)

def hb.ended.goal(+s: hb.S, check: Bool, g: Maybe<&2, String>) -> IO(hb.S):
  match check g:
    case True{} Some{+goal}:
      hb.check(s, goal)
    case _ _:
      hb.go.on(s)

# the turn's call ended (Chat.ended): what it never took waits again; a
# failure noted; met its end well with a goal set and nothing waiting, the
# goal is checked
def hb.ended(+s: hb.S, +ok: Bool, +text: String, +left: U32) -> IO(hb.S):
  +s1 = hb.with.due(hb.with.sent(hb.with.wait(s, hb.requeue(hb.sent(s), left, hb.wait(s))), []), True{})
  +on = String.is_empty(hb.halt(s))
  do IO<hb.S>:
    +s2 : hb.S <- Bool.pick(IO(hb.S), Bool.and(Bool.not(ok), on), hb.note(s1, "No reply: " ++ hb.chop(text) ++ ". Send a message to try again."), IO.pure(hb.S, s1))
    hb.ended.goal(s2, Bool.and(ok, Bool.and(on, List.is_empty(&2, hb.Msg, hb.wait(s2)))), hb.goal(s2))

def hb.kept.goal(k: M.me.Kept, g: Maybe<&2, String>) -> M.me.Kept:
  match k:
    case M.me.Kept{p, o, w}:
      M.me.Kept{p, g, w}

def hb.goal.is(m: Maybe<&2, String>, +goal: String) -> Bool:
  match m:
    case Some{g}:
      String.eq(g, goal)
    case None{}:
      False{}

def hb.checked.go(k: Nat, +s: hb.S, +text: String) -> IO(hb.S):
  match k:
    case 0n:
      IO.pure(hb.S, s)
    case 1n:
      hb.note(s, "No goal check: " ++ hb.chop(text) ++ ". The goal stays; /halt drops it.")
    case 2n:
      do IO<hb.S>:
        +m : M.me.Mem = M.me.with.kept(hb.mem(s), hb.kept.goal(M.me.kept(hb.mem(s)), None{}))
        Unit <- M.me.save(m)
        hb.note(hb.with.mem(s, m), "Goal met.")
    case _:
      do IO<hb.S>:
        +p : hb.P <- hb.push(s, "user", Pr.pr.goal.no())
        return hb.queue(hb.p.s(p), hb.p.msg(p))

def hb.word(+x: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(x, 48), U32.is_le(x, 57)), Bool.and(U32.is_ge(x, 65), U32.is_le(x, 90))), Bool.or(Bool.and(U32.is_ge(x, 97), U32.is_le(x, 122)), U32.is_eq(x, 95)))

def hb.lower(+x: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ge(x, 65), U32.is_le(x, 90)), (x + 32 : U32), x)

# "yes" then no word character: k the letters left of it, w the text of them
def hb.yes.at(w: String, s: String) -> Bool:
  match w s:
    case SNil{} SNil{}:
      True{}
    case SNil{} SCon{Chr{+c}, t}:
      Bool.not(hb.word(c))
    case SCon{Chr{+y}, wt} SCon{Chr{+c}, t}:
      Bool.and(U32.is_eq(hb.lower(c), y), hb.yes.at(wt, t))
    case _ _:
      False{}

# /^\W*yes\b/i
def hb.yes(s: String) -> Bool:
  match s:
    case SCon{Chr{+c}, +t}:
      Bool.pick(Bool, hb.word(c), hb.yes.at("yes", SCon{Chr{c}, t}), hb.yes(t))
    case SNil{}:
      False{}

# a goal check's answer (Chat.checked): no check (a failure); met (yes): the
# goal ends; else the user's nudge goes on as their message
def hb.checked(+s: hb.S, +goal: String, +ok: Bool, +text: String) -> IO(hb.S):
  +on = Bool.and(String.is_empty(hb.halt(s)), Bool.and(List.is_empty(&2, hb.Msg, hb.wait(s)), hb.goal.is(hb.goal(s), goal)))
  do IO<hb.S>:
    +s2 : hb.S <- hb.checked.go(Bool.pick(Nat, Bool.not(on), 0n, Bool.pick(Nat, Bool.not(ok), 1n, Bool.pick(Nat, hb.yes(text), 2n, 3n))), s, text)
    hb.go.on(s2)

def hb.kept.work(k: M.me.Kept, w2: List<&2, String>) -> M.me.Kept:
  match k:
    case M.me.Kept{p, g, w}:
      M.me.Kept{p, g, w2}

def hb.kept.pick(k: M.me.Kept, p2: J.Json) -> M.me.Kept:
  match k:
    case M.me.Kept{p, g, w}:
      M.me.Kept{p2, g, w}

# Agents -----------------------------------------------------------------------------

def hb.efforts() -> List<&2, String>:
  ["low", "medium", "high", "xhigh", "max"]

def hb.has(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case []:
      False{}
    case +y <> t:
      Bool.or(String.eq(x, y), hb.has(t, x))

# a name is letters and hyphens, never a path
def hb.name.ok(s: String, +any: Bool) -> Bool:
  match s:
    case SNil{}:
      any
    case SCon{Chr{+c}, t}:
      Bool.and(Bool.or(Bool.or(Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)), Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122))), U32.is_eq(c, 45)), hb.name.ok(t, True{}))

def hb.cap(+w: String) -> String:
  match w:
    case SCon{Chr{+c}, t}:
      SCon{Chr{Bool.pick(U32, Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), (c - 32 : U32), c)}, t}
    case _:
      w

def hb.pick.word(+xs: List<&2, String>, +r: U32) -> String:
  hb.cap(Maybe.default(&2, String, List.get(&2, String, xs, U32.to_nat(U32.mod(r, U32.from_nat(List.length(&2, String, xs))))), "Agent"))

def hb.rand(r: Result<&1, &1, U32 & String, U32>) -> U32:
  match r:
    case Done{x}:
      x
    case Fail{e}:
      7

# a fresh name (Names.ts): an adjective and a noun, one no log has (taken:
# the last drawn was; this loop's verdict as a parameter)
def hb.name.new(n: Nat, taken: Bool, +s: hb.S, +name: String) -> IO(String):
  match n taken:
    case 1n+f True{}:
      do IO<String>:
        a : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
        b : Result<&1, &1, U32 & String, U32> <- IO.random_u32()
        +name2 : String = hb.pick.word(Pr.pr.adjs(), hb.rand(a)) ++ hb.pick.word(Pr.pr.nouns(), hb.rand(b))
        log : Maybe<&2, List<&2, St.st.Root>> <- St.st.agent(hb.dir(s), name2)
        hb.name.new(f, Bool.or(Maybe.is_some(&2, List<&2, St.st.Root>, log), Maybe.is_some(&2, hb.Ag, hb.ag.find(hb.agents(s), name2))), s, name2)
    case _ _:
      IO.pure(String, name)

def hb.ag.view(a: hb.Ag) -> List<&2, V.vw.B>:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      v

def hb.ag.effort(a: hb.Ag) -> String:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      e

def hb.ag.stop(a: hb.Ag) -> Bool:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      st

def hb.ag.replies(a: hb.Ag) -> List<&2, String>:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      r

def hb.ag.with.says(a: hb.Ag, sa2: Maybe<&2, Chan(E.ev.Say)>) -> hb.Ag:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      hb.Ag{n, e, sa2, st, r, v, k}

def hb.pick.effort(p: A.ap.Pick, +e: String) -> A.ap.Pick:
  match p:
    case A.ap.Pick{m, +e0, sp}:
      A.ap.Pick{m, Bool.pick(String, String.is_empty(e), e0, e), sp}

# an agent's call: the view it was given, the devices, its whole log (Tools.ask)
def hb.agent.call(+s: hb.S, +a: hb.Ag) -> IO(hb.S):
  +name = hb.ag.name(a)
  do IO<hb.S>:
    log : String <- M.me.agent.show(hb.dir(s), name)
    +says : Chan(E.ev.Say) <- Chan.new(E.ev.Say, 256)
    +ask : A.ap.Ask = A.ap.Ask{hb.pick.effort(hb.pick(s), hb.ag.effort(a)), hb.system(s, hb.sub()),
      List.append(&2, V.vw.B, hb.ag.view(a), [V.vw.B{hb.devices(s), False{}}, V.vw.B{log, True{}}]), L.tl.sub(name), hb.searches(), False{}}
    Unit <- hb.fresh(hb.ctl(s, name))
    Unit <- S.mu.must(Unit, "mkdir work", S.mu.mkdirs(hb.cfg.work(hb.cfg(s)) ++ "/" ++ name))
    Unit <- IO.spawn(Unit, G.ag.run(hb.env(s, name), ask, says))
    return hb.with.agents(s, hb.ag.set(hb.agents(s), hb.ag.with.says(a, Some{says})))

# an agent started on a task, with the view as it is now (Tools.start)
def hb.agent.start(+s: hb.S, +task: String, +effort: String) -> IO(hb.P):
  do IO<hb.P>:
    +name : String <- hb.name.new(16n, True{}, s, "")
    +a : hb.Ag = hb.Ag{name, effort, None{}, False{}, [], hb.view(s, M.me.count(hb.mem(s))), 0}
    +s1 : hb.S <- hb.alog(hb.with.agents(s, hb.ag.set(hb.agents(s), a)), a, "note", "subagent" ++ Bool.pick(String, String.is_empty(effort), "", " at effort " ++ effort))
    +s2 : hb.S <- hb.alog.by(s1, hb.ag.find(hb.agents(s1), name), "user", task)
    +s3 : hb.S <- hb.agent.call(s2, Maybe.default(&2, hb.Ag, hb.ag.find(hb.agents(s2), name), a))
    return hb.P{s3, hb.Msg{0, 0}}

def hb.last.name(as: List<&2, hb.Ag>, +d: String) -> String:
  match as:
    case []:
      d
    case +a <> t:
      hb.last.name(t, hb.ag.name(a))

def hb.spawn.go(ts: List<&2, J.Json>, +s: hb.S, +effort: String, names: List<&2, String>) -> IO(hb.Sn):
  match ts:
    case []:
      IO.pure(hb.Sn, hb.Sn{s, List.reverse(&2, String, names)})
    case J.JStr{+task} <> rest:
      do IO<hb.Sn>:
        p : hb.P <- hb.agent.start(s, task, effort)
        +s2 : hb.S = hb.p.s(p)
        hb.spawn.go(rest, s2, effort, hb.last.name(hb.agents(s2), "") <> names)
    case x <> rest:
      hb.spawn.go(rest, s, effort, names)

# the state and some names
type hb.Sn is Data:
  hb.Sn{s: hb.S, names: List<&2, String>}

def hb.sn.s(x: hb.Sn) -> hb.S:
  match x:
    case hb.Sn{s, n}:
      s

def hb.sn.names(x: hb.Sn) -> List<&2, String>:
  match x:
    case hb.Sn{s, n}:
      n

# An agent known to the chat, or one of an earlier run taken back from its
# log, idle (Tools.agent)
def hb.agent.of(+name: String, log: Maybe<&2, List<&2, St.st.Root>>) -> Maybe<&2, hb.Ag>:
  match log:
    case Some{St.st.Root{i, +kind, +text, sz, d, l, m} <> +rest}:
      +sub = Bool.and(String.eq(kind, "note"), Bool.or(String.eq(text, "subagent"), String.starts_with(text, "subagent at effort ")))
      Bool.pick(Maybe<&2, hb.Ag>, sub, Some{hb.Ag{name, String.drop(text, 19n), None{}, False{}, [], [], U32.from_nat(1n+List.length(&2, St.st.Root, rest))}}, None{})
    case _:
      None{}

def hb.agent.load(+s: hb.S, +name: String) -> IO(Maybe<&2, hb.Ag>):
  Bool.pick(IO(Maybe<&2, hb.Ag>), Bool.not(hb.name.ok(name, False{})), IO.pure(Maybe<&2, hb.Ag>, None{}),
    Bool.pick(IO(Maybe<&2, hb.Ag>), Maybe.is_some(&2, hb.Ag, hb.ag.find(hb.agents(s), name)), IO.pure(Maybe<&2, hb.Ag>, hb.ag.find(hb.agents(s), name)),
      IO.bind(Maybe<&2, List<&2, St.st.Root>>, Maybe<&2, hb.Ag>, St.st.agent(hb.dir(s), name), log => IO.pure(Maybe<&2, hb.Ag>, hb.agent.of(name, log)))))

def hb.ag.says(a: hb.Ag) -> Maybe<&2, Chan(E.ev.Say)>:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      sa

def hb.ag.fresh(a: hb.Ag, v2: List<&2, V.vw.B>) -> hb.Ag:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      hb.Ag{n, e, sa, False{}, [], v2, k}

def hb.tell.go(+s: hb.S, +a: hb.Ag, says: Maybe<&2, Chan(E.ev.Say)>, +message: String) -> IO(hb.Sn):
  match says:
    case Some{c}:
      do IO<hb.Sn>:
        r : Result<&1, &1, E.ev.Say, Unit> <- Chan.send(E.ev.Say, c, E.ev.Text{message})
        return hb.Sn{s, ["Sent. " ++ hb.ag.name(a) ++ " reads it between its tool calls, and its report answers it."]}
    case None{}:
      do IO<hb.Sn>:
        +s2 : hb.S <- hb.agent.call(s, hb.ag.fresh(a, hb.view(s, M.me.count(hb.mem(s)))))
        return hb.Sn{s2, ["Sent. " ++ hb.ag.name(a) ++ "'s reply will reach you as a message."]}

# a message to an agent (Tools.tell): at work, it reads it between its tool
# calls; idle, it goes on from its chat
def hb.tell.on(+s: hb.S, m: Maybe<&2, hb.Ag>, +name: String, +message: String) -> IO(hb.Sn):
  match m:
    case None{}:
      IO.pure(hb.Sn, hb.Sn{s, ["No agent " ++ name ++ " to tell."]})
    case Some{+a}:
      do IO<hb.Sn>:
        +s1 : hb.S <- hb.alog(hb.with.agents(s, hb.ag.set(hb.agents(s), a)), a, "user", message)
        hb.tell.go(s1, Maybe.default(&2, hb.Ag, hb.ag.find(hb.agents(s1), name), a), hb.ag.says(a), message)

def hb.report.text(+name: String, +text: String) -> String:
  "[" ++ name ++ "]\n" ++ text ++ "\n\nFull chat: zoom(\"" ++ name ++ "\")"

def hb.ag.end(a: hb.Ag, +reply: String) -> hb.Ag:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      hb.Ag{n, e, None{}, st, List.append(&2, String, r, [reply]), v, k}

def hb.ag.done(a: hb.Ag) -> hb.Ag:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      hb.Ag{n, e, sa, st, [], v, k}

def hb.reported(stop: Bool, +p: hb.P) -> IO(hb.S):
  match stop:
    case True{}:
      IO.pure(hb.S, hb.p.s(p))
    case False{}:
      hb.take(hb.p.s(p), hb.p.msg(p))

def hb.agent.next(more: Bool, +s1: hb.S, +a: hb.Ag) -> IO(hb.S):
  match more:
    case True{}:
      hb.agent.call(s1, a)
    case False{}:
      do IO<hb.S>:
        p : hb.P <- hb.push(hb.with.agents(s1, hb.ag.set(hb.agents(s1), hb.ag.done(a))), "work", hb.report.text(hb.ag.name(a), T.tx.join(hb.ag.replies(a), "\n\n")))
        hb.reported(hb.ag.stop(a), p)

# an agent's call ended: told what it never took, it goes on; else its report
# is a message of its own, a turn's, unless stopped (Tools.run, Chat.report)
def hb.agent.ended(+s: hb.S, m: Maybe<&2, hb.Ag>, +ok: Bool, +text: String, +left: U32) -> IO(hb.S):
  match m:
    case None{}:
      IO.pure(hb.S, s)
    case Some{a0}:
      +a = hb.ag.end(a0, Bool.pick(String, ok, text, "failed: " ++ text))
      +s1 = hb.with.agents(s, hb.ag.set(hb.agents(s), a))
      hb.agent.next(Bool.and(ok, U32.is_gt(left, 0)), s1, a)

# Requests -----------------------------------------------------------------------------

def hb.answer(+reply: Chan(E.ev.Out), o: E.ev.Out) -> IO(Unit):
  IO.bind(Result<&1, &1, E.ev.Out, Unit>, Unit, Chan.send(E.ev.Out, reply, o), r => IO.pure(Unit, Unit{}))

def hb.num(+j: J.Json, +k: String, +d: U32) -> U32:
  L.tl.n(j, k, d)

def hb.zoom.id(+j: J.Json) -> String:
  L.tl.s(j, "id")

def hb.is.letter(+s: String) -> Bool:
  match s:
    case SCon{Chr{+c}, t}:
      Bool.or(Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)), Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)))
    case _:
      False{}

# zoom (Tools.call): an agent's chat by its name, a page from `at`; else the
# view's line id+n
def hb.zoom(+s: hb.S, +input: J.Json) -> IO(E.ev.Out):
  +id = hb.zoom.id(input)
  +at = hb.num(input, "at", 0)
  Bool.pick(IO(E.ev.Out), hb.is.letter(id),
    IO.bind(String, E.ev.Out, M.me.agent.show(hb.dir(s), Bool.pick(String, hb.name.ok(id, False{}), id, "-")), t => IO.pure(E.ev.Out, E.ev.Out{T.tx.page.at(Bool.pick(String, hb.name.ok(id, False{}), t, "No agent " ++ id ++ "."), at), False{}})),
    IO.bind(String, E.ev.Out, M.me.zoom(hb.mem(s), U32.from_nat(Maybe.default(&2, Nat, Nat.read(id), 4294967295n)), hb.num(input, "n", 1), at), t => IO.pure(E.ev.Out, E.ev.Out{t, False{}})))

def hb.date(+s: hb.S, +input: J.Json) -> IO(E.ev.Out):
  IO.bind(String, E.ev.Out, M.me.date(hb.mem(s), hb.num(input, "id", 4294967295)), t => IO.pure(E.ev.Out, E.ev.Out{t, False{}}))

def hb.sn.out(x: hb.Sn, +reply: Chan(E.ev.Out), +fail: Bool) -> IO(hb.S):
  match x:
    case hb.Sn{s, ns}:
      IO.bind(Unit, hb.S, hb.answer(reply, E.ev.Out{T.tx.join(ns, ""), fail}), u => IO.pure(hb.S, s))

def hb.spawned(x: hb.Sn) -> hb.Sn:
  match x:
    case hb.Sn{s, +ns}:
      hb.Sn{s, ["Started " ++ T.tx.join(ns, ", ") ++ ". Each one's report will reach you as a message when it finishes."]}

def hb.tell.req(+s: hb.S, +input: J.Json, +reply: Chan(E.ev.Out)) -> IO(hb.S):
  +agent = L.tl.s(input, "name")
  do IO<hb.S>:
    m : Maybe<&2, hb.Ag> <- hb.agent.load(s, agent)
    x : hb.Sn <- hb.tell.on(s, m, agent, L.tl.s(input, "message"))
    hb.sn.out(x, reply, False{})

# a spawn or tell, its summaries built (Tools.view)
def hb.serve(+s: hb.S, +w: hb.W) -> IO(hb.S):
  match w:
    case hb.W{who, +name, +input, +reply}:
      +effort = Maybe.default(&2, String, J.js.str(input, "effort"), "")
      +tasks = J.js.arr(input, "tasks")
      Bool.pick(IO(hb.S), String.eq(name, "spawn"),
        Bool.pick(IO(hb.S), Bool.and(Bool.not(String.is_empty(effort)), Bool.not(hb.has(hb.efforts(), effort))),
          IO.bind(Unit, hb.S, hb.answer(reply, E.ev.Out{"No effort " ++ effort ++ "; one of " ++ T.tx.join(hb.efforts(), ", ") ++ ".", True{}}), u => IO.pure(hb.S, s)),
          Bool.pick(IO(hb.S), List.is_empty(&2, J.Json, tasks), IO.bind(Unit, hb.S, hb.answer(reply, E.ev.Out{"No tasks.", False{}}), u => IO.pure(hb.S, s)),
            IO.bind(hb.Sn, hb.S, hb.spawn.go(tasks, s, effort, []), x => hb.sn.out(hb.spawned(x), reply, False{})))),
        hb.tell.req(s, input, reply))

def hb.serve.all(ws: List<&2, hb.W>, +s: hb.S) -> IO(hb.S):
  match ws:
    case []:
      IO.pure(hb.S, s)
    case w <> t:
      IO.bind(hb.S, hb.S, hb.serve(s, w), s2 => hb.serve.all(t, s2))

# a tool the hub runs: zoom and date at once; spawn and tell once every
# message is summarized (their agents see the view whole)
def hb.req(+s: hb.S, +who: String, +name: String, +input: J.Json, +reply: Chan(E.ev.Out)) -> IO(hb.S):
  Bool.pick(IO(hb.S), String.eq(name, "zoom"), IO.bind(E.ev.Out, hb.S, hb.zoom(s, input), o => IO.bind(Unit, hb.S, hb.answer(reply, o), u => IO.pure(hb.S, s))),
    Bool.pick(IO(hb.S), String.eq(name, "date"), IO.bind(E.ev.Out, hb.S, hb.date(s, input), o => IO.bind(Unit, hb.S, hb.answer(reply, o), u => IO.pure(hb.S, s))),
      IO.pure(hb.S, hb.with.reqs(s, List.append(&2, hb.W, hb.reqs(s), [hb.W{who, name, input, reply}])))))

# Stopping ----------------------------------------------------------------------------

def hb.pid.of(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Done{t}:
      U32.from_nat(Maybe.default(&2, Nat, Nat.read(T.tx.trim(t)), 0n))
    case Fail{e}:
      0

def hb.kill.pid(none: Bool, +pid: U32) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        a : U32 <- S.mu.kill(pid, 1, 9)
        b : U32 <- S.mu.kill(pid, 0, 15)
        return Unit{}

# a call's process killed, its stop asked (the call sees it at once); on
# Claude Code, its process group too
def hb.kill(+ctl: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Unit> <- S.mu.save(ctl ++ ".stop", "", 0)
    +pid : U32 <- IO.bind(Result<&1, &1, U32 & String, String>, U32, S.mu.read_file(ctl ++ ".pid"), r2 => IO.pure(U32, hb.pid.of(r2)))
    Unit <- hb.kill.pid(U32.is_eq(pid, 0), pid)
    +cc : U32 <- IO.bind(Result<&1, &1, U32 & String, String>, U32, S.mu.read_file(ctl ++ ".cc.pid"), r2 => IO.pure(U32, hb.pid.of(r2)))
    k : U32 <- Bool.pick(IO(U32), U32.is_eq(cc, 0), IO.pure(U32, 0), S.mu.kill(cc, 1, 15))
    return Unit{}

def hb.ag.says.of(m: Maybe<&2, hb.Ag>) -> Maybe<&2, Chan(E.ev.Say)>:
  match m:
    case Some{a}:
      hb.ag.says(a)
    case None{}:
      None{}

def hb.say.stop(m: Maybe<&2, Chan(E.ev.Say)>) -> IO(Unit):
  match m:
    case Some{c}:
      IO.bind(Result<&1, &1, E.ev.Say, Unit>, Unit, Chan.send(E.ev.Say, c, E.ev.Stop{}), r => IO.pure(Unit, Unit{}))
    case None{}:
      IO.pure(Unit, Unit{})

def hb.turn.says(t: hb.T) -> Maybe<&2, Chan(E.ev.Say)>:
  match t:
    case hb.Call{c}:
      Some{c}
    case _:
      None{}

def hb.ag.stopped(a: hb.Ag) -> hb.Ag:
  match a:
    case hb.Ag{n, e, sa, st, r, v, k}:
      hb.Ag{n, e, sa, True{}, r, v, k}

def hb.stop.one(turn: Bool, +s: hb.S, +n: String) -> IO(hb.S):
  match turn:
    case True{}:
      IO.pure(hb.S, s)
    case False{}:
      do IO<hb.S>:
        Unit <- hb.kill(hb.ctl(s, n))
        Unit <- hb.say.stop(hb.ag.says.of(hb.ag.find(hb.agents(s), n)))
        return hb.with.agents(s, hb.ag.set(hb.agents(s), hb.ag.stopped(Maybe.default(&2, hb.Ag, hb.ag.find(hb.agents(s), n), hb.Ag{n, "", None{}, True{}, [], [], 0}))))

def hb.stop.agents(ns: List<&2, String>, +s: hb.S) -> IO(hb.S):
  match ns:
    case []:
      IO.pure(hb.S, s)
    case +n <> t:
      do IO<hb.S>:
        +s2 : hb.S <- hb.stop.one(String.eq(n, hb.turn.name()), s, n)
        hb.stop.agents(t, s2)

def hb.sel(xs: List<&2, String>, +name: String) -> List<&2, String>:
  match xs:
    case []:
      []
    case +x <> t:
      List.append(&2, String, Bool.pick(List<&2, String>, Bool.or(String.is_empty(name), String.eq(x, name)), [x], []), hb.sel(t, name))

def hb.stop.turn(turn: Bool, +s: hb.S) -> IO(Unit):
  match turn:
    case True{}:
      do IO<Unit>:
        Unit <- hb.kill(hb.ctl(s, ""))
        hb.say.stop(hb.turn.says(hb.turn(s)))
    case False{}:
      IO.pure(Unit, Unit{})

def hb.stop.go(none: Bool, +s: hb.S, +what: List<&2, String>, +why: String, +turn: Bool) -> IO(hb.S):
  match none:
    case True{}:
      IO.bind(Unit, hb.S, IO.print(Tm.tm.status(hb.tty(s), "nothing runs")), u => IO.pure(hb.S, s))
    case False{}:
      do IO<hb.S>:
        Unit <- hb.stop.turn(turn, s)
        +s1 : hb.S <- hb.stop.agents(what, Bool.pick(hb.S, turn, hb.with.halt(s, why), s))
        Bool.pick(IO(hb.S), turn, IO.pure(hb.S, s1), hb.note(s1, why))

# work stopped by the user (Chat.act stop): all, or the one named; the turn's
# why noted as it ends, else at once
def hb.stop(+s: hb.S, +name: String) -> IO(hb.S):
  +what = hb.sel(hb.running(s), Bool.pick(String, Bool.or(String.eq(name, "turn"), String.eq(name, "Unii")), hb.turn.name(), name))
  +why = "Stopped by the user: " ++ T.tx.join(what, ", ") ++ "."
  +turn = hb.has(what, hb.turn.name())
  hb.stop.go(List.is_empty(&2, String, what), s, what, why, turn)

# Commands ------------------------------------------------------------------------------

def hb.word.go(s: String, +acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{32}, t}:
      String.reverse(acc)
    case SCon{c, t}:
      hb.word.go(t, SCon{c, acc})

def hb.cmd.code(+w: String) -> Nat:
  Bool.pick(Nat, String.eq(w, "/help"), 1n, Bool.pick(Nat, String.eq(w, "/quit"), 2n, Bool.pick(Nat, String.eq(w, "/stop"), 3n,
    Bool.pick(Nat, String.eq(w, "/halt"), 4n, Bool.pick(Nat, String.eq(w, "/goal"), 5n, Bool.pick(Nat, String.eq(w, "/model"), 6n,
      Bool.pick(Nat, String.eq(w, "/effort"), 7n, Bool.pick(Nat, String.eq(w, "/status"), 8n, Bool.pick(Nat, String.eq(w, "/export"), 10n,
        Bool.pick(Nat, String.eq(w, "/tree"), 11n, Bool.pick(Nat, String.eq(w, "/plan"), 12n, Bool.pick(Nat, String.eq(w, "/auto"), 13n,
          Bool.pick(Nat, String.starts_with(w, "/"), 9n, 0n)))))))))))))

def hb.tell.user(+s: hb.S, +text: String) -> IO(hb.S):
  IO.bind(Unit, hb.S, IO.print(Tm.tm.status(hb.tty(s), text)), u => IO.pure(hb.S, s))

def hb.pick.json(p: A.ap.Pick) -> J.Json:
  match p:
    case A.ap.Pick{m, e, sp}:
      J.JObj{[J.JKv{"vendor", J.JStr{"claude-api"}}, J.JKv{"model", J.JStr{m}}, J.JKv{"effort", J.JStr{e}}, J.JKv{"speed", J.JStr{sp}}]}

def hb.pick.label(p: A.ap.Pick) -> String:
  match p:
    case A.ap.Pick{m, e, sp}:
      m ++ ":" ++ e ++ ":" ++ sp

def hb.set.pick(+s: hb.S, +p: A.ap.Pick) -> IO(hb.S):
  +m = M.me.with.kept(hb.mem(s), hb.kept.pick(M.me.kept(hb.mem(s)), hb.pick.json(p)))
  do IO<hb.S>:
    Unit <- M.me.save(m)
    hb.tell.user(hb.with.pick(hb.with.mem(s, m), p), "the chat now runs on " ++ hb.pick.label(p))

def hb.set.goal(+s: hb.S, g: Maybe<&2, String>) -> IO(hb.S):
  +m = M.me.with.kept(hb.mem(s), hb.kept.goal(M.me.kept(hb.mem(s)), g))
  IO.bind(Unit, hb.S, M.me.save(m), u => IO.pure(hb.S, hb.with.mem(s, m)))

def hb.status.text(+s: hb.S) -> String:
  +m = hb.mem(s)
  +agents = hb.working(hb.agents(s))
  "view " ++ U32.show(U32.div(M.me.v.size(M.me.view(m)), 1000)) ++ " KB, " ++ U32.show(M.me.count(m)) ++ " messages, " ++ U32.show(M.me.nbusy(m)) ++ " summarizing, "
    ++ Bool.pick(String, hb.busy(hb.turn(s)), "a turn runs, ", "") ++ "agents at work: " ++ Bool.pick(String, List.is_empty(&2, String, agents), "none", T.tx.join(agents, ", ")) ++ "; " ++ hb.pick.label(hb.pick(s))

def hb.with.model(p: A.ap.Pick, +m2: String) -> A.ap.Pick:
  match p:
    case A.ap.Pick{m, e, sp}:
      A.ap.Pick{m2, e, sp}

def hb.with.effort(p: A.ap.Pick, +e2: String) -> A.ap.Pick:
  match p:
    case A.ap.Pick{m, e, sp}:
      A.ap.Pick{m, e2, sp}

# the user's words logged, taken by the turn
def hb.said(+s: hb.S, +text: String) -> IO(hb.S):
  IO.bind(hb.P, hb.S, hb.push(s, "user", text), +p => hb.take(hb.p.s(p), hb.p.msg(p)))

def hb.view.texts(ps: List<&2, R.tr.P>, +nodes: I.im.M<V.vw.Node>) -> List<&2, String>:
  match ps:
    case []:
      []
    case p <> t:
      V.vw.text(nodes, p) <> hb.view.texts(t, nodes)

def hb.cmd(k: Nat, +s: hb.S, +t: String, +w: String, +rest: String) -> IO(hb.S):
  match k:
    case 0n:
      Bool.pick(IO(hb.S), String.is_empty(t), Bool.pick(IO(hb.S), hb.busy(hb.turn(s)), hb.stop(s, "turn"), IO.pure(hb.S, s)), hb.said(s, t))
    case 1n:
      IO.bind(Unit, hb.S, IO.print(Tm.tm.help()), u => IO.pure(hb.S, s))
    case 2n:
      IO.pure(hb.S, hb.with.quit(s))
    case 3n:
      hb.stop(s, rest)
    case 4n:
      IO.bind(hb.S, hb.S, hb.set.goal(s, None{}), s2 => hb.note(s2, "Goal halted by the user."))
    case 5n:
      Bool.pick(IO(hb.S), String.is_empty(rest), hb.tell.user(s, "/goal needs one: /goal <message>."),
        IO.bind(hb.S, hb.S, hb.set.goal(s, Some{rest}), s2 => hb.said(s2, t)))
    case 6n:
      Bool.pick(IO(hb.S), String.is_empty(rest), hb.tell.user(s, "the chat runs on " ++ hb.pick.label(hb.pick(s))), hb.set.pick(s, hb.with.model(hb.pick(s), rest)))
    case 7n:
      Bool.pick(IO(hb.S), hb.has(hb.efforts(), rest), hb.set.pick(s, hb.with.effort(hb.pick(s), rest)),
        hb.tell.user(s, "/effort takes one of " ++ T.tx.join(hb.efforts(), ", ")))
    case 8n:
      hb.tell.user(s, hb.status.text(s))
    case 10n:
      do IO<hb.S>:
        Unit <- X.ex.export(hb.dir(s), M.me.count(hb.mem(s)), "mugen-memory.json")
        hb.tell.user(s, "the memory is in ./mugen-memory.json")
    case 11n:
      do IO<hb.S>:
        w : hb.When <- hb.when()
        tz : U32 <- S.mu.tzoff(hb.when.now(w))
        Unit <- X.ex.tree(hb.dir(s), M.me.count(hb.mem(s)), V.vw.parts(M.me.view(hb.mem(s))), hb.view.texts(V.vw.parts(M.me.view(hb.mem(s))), M.me.nodes(hb.mem(s))), tz, hb.dir(s) ++ "/tree.html")
        hb.tell.user(s, "the memory tree: file://" ++ hb.dir(s) ++ "/tree.html")
    case 12n:
      hb.tell.user(hb.with.mode(s, 1), "plan mode: Unii reads and proposes a plan; it runs no shell, writes and edits nothing, and starts no agents. /auto lets it act.")
    case 13n:
      hb.tell.user(hb.with.mode(s, 0), "auto mode: Unii runs its tools as it needs them. /plan to plan first.")
    case _:
      hb.tell.user(s, w ++ " is no command; nothing was sent. /help lists the commands.")

# a line the user typed (a prompt is due once the hub is idle again)
def hb.line(+s: hb.S, +text: String) -> IO(hb.S):
  +t = T.tx.trim(text)
  +w = hb.word.go(t, "")
  hb.cmd(hb.cmd.code(w), hb.with.due(s, True{}), t, w, T.tx.trim(String.drop(t, String.length(w))))

# Events ------------------------------------------------------------------------------

def hb.entry(+s: hb.S, +who: String, +kind: String, +text: String) -> IO(hb.S):
  Bool.pick(IO(hb.S), String.eq(kind, "user"), IO.pure(hb.S, s),
    Bool.pick(IO(hb.S), String.is_empty(who), IO.bind(hb.P, hb.S, hb.push(s, kind, text), p => IO.pure(hb.S, hb.p.s(p))),
      hb.alog.by(s, hb.ag.find(hb.agents(s), who), kind, text)))

def hb.is.call(t: hb.T) -> Bool:
  match t:
    case hb.Call{c}:
      True{}
    case _:
      False{}

def hb.is.check(t: hb.T, +goal: String) -> Bool:
  match t:
    case hb.Check{+g}:
      String.eq(g, goal)
    case _:
      False{}

def hb.on(+s: hb.S, m: Maybe<&1, E.ev.Ev>) -> IO(hb.S):
  match m:
    case None{}:
      IO.pure(hb.S, hb.with.quit(s))
    case Some{E.ev.Line{t}}:
      hb.line(s, t)
    case Some{E.ev.Eof{}}:
      IO.pure(hb.S, Bool.pick(hb.S, hb.tty(s), hb.with.quit(s), hb.with.eof(s)))
    case Some{E.ev.Built{l, i, line}}:
      hb.built(s, l, i, line)
    case Some{E.ev.Entry{who, kind, text}}:
      hb.entry(s, who, kind, text)
    case Some{E.ev.Show{who, kind, text}}:
      IO.bind(Unit, hb.S, hb.print(s, who, kind, text), u => IO.pure(hb.S, s))
    case Some{E.ev.Req{who, name, input, reply}}:
      hb.req(s, who, name, input, reply)
    case Some{E.ev.End{+who, +ok, +text, stop, +left}}:
      Bool.pick(IO(hb.S), String.is_empty(who), Bool.pick(IO(hb.S), hb.is.call(hb.turn(s)), hb.ended(s, ok, text, left), IO.pure(hb.S, s)),
        hb.agent.ended(s, hb.ag.find(hb.agents(s), who), ok, text, left))
    case Some{E.ev.Goal{+goal, ok, text}}:
      Bool.pick(IO(hb.S), hb.is.check(hb.turn(s), goal), hb.checked(s, goal, ok, text), IO.pure(hb.S, s))

def hb.is.idle(t: hb.T) -> Bool:
  match t:
    case hb.Idle{}:
      True{}
    case _:
      False{}

def hb.is.settle(t: hb.T) -> Bool:
  match t:
    case hb.Settle{}:
      True{}
    case _:
      False{}

# what runs, kept in view.json as it changes (Chat.change)
def hb.work(+s: hb.S) -> IO(hb.S):
  +now = hb.running(s)
  +m = hb.mem(s)
  Bool.pick(IO(hb.S), String.eq(T.tx.join(now, "\n"), T.tx.join(M.me.kept.work(M.me.kept(m)), "\n")), IO.pure(hb.S, s),
    IO.bind(Unit, hb.S, M.me.save(M.me.with.kept(m, hb.kept.work(M.me.kept(m), now))), u => IO.pure(hb.S, hb.with.mem(s, M.me.with.kept(m, hb.kept.work(M.me.kept(m), now))))))

# after each event: a turn starts for messages waiting, a turn waiting on
# summaries goes on once they are built, as do spawns and tells
def hb.after(+s: hb.S) -> IO(hb.S):
  +s1 = Bool.pick(hb.S, Bool.and(hb.is.idle(hb.turn(s)), Bool.not(List.is_empty(&2, hb.Msg, hb.wait(s)))), hb.with.turn(s, hb.Settle{}), s)
  do IO<hb.S>:
    +s2 : hb.S <- Bool.pick(IO(hb.S), hb.is.settle(hb.turn(s1)), hb.settle(s1), IO.pure(hb.S, s1))
    +ready : Bool = Bool.and(Bool.not(List.is_empty(&2, hb.W, hb.reqs(s2))), U32.is_ge(hb.first(s2), M.me.count(hb.mem(s2))))
    +s3 : hb.S <- Bool.pick(IO(hb.S), ready, hb.serve.all(hb.reqs(s2), hb.with.reqs(s2, [])), IO.pure(hb.S, s2))
    hb.work(s3)

# stdin ended (a pipe) and nothing runs or waits: done
def hb.alive(+s: hb.S) -> Bool:
  +idle = Bool.and(Bool.and(hb.is.idle(hb.turn(s)), List.is_empty(&2, String, hb.working(hb.agents(s)))),
    Bool.and(U32.is_eq(M.me.nbusy(hb.mem(s)), 0), Bool.and(List.is_empty(&2, hb.W, hb.reqs(s)), List.is_empty(&2, hb.Msg, hb.wait(s)))))
  Bool.and(Bool.not(hb.quit(s)), Bool.not(Bool.and(hb.eof(s), idle)))

# The prompt -------------------------------------------------------------------------
#
# On a terminal, once the hub is idle and a prompt is due: a line of where
# Unii works, the model, its effort, the context left (the room the view
# has before mugen folds its oldest lines, at 128 KB) and the mode, then a
# lambda to type after.

def hb.tilde(+home: String, +path: String) -> String:
  Bool.pick(String, Bool.and(Bool.not(String.is_empty(home)), String.starts_with(path, home)), "~" ++ String.drop(path, String.length(home)), path)

def hb.workdir(+s: hb.S) -> String:
  hb.tilde(hb.cfg.home(hb.cfg(s)), hb.cfg.work(hb.cfg(s)) ++ "/main")

# the view's room left before it folds, in percent
def hb.left(+s: hb.S) -> U32:
  +size = U32.min(M.me.v.size(M.me.view(hb.mem(s))), M.me.high())
  U32.div(((M.me.high() - size : U32) * 100 : U32), M.me.high())

def hb.pick.model(p: A.ap.Pick) -> String:
  match p:
    case A.ap.Pick{m, e, sp}:
      m

def hb.mode.text(plan: Bool) -> String:
  match plan:
    case True{}:
      Tm.tm.esc("33", "plan")
    case False{}:
      Tm.tm.esc("32", "auto")

def hb.prompt.text(+s: hb.S) -> String:
  +dot = Tm.tm.esc("2", " · ")
  "\n" ++ Tm.tm.esc("2", hb.workdir(s)) ++ dot ++ Tm.tm.esc("36", hb.pick.model(hb.pick(s))) ++ dot ++ A.ap.pick.effort(hb.pick(s)) ++ dot
    ++ U32.show(hb.left(s)) ++ "% left" ++ dot ++ hb.mode.text(hb.plan(s)) ++ "\n" ++ Tm.tm.esc("1;35", "\u{3BB}") ++ " "

def hb.idle(+s: hb.S) -> Bool:
  Bool.and(Bool.and(hb.is.idle(hb.turn(s)), List.is_empty(&2, hb.Msg, hb.wait(s))), Bool.not(hb.quit(s)))

def hb.prompt(+s: hb.S) -> IO(hb.S):
  Bool.pick(IO(hb.S), Bool.and(hb.tty(s), Bool.and(hb.ui.due(hb.ui(s)), hb.idle(s))),
    IO.bind(Unit, hb.S, IO.write(hb.prompt.text(s)), u => IO.pure(hb.S, hb.with.due(s, False{}))), IO.pure(hb.S, s))

def hb.loop(n: Nat, go: Bool, +s: hb.S) -> IO(hb.S):
  match n go:
    case 1n+f True{}:
      do IO<hb.S>:
        m : Maybe<&1, E.ev.Ev> <- Chan.recv(E.ev.Ev, hb.inbox(s))
        +s1 : hb.S <- hb.on(s, m)
        +s2 : hb.S <- hb.after(s1)
        +s3 : hb.S <- hb.prompt(s2)
        hb.loop(f, hb.alive(s3), s3)
    case _ _:
      IO.pure(hb.S, s)

# Leaving and starting -------------------------------------------------------------------

def hb.kill.all(ls: List<&2, String>) -> IO(Unit):
  match ls:
    case []:
      IO.pure(Unit, Unit{})
    case +l <> +t:
      +pid = U32.from_nat(Maybe.default(&2, Nat, Nat.read(T.tx.trim(l)), 0n))
      Bool.pick(IO(Unit), U32.is_eq(pid, 0), hb.kill.all(t), IO.bind(U32, Unit, S.mu.kill(pid, 1, 9), r => hb.kill.all(t)))

def hb.kill.agents(ns: List<&2, String>, +s: hb.S) -> IO(Unit):
  match ns:
    case []:
      IO.pure(Unit, Unit{})
    case +n <> t:
      IO.bind(Unit, Unit, hb.kill(hb.ctl(s, Bool.pick(String, String.eq(n, hb.turn.name()), "", n))), u => hb.kill.agents(t, s))

# as mugen quits: what runs is cut (view.json keeps it, for the next start)
# and every shell's group killed, so no job outlives it
def hb.leave(+s: hb.S) -> IO(Unit):
  do IO<Unit>:
    Unit <- hb.kill.agents(hb.running(s), s)
    gs : String <- IO.bind(Result<&1, &1, U32 & String, String>, String, S.mu.read_file(hb.dir(s) ++ "/run/groups"), r => IO.pure(String, L.tl.text.of(r)))
    Unit <- hb.kill.all(String.lines(gs))
    IO.pure(Unit, Unit{})

def hb.resume.one(turn: Bool, +s: hb.S, +w: String, +msg: hb.Msg, +text: String) -> IO(hb.S):
  match turn:
    case True{}:
      hb.take(s, msg)
    case False{}:
      do IO<hb.S>:
        m : Maybe<&2, hb.Ag> <- hb.agent.load(s, w)
        x : hb.Sn <- hb.tell.on(s, m, w, text)
        return hb.sn.s(x)

def hb.resume.go(ws: List<&2, String>, +s: hb.S, +msg: hb.Msg, +text: String) -> IO(hb.S):
  match ws:
    case []:
      IO.pure(hb.S, s)
    case +w <> t:
      do IO<hb.S>:
        +s2 : hb.S <- hb.resume.one(String.eq(w, hb.turn.name()), s, w, msg, text)
        hb.resume.go(t, s2, msg, text)

# the work a quit or a crash cut goes on, told so (Chat.resume)
def hb.resume(+s: hb.S) -> IO(hb.S):
  +work = M.me.kept.work(M.me.kept(hb.mem(s)))
  +text = "mugen restarted, cutting " ++ T.tx.join(work, ", ") ++ "; nothing was lost: go on."
  Bool.pick(IO(hb.S), List.is_empty(&2, String, work), IO.pure(hb.S, s),
    IO.bind(hb.P, hb.S, hb.push(s, "note", text), +p => hb.resume.go(work, hb.p.s(p), hb.p.msg(p), text)))

def hb.pick.of(+j: J.Json, +d: A.ap.Pick) -> A.ap.Pick:
  match d:
    case A.ap.Pick{+m, +e, +sp}:
      A.ap.Pick{Maybe.default(&2, String, J.js.str(j, "model"), m), Maybe.default(&2, String, J.js.str(j, "effort"), e), Maybe.default(&2, String, J.js.str(j, "speed"), sp)}

def hb.cfg.jobs(c: hb.Cfg) -> U32:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      j

def hb.cfg.sync(c: hb.Cfg) -> U32:
  match c:
    case hb.Cfg{a, d, w, h, sh, r, cp, t, j, sy, ho, ac}:
      sy

def hb.locked(+dir: String, r: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match r:
    case Done{u}:
      IO.pure(Unit, Unit{})
    case Fail{e}:
      IO.die(Unit, 1, "mugen: " ++ dir ++ " is in use by another mugen")

# the chat of the data dir, run till the user leaves (or, from a pipe, till
# stdin ends and nothing runs)
def hb.start(+c: hb.Cfg, +chat: A.ap.Pick) -> IO(Unit):
  +dir = hb.cfg.dir(c)
  do IO<Unit>:
    Unit <- S.mu.must(Unit, "mkdir " ++ dir, S.mu.mkdirs(dir ++ "/run"))
    Unit <- S.mu.must(Unit, "mkdir work", S.mu.mkdirs(hb.cfg.work(c) ++ "/main"))
    lk : Result<&1, &1, U32 & String, Unit> <- S.mu.lock(dir ++ "/lock")
    Unit <- hb.locked(dir, lk)
    +mem : M.me.Mem <- M.me.load(dir, hb.cfg.sync(c), hb.cfg.jobs(c))
    Unit <- S.mu.must(Unit, "run/groups", S.mu.save(dir ++ "/run/groups", "", 0))
    +inbox : Chan(E.ev.Ev) <- Chan.new(E.ev.Ev, 4096)
    +junk : Chan(String) <- Chan.new(String, 1)
    +pick : A.ap.Pick = hb.pick.of(M.me.kept.pick(M.me.kept(mem)), chat)
    +s0 : hb.S = hb.S{c, mem, inbox, junk, pick, hb.Idle{}, [], [], "", [], [], False{}, False{}, "", hb.Ui{0, True{}}}
    Unit <- IO.spawn(Unit, Tm.tm.reader(inbox))
    w : hb.When <- hb.when()
    r : M.me.Mem & List<&2, M.me.Job> <- M.me.pump(mem, hb.when.day(w))
    +s1 : hb.S <- hb.mem.jobs(s0, r)
    Unit <- Bool.pick(IO(Unit), hb.tty(s1), IO.print(Tm.tm.status(True{}, "mugen: " ++ hb.status.text(s1) ++ ". /help")), IO.pure(Unit, Unit{}))
    +s2 : hb.S <- hb.resume(s1)
    +s3 : hb.S <- hb.after(s2)
    +s4 : hb.S <- hb.prompt(s3)
    +s5 : hb.S <- hb.loop(U32.to_nat(4294967295), hb.alive(s4), s4)
    hb.leave(s5)
