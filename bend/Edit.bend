
import Base
import ./Keys.bend as K
import ./Pretty.bend as P
import ./Help.bend as Hl

# Edit: the input (Screen.bend), an emacs-style editor of a message of any
# number of lines. It holds the text before the cursor (reversed) and after
# it; the text last cut (C-k, C-u, C-w, M-d, M-Backspace; C-y yanks it
# back); the history, newest first, and where in it the text is (0: the one
# being written, kept as the draft while the history is browsed); and a
# the history search (M-r), when one is on: what it looks for; and what
# emacs keeps besides (ed.Ex: the mark, the older kills, undo).
#
# Every def is prefixed `ed.` (a program's defs share one namespace).

# Emacs's state (2026-11-12, the user: "selection (with mark), yank, paste,
# search, go to beginning and end, text area commands"): the mark, where
# C-SPC set it while the region is on (cleared by C-g, by an edit, by a
# kill or a copy of the region); the kills before `cut`, newest first (M-y
# after C-y walks them, as emacs's kill ring); what C-/ undoes and C-?
# redoes (the text and the cursor before each change; typing a word is one
# change); the last command (1 typed, 2 a kill forward, 3 a kill back, 4 a
# yank, 0 any other: a kill after a kill adds to it, M-y needs a yank
# before it); the yank's place among the kills and its length; whether C-x
# waits for its second key.
type ed.Snap is Data:
  ed.Snap{text: String, at: Nat}

type ed.Ex is Data:
  ed.Ex{mark: Maybe<&2, Nat>, ring: List<&2, String>, undo: List<&2, ed.Snap>, redo: List<&2, ed.Snap>, last: Nat, yi: Nat, yl: Nat, cx: Bool}

def ed.ex.new() -> ed.Ex:
  ed.Ex{None{}, [], [], [], 0n, 0n, 0n, False{}}

# a new text (sent, taken back): the kills kept, the rest anew
def ed.ex.fresh(x: ed.Ex) -> ed.Ex:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      ed.Ex{None{}, r, [], [], 0n, 0n, 0n, False{}}

type ed.Ed is Data:
  ed.Ed{pre: String, post: String, cut: String, hist: List<&2, String>, at: Nat, draft: String, find: Maybe<&2, String>, ex: ed.Ex}

def ed.new(+hist: List<&2, String>) -> ed.Ed:
  ed.Ed{"", "", "", hist, 0n, "", None{}, ed.ex.new()}

def ed.text(e: ed.Ed) -> String:
  match e:
    case ed.Ed{pre, post, c, h, a, d, f, x}:
      String.reverse(pre) ++ post

def ed.hist(e: ed.Ed) -> List<&2, String>:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      h

def ed.find(e: ed.Ed) -> Maybe<&2, String>:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      f

def ed.is.empty(+e: ed.Ed) -> Bool:
  String.is_empty(ed.text(e))

# the text set whole, the cursor at its end
def ed.set(e: ed.Ed, +text: String) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      ed.Ed{String.reverse(text), "", c, h, a, d, f, x}

# the cursor and the text around it changed (the history's place kept)
def ed.with(e: ed.Ed, +pre: String, +post: String) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      ed.Ed{pre, post, c, h, a, d, f, x}

def ed.pre(e: ed.Ed) -> String:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      p

def ed.post(e: ed.Ed) -> String:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      q

def ed.cutted(e: ed.Ed) -> String:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      c

# the kill before a new one, onto the ring (sixty kept)
def ed.ex.push(x: ed.Ex, +c: String) -> ed.Ex:
  match x:
    case ed.Ex{m, +r, u, v, l, yi, yl, cx}:
      ed.Ex{m, List.take(&2, String, Bool.pick(List<&2, String>, String.is_empty(c), r, c <> r), 60n), u, v, l, yi, yl, cx}

# a cut: what remains, and the text cut (the kill before it onto the ring)
def ed.cut.with(e: ed.Ed, +pre: String, +post: String, +cut: String) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      ed.Ed{pre, post, cut, h, a, d, f, ed.ex.push(x, c)}

def ed.ex(e: ed.Ed) -> ed.Ex:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      x

def ed.with.ex(e: ed.Ed, +x2: ed.Ex) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      ed.Ed{p, q, c, h, a, d, f, x2}

# the text cut set as it is (no kill onto the ring: a kill added to the one before)
def ed.with.cut(e: ed.Ed, +c2: String) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      ed.Ed{p, q, c2, h, a, d, f, x}

def ed.ex.mark(x: ed.Ex) -> Maybe<&2, Nat>:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      m

def ed.ex.ring(x: ed.Ex) -> List<&2, String>:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      r

def ed.ex.undo(x: ed.Ex) -> List<&2, ed.Snap>:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      u

def ed.ex.redo(x: ed.Ex) -> List<&2, ed.Snap>:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      v

def ed.ex.last(x: ed.Ex) -> Nat:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      l

def ed.ex.yi(x: ed.Ex) -> Nat:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      yi

def ed.ex.yl(x: ed.Ex) -> Nat:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      yl

def ed.ex.cx(x: ed.Ex) -> Bool:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      cx

def ed.ex.with.mark(x: ed.Ex, +m2: Maybe<&2, Nat>) -> ed.Ex:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      ed.Ex{m2, r, u, v, l, yi, yl, cx}

def ed.ex.with.ring(x: ed.Ex, +r2: List<&2, String>) -> ed.Ex:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      ed.Ex{m, r2, u, v, l, yi, yl, cx}

def ed.ex.with.undo(x: ed.Ex, +u2: List<&2, ed.Snap>, +v2: List<&2, ed.Snap>) -> ed.Ex:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      ed.Ex{m, r, u2, v2, l, yi, yl, cx}

def ed.ex.with.last(x: ed.Ex, +l2: Nat) -> ed.Ex:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      ed.Ex{m, r, u, v, l2, yi, yl, cx}

def ed.ex.with.yank(x: ed.Ex, +yi2: Nat, +yl2: Nat) -> ed.Ex:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      ed.Ex{m, r, u, v, l, yi2, yl2, cx}

def ed.ex.with.cx(x: ed.Ex, +cx2: Bool) -> ed.Ex:
  match x:
    case ed.Ex{m, r, u, v, l, yi, yl, cx}:
      ed.Ex{m, r, u, v, l, yi, yl, cx2}

def ed.mark(+e: ed.Ed) -> Maybe<&2, Nat>:
  ed.ex.mark(ed.ex(e))

def ed.with.mark(+e: ed.Ed, +m: Maybe<&2, Nat>) -> ed.Ed:
  ed.with.ex(e, ed.ex.with.mark(ed.ex(e), m))

def ed.cx(+e: ed.Ed) -> Bool:
  ed.ex.cx(ed.ex(e))

def ed.with.cx(+e: ed.Ed, +on: Bool) -> ed.Ed:
  ed.with.ex(e, ed.ex.with.cx(ed.ex(e), on))

# the cursor's place: the characters before it
def ed.point(+e: ed.Ed) -> Nat:
  String.length(ed.pre(e))

# the cursor put at n (the history's place, the cut, the rest kept)
def ed.goto(+e: ed.Ed, +n: Nat) -> ed.Ed:
  +t = ed.text(e)
  ed.with(e, String.reverse(String.take(t, n)), String.drop(t, n))

# the region: from a to b, a <= b
type ed.Rg is Data:
  ed.Rg{a: Nat, b: Nat}

# the region (C-SPC's mark to the cursor, the lesser first), while the mark is set
def ed.region.of(m: Maybe<&2, Nat>, +pt: Nat) -> Maybe<&2, ed.Rg>:
  match m:
    case Some{+k}:
      Some{ed.Rg{Nat.min(k, pt), Nat.max(k, pt)}}
    case None{}:
      None{}

def ed.region(+e: ed.Ed) -> Maybe<&2, ed.Rg>:
  ed.region.of(ed.mark(e), ed.point(e))

def ed.slice(+t: String, +a: Nat, +b: Nat) -> String:
  String.take(String.drop(t, a), Nat.sub(b, a))

# the region's text (none: "")
def ed.region.text.of(r: Maybe<&2, ed.Rg>, +t: String) -> String:
  match r:
    case Some{ed.Rg{+a, +b}}:
      ed.slice(t, a, b)
    case None{}:
      ""

def ed.region.text(+e: ed.Ed) -> String:
  ed.region.text.of(ed.region(e), ed.text(e))

def ed.region.on(+e: ed.Ed) -> Bool:
  Maybe.is_some(&2, Nat, ed.mark(e))

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
    case ed.Ed{p, +q, c, h, a, d, f, x}:
      ed.Ed{ed.tail(p), q, c, h, a, d, f, x}

def ed.del(e: ed.Ed) -> ed.Ed:
  match e:
    case ed.Ed{+p, q, c, h, a, d, f, x}:
      ed.Ed{p, ed.tail(q), c, h, a, d, f, x}

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

# C-y: the last kill put back (its place among the kills, 0, and its length, for M-y)
def ed.yank(+e: ed.Ed) -> ed.Ed:
  +c = ed.cutted(e)
  ed.with.ex(ed.put(e, c), ed.ex.with.yank(ed.ex(e), 0n, String.length(c)))

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

# Emacs: the region, the kills, undo (2026-11-12) ------------------------------------

# C-SPC: the mark set where the cursor is (the region on, from there to the cursor)
def ed.set.mark(+e: ed.Ed) -> ed.Ed:
  ed.with.mark(e, Some{ed.point(e)})

# C-g: the region off, a C-x given up
def ed.quit(+e: ed.Ed) -> ed.Ed:
  ed.with.cx(ed.with.mark(e, None{}), False{})

# C-x C-x: the cursor where the mark was, the mark where the cursor was
def ed.xchg.of(m: Maybe<&2, Nat>, +e: ed.Ed) -> ed.Ed:
  match m:
    case Some{+k}:
      ed.with.mark(ed.goto(e, k), Some{ed.point(e)})
    case None{}:
      e

def ed.xchg(+e: ed.Ed) -> ed.Ed:
  ed.xchg.of(ed.mark(e), e)

# C-x h: the whole text the region, the cursor at its start
def ed.mark.all(+e: ed.Ed) -> ed.Ed:
  ed.with.mark(ed.goto(e, 0n), Some{String.length(ed.text(e))})

# M-< and M->: the text's start and end
def ed.bob(+e: ed.Ed) -> ed.Ed:
  ed.goto(e, 0n)

def ed.eob(+e: ed.Ed) -> ed.Ed:
  ed.goto(e, String.length(ed.text(e)))

# C-w with the region on: the region cut (the cursor where it began, the region off)
def ed.kill.rg(r: Maybe<&2, ed.Rg>, +e: ed.Ed) -> ed.Ed:
  match r:
    case Some{ed.Rg{+a, +b}}:
      +t = ed.text(e)
      ed.with.mark(ed.cut.with(e, String.reverse(String.take(t, a)), String.drop(t, b), ed.slice(t, a, b)), None{})
    case None{}:
      ed.kill.wback(e)

# C-w: the region cut while the mark is set, else the word before the cursor
def ed.kill.w(+e: ed.Ed) -> ed.Ed:
  ed.kill.rg(ed.region(e), e)

# M-w: the region copied, as a kill (the text as it was, the region off)
def ed.copy.rg(r: Maybe<&2, ed.Rg>, +e: ed.Ed) -> ed.Ed:
  match r:
    case Some{ed.Rg{+a, +b}}:
      ed.with.mark(ed.cut.with(e, ed.pre(e), ed.post(e), ed.slice(ed.text(e), a, b)), None{})
    case None{}:
      e

def ed.copy.region(+e: ed.Ed) -> ed.Ed:
  ed.copy.rg(ed.region(e), e)

# the kills, newest first: the cut, then the ring
def ed.kills(+e: ed.Ed) -> List<&2, String>:
  ed.cutted(e) <> ed.ex.ring(ed.ex(e))

# M-y right after a yank: what it put back replaced by the kill before that
# one (past the oldest, the newest again)
def ed.yank.pop.on(after: Bool, +e: ed.Ed) -> ed.Ed:
  match after:
    case True{}:
      +ks = ed.kills(e)
      +x = ed.ex(e)
      +i = Nat.mod(Nat.add(ed.ex.yi(x), 1n), Nat.max(List.length(&2, String, ks), 1n))
      +k = Maybe.default(&2, String, List.get(&2, String, ks, i), "")
      ed.with.ex(ed.with(e, String.reverse(k) ++ String.drop(ed.pre(e), ed.ex.yl(x)), ed.post(e)), ed.ex.with.yank(x, i, String.length(k)))
    case False{}:
      e

def ed.yank.pop(+e: ed.Ed) -> ed.Ed:
  ed.yank.pop.on(Nat.is_eq(ed.ex.last(ed.ex(e)), 4n), e)

def ed.snap(+e: ed.Ed) -> ed.Snap:
  ed.Snap{ed.text(e), ed.point(e)}

def ed.restore(s: ed.Snap, +e: ed.Ed) -> ed.Ed:
  match s:
    case ed.Snap{+t, +at}:
      ed.goto(ed.with(e, String.reverse(t), ""), at)

# C-/ (or C-_): the text and the cursor as they were before the last change,
# which C-? (or C-M-_) brings back; the region off
def ed.undo.of(u: List<&2, ed.Snap>, +e: ed.Ed) -> ed.Ed:
  match u:
    case []:
      e
    case +s <> rest:
      +x = ed.ex(e)
      ed.with.ex(ed.restore(s, e), ed.ex.with.mark(ed.ex.with.undo(x, rest, ed.snap(e) <> ed.ex.redo(x)), None{}))

def ed.undo(+e: ed.Ed) -> ed.Ed:
  ed.undo.of(ed.ex.undo(ed.ex(e)), e)

def ed.redo.of(v: List<&2, ed.Snap>, +e: ed.Ed) -> ed.Ed:
  match v:
    case []:
      e
    case +s <> rest:
      +x = ed.ex(e)
      ed.with.ex(ed.restore(s, e), ed.ex.with.mark(ed.ex.with.undo(x, ed.snap(e) <> ed.ex.undo(x), rest), None{}))

def ed.redo(+e: ed.Ed) -> ed.Ed:
  ed.redo.of(ed.ex.redo(ed.ex(e)), e)

# C-t: the characters either side of the cursor swapped, the cursor past
# both; at a line's end, the two before it (the text before the cursor is
# reversed): the new text before and after the cursor
def ed.tr.go(eol: Bool, p: String, q: String) -> P.pp.Two:
  match eol p q:
    case False{} SCon{+c1, +pt} SCon{+d0, +qt}:
      P.pp.Two{SCon{c1, SCon{d0, pt}}, qt}
    case True{} SCon{+c1, SCon{+c2, +pt}} +q2:
      P.pp.Two{SCon{c2, SCon{c1, pt}}, q2}
    case _ +p2 +q2:
      P.pp.Two{p2, q2}

def ed.transpose(+e: ed.Ed) -> ed.Ed:
  +q = ed.post(e)
  +r = ed.tr.go(Bool.or(String.is_empty(q), String.starts_with(q, "\n")), ed.pre(e), q)
  ed.with(e, P.pp.fst(r), P.pp.snd(r))

def ed.up.c(+c: U32) -> U32:
  Bool.pick(U32, P.pp.in(c, 97, 122), (c - 32 : U32), c)

def ed.down.c(+c: U32) -> U32:
  Bool.pick(U32, P.pp.in(c, 65, 90), (c + 32 : U32), c)

# a word's letters: k 0 all up (M-u), 1 all down (M-l), 2 its first up and
# the rest down (M-c); seen: whether a letter came already
def ed.case.go(s: String, +k: Nat, +seen: Bool) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{+c}, +t}:
      +letter = Bool.or(P.pp.in(c, 65, 90), P.pp.in(c, 97, 122))
      +up = Bool.or(Nat.is_eq(k, 0n), Bool.and(Nat.is_eq(k, 2n), Bool.and(letter, Bool.not(seen))))
      SCon{Chr{Bool.pick(U32, up, ed.up.c(c), ed.down.c(c))}, ed.case.go(t, k, Bool.or(seen, letter))}

# M-u, M-l, M-c: the word after the cursor, the cursor past it
def ed.case.word(+e: ed.Ed, +k: Nat) -> ed.Ed:
  +w = ed.word.go(ed.post(e), "")
  ed.with(e, String.reverse(ed.case.go(String.reverse(P.pp.snd(w)), k, False{})) ++ ed.pre(e), P.pp.fst(w))

# C-o: a newline after the cursor, the cursor where it was
def ed.open.line(+e: ed.Ed) -> ed.Ed:
  ed.with(e, ed.pre(e), "\n" ++ ed.post(e))

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
    case ed.Ed{p, q, c, h, a, d, f, x}:
      ed.Ed{String.reverse(text), "", c, h, a2, d2, f, x}

def ed.at.n(e: ed.Ed) -> Nat:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      a

def ed.draft(e: ed.Ed) -> String:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
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
    case ed.Ed{+p, +q, c, +h, a, d, f, x}:
      +now = String.reverse(p) ++ q
      +text = Bool.pick(String, String.is_empty(now), t, t ++ "\n" ++ now)
      +h2 = Bool.pick(List<&2, String>, String.eq(Maybe.default(&2, String, List.get(&2, String, h, 0n), ""), t), List.drop(&2, String, h, 1n), h)
      ed.Ed{String.reverse(text), "", c, h2, 0n, "", None{}, ed.ex.fresh(x)}

# the text sent: the input empty, the text the history's newest
def ed.sent(e: ed.Ed) -> ed.Ed:
  match e:
    case ed.Ed{+p, +q, c, +h, a, d, f, x}:
      +t = String.reverse(p) ++ q
      +keep = Bool.or(String.is_empty(t), String.eq(Maybe.default(&2, String, List.get(&2, String, h, 0n), ""), t))
      ed.Ed{"", "", c, List.take(&2, String, Bool.pick(List<&2, String>, keep, h, t <> h), 2000n), 0n, "", None{}, ed.ex.fresh(x)}

# Searching ----------------------------------------------------------------------

def ed.find.at(hs: List<&2, String>, +q: String, +k: Nat) -> Maybe<&2, Nat>:
  match hs:
    case []:
      None{}
    case +h <> rest:
      Bool.pick(Maybe<&2, Nat>, String.contains(h, q), Some{k}, ed.find.at(rest, q, Nat.add(k, 1n)))

def ed.found(e: ed.Ed, +q: String, m: Maybe<&2, Nat>) -> ed.Ed:
  match e m:
    case ed.Ed{p, q0, c, +h, a, +d, f, x} Some{+k}:
      ed.Ed{String.reverse(Maybe.default(&2, String, List.get(&2, String, h, k), "")), "", c, h, Nat.add(k, 1n), Bool.pick(String, Nat.is_eq(a, 0n), String.reverse(p) ++ q0, d), Some{q}, x}
    case ed.Ed{p, q0, c, h, a, d, f, x} None{}:
      ed.Ed{p, q0, c, h, a, d, Some{q}, x}

# the search for q, from the entry at `from` on
def ed.search(+e: ed.Ed, +q: String, +from: Nat) -> ed.Ed:
  ed.found(e, q, ed.find.at(List.drop(&2, String, ed.hist(e), from), q, from))

def ed.find.off(e: ed.Ed) -> ed.Ed:
  match e:
    case ed.Ed{p, q, c, h, a, d, f, x}:
      ed.Ed{p, q, c, h, a, d, None{}, x}

# a key while searching: a character narrows it, Backspace widens it, M-r or
# C-r finds an older match, C-g and Esc leave it as it was; any other key ends it
# (the text found kept) and is then a key of its own: 0 taken, 1 it ends
def ed.find.k(+key: K.ky.Key) -> Nat:
  match key:
    case K.ky.Char{c}:
      0n
    case K.ky.Back{}:
      0n
    case K.ky.Ctrl{114}:
      0n
    case K.ky.Meta{114}:
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
    case K.ky.Meta{114}:
      ed.search(e, q, ed.at.n(e))
    case _:
      ed.find.off(ed.at(e, 0n, "", ed.draft(e)))

# Keys ---------------------------------------------------------------------------

# a control key's edit, by its letter: 1 C-a, 2 C-e, 3 C-b, 4 C-f, 5 C-d,
# 6 C-h, 7 C-k, 8 C-u, 9 C-w, 10 C-y, 11 C-p, 12 C-n, 13 C-j, 14 C-r, 15
# C-SPC (Keys.bend: C-@), 16 C-/ (C-_), 17 C-?, 18 C-t, 19 C-x, 20 C-g, 0 none
def ed.ctrl.k(+c: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(c, 97), 1n, Bool.pick(Nat, U32.is_eq(c, 101), 2n, Bool.pick(Nat, U32.is_eq(c, 98), 3n,
    Bool.pick(Nat, U32.is_eq(c, 102), 4n, Bool.pick(Nat, U32.is_eq(c, 100), 5n, Bool.pick(Nat, U32.is_eq(c, 104), 6n,
      Bool.pick(Nat, U32.is_eq(c, 107), 7n, Bool.pick(Nat, U32.is_eq(c, 117), 8n, Bool.pick(Nat, U32.is_eq(c, 119), 9n,
        Bool.pick(Nat, U32.is_eq(c, 121), 10n, Bool.pick(Nat, U32.is_eq(c, 112), 11n, Bool.pick(Nat, U32.is_eq(c, 110), 12n,
          Bool.pick(Nat, U32.is_eq(c, 106), 13n, Bool.pick(Nat, U32.is_eq(c, 114), 14n, Bool.pick(Nat, U32.is_eq(c, 64), 15n,
            Bool.pick(Nat, U32.is_eq(c, 95), 16n, Bool.pick(Nat, U32.is_eq(c, 63), 17n, Bool.pick(Nat, U32.is_eq(c, 116), 18n,
              Bool.pick(Nat, U32.is_eq(c, 120), 19n, Bool.pick(Nat, U32.is_eq(c, 103), 20n, 0n))))))))))))))))))))

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
      ed.kill.w(e)
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
    case 15n:
      ed.set.mark(e)
    case 16n:
      ed.undo(e)
    case 17n:
      ed.redo(e)
    case 18n:
      ed.transpose(e)
    case 19n:
      ed.with.cx(e, True{})
    case 20n:
      ed.quit(e)
    case _:
      e

# M-b, M-f, M-d, M-r (the history searched: C-r is the chat's now,
# Screen.bend), M-< and M-> (the text's start and end: on an empty input the
# screen takes them, for the chat), M-u, M-l, M-c, M-y, C-M-_ (redo)
def ed.meta(k: Nat, +e: ed.Ed) -> ed.Ed:
  match k:
    case 1n:
      ed.wleft(e)
    case 2n:
      ed.wright(e)
    case 3n:
      ed.kill.wfwd(e)
    case 4n:
      ed.search(e, "", 0n)
    case 5n:
      ed.bob(e)
    case 6n:
      ed.eob(e)
    case 7n:
      ed.case.word(e, 0n)
    case 8n:
      ed.case.word(e, 1n)
    case 9n:
      ed.case.word(e, 2n)
    case 10n:
      ed.yank.pop(e)
    case 11n:
      ed.redo(e)
    case _:
      e

def ed.meta.k(+c: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(c, 114), 4n, Bool.pick(Nat, U32.is_eq(c, 98), 1n, Bool.pick(Nat, U32.is_eq(c, 102), 2n, Bool.pick(Nat, U32.is_eq(c, 100), 3n,
    Bool.pick(Nat, U32.is_eq(c, 60), 5n, Bool.pick(Nat, U32.is_eq(c, 62), 6n, Bool.pick(Nat, U32.is_eq(c, 117), 7n, Bool.pick(Nat, U32.is_eq(c, 108), 8n,
      Bool.pick(Nat, U32.is_eq(c, 99), 9n, Bool.pick(Nat, U32.is_eq(c, 121), 10n, Bool.pick(Nat, U32.is_eq(c, 31), 11n, 0n)))))))))))

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
    case K.ky.Meta{119}:
      ed.copy.region(e)
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
def ed.key.core(+e: ed.Ed, +key: K.ky.Key) -> ed.Ed:
  ed.find.on(ed.find(e), ed.find.k(key), e, key)

# the key after C-x: C-x (the mark and the cursor swapped), h (the whole
# text the region), u (undo); any other gives C-x up (the screen takes o and
# C-e first)
def ed.cx.key(+e: ed.Ed, key: K.ky.Key) -> ed.Ed:
  match key:
    case K.ky.Ctrl{120}:
      ed.xchg(e)
    case K.ky.Char{104}:
      ed.mark.all(e)
    case K.ky.Char{117}:
      ed.undo(e)
    case _:
      e

# what a key is to emacs's state: 1 typing, 2 a kill forward (C-k, M-d), 3
# a kill back (C-u, M-Backspace, C-w with no region), 4 a yank (C-y, M-y),
# 5 undo or redo, 6 the region's (C-w, M-w with the mark set; C-SPC; C-x's;
# C-g), 0 any other (a move: the region stays and grows)
def ed.kind(key: K.ky.Key, +rg: Bool) -> Nat:
  match key:
    case K.ky.Char{c}:
      1n
    case K.ky.Paste{t}:
      1n
    case K.ky.Newline{}:
      1n
    case K.ky.MetaBack{}:
      3n
    case K.ky.Ctrl{107}:
      2n
    case K.ky.Ctrl{117}:
      3n
    case K.ky.Ctrl{119}:
      Bool.pick(Nat, rg, 6n, 3n)
    case K.ky.Ctrl{121}:
      4n
    case K.ky.Ctrl{106}:
      1n
    case K.ky.Ctrl{95}:
      5n
    case K.ky.Ctrl{63}:
      5n
    case K.ky.Ctrl{64}:
      6n
    case K.ky.Ctrl{120}:
      6n
    case K.ky.Ctrl{103}:
      6n
    case K.ky.Meta{100}:
      2n
    case K.ky.Meta{121}:
      4n
    case K.ky.Meta{31}:
      5n
    case K.ky.Meta{119}:
      6n
    case _:
      0n

# a word's end typed (a space or a newline): what follows it is a new change to undo
def ed.key.ws(key: K.ky.Key) -> Bool:
  match key:
    case K.ky.Char{+c}:
      Bool.or(U32.is_eq(c, 32), U32.is_eq(c, 10))
    case K.ky.Newline{}:
      True{}
    case _:
      False{}

# the kills: a kill right after a kill adds to it (forward after, back
# before), and the ring stays as it was; else as the key left it
def ed.merge.on(go: Bool, +e0: ed.Ed, +e1: ed.Ed, +fwd: Bool) -> ed.Ed:
  match go:
    case True{}:
      +old = ed.cutted(e0)
      +new = ed.cutted(e1)
      ed.with.ex(ed.with.cut(e1, Bool.pick(String, fwd, old ++ new, new ++ old)), ed.ex.with.ring(ed.ex(e1), ed.ex.ring(ed.ex(e0))))
    case False{}:
      e1

# the text changed: the one before onto undo (unless the word being typed
# goes on), redo emptied, the region off
def ed.changed.on(ch: Bool, +e0: ed.Ed, +e1: ed.Ed, +k: Nat, +ws: Bool) -> ed.Ed:
  match ch:
    case True{}:
      +x = ed.ex(e1)
      +same = Bool.and(Bool.and(Nat.is_eq(k, 1n), Nat.is_eq(ed.ex.last(ed.ex(e0)), 1n)), Bool.not(ws))
      +u = Bool.pick(List<&2, ed.Snap>, same, ed.ex.undo(x), List.take(&2, ed.Snap, ed.snap(e0) <> ed.ex.undo(x), 200n))
      ed.with.ex(e1, ed.ex.with.mark(ed.ex.with.undo(x, u, []), None{}))
    case False{}:
      e1

# after an edit: emacs's state kept up (Undo's own keys keep theirs)
def ed.after(+e0: ed.Ed, +e1: ed.Ed, +k: Nat, +ws: Bool) -> ed.Ed:
  +last = ed.ex.last(ed.ex(e0))
  +kill = Bool.or(Nat.is_eq(k, 2n), Nat.is_eq(k, 3n))
  +e2 = ed.merge.on(Bool.and(kill, Bool.or(Nat.is_eq(last, 2n), Nat.is_eq(last, 3n))), e0, e1, Nat.is_eq(k, 2n))
  +ch = Bool.and(Bool.not(Nat.is_eq(k, 5n)), Bool.not(String.eq(ed.text(e0), ed.text(e2))))
  +e3 = ed.changed.on(ch, e0, e2, k, ws)
  ed.with.ex(e3, ed.ex.with.last(ed.ex(e3), Bool.pick(Nat, Nat.is_lt(k, 5n), k, 0n)))

def ed.key.on(cx: Bool, +e: ed.Ed, +key: K.ky.Key) -> ed.Ed:
  match cx:
    case True{}:
      +e0 = ed.with.cx(e, False{})
      ed.after(e0, ed.cx.key(e0, key), Bool.pick(Nat, K.ky.is.char(key, 117), 5n, 6n), False{})
    case False{}:
      ed.after(e, ed.key.core(e, key), ed.kind(key, ed.region.on(e)), ed.key.ws(key))

# a key: C-x's second, or an edit (the history's search's, if one is on)
def ed.key(+e: ed.Ed, +key: K.ky.Key) -> ed.Ed:
  ed.key.on(ed.cx(e), e, key)

# Completing ---------------------------------------------------------------------

# the commands (the first word of each; Help.bend names every one), and
# what may follow some
def ed.words() -> List<&2, String>:
  List.append(&2, String, ["/help", "/quit", "/stop", "/now", "/goal", "/halt", "/model", "/effort", "/status", "/tree", "/export", "/plan", "/auto", "/login", "/restart", "/ana", "/version", "/mouse", "/image", "/spell", "/words",
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
