
import Base
import ./Keys.bend as K
import ./Pretty.bend as P
import ./Help.bend as Hl

# Edit: the input (Screen.bend), an emacs-style editor of a message of any
# number of lines. It holds the text before the cursor (reversed) and after
# it; the text last cut (C-k, C-u, C-w, M-d, M-Backspace; C-y yanks it
# back); the history, newest first, and where in it the text is (0: the one
# being written, kept as the draft while the history is browsed); and a
# reverse search (C-r), when one is on: what it looks for.
#
# Every def is prefixed `ed.` (a program's defs share one namespace).

type ed.Ed is Data:
  ed.Ed{pre: String, post: String, cut: String, hist: List<&2, String>, at: Nat, draft: String, find: Maybe<&2, String>}

def ed.new(+hist: List<&2, String>) -> ed.Ed:
  ed.Ed{"", "", "", hist, 0n, "", None{}}

def ed.text(e: ed.Ed) -> String:
  match e:
    case ed.Ed{pre, post, c, h, a, d, f}:
      String.reverse(pre) ++ post

def ed.hist(e: ed.Ed) -> List<&2, String>:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      h

def ed.find(e: ed.Ed) -> Maybe<&2, String>:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      f

def ed.is.empty(+e: ed.Ed) -> Bool:
  String.is_empty(ed.text(e))

# the text set whole, the cursor at its end
def ed.set(e: ed.Ed, +text: String) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      ed.Ed{String.reverse(text), "", c, h, a, d, f}

# the cursor and the text around it changed (the history's place kept)
def ed.with(e: ed.Ed, +pre: String, +post: String) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      ed.Ed{pre, post, c, h, a, d, f}

def ed.pre(e: ed.Ed) -> String:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      p

def ed.post(e: ed.Ed) -> String:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      q

def ed.cutted(e: ed.Ed) -> String:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      c

# a cut: what remains, and the text cut
def ed.cut.with(e: ed.Ed, +pre: String, +post: String, +cut: String) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      ed.Ed{pre, post, cut, h, a, d, f}

# Moving -------------------------------------------------------------------------

def ed.tail(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{c, +t}:
      t

def ed.head(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+c, t}:
      SCon{c, ""}

# a text's head, up to its first newline (not taken), and the rest from it
def ed.nl.v(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{10}, t}:
      0n
    case _:
      1n

def ed.upto.go(s: String, v: Nat, +acc: String) -> P.pp.Two:
  match s v:
    case SCon{+c, +t} 1n:
      ed.upto.go(t, ed.nl.v(t), SCon{c, acc})
    case SCon{+c, +t} _:
      P.pp.Two{String.reverse(acc), SCon{c, t}}
    case _ _:
      P.pp.Two{String.reverse(acc), ""}

def ed.upto(+s: String) -> P.pp.Two:
  ed.upto.go(s, ed.nl.v(s), "")

# 0 a newline or nothing, 1 a word's character, 2 any other
def ed.word.v(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, Bool.or(Bool.or(P.pp.in(c, 48, 57), P.pp.in(c, 65, 90)), Bool.or(Bool.or(P.pp.in(c, 97, 122), U32.is_eq(c, 95)), U32.is_ge(c, 128))), 1n, 2n)

# 1 when the head is of kind k (ed.word.v), else 0
def ed.kind.is(+s: String, +k: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(ed.word.v(s), k), 1n, 0n)

# characters moved from a to b (both read from their heads) while they are
# of kind k
def ed.move.go(a: String, v: Nat, +k: Nat, +b: String) -> P.pp.Two:
  match a v:
    case SCon{+c, +t} 1n:
      ed.move.go(t, ed.kind.is(t, k), k, SCon{c, b})
    case SCon{+c, +t} _:
      P.pp.Two{SCon{c, t}, b}
    case _ _:
      P.pp.Two{"", b}

# a word's worth moved from a to b: its other characters, then its own
def ed.word.go(+a: String, +b: String) -> P.pp.Two:
  +p = ed.move.go(a, ed.kind.is(a, 2n), 2n, b)
  ed.move.go(P.pp.fst(p), ed.kind.is(P.pp.fst(p), 1n), 1n, P.pp.snd(p))

def ed.back(e: ed.Ed) -> ed.Ed:
  match e:
    case ed.Ed{p, +q, c, h, a, d, f}:
      ed.Ed{ed.tail(p), q, c, h, a, d, f}

def ed.del(e: ed.Ed) -> ed.Ed:
  match e:
    case ed.Ed{+p, q, c, h, a, d, f}:
      ed.Ed{p, ed.tail(q), c, h, a, d, f}

def ed.left(+e: ed.Ed) -> ed.Ed:
  +p = ed.pre(e)
  ed.with(e, ed.tail(p), ed.head(p) ++ ed.post(e))

def ed.right(+e: ed.Ed) -> ed.Ed:
  +q = ed.post(e)
  ed.with(e, ed.head(q) ++ ed.pre(e), ed.tail(q))

# to the start, or the end, of the line the cursor is on
def ed.bol(+e: ed.Ed) -> ed.Ed:
  +t = ed.upto(ed.pre(e))
  ed.with(e, P.pp.snd(t), String.reverse(P.pp.fst(t)) ++ ed.post(e))

def ed.eol(+e: ed.Ed) -> ed.Ed:
  +t = ed.upto(ed.post(e))
  ed.with(e, String.reverse(P.pp.fst(t)) ++ ed.pre(e), P.pp.snd(t))

def ed.wleft(+e: ed.Ed) -> ed.Ed:
  +t = ed.word.go(ed.pre(e), ed.post(e))
  ed.with(e, P.pp.fst(t), P.pp.snd(t))

def ed.wright(+e: ed.Ed) -> ed.Ed:
  +t = ed.word.go(ed.post(e), ed.pre(e))
  ed.with(e, P.pp.snd(t), P.pp.fst(t))

# Cutting ------------------------------------------------------------------------

# C-k: to the line's end, or the newline that ends it
def ed.kill.eol(+e: ed.Ed) -> ed.Ed:
  +t = ed.upto(ed.post(e))
  +at = String.is_empty(P.pp.fst(t))
  ed.cut.with(e, ed.pre(e), Bool.pick(String, at, ed.tail(ed.post(e)), P.pp.snd(t)), Bool.pick(String, at, ed.head(ed.post(e)), P.pp.fst(t)))

# C-u: back to the line's start
def ed.kill.bol(+e: ed.Ed) -> ed.Ed:
  +t = ed.upto(ed.pre(e))
  ed.cut.with(e, P.pp.snd(t), ed.post(e), String.reverse(P.pp.fst(t)))

# C-w, M-Backspace: the word before; M-d: the word after
def ed.kill.wback(+e: ed.Ed) -> ed.Ed:
  +t = ed.word.go(ed.pre(e), "")
  ed.cut.with(e, P.pp.fst(t), ed.post(e), P.pp.snd(t))

def ed.kill.wfwd(+e: ed.Ed) -> ed.Ed:
  +t = ed.word.go(ed.post(e), "")
  ed.cut.with(e, ed.pre(e), P.pp.fst(t), String.reverse(P.pp.snd(t)))

def ed.put(+e: ed.Ed, +s: String) -> ed.Ed:
  ed.with(e, String.reverse(s) ++ ed.pre(e), ed.post(e))

def ed.yank(+e: ed.Ed) -> ed.Ed:
  ed.put(e, ed.cutted(e))

# a paste's text: its line ends as newlines
def ed.crlf(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{13}, SCon{Chr{10}, +t}}:
      SCon{Chr{10}, ed.crlf(t)}
    case SCon{Chr{13}, +t}:
      SCon{Chr{10}, ed.crlf(t)}
    case SCon{+c, +t}:
      SCon{c, ed.crlf(t)}

# Lines and history --------------------------------------------------------------

def ed.cols(+s: String) -> Nat:
  String.length(P.pp.fst(ed.upto(s)))

# up a line, to the same column (or the line's end)
def ed.line.up(+e: ed.Ed) -> ed.Ed:
  +t1 = ed.upto(ed.pre(e))
  +c = String.length(P.pp.fst(t1))
  +t2 = ed.upto(ed.tail(P.pp.snd(t1)))
  +line = String.reverse(P.pp.fst(t2))
  ed.with(e, String.reverse(String.take(line, c)) ++ P.pp.snd(t2), String.drop(line, c) ++ "\n" ++ String.reverse(P.pp.fst(t1)) ++ ed.post(e))

def ed.line.down(+e: ed.Ed) -> ed.Ed:
  +c = ed.cols(ed.pre(e))
  +t1 = ed.upto(ed.post(e))
  +t2 = ed.upto(ed.tail(P.pp.snd(t1)))
  +line = P.pp.fst(t2)
  ed.with(e, String.reverse(String.take(line, c)) ++ "\n" ++ String.reverse(P.pp.fst(t1)) ++ ed.pre(e), String.drop(line, c) ++ P.pp.snd(t2))

def ed.at(e: ed.Ed, +a2: Nat, +d2: String, +text: String) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      ed.Ed{String.reverse(text), "", c, h, a2, d2, f}

def ed.at.n(e: ed.Ed) -> Nat:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      a

def ed.draft(e: ed.Ed) -> String:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      d

# an older entry of the history; a newer one (the draft, past the newest)
def ed.older(+e: ed.Ed) -> ed.Ed:
  +a = ed.at.n(e)
  +h = ed.hist(e)
  Bool.pick(ed.Ed, Nat.is_ge(a, List.length(&2, String, h)), e,
    ed.at(e, Nat.add(a, 1n), Bool.pick(String, Nat.is_eq(a, 0n), ed.text(e), ed.draft(e)), Maybe.default(&2, String, List.get(&2, String, h, a), "")))

def ed.newer(+e: ed.Ed) -> ed.Ed:
  +a = ed.at.n(e)
  Bool.pick(ed.Ed, Nat.is_eq(a, 0n), e,
    ed.at(e, Nat.sub(a, 1n), ed.draft(e), Bool.pick(String, Nat.is_eq(a, 1n), ed.draft(e), Maybe.default(&2, String, List.get(&2, String, ed.hist(e), Nat.sub(a, 2n)), ""))))

def ed.has.nl(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{10}, t}:
      True{}
    case SCon{c, +t}:
      ed.has.nl(t)

def ed.up(+e: ed.Ed) -> ed.Ed:
  Bool.pick(ed.Ed, ed.has.nl(ed.pre(e)), ed.line.up(e), ed.older(e))

def ed.down(+e: ed.Ed) -> ed.Ed:
  Bool.pick(ed.Ed, ed.has.nl(ed.post(e)), ed.line.down(e), ed.newer(e))

# a message taken back from the queue: the text to edit (before whatever was
# typed since), and out of the history, so only the version sent at last is
# kept there
def ed.taken(e: ed.Ed, +t: String) -> ed.Ed:
  match e:
    case ed.Ed{+p, +q, c, +h, a, d, f}:
      +now = String.reverse(p) ++ q
      +text = Bool.pick(String, String.is_empty(now), t, t ++ "\n" ++ now)
      +h2 = Bool.pick(List<&2, String>, String.eq(Maybe.default(&2, String, List.get(&2, String, h, 0n), ""), t), List.drop(&2, String, h, 1n), h)
      ed.Ed{String.reverse(text), "", c, h2, 0n, "", None{}}

# the text sent: the input empty, the text the history's newest
def ed.sent(e: ed.Ed) -> ed.Ed:
  match e:
    case ed.Ed{+p, +q, c, +h, a, d, f}:
      +t = String.reverse(p) ++ q
      +keep = Bool.or(String.is_empty(t), String.eq(Maybe.default(&2, String, List.get(&2, String, h, 0n), ""), t))
      ed.Ed{"", "", c, List.take(&2, String, Bool.pick(List<&2, String>, keep, h, t <> h), 2000n), 0n, "", None{}}

# Searching ----------------------------------------------------------------------

def ed.find.at(hs: List<&2, String>, +q: String, +k: Nat) -> Maybe<&2, Nat>:
  match hs:
    case []:
      None{}
    case +h <> rest:
      Bool.pick(Maybe<&2, Nat>, String.contains(h, q), Some{k}, ed.find.at(rest, q, Nat.add(k, 1n)))

def ed.found(e: ed.Ed, +q: String, m: Maybe<&2, Nat>) -> ed.Ed:
  match e m:
    case ed.Ed{p, q0, c, +h, a, +d, f} Some{+k}:
      ed.Ed{String.reverse(Maybe.default(&2, String, List.get(&2, String, h, k), "")), "", c, h, Nat.add(k, 1n), Bool.pick(String, Nat.is_eq(a, 0n), String.reverse(p) ++ q0, d), Some{q}}
    case ed.Ed{p, q0, c, h, a, d, f} None{}:
      ed.Ed{p, q0, c, h, a, d, Some{q}}

# the search for q, from the entry at `from` on
def ed.search(+e: ed.Ed, +q: String, +from: Nat) -> ed.Ed:
  ed.found(e, q, ed.find.at(List.drop(&2, String, ed.hist(e), from), q, from))

def ed.find.off(e: ed.Ed) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f}:
      ed.Ed{p, q, c, h, a, d, None{}}

# a key while searching: a character narrows it, Backspace widens it, C-r
# finds an older match, C-g and Esc leave it as it was; any other key ends it
# (the text found kept) and is then a key of its own: 0 taken, 1 it ends
def ed.find.k(+key: K.ky.Key) -> Nat:
  match key:
    case K.ky.Char{c}:
      0n
    case K.ky.Back{}:
      0n
    case K.ky.Ctrl{114}:
      0n
    case K.ky.Ctrl{103}:
      0n
    case K.ky.Esc{}:
      0n
    case _:
      1n

def ed.find.key(+e: ed.Ed, +q: String, key: K.ky.Key) -> ed.Ed:
  match key:
    case K.ky.Char{+c}:
      ed.search(e, q ++ SCon{Chr{c}, ""}, Nat.sub(ed.at.n(e), Bool.pick(Nat, Nat.is_eq(ed.at.n(e), 0n), 0n, 1n)))
    case K.ky.Back{}:
      ed.search(e, String.take(q, Nat.sub(String.length(q), 1n)), 0n)
    case K.ky.Ctrl{114}:
      ed.search(e, q, ed.at.n(e))
    case _:
      ed.find.off(ed.at(e, 0n, "", ed.draft(e)))

# Keys ---------------------------------------------------------------------------

# a control key's edit, by its letter: 1 C-a, 2 C-e, 3 C-b, 4 C-f, 5 C-d,
# 6 C-h, 7 C-k, 8 C-u, 9 C-w, 10 C-y, 11 C-p, 12 C-n, 13 C-j, 14 C-r, 0 none
def ed.ctrl.k(+c: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(c, 97), 1n, Bool.pick(Nat, U32.is_eq(c, 101), 2n, Bool.pick(Nat, U32.is_eq(c, 98), 3n,
    Bool.pick(Nat, U32.is_eq(c, 102), 4n, Bool.pick(Nat, U32.is_eq(c, 100), 5n, Bool.pick(Nat, U32.is_eq(c, 104), 6n,
      Bool.pick(Nat, U32.is_eq(c, 107), 7n, Bool.pick(Nat, U32.is_eq(c, 117), 8n, Bool.pick(Nat, U32.is_eq(c, 119), 9n,
        Bool.pick(Nat, U32.is_eq(c, 121), 10n, Bool.pick(Nat, U32.is_eq(c, 112), 11n, Bool.pick(Nat, U32.is_eq(c, 110), 12n,
          Bool.pick(Nat, U32.is_eq(c, 106), 13n, Bool.pick(Nat, U32.is_eq(c, 114), 14n, 0n))))))))))))))

def ed.ctrl(k: Nat, +e: ed.Ed) -> ed.Ed:
  match k:
    case 1n:
      ed.bol(e)
    case 2n:
      ed.eol(e)
    case 3n:
      ed.left(e)
    case 4n:
      ed.right(e)
    case 5n:
      ed.del(e)
    case 6n:
      ed.back(e)
    case 7n:
      ed.kill.eol(e)
    case 8n:
      ed.kill.bol(e)
    case 9n:
      ed.kill.wback(e)
    case 10n:
      ed.yank(e)
    case 11n:
      ed.up(e)
    case 12n:
      ed.down(e)
    case 13n:
      ed.put(e, "\n")
    case 14n:
      ed.search(e, "", 0n)
    case _:
      e

# M-b, M-f, M-d
def ed.meta(k: Nat, +e: ed.Ed) -> ed.Ed:
  match k:
    case 1n:
      ed.wleft(e)
    case 2n:
      ed.wright(e)
    case 3n:
      ed.kill.wfwd(e)
    case _:
      e

def ed.meta.k(+c: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(c, 98), 1n, Bool.pick(Nat, U32.is_eq(c, 102), 2n, Bool.pick(Nat, U32.is_eq(c, 100), 3n, 0n)))

# the cursor keys and Delete (Keys.bend ky.Nav)
def ed.nav(k: U32, +e: ed.Ed) -> ed.Ed:
  match k:
    case 1:
      ed.up(e)
    case 2:
      ed.down(e)
    case 3:
      ed.right(e)
    case 4:
      ed.left(e)
    case 5:
      ed.bol(e)
    case 6:
      ed.eol(e)
    case 9:
      ed.del(e)
    case _:
      e

# an editing key (the screen takes the others first)
def ed.edit(+e: ed.Ed, key: K.ky.Key) -> ed.Ed:
  match key:
    case K.ky.Char{+c}:
      ed.put(e, SCon{Chr{c}, ""})
    case K.ky.Paste{+t}:
      ed.put(e, ed.crlf(t))
    case K.ky.Newline{}:
      ed.put(e, "\n")
    case K.ky.Back{}:
      ed.back(e)
    case K.ky.MetaBack{}:
      ed.kill.wback(e)
    case K.ky.Ctrl{+c}:
      ed.ctrl(ed.ctrl.k(c), e)
    case K.ky.Meta{+c}:
      ed.meta(ed.meta.k(c), e)
    case K.ky.Nav{k, m}:
      ed.nav(k, e)
    case _:
      e

def ed.find.on(m: Maybe<&2, String>, k: Nat, +e: ed.Ed, +key: K.ky.Key) -> ed.Ed:
  match m k:
    case Some{+q} 0n:
      ed.find.key(e, q, key)
    case Some{q} _:
      ed.edit(ed.find.off(e), key)
    case None{} _:
      ed.edit(e, key)

# a key: to the search if one is on, else an edit
def ed.key(+e: ed.Ed, +key: K.ky.Key) -> ed.Ed:
  ed.find.on(ed.find(e), ed.find.k(key), e, key)

# Completing ---------------------------------------------------------------------

# the commands (the first word of each; Help.bend names every one), and
# what may follow some
def ed.words() -> List<&2, String>:
  List.append(&2, String, ["/help", "/quit", "/stop", "/now", "/goal", "/halt", "/model", "/effort", "/status", "/tree", "/export", "/plan", "/auto", "/mouse", "/image", "/spell", "/words",
    "/model opus-5.5", "/model sonnet-5.5", "/model haiku-5.5", "/effort low", "/effort medium", "/effort high", "/effort xhigh", "/effort max", "/spell on", "/spell off", "/words add", "/words rm"], Hl.hl.cmds())

def ed.starting(ws: List<&2, String>, +p: String) -> List<&2, String>:
  match ws:
    case []:
      []
    case +w <> rest:
      List.append(&2, String, Bool.pick(List<&2, String>, String.starts_with(w, p), [w], []), ed.starting(rest, p))

def ed.common(a: String, b: String) -> String:
  match a b:
    case SCon{Chr{+x}, +s} SCon{Chr{+y}, +t}:
      Bool.pick(String, U32.is_eq(x, y), SCon{Chr{x}, ed.common(s, t)}, "")
    case _ _:
      ""

def ed.prefix(ws: List<&2, String>, +acc: String) -> String:
  match ws:
    case []:
      acc
    case +w <> rest:
      ed.prefix(rest, ed.common(acc, w))

# Tab on a command: the text completed as far as the commands it may be
# agree; the matches, to show when more than one
def ed.complete(+e: ed.Ed) -> ed.Ed:
  +t = ed.text(e)
  +ms = ed.starting(ed.words(), t)
  +one = Nat.is_eq(List.length(&2, String, ms), 1n)
  Bool.pick(ed.Ed, Bool.or(Bool.not(String.starts_with(t, "/")), List.is_empty(&2, String, ms)), e,
    ed.set(e, Bool.pick(String, one, Maybe.default(&2, String, List.get(&2, String, ms, 0n), t) ++ " ", ed.prefix(ms, Maybe.default(&2, String, List.get(&2, String, ms, 0n), t)))))

def ed.matches(+e: ed.Ed) -> List<&2, String>:
  +t = ed.text(e)
  Bool.pick(List<&2, String>, String.starts_with(t, "/"), ed.starting(ed.words(), t), [])

# Laying out ---------------------------------------------------------------------
#
# The text in rows of `room` columns (after the prompt), and where the
# cursor falls: it is where k is 1 (k counts down to it, then stays 0).

type ed.Lay is Data:
  ed.Lay{rows: List<&2, String>, row: U32, col: U32}

def ed.lay.row(l: ed.Lay) -> U32:
  match l:
    case ed.Lay{r, y, x}:
      y

def ed.lay.col(l: ed.Lay) -> U32:
  match l:
    case ed.Lay{r, y, x}:
      x

def ed.lay.rows(l: ed.Lay) -> List<&2, String>:
  match l:
    case ed.Lay{r, y, x}:
      r

# what the next character does: 0 none left, 1 a newline, 2 it fits the row
# (a control character, a tab say, is shown as a space), 3 it starts a row
def ed.lay.v(s: String, +col: U32, +room: U32) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{10}, t}:
      1n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, U32.is_le((col + P.pp.cw(c) : U32), room), 2n, 3n)

def ed.lay.go(n: Nat, s: String, v: Nat, +k: Nat, +room: U32, +col: U32, +cur: String, +rows: List<&2, String>, +y: U32, +cy: U32, +cx: U32) -> ed.Lay:
  match n s v:
    case 1n+f SCon{c, +t} 1n:
      +here = Nat.is_eq(k, 1n)
      ed.lay.go(f, t, ed.lay.v(t, 0, room), Nat.sub(k, 1n), room, 0, "", String.reverse(cur) <> rows, (y + 1 : U32), Bool.pick(U32, here, y, cy), Bool.pick(U32, here, col, cx))
    case 1n+f SCon{Chr{+c}, +t} 2n:
      +here = Nat.is_eq(k, 1n)
      +col2 = (col + P.pp.cw(c) : U32)
      ed.lay.go(f, t, ed.lay.v(t, col2, room), Nat.sub(k, 1n), room, col2, SCon{Chr{Bool.pick(U32, U32.is_lt(c, 32), 32, c)}, cur}, rows, y, Bool.pick(U32, here, y, cy), Bool.pick(U32, here, col, cx))
    case 1n+f SCon{+c, +t} 3n:
      ed.lay.go(f, SCon{c, t}, 2n, k, room, 0, "", String.reverse(cur) <> rows, (y + 1 : U32), cy, cx)
    case _ _ _:
      +here = Nat.is_eq(k, 1n)
      +wrap = Bool.and(here, U32.is_ge(col, room))
      ed.Lay{List.reverse(&2, String, Bool.pick(List<&2, String>, wrap, "" <> String.reverse(cur) <> rows, String.reverse(cur) <> rows)),
        Bool.pick(U32, here, Bool.pick(U32, wrap, (y + 1 : U32), y), cy), Bool.pick(U32, here, Bool.pick(U32, wrap, 0, col), cx)}

def ed.lay(+e: ed.Ed, +room: U32) -> ed.Lay:
  +t = ed.text(e)
  ed.lay.go(P.pp.fuel(), t, ed.lay.v(t, 0, room), Nat.add(String.length(ed.pre(e)), 1n), U32.max(room, 4), 0, "", [], 0, 0, 0)
