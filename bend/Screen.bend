
import Base
import ./Sys.bend as S
import ./Json.bend as J
import ./Ev.bend as E
import ./Keys.bend as K
import ./Edit.bend as D
import ./Pretty.bend as P

# Screen: mugen on a terminal, full screen. One computation owns the
# terminal: it reads the keys (raw mode), draws the chat, and sends the
# hub (Hub.bend) the lines typed; the hub tells it what to show (sc.Put, as
# it logs) and how it is (sc.State: Unii's work, the messages waiting, the
# status line). Top down: the chat, scrolled with PgUp, PgDn and the wheel,
# each tool call one block (a click opens or folds it, C-o all of them);
# then a rule, what runs (with a spinner and its time), the messages waiting
# for Unii, the status line, and the input (Edit.bend) after the lambda.
#
# Keys: Enter sends; Shift-, Alt-, Ctrl-Enter or C-j make a new line (so
# does a "\" ending the text); C-s sends the waiting messages now (Hub's
# /now); C-g stops Unii's turn; Esc twice, C-c on an empty input or C-d
# leave. The terminal comes back as it was on every way out, a signal's
# too (Sys.bend mu.raw).
#
# Every def is prefixed `sc.` (a program's defs share one namespace).

def sc.fuel() -> Nat:
  U32.to_nat(4294967295)

def sc.csi() -> String:
  "\u{1B}["

# the alternate screen, no wrap at the margin, the mouse (SGR reports),
# bracketed paste, modifyOtherKeys and kitty's disambiguated keys (each a
# way for Shift-Enter to be told from Enter)
def sc.init() -> String:
  "\u{1B}[?1049h\u{1B}[?7l\u{1B}[?1000h\u{1B}[?1006h\u{1B}[?2004h\u{1B}[>4;1m\u{1B}[>1u\u{1B}[H\u{1B}[2J"

def sc.back() -> String:
  "\u{1B}[<u\u{1B}[>4;0m\u{1B}[?2004l\u{1B}[?1006l\u{1B}[?1000l\u{1B}[?7h\u{1B}[?25h\u{1B}[?1049l"

# Types --------------------------------------------------------------------------

# A block of the chat: its id, who ("" Unii's), its kind, text, a tool
# call's result ("" none yet), open (unfolded), whether its tool runs and
# since when; its rows, bottom up, as drawn at width w (0: not yet), and how
# many they are
type sc.Blk is Data:
  sc.Blk{id: U32, who: String, kind: String, text: String, res: String, open: Bool, run: Bool, t0: Nat, w: U32, rows: List<&2, String>, n: U32}

# How the hub is: whether Unii works and at what since when; the messages
# waiting for it, and those handed to its running call (each a line);
# the status line (SGR in it); the agents at work
type sc.St is Data:
  sc.St{busy: Bool, what: String, since: Nat, wait: List<&2, String>, sent: List<&2, String>, line: String, agents: List<&2, String>}

# what the screen hears: a key (and when, IO.now), an entry to show, the
# hub's state, a tick (5 a second), stdin's end, and the hub leaving (the
# terminal given back, then `done` told)
type sc.In is Data:
  sc.Key{key: K.ky.Key, at: Nat}
  sc.Put{who: String, kind: String, text: String}
  sc.State{st: sc.St}
  sc.Tick{}
  sc.Eof{}
  sc.Bye{done: Chan(Unit)}

# what never changes: the hub's inbox, our own, home (~ in paths), the
# history's file
type sc.Cf is Data:
  sc.Cf{hub: Chan(E.ev.Ev), me: Chan(sc.In), home: String, hfile: String}

# the chat: its blocks (newest first), the next id, the rows scrolled up
# from its end, and the ids of the blocks on its rows as drawn (top down)
type sc.Tr is Data:
  sc.Tr{blks: List<&2, sc.Blk>, next: U32, off: U32, ids: List<&2, U32>}

# the terminal: its columns and rows, what to draw (0 nothing, 1 the lines
# under the chat, 2 all), the mouse's reports on, the rows under the chat as
# last drawn
type sc.Tm is Data:
  sc.Tm{w: U32, h: U32, draw: U32, mouse: Bool, low: U32}

# the moment: now (IO.now), the last Esc (0 none), a word for the user
# under the chat, leaving asked, the terminal given back
type sc.U is Data:
  sc.U{now: Nat, esc: Nat, hint: String, quit: Bool, done: Bool}

type sc.S is Data:
  sc.S{cf: sc.Cf, ed: D.ed.Ed, tr: sc.Tr, tm: sc.Tm, st: sc.St, u: sc.U}

def sc.idle() -> sc.St:
  sc.St{False{}, "", 0n, [], [], "", []}

# Fields -------------------------------------------------------------------------

def sc.cf(s: sc.S) -> sc.Cf:
  match s:
    case sc.S{c, e, t, m, st, u}:
      c

def sc.ed(s: sc.S) -> D.ed.Ed:
  match s:
    case sc.S{c, e, t, m, st, u}:
      e

def sc.tr(s: sc.S) -> sc.Tr:
  match s:
    case sc.S{c, e, t, m, st, u}:
      t

def sc.tm(s: sc.S) -> sc.Tm:
  match s:
    case sc.S{c, e, t, m, st, u}:
      m

def sc.st(s: sc.S) -> sc.St:
  match s:
    case sc.S{c, e, t, m, st, u}:
      st

def sc.u(s: sc.S) -> sc.U:
  match s:
    case sc.S{c, e, t, m, st, u}:
      u

def sc.with.ed(s: sc.S, +e2: D.ed.Ed) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u}:
      sc.S{c, e2, t, m, st, u}

def sc.with.tr(s: sc.S, +t2: sc.Tr) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u}:
      sc.S{c, e, t2, m, st, u}

def sc.with.tm(s: sc.S, +m2: sc.Tm) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u}:
      sc.S{c, e, t, m2, st, u}

def sc.with.st(s: sc.S, +st2: sc.St) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u}:
      sc.S{c, e, t, m, st2, u}

def sc.with.u(s: sc.S, +u2: sc.U) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u}:
      sc.S{c, e, t, m, st, u2}

def sc.cf.hub(c: sc.Cf) -> Chan(E.ev.Ev):
  match c:
    case sc.Cf{h, m, ho, hf}:
      h

def sc.cf.me(c: sc.Cf) -> Chan(sc.In):
  match c:
    case sc.Cf{h, m, ho, hf}:
      m

def sc.cf.home(c: sc.Cf) -> String:
  match c:
    case sc.Cf{h, m, ho, hf}:
      ho

def sc.cf.hfile(c: sc.Cf) -> String:
  match c:
    case sc.Cf{h, m, ho, hf}:
      hf

def sc.hub(+s: sc.S) -> Chan(E.ev.Ev):
  sc.cf.hub(sc.cf(s))

def sc.home(+s: sc.S) -> String:
  sc.cf.home(sc.cf(s))

def sc.tr.blks(t: sc.Tr) -> List<&2, sc.Blk>:
  match t:
    case sc.Tr{b, n, o, i}:
      b

def sc.tr.next(t: sc.Tr) -> U32:
  match t:
    case sc.Tr{b, n, o, i}:
      n

def sc.tr.off(t: sc.Tr) -> U32:
  match t:
    case sc.Tr{b, n, o, i}:
      o

def sc.tr.ids(t: sc.Tr) -> List<&2, U32>:
  match t:
    case sc.Tr{b, n, o, i}:
      i

def sc.blks(+s: sc.S) -> List<&2, sc.Blk>:
  sc.tr.blks(sc.tr(s))

def sc.off(+s: sc.S) -> U32:
  sc.tr.off(sc.tr(s))

def sc.with.blks(+s: sc.S, +bs: List<&2, sc.Blk>) -> sc.S:
  +t = sc.tr(s)
  sc.with.tr(s, sc.Tr{bs, sc.tr.next(t), sc.tr.off(t), sc.tr.ids(t)})

def sc.with.off(+s: sc.S, +o: U32) -> sc.S:
  +t = sc.tr(s)
  sc.with.tr(s, sc.Tr{sc.tr.blks(t), sc.tr.next(t), o, sc.tr.ids(t)})

def sc.tm.w(t: sc.Tm) -> U32:
  match t:
    case sc.Tm{w, h, d, m, l}:
      w

def sc.tm.h(t: sc.Tm) -> U32:
  match t:
    case sc.Tm{w, h, d, m, l}:
      h

def sc.tm.draw(t: sc.Tm) -> U32:
  match t:
    case sc.Tm{w, h, d, m, l}:
      d

def sc.tm.mouse(t: sc.Tm) -> Bool:
  match t:
    case sc.Tm{w, h, d, m, l}:
      m

def sc.tm.low(t: sc.Tm) -> U32:
  match t:
    case sc.Tm{w, h, d, m, l}:
      l

def sc.w(+s: sc.S) -> U32:
  sc.tm.w(sc.tm(s))

def sc.h(+s: sc.S) -> U32:
  sc.tm.h(sc.tm(s))

# what to draw, at least k
def sc.tm.dirty(t: sc.Tm, +k: U32) -> sc.Tm:
  match t:
    case sc.Tm{w, h, d, m, l}:
      sc.Tm{w, h, U32.max(d, k), m, l}

def sc.dirty(+s: sc.S, +k: U32) -> sc.S:
  sc.with.tm(s, sc.tm.dirty(sc.tm(s), k))

def sc.u.now(u: sc.U) -> Nat:
  match u:
    case sc.U{n, e, h, q, d}:
      n

def sc.u.esc(u: sc.U) -> Nat:
  match u:
    case sc.U{n, e, h, q, d}:
      e

def sc.u.hint(u: sc.U) -> String:
  match u:
    case sc.U{n, e, h, q, d}:
      h

def sc.u.quit(u: sc.U) -> Bool:
  match u:
    case sc.U{n, e, h, q, d}:
      q

def sc.u.done(u: sc.U) -> Bool:
  match u:
    case sc.U{n, e, h, q, d}:
      d

def sc.now(+s: sc.S) -> Nat:
  sc.u.now(sc.u(s))

def sc.hint(+s: sc.S) -> String:
  sc.u.hint(sc.u(s))

def sc.with.now(+s: sc.S, +n2: Nat) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{n2, sc.u.esc(u), sc.u.hint(u), sc.u.quit(u), sc.u.done(u)})

def sc.with.esc(+s: sc.S, +e2: Nat) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{sc.u.now(u), e2, sc.u.hint(u), sc.u.quit(u), sc.u.done(u)})

def sc.with.hint(+s: sc.S, +h2: String) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{sc.u.now(u), sc.u.esc(u), h2, sc.u.quit(u), sc.u.done(u)})

def sc.with.quit(+s: sc.S) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{sc.u.now(u), sc.u.esc(u), sc.u.hint(u), True{}, sc.u.done(u)})

def sc.with.done(+s: sc.S) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{sc.u.now(u), sc.u.esc(u), sc.u.hint(u), sc.u.quit(u), True{}})

def sc.st.busy(t: sc.St) -> Bool:
  match t:
    case sc.St{b, w, si, wa, se, l, a}:
      b

def sc.st.what(t: sc.St) -> String:
  match t:
    case sc.St{b, w, si, wa, se, l, a}:
      w

def sc.st.since(t: sc.St) -> Nat:
  match t:
    case sc.St{b, w, si, wa, se, l, a}:
      si

def sc.st.wait(t: sc.St) -> List<&2, String>:
  match t:
    case sc.St{b, w, si, wa, se, l, a}:
      wa

def sc.st.sent(t: sc.St) -> List<&2, String>:
  match t:
    case sc.St{b, w, si, wa, se, l, a}:
      se

def sc.st.line(t: sc.St) -> String:
  match t:
    case sc.St{b, w, si, wa, se, l, a}:
      l

def sc.st.agents(t: sc.St) -> List<&2, String>:
  match t:
    case sc.St{b, w, si, wa, se, l, a}:
      a

# Blocks -------------------------------------------------------------------------

def sc.blk.id(b: sc.Blk) -> U32:
  match b:
    case sc.Blk{i, w, k, t, r, o, ru, t0, bw, rs, n}:
      i

def sc.blk.n(b: sc.Blk) -> U32:
  match b:
    case sc.Blk{i, w, k, t, r, o, ru, t0, bw, rs, n}:
      n

def sc.blk.rows(b: sc.Blk) -> List<&2, String>:
  match b:
    case sc.Blk{i, w, k, t, r, o, ru, t0, bw, rs, n}:
      rs

# its rows drawn anew at width w (bottom up)
def sc.blk.draw(b: sc.Blk, +w: U32, +home: String) -> sc.Blk:
  match b:
    case sc.Blk{i, +who, +k, +t, +r, +o, +ru, t0, bw, rs, n}:
      +rows = List.reverse(&2, String, P.pp.block(k, who, t, r, o, ru, w, home))
      sc.Blk{i, who, k, t, r, o, ru, t0, w, rows, U32.from_nat(List.length(&2, String, rows))}

def sc.blk.w(b: sc.Blk) -> U32:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      bw

def sc.blk.redraw(same: Bool, +b: sc.Blk, +w: U32, +home: String) -> sc.Blk:
  match same:
    case True{}:
      b
    case False{}:
      sc.blk.draw(b, w, home)

# drawn at w, unless it already is
def sc.blk.fresh(+b: sc.Blk, +w: U32, +home: String) -> sc.Blk:
  sc.blk.redraw(U32.is_eq(sc.blk.w(b), w), b, w, home)

def sc.blk.new(+id: U32, +who: String, +kind: String, +text: String, +run: Bool, +now: Nat, +w: U32, +home: String) -> sc.Blk:
  sc.blk.draw(sc.Blk{id, who, kind, text, "", False{}, run, now, 0, [], 0}, w, home)

def sc.blk.toggle(b: sc.Blk, +w: U32, +home: String) -> sc.Blk:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      sc.blk.draw(sc.Blk{i, who, k, t, r, Bool.not(o), ru, t0, 0, [], 0}, w, home)

def sc.blk.foldable(b: sc.Blk) -> Bool:
  match b:
    case sc.Blk{i, who, +k, +t, +r, o, ru, t0, bw, rs, n}:
      P.pp.foldable(k, t, r)

def sc.blk.is.open(b: sc.Blk) -> Bool:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      o

def sc.blk.opened(b: sc.Blk, +o2: Bool, +w: U32, +home: String) -> sc.Blk:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      sc.blk.draw(sc.Blk{i, who, k, t, r, o2, ru, t0, 0, [], 0}, w, home)

def sc.blk.set.go(change: Bool, +b: sc.Blk, +o2: Bool, +w: U32, +home: String) -> sc.Blk:
  match change:
    case True{}:
      sc.blk.opened(b, o2, w, home)
    case False{}:
      b

def sc.blk.set.open(+b: sc.Blk, +o2: Bool, +w: U32, +home: String) -> sc.Blk:
  sc.blk.set.go(Bool.and(sc.blk.foldable(b), Bool.xor(sc.blk.is.open(b), o2)), b, o2, w, home)

# a tool call waiting on its result: who's, and (if text is not "") this one
def sc.blk.waits(b: sc.Blk, +who: String, +text: String) -> Bool:
  match b:
    case sc.Blk{i, +w, +k, +t, +r, o, ru, t0, bw, rs, n}:
      Bool.and(Bool.and(String.eq(k, "tool"), String.is_empty(r)), Bool.and(String.eq(w, who), Bool.or(String.is_empty(text), String.eq(t, text))))

# its result in (or, res empty, its run over), drawn anew
def sc.blk.result(b: sc.Blk, +res: String, +w: U32, +home: String) -> sc.Blk:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      sc.blk.draw(sc.Blk{i, who, k, t, res, o, False{}, t0, 0, [], 0}, w, home)

def sc.attach.more(m: Maybe<&2, List<&2, sc.Blk>>, +b: sc.Blk) -> Maybe<&2, List<&2, sc.Blk>>:
  match m:
    case Some{+bs}:
      Some{b <> bs}
    case None{}:
      None{}

def sc.attach.v(bs: List<&2, sc.Blk>, +who: String, +text: String) -> Bool:
  match bs:
    case []:
      False{}
    case +b <> rest:
      sc.blk.waits(b, who, text)

# the newest block that waits (sc.blk.waits), its result set; None if none
# does (hit: the head waits)
def sc.attach(bs: List<&2, sc.Blk>, hit: Bool, +who: String, +text: String, +res: String, +w: U32, +home: String) -> Maybe<&2, List<&2, sc.Blk>>:
  match bs hit:
    case Nil{} _:
      None{}
    case +b <> +rest True{}:
      Some{sc.blk.result(b, res, w, home) <> rest}
    case +b <> +rest False{}:
      sc.attach.more(sc.attach(rest, sc.attach.v(rest, who, text), who, text, res, w, home), b)

def sc.blk.runs(b: sc.Blk) -> Bool:
  match b:
    case sc.Blk{i, +who, k, t, r, o, ru, t0, bw, rs, n}:
      Bool.and(ru, String.is_empty(who))

# the newest running call of Unii's: its text and since when
def sc.running(bs: List<&2, sc.Blk>) -> Maybe<&2, sc.Blk>:
  match bs:
    case []:
      None{}
    case +b <> rest:
      Bool.pick(Maybe<&2, sc.Blk>, sc.blk.runs(b), Some{b}, sc.running(rest))

def sc.toggle.v(bs: List<&2, sc.Blk>, +id: U32) -> Bool:
  match bs:
    case []:
      False{}
    case +b <> rest:
      U32.is_eq(sc.blk.id(b), id)

# the block of this id opened or folded (hit: the head is it)
def sc.toggle(bs: List<&2, sc.Blk>, hit: Bool, +id: U32, +w: U32, +home: String) -> List<&2, sc.Blk>:
  match bs hit:
    case Nil{} _:
      []
    case b <> +rest True{}:
      sc.blk.toggle(b, w, home) <> rest
    case +b <> +rest False{}:
      b <> sc.toggle(rest, sc.toggle.v(rest, id), id, w, home)

def sc.blk.closed(b: sc.Blk) -> Bool:
  match b:
    case sc.Blk{i, who, +k, +t, +r, o, ru, t0, bw, rs, n}:
      Bool.and(P.pp.foldable(k, t, r), Bool.not(o))

def sc.any.closed(bs: List<&2, sc.Blk>) -> Bool:
  match bs:
    case []:
      False{}
    case +b <> rest:
      Bool.or(sc.blk.closed(b), sc.any.closed(rest))

def sc.open.all(bs: List<&2, sc.Blk>, +o: Bool, +w: U32, +home: String) -> List<&2, sc.Blk>:
  match bs:
    case []:
      []
    case b <> rest:
      sc.blk.set.open(b, o, w, home) <> sc.open.all(rest, o, w, home)

# Drawing ------------------------------------------------------------------------
#
# The chat's rows are its blocks' rows, from the newest up: as many as the
# rows scrolled up plus the room there is, of which the top ones show. The
# blocks drawn on the way are kept drawn (a resize draws them anew as they
# are reached); off is held to what there is.

type sc.G is Data:
  sc.G{bs: List<&2, sc.Blk>, rows: List<&2, String>, ids: List<&2, U32>, k: U32}

def sc.g.bs(g: sc.G) -> List<&2, sc.Blk>:
  match g:
    case sc.G{b, r, i, k}:
      b

def sc.g.rows(g: sc.G) -> List<&2, String>:
  match g:
    case sc.G{b, r, i, k}:
      r

def sc.g.ids(g: sc.G) -> List<&2, U32>:
  match g:
    case sc.G{b, r, i, k}:
      i

def sc.g.k(g: sc.G) -> U32:
  match g:
    case sc.G{b, r, i, k}:
      k

def sc.g.with.bs(g: sc.G, +bs: List<&2, sc.Blk>) -> sc.G:
  match g:
    case sc.G{b, r, i, k}:
      sc.G{bs, r, i, k}

# a block's rows (bottom up) onto the rows (top down), while more are needed
def sc.take.rows(rs: List<&2, String>, more: Bool, +id: U32, +need: U32, +k: U32, +rows: List<&2, String>, +ids: List<&2, U32>) -> sc.G:
  match rs more:
    case r <> +rest True{}:
      +k2 = (k + 1 : U32)
      sc.take.rows(rest, U32.is_lt(k2, need), id, need, k2, r <> rows, id <> ids)
    case _ _:
      sc.G{[], rows, ids, k}

def sc.gather(bs: List<&2, sc.Blk>, more: Bool, +need: U32, +k: U32, +rows: List<&2, String>, +ids: List<&2, U32>, +w: U32, +home: String) -> sc.G:
  match bs more:
    case b <> +rest True{}:
      +b2 = sc.blk.fresh(b, w, home)
      +g = sc.take.rows(sc.blk.rows(b2), U32.is_lt(k, need), sc.blk.id(b2), need, k, rows, ids)
      +g2 = sc.gather(rest, U32.is_lt(sc.g.k(g), need), need, sc.g.k(g), sc.g.rows(g), sc.g.ids(g), w, home)
      sc.g.with.bs(g2, b2 <> sc.g.bs(g2))
    case +b <> +rest False{}:
      sc.G{b <> rest, rows, ids, k}
    case _ _:
      sc.G{[], rows, ids, k}

def sc.at(+r: U32) -> String:
  "\u{1B}[" ++ U32.show(r) ++ ";1H\u{1B}[2K"

# rows from screen row r down, n of them (the missing ones empty)
def sc.paint.rows(n: Nat, rs: List<&2, String>, +r: U32) -> List<&2, String>:
  match n rs:
    case 0n _:
      []
    case 1n+f Nil{}:
      sc.at(r) <> sc.paint.rows(f, [], (r + 1 : U32))
    case 1n+f x <> rest:
      (sc.at(r) ++ x) <> sc.paint.rows(f, rest, (r + 1 : U32))

def sc.rule(+w: U32, +off: U32) -> String:
  +say = "\u{2193} " ++ U32.show(off) ++ " rows below \u{b7} M-> or End follows"
  Bool.pick(String, U32.is_eq(off, 0), P.pp.paint("2", String.repeat("\u{2500}", U32.to_nat(w))),
    P.pp.paint("2", "\u{2500}\u{2500} ") ++ P.pp.paint("33", say) ++ P.pp.paint("2", " " ++ String.repeat("\u{2500}", U32.to_nat((w - U32.min(w, (P.pp.width(say) + 4 : U32)) : U32)))))

def sc.frames() -> List<&2, String>:
  ["\u{280b}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283c}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280f}"]

def sc.spin(+now: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, sc.frames(), Nat.mod(Nat.div(now, 100n), 10n)), "*")

def sc.two(+n: Nat) -> String:
  Bool.pick(String, Nat.is_lt(n, 10n), "0", "") ++ Nat.show(n)

# a time, as 12s, 3m 05s, 1h 02m
def sc.ago(+ms: Nat) -> String:
  +t = Nat.div(ms, 1000n)
  Bool.pick(String, Nat.is_lt(t, 60n), Nat.show(t) ++ "s",
    Bool.pick(String, Nat.is_lt(t, 3600n), Nat.show(Nat.div(t, 60n)) ++ "m " ++ sc.two(Nat.mod(t, 60n)) ++ "s",
      Nat.show(Nat.div(t, 3600n)) ++ "h " ++ sc.two(Nat.mod(Nat.div(t, 60n), 60n)) ++ "m"))

def sc.blk.text(b: sc.Blk) -> String:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      t

def sc.blk.t0(b: sc.Blk) -> Nat:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      t0

def sc.tool.now(m: Maybe<&2, sc.Blk>, +now: Nat, +home: String) -> String:
  match m:
    case Some{+b}:
      +name = P.pp.tool.name(sc.blk.text(b))
      " \u{b7} " ++ P.pp.paint("33", "\u{25b8} " ++ name) ++ " " ++ sc.ago(Nat.sub(now, sc.blk.t0(b))) ++ "  " ++ P.pp.paint("2", P.pp.clean(P.pp.summary(name, P.pp.tool.input(sc.blk.text(b)), home)))
    case None{}:
      ""

# what runs: Unii's turn and its time, its tool running, the agents at work
def sc.act(+s: sc.S) -> List<&2, String>:
  +st = sc.st(s)
  +run = sc.running(sc.blks(s))
  +ags = sc.st.agents(st)
  +busy = sc.st.busy(st)
  +now = sc.now(s)
  +what = Bool.pick(String, busy, sc.st.what(st) ++ " \u{b7} " ++ sc.ago(Nat.sub(now, sc.st.since(st))), "")
  +agents = Bool.pick(String, List.is_empty(&2, String, ags), "", Bool.pick(String, busy, " \u{b7} ", "") ++ String.join(ags, ", ") ++ " at work")
  Bool.pick(List<&2, String>, Bool.and(Bool.and(Bool.not(busy), List.is_empty(&2, String, ags)), Maybe.is_none(&2, sc.Blk, run)), [],
    [P.pp.sgr.cut(P.pp.paint("1;33", sc.spin(now)) ++ " " ++ what ++ agents ++ sc.tool.now(run, now, sc.home(s)), sc.w(s))])

def sc.first(+xs: List<&2, String>) -> String:
  P.pp.fit(P.pp.clean(Maybe.default(&2, String, List.get(&2, String, xs, 0n), "")), 48)

def sc.more(+xs: List<&2, String>) -> String:
  +n = List.length(&2, String, xs)
  Bool.pick(String, Nat.is_le(n, 1n), "", " +" ++ Nat.show(Nat.sub(n, 1n)) ++ " more")

# the messages waiting for Unii, and those its call has
def sc.queue(+s: sc.S) -> List<&2, String>:
  +st = sc.st(s)
  +wa = sc.st.wait(st)
  +se = sc.st.sent(st)
  +w = sc.w(s)
  List.append(&2, String,
    Bool.pick(List<&2, String>, List.is_empty(&2, String, wa), [],
      [P.pp.sgr.cut(P.pp.paint("33", "\u{29d7} " ++ Nat.show(List.length(&2, String, wa)) ++ " waiting: ") ++ "\u{ab}" ++ sc.first(wa) ++ "\u{bb}" ++ sc.more(wa) ++ P.pp.paint("2", " \u{b7} C-s sends now"), w)]),
    Bool.pick(List<&2, String>, List.is_empty(&2, String, se), [],
      [P.pp.sgr.cut(P.pp.paint("36", "\u{2192} handed to Unii: ") ++ "\u{ab}" ++ sc.first(se) ++ "\u{bb}" ++ sc.more(se) ++ P.pp.paint("2", " \u{b7} read after its running tool \u{b7} C-s cuts the tool"), w)]))

def sc.find.row(m: Maybe<&2, String>) -> List<&2, String>:
  match m:
    case Some{q}:
      [P.pp.paint("33", "reverse search: ") ++ q ++ P.pp.paint("2", "  (C-r older \u{b7} C-g back)")]
    case None{}:
      []

def sc.placeholder() -> String:
  "Enter sends \u{b7} Shift- or Alt-Enter: a new line \u{b7} C-s sends waiting now \u{b7} C-g stops Unii \u{b7} Esc Esc leaves"

# The lines under the chat, top down, and where the cursor is among them
type sc.Low is Data:
  sc.Low{rows: List<&2, String>, row: U32, col: U32}

def sc.low.rows(l: sc.Low) -> List<&2, String>:
  match l:
    case sc.Low{r, y, x}:
      r

def sc.low.row(l: sc.Low) -> U32:
  match l:
    case sc.Low{r, y, x}:
      y

def sc.low.col(l: sc.Low) -> U32:
  match l:
    case sc.Low{r, y, x}:
      x

def sc.prompt(rs: List<&2, String>, +first: Bool) -> List<&2, String>:
  match rs:
    case []:
      []
    case r <> rest:
      (Bool.pick(String, first, P.pp.paint("1;35", "\u{3bb}") ++ " ", "  ") ++ r) <> sc.prompt(rest, False{})

def sc.low(+s: sc.S) -> sc.Low:
  +w = sc.w(s)
  +e = sc.ed(s)
  +lay = D.ed.lay(e, (w - 2 : U32))
  +max = U32.max(1, U32.div(sc.h(s), 3))
  +n = U32.from_nat(List.length(&2, String, D.ed.lay.rows(lay)))
  +cy = D.ed.lay.row(lay)
  +top = Bool.pick(U32, U32.is_lt(cy, max), 0, ((cy - max : U32) + 1 : U32))
  +shown = List.take(&2, String, List.drop(&2, String, D.ed.lay.rows(lay), U32.to_nat(top)), U32.to_nat(max))
  +hint = sc.hint(s)
  +matches = D.ed.matches(e)
  +info = Bool.pick(List<&2, String>, Bool.not(String.is_empty(hint)), [P.pp.sgr.cut(P.pp.paint("2", hint), w)], sc.find.row(D.ed.find(e)))
  +line = sc.st.line(sc.st(s))
  +empty = D.ed.is.empty(e)
  +input = Bool.pick(List<&2, String>, empty, [P.pp.paint("2", P.pp.fit(sc.placeholder(), (w - 2 : U32)))], shown)
  +head = List.concat(&2, String, [[sc.rule(w, sc.off(s))], sc.act(s), sc.queue(s), info, [P.pp.sgr.cut(Bool.pick(String, String.is_empty(line), P.pp.paint("1;35", "\u{7121}\u{9650} mugen"), line), w)]])
  sc.Low{List.append(&2, String, head, sc.prompt(input, True{})), (U32.from_nat(List.length(&2, String, head)) + (cy - top : U32) : U32), (D.ed.lay.col(lay) + 2 : U32)}

def sc.cursor(+r: U32, +c: U32) -> String:
  "\u{1B}[" ++ U32.show(r) ++ ";" ++ U32.show((c + 1 : U32)) ++ "H"

def sc.with.drawn(+s: sc.S, +g: sc.G, +ids: List<&2, U32>, +off: U32, +low: U32) -> sc.S:
  +t = sc.tr(s)
  +m = sc.tm(s)
  sc.with.tm(sc.with.tr(s, sc.Tr{sc.g.bs(g), sc.tr.next(t), off, ids}), sc.Tm{sc.tm.w(m), sc.tm.h(m), 0, sc.tm.mouse(m), low})

# all of it
def sc.draw.all(+s: sc.S) -> IO(sc.S):
  +low = sc.low(s)
  +lrows = sc.low.rows(low)
  +nl = U32.from_nat(List.length(&2, String, lrows))
  +h = sc.h(s)
  +t = Bool.pick(U32, U32.is_gt(h, nl), (h - nl : U32), 0)
  +off = sc.off(s)
  +need = (off + t : U32)
  +g = sc.gather(sc.blks(s), U32.is_gt(need, 0), need, 0, [], [], sc.w(s), sc.home(s))
  +k = sc.g.k(g)
  +off2 = U32.min(off, (k - U32.min(k, t) : U32))
  +rows = List.take(&2, String, sc.g.rows(g), U32.to_nat(t))
  +ids = List.take(&2, U32, sc.g.ids(g), U32.to_nat(t))
  +out = String.concat(List.concat(&2, String, [["\u{1B}[?2026h\u{1B}[?25l"], sc.paint.rows(U32.to_nat(t), rows, 1), sc.paint.rows(U32.to_nat(nl), lrows, (t + 1 : U32)),
    [sc.cursor((t + (sc.low.row(low) + 1 : U32) : U32), sc.low.col(low)), "\u{1B}[?25h\u{1B}[?2026l"]]))
  IO.bind(Unit, sc.S, IO.write(out), u => IO.pure(sc.S, sc.with.drawn(s, g, ids, off2, nl)))

def sc.with.clean(+s: sc.S) -> sc.S:
  +m = sc.tm(s)
  sc.with.tm(s, sc.Tm{sc.tm.w(m), sc.tm.h(m), 0, sc.tm.mouse(m), sc.tm.low(m)})

# the lines under the chat only; all if their number changed
def sc.draw.low(+s: sc.S) -> IO(sc.S):
  +low = sc.low(s)
  +lrows = sc.low.rows(low)
  +nl = U32.from_nat(List.length(&2, String, lrows))
  +h = sc.h(s)
  +t = Bool.pick(U32, U32.is_gt(h, nl), (h - nl : U32), 0)
  +out = String.concat(List.concat(&2, String, [["\u{1B}[?2026h\u{1B}[?25l"], sc.paint.rows(U32.to_nat(nl), lrows, (t + 1 : U32)),
    [sc.cursor((t + (sc.low.row(low) + 1 : U32) : U32), sc.low.col(low)), "\u{1B}[?25h\u{1B}[?2026l"]]))
  Bool.pick(IO(sc.S), U32.is_eq(nl, sc.tm.low(sc.tm(s))), IO.bind(Unit, sc.S, IO.write(out), u => IO.pure(sc.S, sc.with.clean(s))), sc.draw.all(s))

def sc.draw.go(k: U32, +s: sc.S) -> IO(sc.S):
  match k:
    case 0:
      IO.pure(sc.S, s)
    case 1:
      sc.draw.low(s)
    case _:
      sc.draw.all(s)

def sc.draw(+s: sc.S) -> IO(sc.S):
  sc.draw.go(Bool.pick(U32, sc.u.done(sc.u(s)), 0, sc.tm.draw(sc.tm(s))), s)

# Entries ------------------------------------------------------------------------

def sc.tr.add(t: sc.Tr, +b: sc.Blk) -> sc.Tr:
  match t:
    case sc.Tr{bs, n, +o, i}:
      sc.Tr{List.take(&2, sc.Blk, b <> bs, 400n), (n + 1 : U32), Bool.pick(U32, U32.is_eq(o, 0), 0, (o + sc.blk.n(b) : U32)), i}

# a block more, at the chat's end (the view held where it is if scrolled up)
def sc.add(+s: sc.S, +who: String, +kind: String, +text: String, +run: Bool) -> sc.S:
  +b = sc.blk.new(sc.tr.next(sc.tr(s)), who, kind, text, run, sc.now(s), sc.w(s), sc.home(s))
  sc.dirty(sc.with.tr(s, sc.tr.add(sc.tr(s), b)), 2)

def sc.attached(m: Maybe<&2, List<&2, sc.Blk>>, +s: sc.S, +who: String, +kind: String, +text: String) -> sc.S:
  match m:
    case Some{+bs}:
      sc.dirty(sc.with.blks(s, bs), 2)
    case None{}:
      sc.add(s, who, kind, text, False{})

# 0 a bell, 1 a tool starts, 2 a call (its result follows), 3 a result, 4 any other
def sc.put.k(+kind: String) -> Nat:
  Bool.pick(Nat, String.eq(kind, "bell"), 0n, Bool.pick(Nat, String.eq(kind, "run"), 1n,
    Bool.pick(Nat, String.eq(kind, "tool"), 2n, Bool.pick(Nat, String.eq(kind, "echo"), 3n, 4n))))

def sc.put(k: Nat, +s: sc.S, +who: String, +kind: String, +text: String) -> IO(sc.S):
  match k:
    case 0n:
      IO.bind(Unit, sc.S, IO.write("\u{7}"), u => IO.pure(sc.S, s))
    case 1n:
      IO.pure(sc.S, sc.add(s, who, "tool", text, True{}))
    case 2n:
      IO.pure(sc.S, sc.attached(sc.attach(sc.blks(s), sc.attach.v(sc.blks(s), who, text), who, text, "", sc.w(s), sc.home(s)), s, who, "tool", text))
    case 3n:
      IO.pure(sc.S, sc.attached(sc.attach(sc.blks(s), sc.attach.v(sc.blks(s), who, ""), who, "", text, sc.w(s), sc.home(s)), s, who, "echo", text))
    case _:
      IO.pure(sc.S, sc.add(s, who, kind, text, False{}))

# History -------------------------------------------------------------------------
#
# $MUGEN_DIR/history: an entry a line, as rlwrap kept it; one of many lines
# (or starting with a quote) as a JSON string.

def sc.hist.of(m: Maybe<&2, J.Json>, +l: String) -> String:
  match m:
    case Some{J.JStr{s}}:
      s
    case _:
      l

def sc.hist.line(+l: String) -> String:
  Bool.pick(String, String.starts_with(l, "\""), sc.hist.of(J.js.read(l), l), l)

def sc.hist.lines(ls: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match ls:
    case []:
      acc
    case +l <> rest:
      sc.hist.lines(rest, Bool.pick(List<&2, String>, String.is_empty(l), acc, sc.hist.line(l) <> acc))

def sc.hist.got(r: Result<&1, &1, U32 & String, String>) -> List<&2, String>:
  match r:
    case Done{t}:
      List.take(&2, String, sc.hist.lines(String.lines(t), []), 2000n)
    case Fail{e}:
      []

def sc.hist.load(+path: String) -> IO(List<&2, String>):
  IO.bind(Result<&1, &1, U32 & String, String>, List<&2, String>, S.mu.read_file(path), r => IO.pure(List<&2, String>, sc.hist.got(r)))

def sc.hist.enc(+t: String) -> String:
  Bool.pick(String, Bool.or(String.contains(t, "\n"), String.starts_with(t, "\"")), J.js.write(J.JStr{t}), t)

# Keys --------------------------------------------------------------------------

def sc.send(+s: sc.S, +text: String) -> IO(Unit):
  E.ev.send(sc.hub(s), E.ev.Line{text})

# what the room for the chat is, about (for a page's scroll)
def sc.page(+s: sc.S) -> U32:
  +h = sc.h(s)
  +low = sc.tm.low(sc.tm(s))
  U32.max(1, Bool.pick(U32, U32.is_gt(h, (low + 2 : U32)), ((h - low : U32) - 2 : U32), 1))

def sc.scroll(+s: sc.S, +up: Bool, +n: U32) -> sc.S:
  +o = sc.off(s)
  sc.dirty(sc.with.off(s, Bool.pick(U32, up, Bool.pick(U32, U32.is_gt(o, (4294967295 - n : U32)), o, (o + n : U32)), (o - U32.min(o, n) : U32))), 2)

# leaving: asked of the hub, which says Bye once all is cut
def sc.quit(+s: sc.S) -> IO(sc.S):
  Bool.pick(IO(sc.S), sc.u.quit(sc.u(s)), IO.pure(sc.S, s),
    IO.bind(Unit, sc.S, sc.send(s, "/quit"), u => IO.pure(sc.S, sc.dirty(sc.with.hint(sc.with.quit(s), "leaving \u{2026}"), 1))))

def sc.edit(+s: sc.S, +key: K.ky.Key) -> sc.S:
  sc.dirty(sc.with.hint(sc.with.ed(s, D.ed.key(sc.ed(s), key)), ""), 1)

def sc.mouse.say(on: Bool) -> String:
  match on:
    case True{}:
      "\u{1B}[?1000h\u{1B}[?1006h"
    case False{}:
      "\u{1B}[?1006l\u{1B}[?1000l"

# /mouse: the mouse's reports off (the terminal selects text) or on
def sc.mouse(+s: sc.S) -> IO(sc.S):
  +m = sc.tm(s)
  +on = Bool.not(sc.tm.mouse(m))
  do IO<sc.S>:
    Unit <- IO.write(sc.mouse.say(on))
    return sc.dirty(sc.with.hint(sc.with.tm(s, sc.Tm{sc.tm.w(m), sc.tm.h(m), sc.tm.draw(m), on, sc.tm.low(m)}),
      Bool.pick(String, on, "the mouse scrolls and opens blocks (/mouse to select text instead)", "the terminal selects text now (/mouse for the mouse back)")), 1)

def sc.cmd.word(+t: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(String.trim(t), ' '), 0n), "")

# a message or a command, sent: shown, kept in the history, the chat followed
def sc.sent(+s: sc.S, +t: String) -> IO(sc.S):
  +cmd = String.starts_with(String.trim(t), "/")
  +s1 = sc.with.off(sc.with.hint(sc.with.ed(s, D.ed.sent(sc.ed(s))), ""), 0)
  do IO<sc.S>:
    Unit <- sc.send(s, t)
    a : Result<&1, &1, U32 & String, Nat> <- S.mu.append(sc.cf.hfile(sc.cf(s)), sc.hist.enc(t) ++ "\n", 0)
    return Bool.pick(sc.S, cmd, sc.add(s1, "", "say", "\u{203a} " ++ String.trim(t), False{}), sc.add(s1, "", "user", t, False{}))

# Enter: a "\" before the cursor at the text's end is a new line; an empty
# text, nothing; /mouse is the screen's; else sent
def sc.enter.k(+s: sc.S) -> Nat:
  +e = sc.ed(s)
  +t = D.ed.text(e)
  Bool.pick(Nat, Bool.and(String.is_empty(D.ed.post(e)), String.starts_with(D.ed.pre(e), "\\")), 0n,
    Bool.pick(Nat, String.is_empty(String.trim(t)), 1n, Bool.pick(Nat, String.eq(String.trim(t), "/mouse"), 2n, 3n)))

def sc.enter(k: Nat, +s: sc.S) -> IO(sc.S):
  match k:
    case 0n:
      +e = sc.ed(s)
      IO.pure(sc.S, sc.dirty(sc.with.ed(s, D.ed.with(e, "\n" ++ D.ed.tail(D.ed.pre(e)), "")), 1))
    case 1n:
      IO.pure(sc.S, s)
    case 2n:
      sc.mouse(sc.with.ed(s, D.ed.sent(sc.ed(s))))
    case _:
      sc.sent(s, D.ed.text(sc.ed(s)))

# C-c: the input cleared (C-y brings it back), or, empty, leaving
def sc.ctrl.c(+s: sc.S) -> IO(sc.S):
  +e = sc.ed(s)
  Bool.pick(IO(sc.S), D.ed.is.empty(e), sc.quit(s),
    IO.pure(sc.S, sc.dirty(sc.with.hint(sc.with.ed(s, D.ed.cut.with(e, "", "", D.ed.text(e))), "cleared (C-y brings it back) \u{b7} C-c again leaves"), 1)))

# Esc: twice within 0.8 s leaves
def sc.esc(+s: sc.S) -> IO(sc.S):
  +now = sc.now(s)
  +last = sc.u.esc(sc.u(s))
  Bool.pick(IO(sc.S), Bool.and(Nat.is_gt(last, 0n), Nat.is_le(Nat.sub(now, last), 800n)), sc.quit(s),
    IO.pure(sc.S, sc.dirty(sc.with.hint(sc.with.esc(s, now), "Esc again leaves mugen"), 1)))

def sc.tab(+s: sc.S) -> sc.S:
  +e = D.ed.complete(sc.ed(s))
  +ms = D.ed.matches(e)
  sc.dirty(sc.with.hint(sc.with.ed(s, e), Bool.pick(String, Nat.is_gt(List.length(&2, String, ms), 1n), String.join(ms, "  "), "")), 1)

def sc.blk.n.of(bs: List<&2, sc.Blk>, +id: U32) -> U32:
  match bs:
    case []:
      0
    case +b <> rest:
      Bool.pick(U32, U32.is_eq(sc.blk.id(b), id), sc.blk.n(b), sc.blk.n.of(rest, id))

def sc.newest(bs: List<&2, sc.Blk>) -> U32:
  match bs:
    case []:
      0
    case +b <> rest:
      sc.blk.id(b)

# a click on a block's row opens it, or folds it. Its header stays where it
# is on the screen (the rows scrolled up grow or shrink with it), unless it
# is the last block and the chat follows its end.
def sc.click(+s: sc.S, +y: U32) -> sc.S:
  +ids = sc.tr.ids(sc.tr(s))
  +m = List.get(&2, U32, ids, U32.to_nat((y - 1 : U32)))
  +id = Maybe.default(&2, U32, m, 0)
  +bs = sc.blks(s)
  +bs2 = sc.toggle(bs, sc.toggle.v(bs, id), id, sc.w(s), sc.home(s))
  +n0 = sc.blk.n.of(bs, id)
  +n1 = sc.blk.n.of(bs2, id)
  +o = sc.off(s)
  +follow = Bool.and(U32.is_eq(o, 0), U32.is_eq(sc.newest(bs), id))
  +o2 = Bool.pick(U32, follow, 0, Bool.pick(U32, U32.is_ge(n1, n0), (o + (n1 - n0 : U32) : U32), (o - U32.min(o, (n0 - n1 : U32)) : U32)))
  Bool.pick(sc.S, Bool.or(U32.is_eq(y, 0), Maybe.is_none(&2, U32, m)), s, sc.dirty(sc.with.off(sc.with.blks(s, bs2), o2), 2))

def sc.all(+s: sc.S) -> sc.S:
  +bs = sc.blks(s)
  sc.dirty(sc.with.blks(s, sc.open.all(bs, sc.any.closed(bs), sc.w(s), sc.home(s))), 2)

# what a key does: 0 an edit, 1 Enter, 2 C-c, 3 C-d, 4 C-g, 5 C-s, 6 C-o,
# 7 C-l, 8 Esc, 9 Tab, 10 PgUp, 11 PgDn, 12 M-<, 13 M-> or End on an empty
# input, 14 the wheel up, 15 down, 16 a click, 17 nothing. While searching,
# Enter, C-g and Esc are the search's.
def sc.key.k(key: K.ky.Key, +find: Bool, +empty: Bool) -> Nat:
  match key:
    case K.ky.Enter{}:
      Bool.pick(Nat, find, 0n, 1n)
    case K.ky.Ctrl{99}:
      2n
    case K.ky.Ctrl{100}:
      Bool.pick(Nat, empty, 3n, 0n)
    case K.ky.Ctrl{103}:
      Bool.pick(Nat, find, 0n, 4n)
    case K.ky.Ctrl{115}:
      5n
    case K.ky.Ctrl{111}:
      6n
    case K.ky.Ctrl{108}:
      7n
    case K.ky.Esc{}:
      Bool.pick(Nat, find, 0n, 8n)
    case K.ky.Tab{}:
      9n
    case K.ky.Nav{7, m}:
      10n
    case K.ky.Nav{8, m}:
      11n
    case K.ky.Meta{60}:
      12n
    case K.ky.Meta{62}:
      13n
    case K.ky.Nav{6, m}:
      Bool.pick(Nat, empty, 13n, 0n)
    case K.ky.Mouse{64, x, y, up}:
      14n
    case K.ky.Mouse{65, x, y, up}:
      15n
    case K.ky.Mouse{0, x, y, False{}}:
      16n
    case K.ky.Mouse{b, x, y, up}:
      17n
    case K.ky.Focus{on}:
      17n
    case K.ky.Other{}:
      17n
    case _:
      0n

def sc.mouse.y(key: K.ky.Key) -> U32:
  match key:
    case K.ky.Mouse{b, x, y, up}:
      y
    case _:
      0

def sc.key.go(k: Nat, +s: sc.S, +key: K.ky.Key) -> IO(sc.S):
  match k:
    case 0n:
      IO.pure(sc.S, sc.edit(s, key))
    case 1n:
      sc.enter(sc.enter.k(s), s)
    case 2n:
      sc.ctrl.c(s)
    case 3n:
      sc.quit(s)
    case 4n:
      IO.bind(Unit, sc.S, sc.send(s, "/stop"), u => IO.pure(sc.S, sc.dirty(sc.with.hint(s, ""), 1)))
    case 5n:
      IO.bind(Unit, sc.S, sc.send(s, "/now"), u => IO.pure(sc.S, sc.dirty(sc.with.hint(s, ""), 1)))
    case 6n:
      IO.pure(sc.S, sc.all(s))
    case 7n:
      IO.pure(sc.S, sc.dirty(s, 2))
    case 8n:
      sc.esc(s)
    case 9n:
      IO.pure(sc.S, sc.tab(s))
    case 10n:
      IO.pure(sc.S, sc.scroll(s, True{}, sc.page(s)))
    case 11n:
      IO.pure(sc.S, sc.scroll(s, False{}, sc.page(s)))
    case 12n:
      IO.pure(sc.S, sc.scroll(s, True{}, 4294967295))
    case 13n:
      IO.pure(sc.S, sc.dirty(sc.with.off(s, 0), 2))
    case 14n:
      IO.pure(sc.S, sc.scroll(s, True{}, 3))
    case 15n:
      IO.pure(sc.S, sc.scroll(s, False{}, 3))
    case 16n:
      IO.pure(sc.S, sc.click(s, sc.mouse.y(key)))
    case _:
      IO.pure(sc.S, s)

def sc.key(+s: sc.S, +key: K.ky.Key) -> IO(sc.S):
  +e = sc.ed(s)
  +s1 = Bool.pick(sc.S, Nat.is_eq(sc.key.k(key, Maybe.is_some(&2, String, D.ed.find(e)), D.ed.is.empty(e)), 8n), s, sc.with.esc(s, 0n))
  sc.key.go(sc.key.k(key, Maybe.is_some(&2, String, D.ed.find(e)), D.ed.is.empty(e)), s1, key)

# Events ------------------------------------------------------------------------

def sc.size(+s: sc.S, +ws: U32) -> sc.S:
  +m = sc.tm(s)
  +w = U32.max(20, U32.and(ws, 65535))
  +h = U32.max(6, U32.shrn(ws, 16n))
  Bool.pick(sc.S, Bool.or(U32.is_eq(ws, 0), Bool.and(U32.is_eq(w, sc.tm.w(m)), U32.is_eq(h, sc.tm.h(m)))), s,
    sc.with.tm(s, sc.Tm{w, h, 2, sc.tm.mouse(m), sc.tm.low(m)}))

# a tick: the size checked; the spinner and the times on, if anything runs
def sc.tick(+s: sc.S) -> IO(sc.S):
  do IO<sc.S>:
    now : Nat <- IO.now()
    ws : U32 <- S.mu.winsize()
    +s1 : sc.S = sc.size(sc.with.now(s, now), ws)
    +live : Bool = Bool.or(Bool.or(sc.st.busy(sc.st(s1)), Maybe.is_some(&2, sc.Blk, sc.running(sc.blks(s1)))), Bool.not(List.is_empty(&2, String, sc.st.agents(sc.st(s1)))))
    return Bool.pick(sc.S, live, sc.dirty(s1, 1), s1)

# the hub leaves: the terminal as it was, the hub told
def sc.bye(+s: sc.S, +done: Chan(Unit)) -> IO(sc.S):
  do IO<sc.S>:
    r : U32 <- S.mu.raw(0, sc.back())
    Unit <- Chan.close(sc.In, sc.cf.me(sc.cf(s)))
    x : Result<&1, &1, Unit, Unit> <- Chan.send(Unit, done, Unit{})
    return sc.with.done(s)

def sc.on(+s: sc.S, m: Maybe<&1, sc.In>) -> IO(sc.S):
  match m:
    case None{}:
      IO.pure(sc.S, sc.with.done(s))
    case Some{sc.Key{+key, +at}}:
      sc.key(sc.with.now(s, at), key)
    case Some{sc.Put{+who, +kind, +text}}:
      sc.put(sc.put.k(kind), s, who, kind, text)
    case Some{sc.State{+st}}:
      IO.pure(sc.S, sc.dirty(sc.with.st(s, st), 1))
    case Some{sc.Tick{}}:
      sc.tick(s)
    case Some{sc.Eof{}}:
      sc.quit(s)
    case Some{sc.Bye{+done}}:
      sc.bye(s, done)

# what more came meanwhile, taken before drawing
def sc.drain(n: Nat, p: Poll<&1, &1, Maybe<&1, sc.In>, Unit>, +s: sc.S) -> IO(sc.S):
  match n p:
    case 1n+f Ready{Some{+x}}:
      do IO<sc.S>:
        +s1 : sc.S <- sc.on(s, Some{x})
        p2 : Poll<&1, &1, Maybe<&1, sc.In>, Unit> <- Bool.pick(IO(Poll<&1, &1, Maybe<&1, sc.In>, Unit>), sc.u.done(sc.u(s1)), IO.pure(Poll<&1, &1, Maybe<&1, sc.In>, Unit>, Wait{Unit{}}), Chan.try_recv(sc.In, sc.cf.me(sc.cf(s1)), 0))
        sc.drain(f, p2, s1)
    case _ _:
      IO.pure(sc.S, s)

def sc.loop(n: Nat, go: Bool, +s: sc.S) -> IO(Unit):
  match n go:
    case 1n+f True{}:
      do IO<Unit>:
        m : Maybe<&1, sc.In> <- Chan.recv(sc.In, sc.cf.me(sc.cf(s)))
        +s1 : sc.S <- sc.on(s, m)
        p : Poll<&1, &1, Maybe<&1, sc.In>, Unit> <- Bool.pick(IO(Poll<&1, &1, Maybe<&1, sc.In>, Unit>), sc.u.done(sc.u(s1)), IO.pure(Poll<&1, &1, Maybe<&1, sc.In>, Unit>, Wait{Unit{}}), Chan.try_recv(sc.In, sc.cf.me(sc.cf(s1)), 0))
        +s2 : sc.S <- sc.drain(256n, p, s1)
        +s3 : sc.S <- sc.draw(s2)
        sc.loop(f, Bool.not(sc.u.done(sc.u(s3))), s3)
    case _ _:
      IO.pure(Unit, Unit{})

# Reading the keys ---------------------------------------------------------------

def sc.keys(ks: List<&2, K.ky.Key>, +at: Nat, +me: Chan(sc.In)) -> IO(Unit):
  match ks:
    case []:
      IO.pure(Unit, Unit{})
    case k <> rest:
      IO.bind(Result<&1, &1, sc.In, Unit>, Unit, Chan.send(sc.In, me, sc.Key{k, at}), r => sc.keys(rest, at, me))

def sc.read(fuel: Nat, +me: Chan(sc.In), st: K.ky.St, r: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match fuel r:
    case 1n+f Tuple{file, Done{SCon{h, t}}}:
      +o = K.ky.feed(st, SCon{h, t})
      do IO<Unit>:
        now : Nat <- IO.now()
        Unit <- sc.keys(K.ky.out.keys(o), now, me)
        r2 : File & Result<&1, &1, U32 & String, String> <- File.read(file, 65536)
        sc.read(f, me, K.ky.out.st(o), r2)
    case _ Tuple{file, _}:
      do IO<Unit>:
        x : Result<&1, &1, sc.In, Unit> <- Chan.send(sc.In, me, sc.Eof{})
        File.close(file)

def sc.reader.got(+me: Chan(sc.In), r: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match r:
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(file, 65536), r2 => sc.read(sc.fuel(), me, K.ky.start(), r2))
    case Fail{e}:
      IO.bind(Result<&1, &1, sc.In, Unit>, Unit, Chan.send(sc.In, me, sc.Eof{}), x => IO.pure(Unit, Unit{}))

def sc.reader(+me: Chan(sc.In)) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open("/dev/stdin", "r"), r => sc.reader.got(me, r))

# five ticks a second, till the screen closes its inbox
def sc.ticker(n: Nat, +me: Chan(sc.In), r: Result<&1, &1, sc.In, Unit>) -> IO(Unit):
  match n r:
    case 1n+f Done{u}:
      do IO<Unit>:
        Unit <- IO.sleep(200)
        r2 : Result<&1, &1, sc.In, Unit> <- Chan.send(sc.In, me, sc.Tick{})
        sc.ticker(f, me, r2)
    case _ _:
      IO.pure(Unit, Unit{})

# Starting -----------------------------------------------------------------------

# the screen, run till the hub says Bye: hub its inbox, me ours, home (~ in
# paths), the history's file
def sc.run(+hub: Chan(E.ev.Ev), +me: Chan(sc.In), +home: String, +hfile: String) -> IO(Unit):
  do IO<Unit>:
    r : U32 <- S.mu.raw(1, sc.back())
    Unit <- IO.write(sc.init())
    ws : U32 <- S.mu.winsize()
    hist : List<&2, String> <- sc.hist.load(hfile)
    now : Nat <- IO.now()
    +s0 : sc.S = sc.size(sc.S{sc.Cf{hub, me, home, hfile}, D.ed.new(hist), sc.Tr{[], 1, 0, []}, sc.Tm{80, 24, 2, True{}, 0}, sc.idle(), sc.U{now, 0n, "", False{}, False{}}}, ws)
    Unit <- IO.spawn(Unit, sc.reader(me))
    Unit <- IO.spawn(Unit, sc.ticker(sc.fuel(), me, Done{Unit{}}))
    +s1 : sc.S <- sc.draw(sc.dirty(s0, 2))
    sc.loop(sc.fuel(), True{}, s1)

# what the hub says (sent, whatever came of it)
def sc.tell(+me: Chan(sc.In), +x: sc.In) -> IO(Unit):
  IO.bind(Result<&1, &1, sc.In, Unit>, Unit, Chan.send(sc.In, me, x), r => IO.pure(Unit, Unit{}))
