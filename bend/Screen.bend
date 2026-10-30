
import Base
import ./Sys.bend as S
import ./Json.bend as J
import ./Ev.bend as E
import ./Keys.bend as K
import ./Edit.bend as D
import ./Pretty.bend as P
import ./Pic.bend as Pc
import ./Spell.bend as Sp
import ./Store.bend as St

# Screen: mugen on a terminal, full screen. One computation owns the
# terminal: it reads the keys (raw mode), draws the chat, and sends the
# hub (Hub.bend) the lines typed; the hub tells it what to show (sc.Put, as
# it logs) and how it is (sc.State: mugen's work, the messages waiting, the
# status line). Top down: the chat, scrolled with PgUp, PgDn and the wheel
# (Home and End on an empty input: its top and end; M-Up and M-Down: from
# one of mugen's answers to the next, see Answers), each tool call one
# block, open (a click folds or opens it, M-o all; a drag selects text and
# copies it, see Selecting); then a rule, what runs (with a spinner and its
# time), the messages waiting for mugen, the status line, and the input
# (Edit.bend) after the lambda, spellchecked (Spell.bend; see The
# spellcheck).
#
# Keys: Enter sends; Shift-, Alt-, Ctrl-Enter or C-j make a new line (so
# does a "\" ending the text); C-s sends the waiting messages now (Hub's
# /now); C-g stops mugen's turn; Shift-Tab switches plan and auto mode;
# Esc twice, C-c on an empty input or C-d leave. The terminal comes back as it was on every way out, a signal's
# too (Sys.bend mu.raw).
#
# Every def is prefixed `sc.` (a program's defs share one namespace).

def sc.fuel() -> Nat:
  U32.to_nat(4294967295)

def sc.csi() -> String:
  "\u{1B}["

# the alternate screen, no wrap at the margin, the mouse (SGR reports, its
# moves too: the spellcheck's box opens where it points),
# bracketed paste, modifyOtherKeys and kitty's disambiguated keys (each a
# way for Shift-Enter to be told from Enter)
def sc.init() -> String:
  "\u{1B}[?1049h\u{1B}[?7l\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1003h\u{1B}[?1006h\u{1B}[?2004h\u{1B}[>4;1m\u{1B}[>1u\u{1B}[H\u{1B}[2J"

def sc.back() -> String:
  "\u{1B}[<u\u{1B}[>4;0m\u{1B}[?2004l\u{1B}[?1006l\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?7h\u{1B}[?25h\u{1B}[?1049l"

# Types --------------------------------------------------------------------------

# A block of the chat: its id, who ("" mugen's), its kind, text, a tool
# call's result ("" none yet), open (unfolded), whether its tool runs and
# since when; its rows, bottom up, as drawn at width w (0: not yet), and how
# many they are
type sc.Blk is Data:
  sc.Blk{id: U32, who: String, kind: String, text: String, res: String, open: Bool, run: Bool, t0: Nat, w: U32, rows: List<&2, String>, n: U32}

# How the hub is: whether mugen works and at what since when; the messages
# waiting for it, and those handed to its running call (each a line);
# the status line (SGR in it); the agents at work
type sc.St is Data:
  sc.St{busy: Bool, what: String, since: Nat, wait: List<&2, String>, sent: List<&2, String>, line: String, agents: List<&2, String>, plan: Bool}

# what the screen hears: a key (and when, IO.now), an entry to show, the
# hub's state, a tick (5 a second), stdin's end, and the hub leaving (the
# terminal given back, then `done` told); a message taken back from the
# queue; hunspell's answer about the words asked (Spell.bend); the first of
# the log's messages the chat opened with (Since), and older messages read
# from the log for M-Up (Old: the user's, mugen's answers, the agents'
# reports, the oldest first, from message `from` up to `before`)
type sc.OldM is Data:
  sc.OldM{kind: String, text: String}

type sc.In is Data:
  sc.Key{key: K.ky.Key, at: Nat}
  sc.Put{who: String, kind: String, text: String}
  sc.State{st: sc.St}
  sc.Tick{}
  sc.Eof{}
  sc.Bye{done: Chan(Unit)}
  sc.Back{text: String}
  sc.Spelt{words: List<&2, String>, out: S.mu.Out}
  sc.Since{from: U32}
  sc.Old{before: U32, from: U32, ms: List<&2, sc.OldM>}

# what never changes: the hub's inbox, our own, home (~ in paths), the
# history's file
type sc.Cf is Data:
  sc.Cf{hub: Chan(E.ev.Ev), me: Chan(sc.In), home: String, hfile: String}

# where the chat's top row was when last drawn: its block's id (0 none),
# the row's place in that block (from the block's top), and the rows
# scrolled up then. While those are still the rows scrolled up, the view
# is held on that row: what comes below (a block more, a result under its
# call) never moves what is being read.
type sc.An is Data:
  sc.An{id: U32, row: U32, off: U32}

# the chat: its blocks (newest first; the last 400, and before them the
# messages and answers only, sc.keep), the next id, the rows scrolled up
# from its end, the ids of the blocks on its rows as drawn (top down), and
# where its top row was; the agent whose tab shows ("" none) and its
# blocks, all of its log's (Store.bend st.agent) and those since; the
# first of the log's messages the chat has (0: all, or none sent)
type sc.Tr is Data:
  sc.Tr{blks: List<&2, sc.Blk>, next: U32, off: U32, ids: List<&2, U32>, an: sc.An, ag: String, abs: List<&2, sc.Blk>, old: U32}

# the terminal: its columns and rows, what to draw (0 nothing, 1 the lines
# under the chat, 2 all), the mouse's reports on, the rows under the chat as
# last drawn
type sc.Tm is Data:
  sc.Tm{w: U32, h: U32, draw: U32, mouse: Bool, low: U32}

# the moment: now (IO.now), the last Esc (0 none), a word for the user
# under the chat, leaving asked, the terminal given back, whose blocks the
# chat shows ("" all, "mugen" its own, else an agent's name)
type sc.U is Data:
  sc.U{now: Nat, esc: Nat, hint: String, quit: Bool, done: Bool, focus: String}

# a selection by the mouse: on (the left button is down), moved (dragged),
# where it began and where it is (column, row; from 1), and the chat's rows
# as last drawn (top down, SGR in them), whose text it takes
type sc.Sel is Data:
  sc.Sel{on: Bool, moved: Bool, x0: U32, y0: U32, x1: U32, y1: U32, rows: List<&2, String>, pin: U32}

# a selection's ends in reading order (column, row of each)
type sc.Ends is Data:
  sc.Ends{xa: U32, ya: U32, xb: U32, yb: U32}

# a row cut in three: before the selection, inside, after
type sc.Three is Data:
  sc.Three{a: String, b: String, c: String}

type sc.S is Data:
  sc.S{cf: sc.Cf, ed: D.ed.Ed, tr: sc.Tr, tm: sc.Tm, st: sc.St, u: sc.U, z: sc.Sel, k: Sp.sp.Sp}

def sc.idle() -> sc.St:
  sc.St{False{}, "", 0n, [], [], "", [], False{}}

# Fields -------------------------------------------------------------------------

def sc.cf(s: sc.S) -> sc.Cf:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      c

def sc.ed(s: sc.S) -> D.ed.Ed:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      e

def sc.tr(s: sc.S) -> sc.Tr:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      t

def sc.tm(s: sc.S) -> sc.Tm:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      m

def sc.st(s: sc.S) -> sc.St:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      st

def sc.u(s: sc.S) -> sc.U:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      u

def sc.with.ed(s: sc.S, +e2: D.ed.Ed) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      sc.S{c, e2, t, m, st, u, z, k}

def sc.with.tr(s: sc.S, +t2: sc.Tr) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      sc.S{c, e, t2, m, st, u, z, k}

def sc.with.tm(s: sc.S, +m2: sc.Tm) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      sc.S{c, e, t, m2, st, u, z, k}

def sc.with.st(s: sc.S, +st2: sc.St) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      sc.S{c, e, t, m, st2, u, z, k}

def sc.with.u(s: sc.S, +u2: sc.U) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      sc.S{c, e, t, m, st, u2, z, k}

def sc.z(s: sc.S) -> sc.Sel:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      z

def sc.with.z(s: sc.S, +z2: sc.Sel) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      sc.S{c, e, t, m, st, u, z2, k}

# the spellcheck's state (Spell.bend)
def sc.sp(s: sc.S) -> Sp.sp.Sp:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      k

def sc.with.sp(s: sc.S, +k2: Sp.sp.Sp) -> sc.S:
  match s:
    case sc.S{c, e, t, m, st, u, z, k}:
      sc.S{c, e, t, m, st, u, z, k2}

def sc.sel.none(+rows: List<&2, String>) -> sc.Sel:
  sc.Sel{False{}, False{}, 0, 0, 0, 0, rows, 0}

def sc.sel.on(z: sc.Sel) -> Bool:
  match z:
    case sc.Sel{on, mv, x0, y0, x1, y1, rs, pn}:
      on

def sc.sel.moved(z: sc.Sel) -> Bool:
  match z:
    case sc.Sel{on, mv, x0, y0, x1, y1, rs, pn}:
      mv

def sc.sel.rows(z: sc.Sel) -> List<&2, String>:
  match z:
    case sc.Sel{on, mv, x0, y0, x1, y1, rs, pn}:
      rs

# the selection's ends in reading order: the first's column and row, the
# last's (a drag up or left swaps them)
def sc.sel.ends(z: sc.Sel) -> sc.Ends:
  match z:
    case sc.Sel{on, mv, +x0, +y0, +x1, +y1, rs, pn}:
      +back = Bool.or(U32.is_lt(y1, y0), Bool.and(U32.is_eq(y1, y0), U32.is_lt(x1, x0)))
      sc.Ends{Bool.pick(U32, back, x1, x0), Bool.pick(U32, back, y1, y0), Bool.pick(U32, back, x0, x1), Bool.pick(U32, back, y0, y1)}

# a press: a selection begins where it is
def sc.sel.press(z: sc.Sel, +x: U32, +y: U32) -> sc.Sel:
  match z:
    case sc.Sel{on, mv, x0, y0, x1, y1, rs, pn}:
      sc.Sel{True{}, False{}, x, y, x, y, rs, pn}

# a drag: the selection reaches where the mouse is
def sc.sel.drag(z: sc.Sel, +x: U32, +y: U32) -> sc.Sel:
  match z:
    case sc.Sel{on, mv, x0, y0, x1, y1, rs, pn}:
      sc.Sel{on, True{}, x0, y0, x, y, rs, pn}

# the chat's rows and the prompt pinned on top (0 none), as drawn now
def sc.sel.with.drawn(z: sc.Sel, +rows: List<&2, String>, +pin: U32) -> sc.Sel:
  match z:
    case sc.Sel{on, mv, x0, y0, x1, y1, rs, pn}:
      sc.Sel{on, mv, x0, y0, x1, y1, rows, pin}

def sc.sel.pin(z: sc.Sel) -> U32:
  match z:
    case sc.Sel{on, mv, x0, y0, x1, y1, rs, pn}:
      pn

# the selection over, what is drawn kept
def sc.sel.off(z: sc.Sel) -> sc.Sel:
  match z:
    case sc.Sel{on, mv, x0, y0, x1, y1, rs, pn}:
      sc.Sel{False{}, False{}, 0, 0, 0, 0, rs, pn}

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
    case sc.Tr{b, n, o, i, a, g, x, d}:
      b

def sc.tr.next(t: sc.Tr) -> U32:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      n

def sc.tr.off(t: sc.Tr) -> U32:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      o

def sc.tr.ids(t: sc.Tr) -> List<&2, U32>:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      i

def sc.tr.an(t: sc.Tr) -> sc.An:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      a

def sc.tr.ag(t: sc.Tr) -> String:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      g

def sc.tr.abs(t: sc.Tr) -> List<&2, sc.Blk>:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      x

def sc.tr.old(t: sc.Tr) -> U32:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      d

def sc.tr.with.old(t: sc.Tr, +d2: U32) -> sc.Tr:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      sc.Tr{b, n, o, i, a, g, x, d2}

# the agent whose log is loaded, and its blocks
def sc.tr.with.ag(t: sc.Tr, +g2: String, +x2: List<&2, sc.Blk>) -> sc.Tr:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      sc.Tr{b, n, o, i, a, g2, x2, d}

# the next id, past k taken
def sc.tr.took(t: sc.Tr, +k: U32) -> sc.Tr:
  match t:
    case sc.Tr{b, n, o, i, a, g, x, d}:
      sc.Tr{b, (n + k : U32), o, i, a, g, x, d}

def sc.an.id(a: sc.An) -> U32:
  match a:
    case sc.An{i, r, o}:
      i

def sc.an.row(a: sc.An) -> U32:
  match a:
    case sc.An{i, r, o}:
      r

def sc.an.off(a: sc.An) -> U32:
  match a:
    case sc.An{i, r, o}:
      o

# a block more at the end, while scrolled up (o > 0): the rows scrolled up
# grow by its k rows, and so do those the top row was drawn at
def sc.an.bump(a: sc.An, +o: U32, +k: U32) -> sc.An:
  match a:
    case sc.An{i, r, +ao}:
      sc.An{i, r, Bool.pick(U32, U32.is_eq(o, 0), ao, (ao + k : U32))}

def sc.blks(+s: sc.S) -> List<&2, sc.Blk>:
  sc.tr.blks(sc.tr(s))

def sc.off(+s: sc.S) -> U32:
  sc.tr.off(sc.tr(s))

def sc.with.blks(+s: sc.S, +bs: List<&2, sc.Blk>) -> sc.S:
  +t = sc.tr(s)
  sc.with.tr(s, sc.Tr{bs, sc.tr.next(t), sc.tr.off(t), sc.tr.ids(t), sc.tr.an(t), sc.tr.ag(t), sc.tr.abs(t), sc.tr.old(t)})

def sc.with.off(+s: sc.S, +o: U32) -> sc.S:
  +t = sc.tr(s)
  sc.with.tr(s, sc.Tr{sc.tr.blks(t), sc.tr.next(t), o, sc.tr.ids(t), sc.tr.an(t), sc.tr.ag(t), sc.tr.abs(t), sc.tr.old(t)})

def sc.u.focus(u: sc.U) -> String:
  match u:
    case sc.U{n, e, h, q, d, f}:
      f

def sc.focus(+s: sc.S) -> String:
  sc.u.focus(sc.u(s))

# whether the chat shows the loaded agent's tab (its whole log)
def sc.ag.on(+s: sc.S) -> Bool:
  +f = sc.focus(s)
  Bool.and(Bool.not(Bool.or(String.is_empty(f), String.eq(f, "mugen"))), String.eq(f, sc.tr.ag(sc.tr(s))))

# the blocks the chat shows: the loaded agent's on its tab, else the chat's
def sc.vw(+s: sc.S) -> List<&2, sc.Blk>:
  +t = sc.tr(s)
  Bool.pick(List<&2, sc.Blk>, sc.ag.on(s), sc.tr.abs(t), sc.tr.blks(t))

def sc.with.vw.go(on: Bool, +s: sc.S, +bs: List<&2, sc.Blk>) -> sc.S:
  match on:
    case True{}:
      +t = sc.tr(s)
      sc.with.tr(s, sc.tr.with.ag(t, sc.tr.ag(t), bs))
    case False{}:
      sc.with.blks(s, bs)

def sc.with.vw(+s: sc.S, +bs: List<&2, sc.Blk>) -> sc.S:
  sc.with.vw.go(sc.ag.on(s), s, bs)

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
    case sc.U{n, e, h, q, d, f}:
      n

def sc.u.esc(u: sc.U) -> Nat:
  match u:
    case sc.U{n, e, h, q, d, f}:
      e

def sc.u.hint(u: sc.U) -> String:
  match u:
    case sc.U{n, e, h, q, d, f}:
      h

def sc.u.quit(u: sc.U) -> Bool:
  match u:
    case sc.U{n, e, h, q, d, f}:
      q

def sc.u.done(u: sc.U) -> Bool:
  match u:
    case sc.U{n, e, h, q, d, f}:
      d

def sc.now(+s: sc.S) -> Nat:
  sc.u.now(sc.u(s))

def sc.hint(+s: sc.S) -> String:
  sc.u.hint(sc.u(s))

def sc.with.now(+s: sc.S, +n2: Nat) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{n2, sc.u.esc(u), sc.u.hint(u), sc.u.quit(u), sc.u.done(u), sc.u.focus(u)})

def sc.with.esc(+s: sc.S, +e2: Nat) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{sc.u.now(u), e2, sc.u.hint(u), sc.u.quit(u), sc.u.done(u), sc.u.focus(u)})

def sc.with.hint(+s: sc.S, +h2: String) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{sc.u.now(u), sc.u.esc(u), h2, sc.u.quit(u), sc.u.done(u), sc.u.focus(u)})

def sc.with.quit(+s: sc.S) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{sc.u.now(u), sc.u.esc(u), sc.u.hint(u), True{}, sc.u.done(u), sc.u.focus(u)})

def sc.with.done(+s: sc.S) -> sc.S:
  +u = sc.u(s)
  sc.with.u(s, sc.U{sc.u.now(u), sc.u.esc(u), sc.u.hint(u), sc.u.quit(u), True{}, sc.u.focus(u)})

# Views ----------------------------------------------------------------------------
#
# The chat shows every block (focus "": all), or mugen's own ("mugen"), or
# one agent's (its name). Once agents work, tabs follow the status line:
# all, mugen, each agent at work (and the one in view); a click on one, or
# M-Left / M-Right, switches to it, at the chat's end.

def sc.blk.who(b: sc.Blk) -> String:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      who

def sc.shows(+focus: String, +who: String) -> Bool:
  Bool.or(String.is_empty(focus), String.eq(Bool.pick(String, String.is_empty(who), "mugen", who), focus))

# whether the chat shows the first block
def sc.shows.head(bs: List<&2, sc.Blk>, +focus: String) -> Bool:
  match bs:
    case []:
      True{}
    case +b <> rest:
      sc.shows(focus, sc.blk.who(b))

def sc.has(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case []:
      False{}
    case +y <> rest:
      Bool.or(String.eq(x, y), sc.has(rest, x))

def sc.tab.of(+focus: String) -> String:
  Bool.pick(String, String.is_empty(focus), "all", focus)

# the tabs: none while no agent works and the chat shows all, or mugen's own
def sc.tabs(+ags: List<&2, String>, +focus: String) -> List<&2, String>:
  +mine = Bool.or(String.is_empty(focus), String.eq(focus, "mugen"))
  +extra = Bool.pick(List<&2, String>, Bool.or(mine, sc.has(ags, focus)), [], [focus])
  +all = List.concat(&2, String, [["all", "mugen"], ags, extra])
  Bool.pick(List<&2, String>, Bool.and(List.is_empty(&2, String, ags), List.is_empty(&2, String, extra)), Bool.pick(List<&2, String>, String.is_empty(focus), [], all), all)

def sc.tab.paint(+t: String, +on: Bool, +ags: List<&2, String>) -> String:
  +dot = Bool.pick(String, sc.has(ags, t), " \u{25cf}", "")
  Bool.pick(String, on, P.pp.paint("1;7", " " ++ t ++ dot ++ " "), P.pp.paint("2", " " ++ t ++ dot ++ " "))

def sc.tabs.paint(ts: List<&2, String>, +focus: String, +ags: List<&2, String>) -> String:
  match ts:
    case []:
      ""
    case +t <> rest:
      sc.tab.paint(t, String.eq(t, sc.tab.of(focus)), ags) ++ sc.tabs.paint(rest, focus, ags)

# a tab's width on the screen
def sc.tab.w(+t: String, +ags: List<&2, String>) -> U32:
  (U32.from_nat(String.length(t)) + Bool.pick(U32, sc.has(ags, t), 4, 2) : U32)

# the tab at column x (from 0, past the status line): "" none
def sc.tab.at(ts: List<&2, String>, +x: U32, +ags: List<&2, String>) -> Maybe<&2, String>:
  match ts:
    case []:
      None{}
    case +t <> rest:
      +tw = sc.tab.w(t, ags)
      Bool.pick(Maybe<&2, String>, U32.is_lt(x, tw), Some{t}, sc.tab.at(rest, (x - tw : U32), ags))

def sc.tab.index(ts: List<&2, String>, +t: String, +i: Nat) -> Nat:
  match ts:
    case []:
      0n
    case +y <> rest:
      Bool.pick(Nat, String.eq(y, t), i, sc.tab.index(rest, t, Nat.add(i, 1n)))

# the chat on tab t, at its end
def sc.with.focus(+s: sc.S, +t: String) -> sc.S:
  +u = sc.u(s)
  +f = Bool.pick(String, String.eq(t, "all"), "", t)
  sc.dirty(sc.with.off(sc.with.u(s, sc.U{sc.u.now(u), sc.u.esc(u), "", sc.u.quit(u), sc.u.done(u), f}), 0), 2)

def sc.st.busy(t: sc.St) -> Bool:
  match t:
    case sc.St{b, w, si, wa, se, l, a, pl}:
      b

def sc.st.what(t: sc.St) -> String:
  match t:
    case sc.St{b, w, si, wa, se, l, a, pl}:
      w

def sc.st.since(t: sc.St) -> Nat:
  match t:
    case sc.St{b, w, si, wa, se, l, a, pl}:
      si

def sc.st.wait(t: sc.St) -> List<&2, String>:
  match t:
    case sc.St{b, w, si, wa, se, l, a, pl}:
      wa

def sc.st.sent(t: sc.St) -> List<&2, String>:
  match t:
    case sc.St{b, w, si, wa, se, l, a, pl}:
      se

def sc.st.line(t: sc.St) -> String:
  match t:
    case sc.St{b, w, si, wa, se, l, a, pl}:
      l

def sc.st.agents(t: sc.St) -> List<&2, String>:
  match t:
    case sc.St{b, w, si, wa, se, l, a, pl}:
      a

# whether mugen is in plan mode (Hub's /plan), else auto
def sc.st.plan(t: sc.St) -> Bool:
  match t:
    case sc.St{b, w, si, wa, se, l, a, pl}:
      pl

def sc.st.with.plan(t: sc.St, +p2: Bool) -> sc.St:
  match t:
    case sc.St{b, w, si, wa, se, l, a, pl}:
      sc.St{b, w, si, wa, se, l, a, p2}

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
  sc.blk.draw(sc.Blk{id, who, kind, text, "", True{}, run, now, 0, [], 0}, w, home)

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

# the newest running call of mugen's: its text and since when
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

def sc.gather(bs: List<&2, sc.Blk>, more: Bool, show: Bool, +need: U32, +k: U32, +rows: List<&2, String>, +ids: List<&2, U32>, +w: U32, +home: String, +focus: String) -> sc.G:
  match bs more show:
    case b <> +rest True{} True{}:
      +b2 = sc.blk.fresh(b, w, home)
      +g = sc.take.rows(sc.blk.rows(b2), U32.is_lt(k, need), sc.blk.id(b2), need, k, rows, ids)
      +g2 = sc.gather(rest, U32.is_lt(sc.g.k(g), need), sc.shows.head(rest, focus), need, sc.g.k(g), sc.g.rows(g), sc.g.ids(g), w, home, focus)
      sc.g.with.bs(g2, b2 <> sc.g.bs(g2))
    case b <> +rest True{} False{}:
      +g2 = sc.gather(rest, True{}, sc.shows.head(rest, focus), need, k, rows, ids, w, home, focus)
      sc.g.with.bs(g2, b <> sc.g.bs(g2))
    case +b <> +rest False{} _:
      sc.G{b <> rest, rows, ids, k}
    case _ _ _:
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

# what runs: mugen's turn and its time, its tool running, the agents at work
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

# the messages waiting for mugen, and those its call has
def sc.queue(+s: sc.S) -> List<&2, String>:
  +st = sc.st(s)
  +wa = sc.st.wait(st)
  +se = sc.st.sent(st)
  +w = sc.w(s)
  List.append(&2, String,
    Bool.pick(List<&2, String>, List.is_empty(&2, String, wa), [],
      [P.pp.sgr.cut(P.pp.paint("33", "\u{29d7} " ++ Nat.show(List.length(&2, String, wa)) ++ " waiting: ") ++ "\u{ab}" ++ sc.first(wa) ++ "\u{bb}" ++ sc.more(wa) ++ P.pp.paint("2", " \u{b7} Up edits \u{b7} C-s sends now"), w)]),
    Bool.pick(List<&2, String>, List.is_empty(&2, String, se), [],
      [P.pp.sgr.cut(P.pp.paint("36", "\u{2192} handed to mugen: ") ++ "\u{ab}" ++ sc.first(se) ++ "\u{bb}" ++ sc.more(se) ++ P.pp.paint("2", " \u{b7} read after its running tool \u{b7} C-s cuts the tool"), w)]))

def sc.find.row(m: Maybe<&2, String>) -> List<&2, String>:
  match m:
    case Some{q}:
      [P.pp.paint("33", "reverse search: ") ++ q ++ P.pp.paint("2", "  (C-r older \u{b7} C-g back)")]
    case None{}:
      []

def sc.placeholder() -> String:
  "Enter sends \u{b7} Alt-Enter: a new line \u{b7} C-s sends waiting now \u{b7} C-g stops mugen \u{b7} Esc Esc leaves"

# The spellcheck's box as laid out: its rows (none: no box), its column and
# row on the screen (from 1), its width
type sc.Bx is Data:
  sc.Bx{rows: List<&2, String>, x: U32, y: U32, w: U32}

def sc.bx.none() -> sc.Bx:
  sc.Bx{[], 0, 0, 0}

def sc.bx.rows(b: sc.Bx) -> List<&2, String>:
  match b:
    case sc.Bx{r, x, y, w}:
      r

def sc.bx.x(b: sc.Bx) -> U32:
  match b:
    case sc.Bx{r, x, y, w}:
      x

def sc.bx.y(b: sc.Bx) -> U32:
  match b:
    case sc.Bx{r, x, y, w}:
      y

def sc.bx.w(b: sc.Bx) -> U32:
  match b:
    case sc.Bx{r, x, y, w}:
      w

def sc.bx.n(+b: sc.Bx) -> U32:
  U32.from_nat(List.length(&2, String, sc.bx.rows(b)))

# what it is drawn as, to tell a box moved or gone (its place and rows)
def sc.bx.key(+b: sc.Bx) -> String:
  U32.show(sc.bx.x(b)) ++ ";" ++ U32.show(sc.bx.y(b)) ++ ";" ++ String.join(sc.bx.rows(b), "|")

def sc.bx.paint(rs: List<&2, String>, +x: U32, +y: U32) -> String:
  match rs:
    case []:
      ""
    case +r <> rest:
      "\u{1B}[" ++ U32.show(y) ++ ";" ++ U32.show(x) ++ "H" ++ r ++ sc.bx.paint(rest, x, (y + 1 : U32))

# drawn over what is on the screen
def sc.bx.out(+b: sc.Bx) -> String:
  sc.bx.paint(sc.bx.rows(b), sc.bx.x(b), sc.bx.y(b))

# whether column x, row y is on it
def sc.bx.on(+b: sc.Bx, +x: U32, +y: U32) -> Bool:
  +bx = sc.bx.x(b)
  +by = sc.bx.y(b)
  Bool.and(Bool.and(U32.is_gt(by, 0), Bool.and(U32.is_ge(y, by), U32.is_lt(y, (by + sc.bx.n(b) : U32)))), Bool.and(U32.is_ge(x, bx), U32.is_lt(x, (bx + sc.bx.w(b) : U32))))

# The input as the spellcheck sees it: the bad words, the one the keys fix
# (the mouse's, else the cursor's), the box over it (if open), the rows as
# laid out (plain) and where each starts in the text, the first row shown,
# how many show, and the screen row (from 1) of the first shown
type sc.Sl is Data:
  sc.Sl{fs: List<&2, Sp.sp.F>, tgt: Maybe<&2, Sp.sp.F>, box: sc.Bx, rows: List<&2, String>, sts: List<&2, Nat>, top: U32, n: U32, y0: U32}

def sc.sl.fs(l: sc.Sl) -> List<&2, Sp.sp.F>:
  match l:
    case sc.Sl{f, g, b, r, st, t, n, y}:
      f

def sc.sl.tgt(l: sc.Sl) -> Maybe<&2, Sp.sp.F>:
  match l:
    case sc.Sl{f, g, b, r, st, t, n, y}:
      g

def sc.sl.box(l: sc.Sl) -> sc.Bx:
  match l:
    case sc.Sl{f, g, b, r, st, t, n, y}:
      b

def sc.sl.rows(l: sc.Sl) -> List<&2, String>:
  match l:
    case sc.Sl{f, g, b, r, st, t, n, y}:
      r

def sc.sl.sts(l: sc.Sl) -> List<&2, Nat>:
  match l:
    case sc.Sl{f, g, b, r, st, t, n, y}:
      st

def sc.sl.top(l: sc.Sl) -> U32:
  match l:
    case sc.Sl{f, g, b, r, st, t, n, y}:
      t

def sc.sl.n(l: sc.Sl) -> U32:
  match l:
    case sc.Sl{f, g, b, r, st, t, n, y}:
      n

def sc.sl.y0(l: sc.Sl) -> U32:
  match l:
    case sc.Sl{f, g, b, r, st, t, n, y}:
      y

# The lines under the chat, top down, where the cursor is among them, the
# status line's row among them, and the spellcheck's view of the input
type sc.Low is Data:
  sc.Low{rows: List<&2, String>, row: U32, col: U32, stat: U32, sl: sc.Sl}

def sc.low.rows(l: sc.Low) -> List<&2, String>:
  match l:
    case sc.Low{r, y, x, st, sl}:
      r

def sc.low.row(l: sc.Low) -> U32:
  match l:
    case sc.Low{r, y, x, st, sl}:
      y

def sc.low.col(l: sc.Low) -> U32:
  match l:
    case sc.Low{r, y, x, st, sl}:
      x

# the status line's row among them
def sc.low.stat(l: sc.Low) -> U32:
  match l:
    case sc.Low{r, y, x, st, sl}:
      st

def sc.low.sl(l: sc.Low) -> sc.Sl:
  match l:
    case sc.Low{r, y, x, st, sl}:
      sl

def sc.low.box(+l: sc.Low) -> sc.Bx:
  sc.sl.box(sc.low.sl(l))

# the input's bad words (none while the spellcheck is off)
def sc.flags.go(on: Bool, +s: sc.S) -> List<&2, Sp.sp.F>:
  match on:
    case False{}:
      []
    case True{}:
      +e = sc.ed(s)
      Sp.sp.flag(Sp.sp.words(D.ed.text(e), String.length(D.ed.pre(e))), Sp.sp.bad(sc.sp(s)))

def sc.flags(+s: sc.S) -> List<&2, Sp.sp.F>:
  sc.flags.go(Sp.sp.on(sc.sp(s)), s)

# the box for the word the keys fix, over it, if it shows (open, and its
# row among those shown); w the screen's width
def sc.box.at(m: Maybe<&2, Sp.sp.F>, +open: Bool, +rows: List<&2, String>, +sts: List<&2, Nat>, +top: U32, +n: U32, +y0: U32, +w: U32) -> sc.Bx:
  match m:
    case None{}:
      sc.bx.none()
    case Some{+f}:
      +p = Sp.sp.place(rows, sts, Sp.sp.f.at(f), 0)
      +r = Sp.sp.pt.row(p)
      +vis = Bool.and(open, Bool.and(U32.is_ge(r, top), U32.is_lt(r, (top + n : U32))))
      +wy = (y0 + (r - U32.min(r, top) : U32) : U32)
      +brows = Sp.sp.box.rows(f)
      +nb = U32.from_nat(List.length(&2, String, brows))
      +bw = Sp.sp.box.width(f)
      +by = Bool.pick(U32, U32.is_gt(wy, nb), (wy - nb : U32), 1)
      +wx = (Sp.sp.pt.col(p) + 3 : U32)
      +bx = U32.max(1, U32.min(wx, ((w - U32.min(w, bw) : U32) + 1 : U32)))
      Bool.pick(sc.Bx, vis, sc.Bx{brows, bx, by, bw}, sc.bx.none())

# the status line: the hub's (mugen's name till it comes), then the tabs
def sc.status.base(+s: sc.S) -> String:
  +line = sc.st.line(sc.st(s))
  Bool.pick(String, String.is_empty(line), P.pp.paint("1;35", "\u{7121}\u{9650} mugen"), line)

def sc.status(+s: sc.S) -> String:
  +ags = sc.st.agents(sc.st(s))
  +ts = sc.tabs(ags, sc.focus(s))
  sc.status.base(s) ++ Bool.pick(String, List.is_empty(&2, String, ts), "", P.pp.paint("2", " \u{b7} ") ++ sc.tabs.paint(ts, sc.focus(s), ags))

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
  +cy = D.ed.lay.row(lay)
  +top = Bool.pick(U32, U32.is_lt(cy, max), 0, ((cy - max : U32) + 1 : U32))
  +text = D.ed.text(e)
  +lrows = D.ed.lay.rows(lay)
  +fs = sc.flags(s)
  +painted = Sp.sp.paint(lrows, text, Sp.sp.mask(fs, 0n, String.length(text)))
  +shown = List.take(&2, String, List.drop(&2, String, painted, U32.to_nat(top)), U32.to_nat(max))
  +hint = sc.hint(s)
  +info = Bool.pick(List<&2, String>, Bool.not(String.is_empty(hint)), [P.pp.sgr.cut(P.pp.paint("2", hint), w)], sc.find.row(D.ed.find(e)))
  +empty = D.ed.is.empty(e)
  +input = Bool.pick(List<&2, String>, empty, [P.pp.paint("2", P.pp.fit(sc.placeholder(), (w - 2 : U32)))], shown)
  +head = List.concat(&2, String, [[sc.rule(w, sc.off(s))], sc.act(s), sc.queue(s), info, [P.pp.sgr.cut(sc.status(s), w)]])
  +nh = U32.from_nat(List.length(&2, String, head))
  +rows = List.append(&2, String, head, sc.prompt(input, True{}))
  +nl = U32.from_nat(List.length(&2, String, rows))
  +h = sc.h(s)
  +y0 = (Bool.pick(U32, U32.is_gt(h, nl), (h - nl : U32), 0) + (nh + 1 : U32) : U32)
  +nsh = U32.from_nat(List.length(&2, String, shown))
  +sp = sc.sp(s)
  +tgt = Sp.sp.target(fs, String.length(D.ed.pre(e)), Sp.sp.mx(sp))
  +open = Bool.and(Bool.not(Nat.is_eq(Sp.sp.key.of(tgt), Sp.sp.shut(sp))), Maybe.is_none(&2, String, D.ed.find(e)))
  +sts = Sp.sp.starts(lrows, text, 0n)
  +box = sc.box.at(tgt, open, lrows, sts, top, nsh, y0, w)
  sc.Low{rows, (nh + (cy - top : U32) : U32), (D.ed.lay.col(lay) + 2 : U32), (nh - 1 : U32), sc.Sl{fs, tgt, box, lrows, sts, top, nsh, y0}}

# Selecting -----------------------------------------------------------------------
#
# The left button dragged over the chat selects its text: the rows show it
# reversed, and letting go copies it (to X's clipboard by xclip, and to
# tmux's buffers, which tmux hands the terminal as OSC 52). A press let go
# where it was is a click. Shift-drag is the terminal's own selection.

def sc.ends.xa(e: sc.Ends) -> U32:
  match e:
    case sc.Ends{xa, ya, xb, yb}:
      xa

def sc.ends.ya(e: sc.Ends) -> U32:
  match e:
    case sc.Ends{xa, ya, xb, yb}:
      ya

def sc.ends.xb(e: sc.Ends) -> U32:
  match e:
    case sc.Ends{xa, ya, xb, yb}:
      xb

def sc.ends.yb(e: sc.Ends) -> U32:
  match e:
    case sc.Ends{xa, ya, xb, yb}:
      yb

# a row's text cut where the selection meets it: before, inside, after.
# Row y of the ends takes columns from xa on its first row, to xb on its
# last, all between.
def sc.cut(+r: String, +y: U32, +e: sc.Ends) -> sc.Three:
  +p = P.pp.clean(r)
  +from = Bool.pick(U32, U32.is_eq(y, sc.ends.ya(e)), sc.ends.xa(e), 1)
  +to = Bool.pick(U32, U32.is_eq(y, sc.ends.yb(e)), sc.ends.xb(e), 65535)
  +a = P.pp.take(p, (from - 1 : U32))
  +b = P.pp.take(P.pp.snd(a), (to - U32.min(to, (from - 1 : U32)) : U32))
  sc.Three{P.pp.fst(a), P.pp.fst(b), P.pp.snd(b)}

def sc.three.a(t: sc.Three) -> String:
  match t:
    case sc.Three{a, b, c}:
      a

def sc.three.b(t: sc.Three) -> String:
  match t:
    case sc.Three{a, b, c}:
      b

def sc.three.c(t: sc.Three) -> String:
  match t:
    case sc.Three{a, b, c}:
      c

# whether row y is selected: 1 yes, 0 no
def sc.in.k(+y: U32, +e: sc.Ends) -> Nat:
  Bool.pick(Nat, Bool.and(U32.is_ge(y, sc.ends.ya(e)), U32.is_le(y, sc.ends.yb(e))), 1n, 0n)

def sc.hl.one(k: Nat, +r: String, +y: U32, +e: sc.Ends) -> String:
  match k:
    case 0n:
      r
    case _:
      +t = sc.cut(r, y, e)
      sc.three.a(t) ++ "\u{1B}[7m" ++ sc.three.b(t) ++ "\u{1B}[27m" ++ sc.three.c(t)

# the rows (top down, from row y), the selected ones reversed
def sc.hl.rows(rs: List<&2, String>, +y: U32, +e: sc.Ends) -> List<&2, String>:
  match rs:
    case []:
      []
    case r <> rest:
      sc.hl.one(sc.in.k(y, e), r, y, e) <> sc.hl.rows(rest, (y + 1 : U32), e)

def sc.take.one(k: Nat, +r: String, +y: U32, +e: sc.Ends, +acc: List<&2, String>) -> List<&2, String>:
  match k:
    case 0n:
      acc
    case _:
      String.trim_end(sc.three.b(sc.cut(r, y, e))) <> acc

# the selected text of the rows (top down, from row y), its lines reversed
def sc.take.sel(rs: List<&2, String>, +y: U32, +e: sc.Ends, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case []:
      acc
    case r <> rest:
      sc.take.sel(rest, (y + 1 : U32), e, sc.take.one(sc.in.k(y, e), r, y, e, acc))

def sc.sel.text(+z: sc.Sel) -> String:
  String.join(List.reverse(&2, String, sc.take.sel(sc.sel.rows(z), 1, sc.sel.ends(z), [])), "\n")

# the rows to paint: reversed where a drag selects
def sc.sel.show.go(k: Nat, +z: sc.Sel, +rows: List<&2, String>) -> List<&2, String>:
  match k:
    case 0n:
      rows
    case _:
      sc.hl.rows(rows, 1, sc.sel.ends(z))

def sc.sel.show(+z: sc.Sel, +rows: List<&2, String>) -> List<&2, String>:
  sc.sel.show.go(Bool.pick(Nat, Bool.and(sc.sel.on(z), sc.sel.moved(z)), 1n, 0n), z, rows)

# copying: X's clipboard (xclip), tmux's buffer (and so the terminal's, by
# OSC 52), or outside tmux the terminal's own, by an OSC 52 of ours (a
# terminal that takes it, as Windows Terminal, kitty, WezTerm, foot, iTerm2
# do, and over ssh too: issue #2); whichever is there. It says where it
# went: x X's, t tmux's, o the terminal's (sent, not known taken).
def sc.clip() -> String:
  "t=$(cat); r=; if [ -n \"$DISPLAY\" ] && command -v xclip >/dev/null && printf %s \"$t\" | xclip -selection clipboard >/dev/null 2>&1; then r=x; fi; if [ -n \"$TMUX\" ]; then if printf %s \"$t\" | tmux load-buffer -w - >/dev/null 2>&1; then r=${r}t; fi; elif { printf '\\033]52;c;%s\\a' \"$(printf %s \"$t\" | base64 | tr -d '\\n')\" > /dev/tty; } 2>/dev/null; then r=${r}o; fi; printf %s \"$r\""

def sc.cursor(+r: U32, +c: U32) -> String:
  "\u{1B}[" ++ U32.show(r) ++ ";" ++ U32.show((c + 1 : U32)) ++ "H"

def sc.with.drawn(+s: sc.S, +g: sc.G, +ids: List<&2, U32>, +off: U32, +an: sc.An, +low: U32, +rows: List<&2, String>, +pin: U32) -> sc.S:
  +t = sc.tr(s)
  +m = sc.tm(s)
  +s1 = sc.with.tr(s, sc.Tr{sc.tr.blks(t), sc.tr.next(t), off, ids, an, sc.tr.ag(t), sc.tr.abs(t), sc.tr.old(t)})
  sc.with.z(sc.with.tm(sc.with.vw(s1, sc.g.bs(g)), sc.Tm{sc.tm.w(m), sc.tm.h(m), 0, sc.tm.mouse(m), low}), sc.sel.with.drawn(sc.z(s), rows, pin))

# The prompt pinned on top: the newest of the user's messages at or above
# the chat's top row (its block's id under it) stays on the first row, on
# its background, while what answers it is read; a click there scrolls to
# it. (At: an answer M-Up brings to the second row has its message's last
# row on the first, and that message is the one pinned, not the one before.)

def sc.blk.kind(b: sc.Blk) -> String:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      k

# the next block: 0 none, 1 the one pinned, 2 not it
def sc.pin.v(bs: List<&2, sc.Blk>, +top: U32) -> Nat:
  match bs:
    case []:
      0n
    case +b <> rest:
      Bool.pick(Nat, Bool.and(String.eq(sc.blk.kind(b), "user"), U32.is_le(sc.blk.id(b), top)), 1n, 2n)

def sc.pin.go(bs: List<&2, sc.Blk>, v: Nat, +top: U32) -> Maybe<&2, sc.Blk>:
  match bs v:
    case b <> rest 1n:
      Some{b}
    case b <> +rest 2n:
      sc.pin.go(rest, sc.pin.v(rest, top), top)
    case _ _:
      None{}

def sc.pin.id(m: Maybe<&2, sc.Blk>) -> U32:
  match m:
    case None{}:
      0
    case Some{b}:
      sc.blk.id(b)

# its row: the first line, how many more, an arrow up
def sc.pin.row(m: Maybe<&2, sc.Blk>, +w: U32) -> String:
  match m:
    case None{}:
      ""
    case Some{b}:
      +ls = P.pp.lines(P.pp.clean(sc.blk.text(b)))
      +n = List.length(&2, String, ls)
      +more = Bool.pick(String, Nat.is_le(n, 1n), "", " (+" ++ Nat.show(Nat.sub(n, 1n)) ++ " lines)") ++ " \u{2191}"
      +room = (w - U32.min(w, (P.pp.width(more) + 3 : U32)) : U32)
      P.pp.bg(P.pp.user.bg(), w, P.pp.paint("1;35", "\u{276f} ") ++ P.pp.paint("1", P.pp.fit(Maybe.default(&2, String, List.get(&2, String, ls, 0n), ""), room)) ++ P.pp.paint("2", more))

# the rows (and their ids) with the pinned prompt over the first
def sc.pinned.rows(+pid: U32, +prow: String, +rows: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_eq(pid, 0), rows, prow <> List.drop(&2, String, rows, 1n))

def sc.pinned.ids(+pid: U32, +ids: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(pid, 0), ids, 0 <> List.drop(&2, U32, ids, 1n))

# the rows from the newest block up to block id's, inclusive (each drawn at w)
def sc.rows.to(bs: List<&2, sc.Blk>, go: Bool, +id: U32, +w: U32, +home: String, +acc: U32, +focus: String) -> U32:
  match bs go:
    case b <> rest True{}:
      +b2 = sc.blk.fresh(b, w, home)
      +n = Bool.pick(U32, sc.shows(focus, sc.blk.who(b2)), sc.blk.n(b2), 0)
      sc.rows.to(rest, Bool.not(U32.is_eq(sc.blk.id(b2), id)), id, w, home, (acc + n : U32), focus)
    case _ _:
      acc

# a click on the pinned prompt: the chat scrolled to put it on top
def sc.to.pin(+s: sc.S) -> sc.S:
  +total = sc.rows.to(sc.blks(s), True{}, sc.sel.pin(sc.z(s)), sc.w(s), sc.home(s), 0, sc.focus(s))
  +h = sc.h(s)
  +t = (h - U32.min(h, sc.tm.low(sc.tm(s))) : U32)
  sc.dirty(sc.with.off(s, (total - U32.min(total, t) : U32)), 2)

# Answers: M-Up and M-Down (or M-p and M-n, or M-{ and M-}, as Emacs's
# previous and next, paragraph back and forward) go from one of mugen's answers to
# the one before or after it, past its thoughts, its tools and what they
# said. An answer is a "unii" block of mugen's (on an agent's tab, the
# agent's). The one gone to is put on the chat's second row: the first is
# the pinned prompt's, the message it answers.

def sc.ans.is(+b: sc.Blk, +focus: String) -> Bool:
  +who = sc.blk.who(b)
  Bool.and(String.eq(sc.blk.kind(b), "unii"), Bool.pick(Bool, Bool.or(String.is_empty(focus), String.eq(focus, "mugen")), String.is_empty(who), String.eq(who, focus)))

# a block's rows on the chat shown (0 where it is another's tab's)
def sc.ans.n(+b: sc.Blk, +focus: String) -> U32:
  Bool.pick(U32, sc.shows(focus, sc.blk.who(b)), sc.blk.n(b), 0)

# the rows from the chat's end to the top of the nearest answer whose top
# is above row ref (rows counted from the end too), the newest block first,
# acc the rows of those passed; 0 none
def sc.ans.up(bs: List<&2, sc.Blk>, hit: Bool, +ref: U32, +acc: U32, +w: U32, +home: String, +focus: String) -> U32:
  match bs hit:
    case _ True{}:
      acc
    case Nil{} False{}:
      0
    case b <> rest False{}:
      +b2 = sc.blk.fresh(b, w, home)
      +top = (acc + sc.ans.n(b2, focus) : U32)
      sc.ans.up(rest, Bool.and(sc.ans.is(b2, focus), U32.is_gt(top, ref)), ref, top, w, home, focus)

# the same for the nearest answer whose top is below row ref: the last one
# passed (got) before a block's top reaches ref
def sc.ans.down(bs: List<&2, sc.Blk>, more: Bool, +ref: U32, +acc: U32, +got: U32, +w: U32, +home: String, +focus: String) -> U32:
  match bs more:
    case _ False{}:
      got
    case Nil{} True{}:
      got
    case b <> rest True{}:
      +b2 = sc.blk.fresh(b, w, home)
      +top = (acc + sc.ans.n(b2, focus) : U32)
      +below = U32.is_lt(top, ref)
      sc.ans.down(rest, below, ref, top, Bool.pick(U32, Bool.and(below, sc.ans.is(b2, focus)), top, got), w, home, focus)

def sc.ans.find(up: Bool, +bs: List<&2, sc.Blk>, +ref: U32, +w: U32, +home: String, +focus: String) -> U32:
  match up:
    case True{}:
      sc.ans.up(bs, False{}, ref, 0, w, home, focus)
    case False{}:
      sc.ans.down(bs, True{}, ref, 0, 0, w, home, focus)

# the chat's rows, the lines under it laid out as they will be drawn
def sc.ans.t(+s: sc.S) -> U32:
  +h = sc.h(s)
  +nl = U32.from_nat(List.length(&2, String, sc.low.rows(sc.low(s))))
  Bool.pick(U32, U32.is_gt(h, nl), (h - nl : U32), 0)

# the chat scrolled to the answer found (top: the rows from the chat's end
# to its top row), that row the chat's second, counted with the lines
# under the chat as they will be (a hint said or gone changes how many);
# none above: the top row as drawn (at) kept, and that said; none below:
# the end
def sc.ans.go(+s: sc.S, +up: Bool, +top: U32, +at: U32) -> sc.S:
  +none = U32.is_eq(top, 0)
  +s1 = sc.with.hint(s, Bool.pick(String, Bool.and(none, up), "no answer of mugen's above", ""))
  +t = sc.ans.t(s1)
  +want = Bool.pick(U32, none, Bool.pick(U32, up, at, 0), (top + 1 : U32))
  sc.dirty(sc.with.off(s1, (want - U32.min(want, t) : U32)), 2)

# M-Up (up) and M-Down: the answer before or after the one on the chat's
# second row (where the one gone to last is), from the rows as drawn
def sc.to.ans(+s: sc.S, +up: Bool) -> sc.S:
  +h = sc.h(s)
  +t = (h - U32.min(h, sc.tm.low(sc.tm(s))) : U32)
  +at = (sc.off(s) + t : U32)
  +ref = (at - U32.min(at, 1) : U32)
  sc.ans.go(s, up, sc.ans.find(up, sc.vw(s), ref, sc.w(s), sc.home(s), sc.focus(s)), at)

def sc.to.ans.ask(ask: Bool, +s: sc.S, +old: U32, +top: U32, +at: U32) -> IO(sc.S):
  match ask:
    case True{}:
      IO.bind(Unit, sc.S, E.ev.send(sc.hub(s), E.ev.Older{old}), u => IO.pure(sc.S, sc.dirty(sc.with.hint(s, "reading older answers from the log\u{2026}"), 1)))
    case False{}:
      IO.pure(sc.S, sc.ans.go(s, True{}, top, at))

# M-Up with no answer of mugen's above in the chat's blocks: on the chat
# (not an agent's tab), the hub is asked for the log's answer before the
# first message the chat has (sc.Old brings it, and this again), unless the
# chat has the log's first message
def sc.to.ans.up(+s: sc.S) -> IO(sc.S):
  +h = sc.h(s)
  +t = (h - U32.min(h, sc.tm.low(sc.tm(s))) : U32)
  +at = (sc.off(s) + t : U32)
  +ref = (at - U32.min(at, 1) : U32)
  +focus = sc.focus(s)
  +top = sc.ans.find(True{}, sc.vw(s), ref, sc.w(s), sc.home(s), focus)
  +old = sc.tr.old(sc.tr(s))
  +ask = Bool.and(U32.is_eq(top, 0), Bool.and(Bool.or(String.is_empty(focus), String.eq(focus, "mugen")), U32.is_gt(old, 0)))
  sc.to.ans.ask(ask, s, old, top, at)

# the lowest id of the chat's blocks (the oldest's), else n
def sc.blk.low(bs: List<&2, sc.Blk>, +n: U32) -> U32:
  match bs:
    case []:
      n
    case b <> rest:
      sc.blk.low(rest, sc.blk.id(b))

# the log's older messages as blocks, the newest first, ids under id
def sc.old.blks(ms: List<&2, sc.OldM>, +id: U32, +now: Nat, +w: U32, +home: String) -> List<&2, sc.Blk>:
  match ms:
    case []:
      []
    case sc.OldM{+kind, +text} <> rest:
      +i = (id - U32.min(id, 1) : U32)
      sc.blk.new(i, "", kind, text, False{}, now, w, home) <> sc.old.blks(rest, i, now, w, home)

# older messages from the log (the oldest first), put before the chat's
# oldest block, the chat's first message then `from`; an answer that is no
# longer asked for (another came first) changes nothing
def sc.old.put(+s: sc.S, +from: U32, ms: List<&2, sc.OldM>) -> sc.S:
  +t = sc.tr(s)
  +bs = sc.blks(s)
  +olds = sc.old.blks(List.reverse(&2, sc.OldM, ms), sc.blk.low(bs, sc.tr.next(t)), sc.now(s), sc.w(s), sc.home(s))
  +s2 = sc.with.blks(s, List.append(&2, sc.Blk, bs, olds))
  sc.with.tr(s2, sc.tr.with.old(sc.tr(s2), from))

def sc.old.got.on(on: Bool, +s: sc.S, +from: U32, ms: List<&2, sc.OldM>) -> IO(sc.S):
  match on:
    case True{}:
      sc.to.ans.up(sc.old.put(s, from, ms))
    case False{}:
      IO.pure(sc.S, s)

def sc.old.got(+s: sc.S, +before: U32, +from: U32, ms: List<&2, sc.OldM>) -> IO(sc.S):
  sc.old.got.on(U32.is_eq(before, sc.tr.old(sc.tr(s))), s, from, ms)

def sc.blk.has(bs: List<&2, sc.Blk>, +id: U32) -> Bool:
  match bs:
    case []:
      False{}
    case b <> rest:
      Bool.or(U32.is_eq(sc.blk.id(b), id), sc.blk.has(rest, id))

# the rows scrolled up: those that put the chat's top row back where it was
# drawn (k 1: nothing but new rows moved it), else off as it is (k 0). The
# top row is the row-th of its block's, so as many rows are left from it to
# the chat's end as there are to its block's top, less row; t of them show.
def sc.an.go(k: Nat, +a: sc.An, bs: List<&2, sc.Blk>, +off: U32, +t: U32, +w: U32, +home: String, +focus: String) -> U32:
  match k:
    case 0n:
      off
    case _:
      +n = sc.rows.to(bs, True{}, sc.an.id(a), w, home, 0, focus)
      +top = (n - U32.min(n, sc.an.row(a)) : U32)
      (top - U32.min(top, t) : U32)

# held while scrolled up and not scrolled since the last draw (the rows
# scrolled up are still those the top row was drawn at), its block still there
def sc.an.held(+s: sc.S, +off: U32, +t: U32) -> U32:
  +a = sc.tr.an(sc.tr(s))
  +id = sc.an.id(a)
  +bs = sc.vw(s)
  +same = Bool.and(U32.is_gt(off, 0), U32.is_eq(sc.an.off(a), off))
  +k = Bool.pick(Nat, Bool.and(same, Bool.and(Bool.not(U32.is_eq(id, 0)), sc.blk.has(bs, id))), 1n, 0n)
  sc.an.go(k, a, bs, off, t, sc.w(s), sc.home(s), sc.focus(s))

# the top row as drawn: its block's id, its place there (the rows from the
# chat's end to the block's top, less the seen ones: those from the end up to
# the top row), and the rows scrolled up
def sc.an.take(bs: List<&2, sc.Blk>, +top: U32, +seen: U32, +off: U32, +w: U32, +home: String, +focus: String) -> sc.An:
  +n = sc.rows.to(bs, True{}, top, w, home, 0, focus)
  sc.An{top, (n - U32.min(n, seen) : U32), off}

# all of it (the lines under the chat laid out again once the rows scrolled
# up are known: the rule says how many are below)
def sc.draw.all(+s: sc.S) -> IO(sc.S):
  +nl = U32.from_nat(List.length(&2, String, sc.low.rows(sc.low(s))))
  +h = sc.h(s)
  +t = Bool.pick(U32, U32.is_gt(h, nl), (h - nl : U32), 0)
  +off = sc.an.held(s, sc.off(s), t)
  +need = (off + t : U32)
  +focus = sc.focus(s)
  +g = sc.gather(sc.vw(s), U32.is_gt(need, 0), sc.shows.head(sc.vw(s), focus), need, 0, [], [], sc.w(s), sc.home(s), focus)
  +k = sc.g.k(g)
  +off2 = U32.min(off, (k - U32.min(k, t) : U32))
  +low = sc.low(sc.with.off(s, off2))
  +lrows = sc.low.rows(low)
  +rows0 = List.take(&2, String, sc.g.rows(g), U32.to_nat(t))
  +ids0 = List.take(&2, U32, sc.g.ids(g), U32.to_nat(t))
  +an = sc.an.take(sc.g.bs(g), Maybe.default(&2, U32, List.get(&2, U32, ids0, 0n), 0), (off2 + U32.from_nat(List.length(&2, String, rows0)) : U32), off2, sc.w(s), sc.home(s), focus)
  +pm = sc.pin.go(sc.g.bs(g), sc.pin.v(sc.g.bs(g), Maybe.default(&2, U32, List.get(&2, U32, ids0, 0n), 0)), Maybe.default(&2, U32, List.get(&2, U32, ids0, 0n), 0))
  +pid = Bool.pick(U32, Bool.and(U32.is_ge(t, 4), Bool.or(String.is_empty(focus), String.eq(focus, "mugen"))), sc.pin.id(pm), 0)
  +rows = sc.pinned.rows(pid, sc.pin.row(pm, sc.w(s)), rows0)
  +ids = sc.pinned.ids(pid, ids0)
  +out = String.concat(List.concat(&2, String, [["\u{1B}[?2026h\u{1B}[?25l"], sc.paint.rows(U32.to_nat(t), sc.sel.show(sc.z(s), rows), 1), sc.paint.rows(U32.to_nat(nl), lrows, (t + 1 : U32)),
    [sc.bx.out(sc.low.box(low)), sc.cursor((t + (sc.low.row(low) + 1 : U32) : U32), sc.low.col(low)), "\u{1B}[?25h\u{1B}[?2026l"]]))
  +s2 = sc.with.sp(s, Sp.sp.with.drawn(sc.sp(s), sc.bx.key(sc.low.box(low))))
  IO.bind(Unit, sc.S, IO.write(out), u => IO.pure(sc.S, sc.with.drawn(s2, g, ids, off2, an, nl, rows, pid)))

def sc.with.clean(+s: sc.S) -> sc.S:
  +m = sc.tm(s)
  sc.with.tm(s, sc.Tm{sc.tm.w(m), sc.tm.h(m), 0, sc.tm.mouse(m), sc.tm.low(m)})

# the lines under the chat only; all if their number changed, or the
# spellcheck's box did (what it covered drawn again)
def sc.draw.low.go(same: Bool, +s: sc.S, +low: sc.Low) -> IO(sc.S):
  match same:
    case True{}:
      +lrows = sc.low.rows(low)
      +nl = U32.from_nat(List.length(&2, String, lrows))
      +h = sc.h(s)
      +t = Bool.pick(U32, U32.is_gt(h, nl), (h - nl : U32), 0)
      +out = String.concat(List.concat(&2, String, [["\u{1B}[?2026h\u{1B}[?25l"], sc.paint.rows(U32.to_nat(nl), lrows, (t + 1 : U32)),
        [sc.bx.out(sc.low.box(low)), sc.cursor((t + (sc.low.row(low) + 1 : U32) : U32), sc.low.col(low)), "\u{1B}[?25h\u{1B}[?2026l"]]))
      IO.bind(Unit, sc.S, IO.write(out), u => IO.pure(sc.S, sc.with.clean(s)))
    case False{}:
      sc.draw.all(s)

def sc.draw.low(+s: sc.S) -> IO(sc.S):
  +low = sc.low(s)
  +nl = U32.from_nat(List.length(&2, String, sc.low.rows(low)))
  +same = Bool.and(U32.is_eq(nl, sc.tm.low(sc.tm(s))), String.eq(sc.bx.key(sc.low.box(low)), Sp.sp.drawn(sc.sp(s))))
  sc.draw.low.go(same, s, low)

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

# The chat keeps its newest 400 blocks, and of those before them the
# messages and answers (the user's, mugen's, the agents' reports: mugen's
# own, not an agent's tab's), so M-Up reaches every answer since the chat
# opened, past any number of tool calls; older ones the log gives (sc.Old).
def sc.keep.one(on: Bool, b: sc.Blk, rest: List<&2, sc.Blk>) -> List<&2, sc.Blk>:
  match on:
    case True{}:
      b <> rest
    case False{}:
      rest

def sc.keep.is(+b: sc.Blk) -> Bool:
  +k = sc.blk.kind(b)
  Bool.and(String.is_empty(sc.blk.who(b)), Bool.or(String.eq(k, "user"), Bool.or(String.eq(k, "unii"), String.eq(k, "work"))))

def sc.keep.old(bs: List<&2, sc.Blk>) -> List<&2, sc.Blk>:
  match bs:
    case []:
      []
    case +b <> rest:
      sc.keep.one(sc.keep.is(b), b, sc.keep.old(rest))

def sc.keep(+bs: List<&2, sc.Blk>) -> List<&2, sc.Blk>:
  List.append(&2, sc.Blk, List.take(&2, sc.Blk, bs, 400n), sc.keep.old(List.drop(&2, sc.Blk, bs, 400n)))

def sc.tr.add(t: sc.Tr, +b: sc.Blk) -> sc.Tr:
  match t:
    case sc.Tr{bs, n, +o, i, a, g, x, d}:
      +k = sc.blk.n(b)
      sc.Tr{sc.keep(b <> bs), (n + 1 : U32), Bool.pick(U32, U32.is_eq(o, 0), 0, (o + k : U32)), i, sc.an.bump(a, o, k), g, x, d}

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

def sc.put.chat(k: Nat, +s: sc.S, +who: String, +kind: String, +text: String) -> sc.S:
  match k:
    case 1n:
      sc.add(s, who, "tool", text, True{})
    case 2n:
      sc.attached(sc.attach(sc.blks(s), sc.attach.v(sc.blks(s), who, text), who, text, "", sc.w(s), sc.home(s)), s, who, "tool", text)
    case 3n:
      sc.attached(sc.attach(sc.blks(s), sc.attach.v(sc.blks(s), who, ""), who, "", text, sc.w(s), sc.home(s)), s, who, "echo", text)
    case _:
      sc.add(s, who, kind, text, False{})

# The agent's tab --------------------------------------------------------------
#
# An agent's tab shows its whole log: as the tab opens, the agent's log
# (docs/agent/NAME.jsonl, Store.bend st.agent) is read into blocks of the
# tab's own (drawn as the chat reaches them), and what the agent does after
# joins them too; so Home there reaches its first message, however long it
# ran (the chat keeps only its last 400 blocks).

# a block not drawn yet
def sc.blk.raw(+id: U32, +who: String, +kind: String, +text: String, +run: Bool, +now: Nat) -> sc.Blk:
  sc.Blk{id, who, kind, text, "", True{}, run, now, 0, [], 0}

def sc.blk.got(b: sc.Blk, +res: String) -> sc.Blk:
  match b:
    case sc.Blk{i, who, k, t, r, o, ru, t0, bw, rs, n}:
      sc.Blk{i, who, k, t, res, o, False{}, t0, 0, [], 0}

# sc.attach, the block not drawn
def sc.attach.raw(bs: List<&2, sc.Blk>, hit: Bool, +who: String, +text: String, +res: String) -> Maybe<&2, List<&2, sc.Blk>>:
  match bs hit:
    case Nil{} _:
      None{}
    case +b <> +rest True{}:
      Some{sc.blk.got(b, res) <> rest}
    case +b <> +rest False{}:
      sc.attach.more(sc.attach.raw(rest, sc.attach.v(rest, who, text), who, text, res), b)

def sc.ag.or(m: Maybe<&2, List<&2, sc.Blk>>, +b: sc.Blk, +bs: List<&2, sc.Blk>) -> List<&2, sc.Blk>:
  match m:
    case Some{+x}:
      x
    case None{}:
      b <> bs

# an entry of the agent's onto its blocks, as sc.put takes it (k: sc.put.k)
def sc.ag.step(k: Nat, +bs: List<&2, sc.Blk>, +id: U32, +who: String, +kind: String, +text: String, +now: Nat) -> List<&2, sc.Blk>:
  match k:
    case 0n:
      bs
    case 1n:
      sc.blk.raw(id, who, "tool", text, True{}, now) <> bs
    case 2n:
      sc.ag.or(sc.attach.raw(bs, sc.attach.v(bs, who, text), who, text, ""), sc.blk.raw(id, who, "tool", text, False{}, now), bs)
    case 3n:
      sc.ag.or(sc.attach.raw(bs, sc.attach.v(bs, who, ""), who, "", text), sc.blk.raw(id, who, "echo", text, False{}, now), bs)
    case _:
      sc.blk.raw(id, who, kind, text, False{}, now) <> bs

# the log's entries (oldest first) onto blocks (newest first), their ids
# from id on
def sc.ag.blks(rs: List<&2, St.st.Root>, +who: String, +id: U32, +bs: List<&2, sc.Blk>) -> List<&2, sc.Blk>:
  match rs:
    case []:
      bs
    case +r <> rest:
      +kind = St.st.root.kind(r)
      sc.ag.blks(rest, who, (id + 1 : U32), sc.ag.step(sc.put.k(kind), bs, id, who, kind, St.st.root.text(r), 0n))

def sc.ag.most() -> Nat:
  20000n

# an entry of the loaded agent's: onto its tab's blocks too
def sc.ag.put(go: Bool, +k: Nat, +s: sc.S, +who: String, +kind: String, +text: String) -> sc.S:
  match go:
    case False{}:
      s
    case True{}:
      +t = sc.tr(s)
      +bs = sc.ag.step(k, sc.tr.abs(t), sc.tr.next(t), who, kind, text, sc.now(s))
      sc.dirty(sc.with.tr(s, sc.tr.took(sc.tr.with.ag(t, sc.tr.ag(t), List.take(&2, sc.Blk, bs, sc.ag.most())), 1)), 2)

def sc.put.go(bell: Bool, +k: Nat, +s: sc.S, +who: String, +kind: String, +text: String) -> IO(sc.S):
  match bell:
    case True{}:
      IO.bind(Unit, sc.S, IO.write("\u{7}"), u => IO.pure(sc.S, s))
    case False{}:
      +ag = sc.tr.ag(sc.tr(s))
      IO.pure(sc.S, sc.ag.put(Bool.and(Bool.not(String.is_empty(ag)), String.eq(who, ag)), k, sc.put.chat(k, s, who, kind, text), who, kind, text))

def sc.put(+k: Nat, +s: sc.S, +who: String, +kind: String, +text: String) -> IO(sc.S):
  sc.put.go(Nat.is_eq(k, 0n), k, s, who, kind, text)

# what the agent's tab needs before a draw: 0 nothing, 1 the log of the
# agent whose tab shows loaded (none or another's is), 2 the loaded one
# dropped (no agent's tab shows)
def sc.ag.want(+s: sc.S) -> Nat:
  +f = sc.focus(s)
  +ag = sc.tr.ag(sc.tr(s))
  +agent = Bool.not(Bool.or(String.is_empty(f), String.eq(f, "mugen")))
  Bool.pick(Nat, agent, Bool.pick(Nat, String.eq(f, ag), 0n, 1n), Bool.pick(Nat, String.is_empty(ag), 0n, 2n))

def sc.ag.got(m: Maybe<&2, List<&2, St.st.Root>>, +s: sc.S, +name: String) -> sc.S:
  +rs = Maybe.default(&2, List<&2, St.st.Root>, m, [])
  +t = sc.tr(s)
  +bs = sc.ag.blks(rs, name, sc.tr.next(t), [])
  sc.dirty(sc.with.tr(s, sc.tr.took(sc.tr.with.ag(t, name, List.take(&2, sc.Blk, bs, sc.ag.most())), U32.from_nat(List.length(&2, St.st.Root, rs)))), 2)

# the mugen dir (the history's file's)
def sc.mugen(+s: sc.S) -> String:
  String.reverse(String.drop(String.reverse(sc.cf.hfile(sc.cf(s))), 8n))

def sc.ag.load(k: Nat, +s: sc.S) -> IO(sc.S):
  match k:
    case 1n:
      +name = sc.focus(s)
      IO.bind(Maybe<&2, List<&2, St.st.Root>>, sc.S, St.st.agent(sc.mugen(s), name), m => IO.pure(sc.S, sc.ag.got(m, s, name)))
    case 2n:
      IO.pure(sc.S, sc.with.tr(s, sc.tr.with.ag(sc.tr(s), "", [])))
    case _:
      IO.pure(sc.S, s)

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

# the most rows scrolled up (the top, whatever the chat's length: the
# drawing adds the screen's rows to it, which must not wrap a U32)
def sc.top() -> U32:
  1073741824

def sc.scroll(+s: sc.S, +up: Bool, +n: U32) -> sc.S:
  +o = sc.off(s)
  sc.dirty(sc.with.off(s, Bool.pick(U32, up, U32.min(sc.top(), Bool.pick(U32, U32.is_gt(o, (4294967295 - n : U32)), o, (o + n : U32))), (o - U32.min(o, n) : U32))), 2)

# leaving: asked of the hub, which says Bye once all is cut
def sc.quit(+s: sc.S) -> IO(sc.S):
  Bool.pick(IO(sc.S), sc.u.quit(sc.u(s)), IO.pure(sc.S, s),
    IO.bind(Unit, sc.S, sc.send(s, "/quit"), u => IO.pure(sc.S, sc.dirty(sc.with.hint(sc.with.quit(s), "leaving \u{2026}"), 1))))

# after an edit: the word the mouse pointed at forgotten (the box follows
# the cursor), the box Esc closed kept closed only while on the same word
def sc.sp.moved(+s: sc.S) -> sc.S:
  +sp = sc.sp(s)
  +e = sc.ed(s)
  +k = Sp.sp.key.of(Sp.sp.target(sc.flags(s), String.length(D.ed.pre(e)), 0n))
  sc.with.sp(s, Sp.sp.with.shut(Sp.sp.with.mx(sp, 0n), Bool.pick(Nat, Nat.is_eq(k, Sp.sp.shut(sp)), k, 0n)))

def sc.edit(+s: sc.S, +key: K.ky.Key) -> sc.S:
  sc.dirty(sc.with.hint(sc.sp.moved(sc.with.ed(s, D.ed.key(sc.ed(s), key))), ""), 1)

def sc.mouse.say(on: Bool) -> String:
  match on:
    case True{}:
      "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1003h\u{1B}[?1006h"
    case False{}:
      "\u{1B}[?1006l\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l"

# /mouse: the mouse's reports off (the terminal selects text) or on
def sc.mouse(+s: sc.S) -> IO(sc.S):
  +m = sc.tm(s)
  +on = Bool.not(sc.tm.mouse(m))
  do IO<sc.S>:
    Unit <- IO.write(sc.mouse.say(on))
    return sc.dirty(sc.with.hint(sc.with.tm(s, sc.Tm{sc.tm.w(m), sc.tm.h(m), sc.tm.draw(m), on, sc.tm.low(m)}),
      Bool.pick(String, on, "the mouse scrolls, opens blocks and copies what it drags over (/mouse gives it to the terminal)", "the terminal has the mouse now (/mouse for mugen's back)")), 1)

def sc.cmd.word(+t: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(String.trim(t), ' '), 0n), "")

# a message or a command, sent: kept in the history, the chat followed; a
# command shown, a message once the hub logs it (it holds one sent while
# mugen works, which Up can take back)
def sc.sent(+s: sc.S, +t: String) -> IO(sc.S):
  +cmd = String.starts_with(String.trim(t), "/")
  +s1 = sc.with.off(sc.with.hint(sc.with.ed(s, D.ed.sent(sc.ed(s))), ""), 0)
  do IO<sc.S>:
    Unit <- sc.send(s, t)
    a : Result<&1, &1, U32 & String, Nat> <- S.mu.append(sc.cf.hfile(sc.cf(s)), sc.hist.enc(t) ++ "\n", 0)
    return Bool.pick(sc.S, cmd, sc.add(s1, "", "say", "\u{203a} " ++ String.trim(t), False{}), sc.dirty(s1, 1))

# /image [path] on the draft's last line: the image (or the clipboard's)
# kept in the mugen dir (Pic.bend), a line naming it in its place, for the
# message being written to take; the rest of the draft kept
def sc.last.line(+t: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, List.reverse(&2, String, String.lines(t)), 0n), "")

def sc.before.last(+t: String) -> String:
  +ls = String.lines(t)
  String.join(List.take(&2, String, ls, Nat.sub(List.length(&2, String, ls), 1n)), "\n")

def sc.img.is(+t: String) -> Bool:
  +l = String.trim(sc.last.line(t))
  Bool.or(String.eq(l, "/image"), String.starts_with(l, "/image "))

def sc.img.got(+s: sc.S, +t: String, +g: Pc.pc.Got) -> sc.S:
  +n = Pc.pc.got.name(g)
  +b = sc.before.last(t)
  +d = Bool.pick(String, String.is_empty(n), t, b ++ Bool.pick(String, String.is_empty(b), "", "\n") ++ Pc.pc.line(n) ++ "\n")
  sc.dirty(sc.with.hint(sc.with.ed(s, D.ed.set(sc.ed(s), d)), Pc.pc.got.note(g)), 1)

def sc.img.attach(+s: sc.S) -> IO(sc.S):
  +t = D.ed.text(sc.ed(s))
  IO.bind(Pc.pc.Got, sc.S, Pc.pc.attach(sc.mugen(s), sc.cf.home(sc.cf(s)), String.drop(String.trim(sc.last.line(t)), 6n)), g => IO.pure(sc.S, sc.img.got(s, t, g)))

# Your words -----------------------------------------------------------------------
#
# M-a (or a click on the box's + add row) on a word: added to your words
# (Spell.bend sp.dict, ~/.hunspell_en_US), or, one of yours already, taken
# out. /words lists them; /words add WORD... and /words rm WORD... change
# them. The file is read at each, and written whole (by a rename); the
# words changed are forgotten, so the next tick asks hunspell anew.

# the words file read: whether it was (or is not there: no words yet), its
# text, why not
type sc.Dr is Data:
  sc.Dr{ok: Bool, text: String, why: String}

def sc.dr.ok(d: sc.Dr) -> Bool:
  match d:
    case sc.Dr{o, t, w}:
      o

def sc.dr.text(d: sc.Dr) -> String:
  match d:
    case sc.Dr{o, t, w}:
      t

def sc.dr.why(d: sc.Dr) -> String:
  match d:
    case sc.Dr{o, t, w}:
      w

def sc.dict.path(+s: sc.S) -> String:
  sc.home(s) ++ Sp.sp.dict.file()

# an effect's error said: its text, or its number
def sc.why(+code: U32, +text: String) -> String:
  Bool.pick(String, String.is_empty(text), "error " ++ U32.show(code), text)

# the file not there (ENOENT) is no words yet
def sc.dr.fail(+code: U32, +text: String) -> sc.Dr:
  sc.Dr{U32.is_eq(code, 2), "", sc.why(code, text)}

def sc.dict.got(r: Result<&1, &1, U32 & String, String>) -> sc.Dr:
  match r:
    case Done{t}:
      sc.Dr{True{}, t, ""}
    case Fail{(code, text)}:
      sc.dr.fail(code, text)

def sc.dict.lines(+d: sc.Dr) -> List<&2, String>:
  Sp.sp.dict.lines(sc.dr.text(d))

def sc.say(+s: sc.S, +hint: String) -> sc.S:
  sc.dirty(sc.with.hint(s, hint), 1)

# a change written: the words it changed forgotten (asked anew), and said
def sc.words.saved(r: Result<&1, &1, U32 & String, Unit>, +s: sc.S, +x: Sp.sp.Dx, +say: String) -> sc.S:
  match r:
    case Done{u}:
      sc.say(sc.with.sp(s, Sp.sp.forget.all(Sp.sp.dx.done(x), sc.sp(s))), say)
    case Fail{(code, text)}:
      sc.say(s, "your words are as they were: ~/.hunspell_en_US can't be written (" ++ sc.why(code, text) ++ ")")

def sc.words.save(+s: sc.S, +x: Sp.sp.Dx, +say: String) -> IO(sc.S):
  IO.bind(Result<&1, &1, U32 & String, Unit>, sc.S, S.mu.save(sc.dict.path(s), Sp.sp.dict.text(Sp.sp.dx.lines(x)), 0), r => IO.pure(sc.S, sc.words.saved(r, s, x, say)))

def sc.quote(+w: String) -> String:
  "\u{ab}" ++ w ++ "\u{bb}"

# what M-a does: 0 adds the word, 1 takes it out, 2 nothing (the dictionary
# has it), 3 nothing (the file can't be read)
def sc.words.toggle.go(k: Nat, +s: sc.S, +w: String, +f: String, +ls: List<&2, String>, +why: String) -> IO(sc.S):
  match k:
    case 0n:
      sc.words.save(s, Sp.sp.dict.add([w], Sp.sp.dx.new(ls)), "\u{2713} " ++ sc.quote(f) ++ " added to your words \u{b7} M-a again takes it out")
    case 1n:
      sc.words.save(s, Sp.sp.dict.rm([w], Sp.sp.dx.new(ls)), sc.quote(f) ++ " taken out of your words \u{b7} M-a puts it back")
    case 2n:
      IO.pure(sc.S, sc.say(s, sc.quote(w) ++ " is in the dictionary already (M-a adds and takes out words of yours)"))
    case _:
      IO.pure(sc.S, sc.say(s, "~/.hunspell_en_US can't be read (" ++ why ++ "), so it is left as it is"))

def sc.words.toggle(+s: sc.S, +w: String, +dr: sc.Dr) -> IO(sc.S):
  +ls = sc.dict.lines(dr)
  +f = Sp.sp.dict.form(w)
  +mine = Sp.sp.dict.has(ls, f)
  +known = Sp.sp.known(sc.sp(s), w)
  +k = Bool.pick(Nat, Bool.not(sc.dr.ok(dr)), 3n, Bool.pick(Nat, mine, 1n, Bool.pick(Nat, known, 2n, 0n)))
  sc.words.toggle.go(k, s, w, f, ls, sc.dr.why(dr))

def sc.dict.w.text(m: Maybe<&2, Sp.sp.W>) -> Maybe<&2, String>:
  match m:
    case Some{w}:
      Some{Sp.sp.w.text(w)}
    case None{}:
      None{}

def sc.dict.word.of(m: Maybe<&2, Sp.sp.F>, +t: String, +cur: Nat) -> Maybe<&2, String>:
  match m:
    case Some{f}:
      Some{Sp.sp.f.text(f)}
    case None{}:
      sc.dict.w.text(Sp.sp.cur.word(t, cur))

# the word M-a is for: the red one the box is for (the mouse's, else the
# cursor's), else any the cursor is in or just after
def sc.dict.word(+s: sc.S) -> Maybe<&2, String>:
  +e = sc.ed(s)
  sc.dict.word.of(sc.sl.tgt(sc.low.sl(sc.low(s))), D.ed.text(e), String.length(D.ed.pre(e)))

def sc.words.key.go(m: Maybe<&2, String>, +s: sc.S) -> IO(sc.S):
  match m:
    case None{}:
      IO.pure(sc.S, sc.say(s, "M-a: put the cursor on a word (or the mouse on a red one) to add it to your words, or take it out"))
    case Some{+w}:
      IO.bind(Result<&1, &1, U32 & String, String>, sc.S, S.mu.read_file(sc.dict.path(s)), r => sc.words.toggle(s, w, sc.dict.got(r)))

# M-a, or a click on the box's + add row
def sc.words.key(+s: sc.S) -> IO(sc.S):
  sc.words.key.go(sc.dict.word(s), s)

# what a change said: the words changed, those left
def sc.words.said(+x: Sp.sp.Dx, +did: String, +left: String) -> String:
  +d = Sp.sp.dx.done(x)
  +l = Sp.sp.dx.left(x)
  +a = Bool.pick(String, List.is_empty(&2, String, d), "", did ++ String.join(d, ", "))
  +b = Bool.pick(String, List.is_empty(&2, String, l), "", Bool.pick(String, List.is_empty(&2, String, d), "", " \u{b7} ") ++ left ++ String.join(l, ", "))
  a ++ b

def sc.words.change(none: Bool, +s: sc.S, +x: Sp.sp.Dx, +say: String) -> IO(sc.S):
  match none:
    case True{}:
      IO.pure(sc.S, sc.say(s, say))
    case False{}:
      sc.words.save(s, x, say)

def sc.words.apply(+s: sc.S, +x: Sp.sp.Dx, +say: String) -> IO(sc.S):
  sc.words.change(List.is_empty(&2, String, Sp.sp.dx.done(x)), s, x, say)

# a change made, if the file was read (else none: it would be lost)
def sc.words.edit(ok: Bool, +s: sc.S, +x: Sp.sp.Dx, +say: String, +why: String) -> IO(sc.S):
  match ok:
    case True{}:
      sc.words.apply(s, x, say)
    case False{}:
      IO.pure(sc.S, sc.say(s, "~/.hunspell_en_US can't be read (" ++ why ++ "), so it is left as it is"))

# /words's page: your words, or how to have some
def sc.words.page(+dr: sc.Dr) -> String:
  +ws = Sp.sp.dict.words(sc.dict.lines(dr))
  +n = List.length(&2, String, ws)
  Bool.pick(String, Bool.not(sc.dr.ok(dr)), "Your words: `~/.hunspell_en_US` can't be read (" ++ sc.dr.why(dr) ++ ").",
    Bool.pick(String, Nat.is_eq(n, 0n), "No words of yours yet. `M-a` on a red word adds it, `/words add WORD\u{2026}` any word; they go in `~/.hunspell_en_US`.",
      "## Your words (" ++ Nat.show(n) ++ ", in ~/.hunspell_en_US)\n" ++ String.join(ws, ", ") ++ "\n\n`M-a` on one of them takes it out, as `/words rm WORD\u{2026}` does."))

# /words: 0 the list, 1 add, 2 rm, 3 neither
def sc.words.cmd.go(k: Nat, +s: sc.S, +ws: List<&2, String>, +dr: sc.Dr) -> IO(sc.S):
  match k:
    case 0n:
      IO.pure(sc.S, sc.add(s, "", "help", sc.words.page(dr), False{}))
    case 1n:
      +x = Sp.sp.dict.add(ws, Sp.sp.dx.new(sc.dict.lines(dr)))
      sc.words.edit(sc.dr.ok(dr), s, x, sc.words.said(x, "\u{2713} added to your words: ", "already yours (or no word): "), sc.dr.why(dr))
    case 2n:
      +x = Sp.sp.dict.rm(ws, Sp.sp.dx.new(sc.dict.lines(dr)))
      sc.words.edit(sc.dr.ok(dr), s, x, sc.words.said(x, "taken out of your words: ", "not yours: "), sc.dr.why(dr))
    case _:
      IO.pure(sc.S, sc.say(s, "/words alone lists your words; /words add WORD\u{2026} and /words rm WORD\u{2026} change them"))

def sc.nonempty(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case []:
      []
    case +x <> rest:
      List.append(&2, String, Bool.pick(List<&2, String>, String.is_empty(x), [], [x]), sc.nonempty(rest))

# /words [add|rm WORD...]
def sc.words.cmd(+s: sc.S, +arg: String) -> IO(sc.S):
  +ts = sc.nonempty(String.split(arg, ' '))
  +verb = Maybe.default(&2, String, List.get(&2, String, ts, 0n), "")
  +ws = List.drop(&2, String, ts, 1n)
  +some = Bool.not(List.is_empty(&2, String, ws))
  +k = Bool.pick(Nat, List.is_empty(&2, String, ts), 0n, Bool.pick(Nat, Bool.and(some, String.eq(verb, "add")), 1n, Bool.pick(Nat, Bool.and(some, String.eq(verb, "rm")), 2n, 3n)))
  IO.bind(Result<&1, &1, U32 & String, String>, sc.S, S.mu.read_file(sc.dict.path(s)), r => sc.words.cmd.go(k, s, ws, sc.dict.got(r)))

# Enter: a "\" before the cursor at the text's end is a new line; an empty
# text, nothing; /mouse, /image, /spell and /words are the screen's; else sent
def sc.enter.k(+s: sc.S) -> Nat:
  +e = sc.ed(s)
  +t = D.ed.text(e)
  Bool.pick(Nat, Bool.and(String.is_empty(D.ed.post(e)), String.starts_with(D.ed.pre(e), "\\")), 0n,
    Bool.pick(Nat, String.is_empty(String.trim(t)), 1n, Bool.pick(Nat, String.eq(String.trim(t), "/mouse"), 2n, Bool.pick(Nat, sc.img.is(t), 4n,
      Bool.pick(Nat, String.eq(sc.cmd.word(t), "/spell"), 5n, Bool.pick(Nat, String.eq(sc.cmd.word(t), "/words"), 6n, 3n))))))

# /spell [on|off]: the spellcheck on or off (alone: switched)
def sc.spell.cmd(+s: sc.S, +arg: String) -> sc.S:
  +sp = sc.sp(s)
  +on = Bool.pick(Bool, String.eq(arg, "on"), True{}, Bool.pick(Bool, String.eq(arg, "off"), False{}, Bool.not(Sp.sp.on(sp))))
  +ok = Bool.or(String.is_empty(arg), Bool.or(String.eq(arg, "on"), String.eq(arg, "off")))
  +say = Bool.pick(String, on, "spellcheck on: point at a red-underlined word, or put the cursor on it, for suggestions \u{b7} M-s fixes it, M-S all, M-a adds it to your words", "spellcheck off (/spell on brings it back)")
  Bool.pick(sc.S, ok, sc.dirty(sc.with.hint(sc.with.sp(s, Sp.sp.with.on(sp, on)), say), 2), sc.dirty(sc.with.hint(s, "/spell takes on or off"), 1))

def sc.enter(k: Nat, +s: sc.S) -> IO(sc.S):
  match k:
    case 0n:
      +e = sc.ed(s)
      IO.pure(sc.S, sc.dirty(sc.with.ed(s, D.ed.with(e, "\n" ++ D.ed.tail(D.ed.pre(e)), "")), 1))
    case 1n:
      IO.pure(sc.S, s)
    case 2n:
      sc.mouse(sc.with.ed(s, D.ed.sent(sc.ed(s))))
    case 4n:
      sc.img.attach(s)
    case 5n:
      +t = String.trim(D.ed.text(sc.ed(s)))
      IO.pure(sc.S, sc.spell.cmd(sc.with.ed(s, D.ed.sent(sc.ed(s))), String.trim(String.drop(t, 6n))))
    case 6n:
      +t = String.trim(D.ed.text(sc.ed(s)))
      sc.words.cmd(sc.with.ed(s, D.ed.sent(sc.ed(s))), String.trim(String.drop(t, 6n)))
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

# Tab after /words rm: a word of yours completed (the text's last word)
def sc.tab.words(+s: sc.S, +ws: List<&2, String>) -> sc.S:
  +e = sc.ed(s)
  +t = D.ed.text(e)
  +p = Maybe.default(&2, String, List.get(&2, String, List.reverse(&2, String, String.split(t, ' ')), 0n), "")
  +head = String.take(t, Nat.sub(String.length(t), String.length(p)))
  +ms = D.ed.starting(ws, p)
  +n = List.length(&2, String, ms)
  +first = Maybe.default(&2, String, List.get(&2, String, ms, 0n), p)
  +t2 = Bool.pick(String, Nat.is_eq(n, 0n), t, head ++ Bool.pick(String, Nat.is_eq(n, 1n), first ++ " ", D.ed.prefix(ms, first)))
  +say = Bool.pick(String, Nat.is_gt(n, 1n), String.join(ms, "  "), Bool.pick(String, Nat.is_eq(n, 0n), "no word of yours starts with " ++ sc.quote(p), ""))
  sc.say(sc.with.ed(s, D.ed.set(e, t2)), say)

# Tab: 1 after /words rm (the file read), 0 any other
def sc.tab.k(+s: sc.S) -> Nat:
  Bool.pick(Nat, String.starts_with(D.ed.text(sc.ed(s)), "/words rm "), 1n, 0n)

def sc.tab.go(k: Nat, +s: sc.S) -> IO(sc.S):
  match k:
    case 1n:
      IO.bind(Result<&1, &1, U32 & String, String>, sc.S, S.mu.read_file(sc.dict.path(s)), r => IO.pure(sc.S, sc.tab.words(s, Sp.sp.dict.words(sc.dict.lines(sc.dict.got(r))))))
    case _:
      IO.pure(sc.S, sc.tab(s))

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
  +bs = sc.vw(s)
  +bs2 = sc.toggle(bs, sc.toggle.v(bs, id), id, sc.w(s), sc.home(s))
  +n0 = sc.blk.n.of(bs, id)
  +n1 = sc.blk.n.of(bs2, id)
  +o = sc.off(s)
  +follow = Bool.and(U32.is_eq(o, 0), U32.is_eq(sc.newest(bs), id))
  +o2 = Bool.pick(U32, follow, 0, Bool.pick(U32, U32.is_ge(n1, n0), (o + (n1 - n0 : U32) : U32), (o - U32.min(o, (n0 - n1 : U32)) : U32)))
  Bool.pick(sc.S, Bool.or(U32.is_eq(y, 0), Maybe.is_none(&2, U32, m)), s, sc.dirty(sc.with.off(sc.with.vw(s, bs2), o2), 2))

def sc.all(+s: sc.S) -> sc.S:
  +bs = sc.vw(s)
  sc.dirty(sc.with.vw(s, sc.open.all(bs, sc.any.closed(bs), sc.w(s), sc.home(s))), 2)

# what a key does: 0 an edit, 1 Enter, 2 C-c, 3 C-d, 4 C-g, 5 C-s, 6 M-o (or C-o,
# tmux's prefix where it is set so),
# 7 C-l, 8 Esc, 9 Tab, 10 PgUp, 11 PgDn, 12 M-< or Home on an empty input,
# 13 M-> or End on an empty input, 14 the wheel up, 15 down, 16 a press, 17
# nothing, 18 a drag, 19 a let go, 20 Up on an empty input with messages
# waiting, 21 M-Left and 22 M-Right with tabs shown, 23 M-s, 24 M-S, 25 M-1
# to M-9 (the spellcheck's), 27 Shift-Tab (plan or auto), 28 the mouse moved
# (no button held), 29 M-a (a word to your words, or out), 30 M-? (/help),
# 31 M-Up, M-p or M-{ (mugen's answer before), 32 M-Down, M-n or M-} (the
# one after).
# While searching, Enter, C-g, Esc and Shift-Tab are the search's.
def sc.key.k(key: K.ky.Key, +find: Bool, +empty: Bool, +back: Bool, +tabs: Bool) -> Nat:
  match key:
    case K.ky.Nav{1, 2}:
      31n
    case K.ky.Nav{2, 2}:
      32n
    case K.ky.Nav{1, m}:
      Bool.pick(Nat, Bool.and(back, Bool.and(empty, Bool.not(find))), 20n, 0n)
    case K.ky.Nav{4, 2}:
      Bool.pick(Nat, tabs, 21n, 0n)
    case K.ky.Nav{3, 2}:
      Bool.pick(Nat, tabs, 22n, 0n)
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
    case K.ky.Meta{111}:
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
    case K.ky.Nav{5, m}:
      Bool.pick(Nat, empty, 12n, 0n)
    case K.ky.BackTab{}:
      Bool.pick(Nat, find, 0n, 27n)
    case K.ky.Meta{115}:
      23n
    case K.ky.Meta{83}:
      24n
    case K.ky.Meta{97}:
      29n
    case K.ky.Meta{63}:
      30n
    case K.ky.Meta{112}:
      31n
    case K.ky.Meta{110}:
      32n
    case K.ky.Meta{123}:
      31n
    case K.ky.Meta{125}:
      32n
    case K.ky.Meta{+c}:
      Bool.pick(Nat, P.pp.in(c, 49, 57), 25n, 0n)
    case K.ky.Mouse{35, x, y, up}:
      28n
    case K.ky.Mouse{64, x, y, up}:
      14n
    case K.ky.Mouse{65, x, y, up}:
      15n
    case K.ky.Mouse{0, x, y, False{}}:
      16n
    case K.ky.Mouse{0, x, y, True{}}:
      19n
    case K.ky.Mouse{32, x, y, up}:
      18n
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

def sc.mouse.x(key: K.ky.Key) -> U32:
  match key:
    case K.ky.Mouse{b, x, y, up}:
      x
    case _:
      0

# a drag: the selection grows (drawn anew); none begun, nothing
def sc.drag(+s: sc.S, +x: U32, +y: U32) -> sc.S:
  +z = sc.z(s)
  Bool.pick(sc.S, sc.sel.on(z), sc.dirty(sc.with.z(s, sc.sel.drag(z, x, y)), 2), s)

# what a let go does: 0 nothing (no press), 1 a click, 2 a copy
def sc.up.k(+z: sc.Sel) -> Nat:
  Bool.pick(Nat, sc.sel.on(z), Bool.pick(Nat, sc.sel.moved(z), 2n, 1n), 0n)

# a click: on the pinned prompt (1) it scrolls there, else it folds
def sc.click.at(k: Nat, +s: sc.S, +y: U32) -> sc.S:
  match k:
    case 1n:
      sc.to.pin(s)
    case _:
      sc.click(s, y)

# what a copy says under the chat, from where sc.clip put it (x X's
# clipboard, t tmux's buffer, o the terminal's by OSC 52, none nowhere)
def sc.copied(+n: Nat, +to: String) -> String:
  +what = Nat.show(n) ++ Bool.pick(String, Nat.is_eq(n, 1n), " line", " lines")
  +x = String.contains(to, "x")
  +t = String.contains(to, "t")
  +o = String.contains(to, "o")
  Bool.pick(String, Bool.or(Bool.or(x, t), o),
    P.pp.paint("1;32", Bool.pick(String, Bool.or(x, t), "\u{2713} copied " ++ what ++ Bool.pick(String, x, " to the clipboard", " to tmux's buffer (the terminal's clipboard too, if it takes OSC 52)"),
      "\u{2713} sent " ++ what ++ " to the terminal's clipboard (by OSC 52, if it takes it)")),
    P.pp.paint("1;31", "\u{2717} not copied: no X display for xclip, no tmux, no terminal"))
    ++ P.pp.paint("2", " \u{b7} Shift-drag selects with the terminal")

def sc.copied.of(o: S.mu.Out, +n: Nat) -> String:
  match o:
    case S.mu.Out{status, out, err}:
      sc.copied(n, out)

# the tabs: a click on one (column x, from 1), or M-Left / M-Right
def sc.tab.click(+s: sc.S, +x: U32) -> sc.S:
  +ags = sc.st.agents(sc.st(s))
  +ts = sc.tabs(ags, sc.focus(s))
  +x0 = (P.pp.vis(sc.status.base(s)) + 3 : U32)
  +c = (x - U32.min(x, 1) : U32)
  +m = Bool.pick(Maybe<&2, String>, U32.is_lt(c, x0), None{}, sc.tab.at(ts, (c - x0 : U32), ags))
  Bool.pick(sc.S, Maybe.is_none(&2, String, m), s, sc.with.focus(s, Maybe.default(&2, String, m, "all")))

def sc.tab.step(+s: sc.S, +fwd: Bool) -> sc.S:
  +ts = sc.tabs(sc.st.agents(sc.st(s)), sc.focus(s))
  +n = List.length(&2, String, ts)
  +i = sc.tab.index(ts, sc.tab.of(sc.focus(s)), 0n)
  +j = Bool.pick(Nat, fwd, Bool.pick(Nat, Nat.is_ge(Nat.add(i, 1n), n), 0n, Nat.add(i, 1n)), Bool.pick(Nat, Nat.is_eq(i, 0n), Nat.sub(n, 1n), Nat.sub(i, 1n)))
  Bool.pick(sc.S, Nat.is_eq(n, 0n), s, sc.with.focus(s, Maybe.default(&2, String, List.get(&2, String, ts, j), "all")))

# the screen row (from 1) of the status line, as drawn now
def sc.status.y(+s: sc.S) -> U32:
  +low = sc.low(s)
  +nl = U32.from_nat(List.length(&2, String, sc.low.rows(low)))
  +h = sc.h(s)
  +t = Bool.pick(U32, U32.is_gt(h, nl), (h - nl : U32), 0)
  (t + (sc.low.stat(low) + 1 : U32) : U32)

# the input set to a fix's text and cursor (the mouse's word forgotten)
def sc.sp.set(+s: sc.S, +x: Sp.sp.Ed, +hint: String) -> sc.S:
  +t = Sp.sp.ed.text(x)
  +c = Sp.sp.ed.cur(x)
  +e = sc.ed(s)
  sc.dirty(sc.with.hint(sc.with.sp(sc.with.ed(s, D.ed.with(e, String.reverse(String.take(t, c)), String.drop(t, c))), Sp.sp.with.shut(Sp.sp.with.mx(sc.sp(s), 0n), 0n)), hint), 1)

# the text and the cursor, for Spell's fixes
def sc.sp.ed(+s: sc.S) -> Sp.sp.Ed:
  +e = sc.ed(s)
  Sp.sp.Ed{D.ed.text(e), String.length(D.ed.pre(e))}

def sc.fix.one(m: Maybe<&2, String>, +s: sc.S, +f: Sp.sp.F, +i: Nat) -> sc.S:
  match m:
    case Some{r}:
      sc.sp.set(s, Sp.sp.fix(sc.sp.ed(s), f, i), "")
    case None{}:
      sc.dirty(sc.with.hint(s, "no suggestion " ++ Nat.show(Nat.add(i, 1n)) ++ " for \u{ab}" ++ Sp.sp.f.text(f) ++ "\u{bb}"), 1)

def sc.fix.go(m: Maybe<&2, Sp.sp.F>, +s: sc.S, +i: Nat) -> sc.S:
  match m:
    case Some{+f}:
      sc.fix.one(List.get(&2, String, Sp.sp.f.sugg(f), i), s, f, i)
    case None{}:
      sc.dirty(sc.with.hint(s, Bool.pick(String, Sp.sp.on(sc.sp(s)), "no misspelled word under the mouse or the cursor", "spellcheck off (/spell on)")), 1)

def sc.word.of(m: Maybe<&2, Nat>, +fs: List<&2, Sp.sp.F>) -> Nat:
  match m:
    case Some{+at}:
      Sp.sp.key.of(Sp.sp.over(fs, at))
    case None{}:
      0n

# the misspelled word at column x, row y of the screen: where it starts,
# plus 1 (0 none). The input's text starts at column 3, after the lambda.
def sc.word.at(+sl: sc.Sl, +x: U32, +y: U32) -> Nat:
  +y0 = sc.sl.y0(sl)
  +in = Bool.and(Bool.and(U32.is_ge(y, y0), U32.is_lt(y, (y0 + sc.sl.n(sl) : U32))), U32.is_ge(x, 3))
  +i = (sc.sl.top(sl) + (y - U32.min(y, y0) : U32) : U32)
  +m = Sp.sp.spot(sc.sl.rows(sl), sc.sl.sts(sl), i, (x - U32.min(x, 3) : U32))
  Bool.pick(Nat, in, sc.word.of(m, sc.sl.fs(sl)), 0n)

def sc.click.go(k: Nat, +s: sc.S, +sl: sc.Sl, +x: U32, +y: U32) -> IO(sc.S):
  match k:
    case 1n:
      IO.pure(sc.S, sc.fix.go(sc.sl.tgt(sl), s, U32.to_nat((y - U32.min(y, sc.bx.y(sc.sl.box(sl))) : U32))))
    case 2n:
      IO.pure(sc.S, sc.dirty(sc.with.sp(s, Sp.sp.with.shut(Sp.sp.with.mx(sc.sp(s), sc.word.at(sl, x, y)), 0n)), 1))
    case 3n:
      IO.pure(sc.S, s)
    case 4n:
      sc.words.key(s)
    case _:
      Bool.pick(IO(sc.S), U32.is_eq(y, sc.status.y(s)), IO.pure(sc.S, sc.dirty(sc.tab.click(s, x), 2)),
        IO.pure(sc.S, sc.click.at(Bool.pick(Nat, Bool.and(U32.is_eq(y, 1), Bool.not(U32.is_eq(sc.sel.pin(sc.z(s)), 0))), 1n, 0n), s, y)))

# what a click is: 1 on a suggestion in the box, 2 on a misspelled word
# of the input (its box opens: a phone has no pointer), 3 on the box's
# keys (nothing), 4 on its + add row (M-a), 0 any other (sc.up)
def sc.click.k(+sl: sc.Sl, +x: U32, +y: U32) -> Nat:
  +b = sc.sl.box(sl)
  +i = (y - U32.min(y, sc.bx.y(b)) : U32)
  +n = sc.bx.n(b)
  Bool.pick(Nat, sc.bx.on(b, x, y), Bool.pick(Nat, U32.is_lt((i + 2 : U32), n), 1n, Bool.pick(Nat, U32.is_eq((i + 2 : U32), n), 4n, 3n)),
    Bool.pick(Nat, Nat.is_eq(sc.word.at(sl, x, y), 0n), 0n, 2n))

def sc.up(k: Nat, +s: sc.S, +x: U32, +y: U32) -> IO(sc.S):
  match k:
    case 0n:
      IO.pure(sc.S, s)
    case 1n:
      +s1 = sc.with.z(s, sc.sel.off(sc.z(s)))
      +sl = sc.low.sl(sc.low(s1))
      sc.click.go(sc.click.k(sl, x, y), s1, sl, x, y)
    case _:
      +z = sc.z(s)
      +text = sc.sel.text(z)
      do IO<sc.S>:
        o : S.mu.Out <- S.mu.run("sh", ["-c", sc.clip()], text, 4096, 5000)
        return sc.dirty(sc.with.hint(sc.with.z(s, sc.sel.off(z)), sc.copied.of(o, List.length(&2, String, P.pp.split(text)))), 2)

# Esc with the box open closes it (and is no first Esc of two that leave)
def sc.esc.or(open: Bool, +s: sc.S) -> IO(sc.S):
  match open:
    case True{}:
      +tgt = sc.sl.tgt(sc.low.sl(sc.low(s)))
      IO.pure(sc.S, sc.dirty(sc.with.sp(s, Sp.sp.with.shut(sc.sp(s), Sp.sp.key.of(tgt))), 1))
    case False{}:
      sc.esc(s)

# M-s (i 0), M-1 to M-9: the word the box is for replaced by suggestion i
def sc.fix(+s: sc.S, +i: Nat) -> sc.S:
  sc.fix.go(sc.sl.tgt(sc.low.sl(sc.low(s))), s, i)

# M-S: every misspelled word of the input replaced by its first suggestion
def sc.fix.every(+s: sc.S) -> sc.S:
  +fs = sc.flags(s)
  +n = Sp.sp.fixable(fs)
  Bool.pick(sc.S, Nat.is_eq(n, 0n), sc.dirty(sc.with.hint(s, "no misspelled word with a suggestion"), 1),
    sc.sp.set(s, Sp.sp.fix.all(fs, sc.sp.ed(s)), "fixed " ++ Nat.show(n) ++ Bool.pick(String, Nat.is_eq(n, 1n), " word", " words")))

def sc.meta.c(key: K.ky.Key) -> U32:
  match key:
    case K.ky.Meta{c}:
      c
    case _:
      0

# Shift-Tab: plan mode, or back to auto (the hub's /plan and /auto), as in
# Claude Code. The mode shows at once, the hub's state says it after.
def sc.mode.flip(+s: sc.S) -> IO(sc.S):
  +st = sc.st(s)
  +plan = Bool.not(sc.st.plan(st))
  +say = Bool.pick(String, plan, P.pp.paint("1;33", "plan mode") ++ P.pp.paint("2", ": mugen reads and proposes, changing nothing \u{b7} Shift-Tab: auto"),
    P.pp.paint("1;32", "auto mode") ++ P.pp.paint("2", ": mugen runs its tools as it needs them \u{b7} Shift-Tab: plan"))
  do IO<sc.S>:
    Unit <- sc.send(s, Bool.pick(String, plan, "/plan", "/auto"))
    return sc.dirty(sc.with.hint(sc.with.st(s, sc.st.with.plan(st, plan)), say), 1)

# Events ------------------------------------------------------------------------

# the mouse moved (mode 1003, no button held): over a misspelled word of the
# input, its box opens; off it, the box closes; on the box, it stays
def sc.hover(+s: sc.S, +x: U32, +y: U32) -> sc.S:
  +sp = sc.sp(s)
  +sl = sc.low.sl(sc.low(s))
  +mx = Bool.pick(Nat, sc.bx.on(sc.sl.box(sl), x, y), Sp.sp.mx(sp), sc.word.at(sl, x, y))
  Bool.pick(sc.S, Nat.is_eq(mx, Sp.sp.mx(sp)), s, sc.dirty(sc.with.sp(s, Sp.sp.with.mx(sp, mx)), 1))

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
      sc.esc.or(Bool.not(List.is_empty(&2, String, sc.bx.rows(sc.low.box(sc.low(s))))), s)
    case 9n:
      sc.tab.go(sc.tab.k(s), s)
    case 10n:
      IO.pure(sc.S, sc.scroll(s, True{}, sc.page(s)))
    case 11n:
      IO.pure(sc.S, sc.scroll(s, False{}, sc.page(s)))
    case 12n:
      IO.pure(sc.S, sc.scroll(s, True{}, sc.top()))
    case 13n:
      IO.pure(sc.S, sc.dirty(sc.with.off(s, 0), 2))
    case 14n:
      IO.pure(sc.S, sc.scroll(s, True{}, 3))
    case 15n:
      IO.pure(sc.S, sc.scroll(s, False{}, 3))
    case 16n:
      IO.pure(sc.S, sc.with.z(s, sc.sel.press(sc.z(s), sc.mouse.x(key), sc.mouse.y(key))))
    case 18n:
      IO.pure(sc.S, sc.drag(s, sc.mouse.x(key), sc.mouse.y(key)))
    case 19n:
      sc.up(sc.up.k(sc.z(s)), s, sc.mouse.x(key), sc.mouse.y(key))
    case 20n:
      IO.bind(Unit, sc.S, sc.send(s, "/back"), u => IO.pure(sc.S, s))
    case 21n:
      IO.pure(sc.S, sc.tab.step(s, False{}))
    case 22n:
      IO.pure(sc.S, sc.tab.step(s, True{}))
    case 23n:
      IO.pure(sc.S, sc.fix(s, 0n))
    case 24n:
      IO.pure(sc.S, sc.fix.every(s))
    case 25n:
      IO.pure(sc.S, sc.fix(s, Nat.sub(U32.to_nat(sc.meta.c(key)), 49n)))
    case 27n:
      sc.mode.flip(s)
    case 28n:
      IO.pure(sc.S, sc.hover(s, sc.mouse.x(key), sc.mouse.y(key)))
    case 29n:
      sc.words.key(s)
    case 30n:
      IO.bind(Unit, sc.S, sc.send(s, "/help"), u => IO.pure(sc.S, sc.dirty(sc.with.off(sc.with.hint(s, ""), 0), 2)))
    case 31n:
      sc.to.ans.up(s)
    case 32n:
      IO.pure(sc.S, sc.to.ans(s, False{}))
    case _:
      IO.pure(sc.S, s)

def sc.key(+s: sc.S, +key: K.ky.Key) -> IO(sc.S):
  +e = sc.ed(s)
  +back = Bool.not(List.is_empty(&2, String, sc.st.wait(sc.st(s))))
  +tabs = Bool.not(List.is_empty(&2, String, sc.tabs(sc.st.agents(sc.st(s)), sc.focus(s))))
  +k = sc.key.k(key, Maybe.is_some(&2, String, D.ed.find(e)), D.ed.is.empty(e), back, tabs)
  +s1 = Bool.pick(sc.S, Bool.or(Nat.is_eq(k, 8n), Nat.is_eq(k, 28n)), s, sc.with.esc(s, 0n))
  sc.key.go(k, s1, key)

# The spellcheck ------------------------------------------------------------------
#
# Spell.bend has the words and the answers; here they are asked (a call to
# hunspell at a time, on a tick, its answer an sc.Spelt), shown (sc.low:
# the underline, the box) and fixed (M-s, M-1 to M-9, a click in the box,
# M-S).

# what the spellcheck looked at last: the text and the cursor
def sc.spell.key(+s: sc.S) -> String:
  +e = sc.ed(s)
  D.ed.text(e) ++ "\u{0}" ++ Nat.show(String.length(D.ed.pre(e)))

# what the hub says (sent, whatever came of it)
def sc.tell(+me: Chan(sc.In), +x: sc.In) -> IO(Unit):
  IO.bind(Result<&1, &1, sc.In, Unit>, Unit, Chan.send(sc.In, me, x), r => IO.pure(Unit, Unit{}))

def sc.spell.job(+me: Chan(sc.In), +ws: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    o : S.mu.Out <- S.mu.run("hunspell", Sp.sp.args(), Sp.sp.ask(ws), 1048576, 10000)
    sc.tell(me, sc.Spelt{ws, o})

def sc.spell.ask(none: Bool, +s: sc.S, +key: String, +ws: List<&2, String>) -> IO(sc.S):
  match none:
    case True{}:
      IO.pure(sc.S, sc.with.sp(s, Sp.sp.with.last(sc.sp(s), key)))
    case False{}:
      do IO<sc.S>:
        Unit <- IO.spawn(Unit, sc.spell.job(sc.cf.me(sc.cf(s)), ws))
        return sc.with.sp(s, Sp.sp.with.asking(sc.sp(s), key))

def sc.spell.look(go: Bool, +s: sc.S, +key: String) -> IO(sc.S):
  match go:
    case False{}:
      IO.pure(sc.S, s)
    case True{}:
      +e = sc.ed(s)
      +ws = Sp.sp.fresh(Sp.sp.words(D.ed.text(e), String.length(D.ed.pre(e))), Sp.sp.seen(sc.sp(s)), [])
      sc.spell.ask(List.is_empty(&2, String, ws), s, key, ws)

# at a tick: once the text or the cursor moved, the words not asked about
# yet asked of hunspell (none while a call is under way)
def sc.spell(+s: sc.S) -> IO(sc.S):
  +sp = sc.sp(s)
  +key = sc.spell.key(s)
  sc.spell.look(Bool.and(Bool.and(Sp.sp.on(sp), Bool.not(Sp.sp.busy(sp))), Bool.not(String.eq(key, Sp.sp.last(sp)))), s, key)

# hunspell's answer kept; it did not run: the spellcheck off, said once
def sc.spelt.go(ran: Bool, +s: sc.S, +ws: List<&2, String>, +out: String, +err: String) -> sc.S:
  match ran:
    case True{}:
      sc.dirty(sc.with.sp(s, Sp.sp.with.got(sc.sp(s), ws, Sp.sp.parse(out, ws))), 1)
    case False{}:
      +why = Maybe.default(&2, String, List.get(&2, String, String.lines(String.trim(err)), 0n), "")
      sc.add(sc.with.sp(s, Sp.sp.with.on(sc.sp(s), False{})), "", "info", "spellcheck off: hunspell (en_US) did not run" ++ Bool.pick(String, String.is_empty(why), "", " (" ++ why ++ ")") ++ "; /spell on tries again", False{})

def sc.spelt(+s: sc.S, +ws: List<&2, String>, o: S.mu.Out) -> sc.S:
  match o:
    case S.mu.Out{+status, +out, +err}:
      sc.spelt.go(Sp.sp.ran(status, out), s, ws, out, err)

def sc.size(+s: sc.S, +ws: U32) -> sc.S:
  +m = sc.tm(s)
  +w = U32.max(20, U32.and(ws, 65535))
  +h = U32.max(6, U32.shrn(ws, 16n))
  Bool.pick(sc.S, Bool.or(U32.is_eq(ws, 0), Bool.and(U32.is_eq(w, sc.tm.w(m)), U32.is_eq(h, sc.tm.h(m)))), s,
    sc.with.tm(s, sc.Tm{w, h, 2, sc.tm.mouse(m), sc.tm.low(m)}))

# A phone noticed. Conduit (on xterm.dart) answers no XTVERSION, so tmux
# knows no type for its client (#{client_termtype} empty), where VTE, xterm,
# kitty and the like each give theirs. There a swipe is the wheel (buttons
# 68 and 69, Keys.bend), so it scrolls the chat while mugen has the mouse;
# Conduit's own tmux-scrollback key scrolls tmux instead. Asked when mugen
# starts and when the width changes (a client of another size took over).
def sc.phone.ask() -> String:
  "[ -n \"$TMUX\" ] && tmux display-message -p '#{client_termtype}|#{client_termname}' 2>/dev/null"

def sc.phone.hint(+mouse: Bool) -> String:
  P.pp.paint("1;36", Bool.pick(String, mouse, "Conduit noticed: swipe to scroll", "Conduit noticed: /mouse, then swipe to scroll"))
    ++ P.pp.paint("2", " \u{b7} not its tmux-scroll key")

def sc.phone.got(o: S.mu.Out, +s: sc.S) -> sc.S:
  match o:
    case S.mu.Out{status, out, err}:
      Bool.pick(sc.S, String.starts_with(out, "|xterm"), sc.dirty(sc.with.hint(s, sc.phone.hint(sc.tm.mouse(sc.tm(s)))), 1), s)

def sc.phone(go: Bool, +s: sc.S) -> IO(sc.S):
  match go:
    case True{}:
      IO.bind(S.mu.Out, sc.S, S.mu.run("sh", ["-c", sc.phone.ask()], "", 4096, 2000), o => IO.pure(sc.S, sc.phone.got(o, s)))
    case False{}:
      IO.pure(sc.S, s)

# a tick: the size checked (a new width: a phone?); the spinner and the
# times on, if anything runs; the input's new words asked of hunspell
def sc.tick(+s: sc.S) -> IO(sc.S):
  do IO<sc.S>:
    now : Nat <- IO.now()
    ws : U32 <- S.mu.winsize()
    +s1 : sc.S = sc.size(sc.with.now(s, now), ws)
    +live : Bool = Bool.or(Bool.or(sc.st.busy(sc.st(s1)), Maybe.is_some(&2, sc.Blk, sc.running(sc.blks(s1)))), Bool.not(List.is_empty(&2, String, sc.st.agents(sc.st(s1)))))
    +s2 : sc.S <- sc.phone(Bool.not(U32.is_eq(sc.w(s), sc.w(s1))), Bool.pick(sc.S, live, sc.dirty(s1, 1), s1))
    sc.spell(s2)

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
    case Some{sc.Spelt{+ws, +o}}:
      IO.pure(sc.S, sc.spelt(s, ws, o))
    case Some{sc.Back{+text}}:
      IO.pure(sc.S, sc.dirty(sc.with.hint(sc.with.ed(s, D.ed.taken(sc.ed(s), text)), "taken back from the queue: edit it, Enter sends it"), 1))
    case Some{sc.Since{+from}}:
      IO.pure(sc.S, sc.with.tr(s, sc.tr.with.old(sc.tr(s), from)))
    case Some{sc.Old{+before, +from, ms}}:
      sc.old.got(s, before, from, ms)

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
        +s2a : sc.S <- sc.ag.load(sc.ag.want(s2), s2)
        +s3 : sc.S <- sc.draw(s2a)
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

# after a read failed: 0 the end, 1 read again, 2 read again in a while.
# The terminal held by another process group (a shell with job control that
# took it, as dash's `set -m` does) or a read cut short (EINTR, EAGAIN) is
# no end: only a terminal gone is (mu.fg 3), or a failure while ours (0)
def sc.read.k(+fg: U32, +code: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(fg, 1), 1n,
    Bool.pick(Nat, Bool.or(U32.is_eq(fg, 2), Bool.and(U32.is_eq(fg, 0), Bool.or(U32.is_eq(code, 4), U32.is_eq(code, 11)))), 2n, 0n))

# the read after a failed one (k as sc.read.k gives it): an empty one, the
# end, for 0
def sc.read.again(k: Nat, file: File) -> IO(File & Result<&1, &1, U32 & String, String>):
  match k:
    case 0n:
      IO.pure(File & Result<&1, &1, U32 & String, String>, (file, Done{""}))
    case 1n:
      File.read(file, 65536)
    case _:
      IO.bind(Unit, File & Result<&1, &1, U32 & String, String>, IO.sleep(100), u => File.read(file, 65536))

def sc.read(fuel: Nat, +me: Chan(sc.In), st: K.ky.St, r: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match fuel r:
    case 1n+f Tuple{file, Done{SCon{h, t}}}:
      +o = K.ky.feed(st, SCon{h, t})
      do IO<Unit>:
        now : Nat <- IO.now()
        Unit <- sc.keys(K.ky.out.keys(o), now, me)
        r2 : File & Result<&1, &1, U32 & String, String> <- File.read(file, 65536)
        sc.read(f, me, K.ky.out.st(o), r2)
    case 1n+f Tuple{file, Fail{(code, text)}}:
      do IO<Unit>:
        v : U32 <- S.mu.fg()
        r2 : File & Result<&1, &1, U32 & String, String> <- sc.read.again(sc.read.k(v, code), file)
        sc.read(f, me, st, r2)
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
    +s0 : sc.S = sc.size(sc.S{sc.Cf{hub, me, home, hfile}, D.ed.new(hist), sc.Tr{[], 16777216, 0, [], sc.An{0, 0, 0}, "", [], 0}, sc.Tm{80, 24, 2, True{}, 0}, sc.idle(), sc.U{now, 0n, "", False{}, False{}, ""}, sc.sel.none([]), Sp.sp.new()}, ws)
    Unit <- IO.spawn(Unit, sc.reader(me))
    Unit <- IO.spawn(Unit, sc.ticker(sc.fuel(), me, Done{Unit{}}))
    +s0p : sc.S <- sc.phone(True{}, s0)
    +s1 : sc.S <- sc.draw(sc.dirty(s0p, 2))
    sc.loop(sc.fuel(), True{}, s1)
