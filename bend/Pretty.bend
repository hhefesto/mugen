
import Base
import ./Json.bend as J

# Pretty: the chat as the screen shows it (Screen.bend): each entry as rows
# of at most w columns, painted with SGR. A tool call is one block with its
# result: a header (the tool, what it was asked, how it went) over the
# output, an edit's or a write's as its diff (line numbers, - red, + green),
# folded to a few lines till a click opens it. Replies get a little
# markdown (code fences, headings, bullets, `code`, **bold**); thoughts are
# dim, folded too. What tools print is cleaned first: escape sequences and
# control characters dropped, tabs to spaces.
#
# Every def is prefixed `pp.` (a program's defs share one namespace).

def pp.fuel() -> Nat:
  U32.to_nat(4294967295)

# Columns -------------------------------------------------------------------------

def pp.in(+c: U32, +a: U32, +b: U32) -> Bool:
  Bool.and(U32.is_ge(c, a), U32.is_le(c, b))

# two columns: the wide East Asian ranges and the emoji
def pp.wide(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.or(pp.in(c, 4352, 4447), pp.in(c, 11904, 12350)), Bool.or(pp.in(c, 12353, 19903), pp.in(c, 19968, 42191))),
    Bool.or(Bool.or(Bool.or(pp.in(c, 44032, 55203), pp.in(c, 63744, 64255)), Bool.or(pp.in(c, 65072, 65103), pp.in(c, 65280, 65376))),
      Bool.or(Bool.or(pp.in(c, 65504, 65510), pp.in(c, 127744, 128591)), Bool.or(Bool.or(pp.in(c, 128640, 128767), pp.in(c, 129280, 129535)), pp.in(c, 131072, 262141)))))

# none: combining marks, zero-width spaces, variation selectors
def pp.zero(+c: U32) -> Bool:
  Bool.or(Bool.or(pp.in(c, 768, 879), pp.in(c, 8203, 8207)), Bool.or(pp.in(c, 65024, 65039), pp.in(c, 8400, 8447)))

def pp.cw(+c: U32) -> U32:
  Bool.pick(U32, pp.zero(c), 0, Bool.pick(U32, pp.wide(c), 2, 1))

def pp.width.go(s: String, +n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{Chr{+c}, t}:
      pp.width.go(t, (n + pp.cw(c) : U32))

# a clean text's columns
def pp.width(s: String) -> U32:
  pp.width.go(s, 0)

def pp.paint(+st: String, +tx: String) -> String:
  Bool.pick(String, Bool.or(String.is_empty(st), String.is_empty(tx)), tx, "\u{1B}[" ++ st ++ "m" ++ tx ++ "\u{1B}[0m")

def pp.spaces(+n: U32) -> String:
  String.repeat(" ", U32.to_nat(n))

# right-aligned in n columns
def pp.pad.left(+s: String, +n: U32) -> String:
  pp.spaces((n - U32.min(pp.width(s), n) : U32)) ++ s

# Our own text, its SGR kept (the status, the help): its columns, and the
# text cut to w of them
def pp.sgr.v(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{27}, SCon{Chr{91}, t}}:
      1n
    case _:
      2n

# a CSI's bytes: 0 none left, 1 a parameter or intermediate, 2 the final
# one, 3 none of these
def pp.csi.v(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, pp.in(c, 32, 63), 1n, Bool.pick(Nat, pp.in(c, 64, 126), 2n, 3n))

def pp.skip.csi.go(s: String, v: Nat) -> String:
  match s v:
    case SCon{c, +t} 1n:
      pp.skip.csi.go(t, pp.csi.v(t))
    case SCon{c, +t} 2n:
      t
    case SCon{+c, +t} 3n:
      SCon{c, t}
    case _ _:
      ""

# a CSI's rest past its final byte
def pp.skip.csi(+s: String) -> String:
  pp.skip.csi.go(s, pp.csi.v(s))

def pp.vis.go(n: Nat, s: String, v: Nat, +col: U32) -> U32:
  match n s v:
    case 1n+f SCon{c, SCon{d, +t}} 1n:
      +r = pp.skip.csi(t)
      pp.vis.go(f, r, pp.sgr.v(r), col)
    case 1n+f SCon{Chr{+c}, +t} 2n:
      pp.vis.go(f, t, pp.sgr.v(t), (col + pp.cw(c) : U32))
    case _ _ _:
      col

def pp.vis(+s: String) -> U32:
  pp.vis.go(pp.fuel(), s, pp.sgr.v(s), 0)

# what comes next in a cut of our own text to w columns: 0 its end (or a
# character past w), 1 an SGR's "ESC [", 2 a character that fits, 4 an SGR's
# parameter byte, 5 its final byte
def pp.sgr.cut.v(s: String, +inside: Bool, +col: U32, +w: U32) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{27}, SCon{Chr{91}, t}}:
      1n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, inside, Bool.pick(Nat, pp.in(c, 64, 126), 5n, 4n), Bool.pick(Nat, U32.is_le((col + pp.cw(c) : U32), w), 2n, 0n))

def pp.sgr.cut.go(n: Nat, s: String, v: Nat, +col: U32, +w: U32, +acc: String) -> String:
  match n s v:
    case 1n+f SCon{+c, SCon{+d, +t}} 1n:
      pp.sgr.cut.go(f, t, pp.sgr.cut.v(t, True{}, col, w), col, w, SCon{d, SCon{c, acc}})
    case 1n+f SCon{Chr{+c}, +t} 2n:
      +col2 = (col + pp.cw(c) : U32)
      pp.sgr.cut.go(f, t, pp.sgr.cut.v(t, False{}, col2, w), col2, w, SCon{Chr{c}, acc})
    case 1n+f SCon{+c, +t} 4n:
      pp.sgr.cut.go(f, t, pp.sgr.cut.v(t, True{}, col, w), col, w, SCon{c, acc})
    case 1n+f SCon{+c, +t} 5n:
      pp.sgr.cut.go(f, t, pp.sgr.cut.v(t, False{}, col, w), col, w, SCon{c, acc})
    case _ _ _:
      String.reverse(acc) ++ "\u{1B}[0m"

def pp.sgr.cut(+s: String, +w: U32) -> String:
  pp.sgr.cut.go(pp.fuel(), s, pp.sgr.cut.v(s, False{}, 0, w), 0, w, "")

# Cleaning ---------------------------------------------------------------------
#
# A text from outside (a tool's output, a reply) as the screen may show it:
# escape sequences and control characters gone, tabs as spaces to the next
# stop of eight, carriage returns dropped.

# 0 nothing, 1 an escape, 2 a tab, 3 a newline, 4 a control character, 5 a
# character kept
def pp.cls(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, U32.is_eq(c, 27), 1n, Bool.pick(Nat, U32.is_eq(c, 9), 2n, Bool.pick(Nat, U32.is_eq(c, 10), 3n,
        Bool.pick(Nat, Bool.or(U32.is_lt(c, 32), Bool.or(U32.is_eq(c, 127), pp.in(c, 128, 159))), 4n, 5n))))

# past an escape: a CSI's rest to its final byte; an OSC's to BEL or ESC \;
# else one character
def pp.skip.osc(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{7}, +t}:
      t
    case SCon{Chr{27}, SCon{Chr{92}, +t}}:
      t
    case SCon{c, +t}:
      pp.skip.osc(t)

def pp.skip(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{91}, +t}:
      pp.skip.csi(t)
    case SCon{Chr{93}, +t}:
      pp.skip.osc(t)
    case SCon{c, +t}:
      t

def pp.clean.go(n: Nat, s: String, v: Nat, +col: U32, +acc: String) -> String:
  match n s v:
    case 1n+f SCon{c, +t} 1n:
      +r = pp.skip(t)
      pp.clean.go(f, r, pp.cls(r), col, acc)
    case 1n+f SCon{c, +t} 2n:
      +k = (8 - U32.mod(col, 8) : U32)
      pp.clean.go(f, t, pp.cls(t), (col + k : U32), pp.spaces(k) ++ acc)
    case 1n+f SCon{c, +t} 3n:
      pp.clean.go(f, t, pp.cls(t), 0, SCon{Chr{10}, acc})
    case 1n+f SCon{c, +t} 4n:
      pp.clean.go(f, t, pp.cls(t), col, acc)
    case 1n+f SCon{Chr{+c}, +t} 5n:
      pp.clean.go(f, t, pp.cls(t), (col + pp.cw(c) : U32), SCon{Chr{c}, acc})
    case _ _ _:
      String.reverse(acc)

def pp.clean(+s: String) -> String:
  pp.clean.go(pp.fuel(), s, pp.cls(s), 0, "")

# Lines ---------------------------------------------------------------------------

def pp.split.go(s: String, +cur: String, +acc: List<&2, String>) -> List<&2, String>:
  match s:
    case SNil{}:
      List.reverse(&2, String, String.reverse(cur) <> acc)
    case SCon{Chr{10}, +t}:
      pp.split.go(t, "", String.reverse(cur) <> acc)
    case SCon{+c, +t}:
      pp.split.go(t, SCon{c, cur}, acc)

# text.split("\n")
def pp.split(+s: String) -> List<&2, String>:
  pp.split.go(s, "", [])

# the text's lines, its last newline dropped
def pp.lines(+s: String) -> List<&2, String>:
  pp.split(Bool.pick(String, String.ends_with(s, "\n"), String.take(s, Nat.sub(String.length(s), 1n)), s))

def pp.len(+xs: List<&2, String>) -> Nat:
  List.length(&2, String, xs)

def pp.digit.v(s: String) -> Nat:
  match s:
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, pp.in(c, 48, 57), 1n, 0n)
    case SNil{}:
      0n

def pp.digits(s: String, v: Nat, +acc: String) -> String:
  match s v:
    case SCon{+c, +t} 1n:
      pp.digits(t, pp.digit.v(t), SCon{c, acc})
    case _ _:
      String.reverse(acc)

# the number a text starts with, else d
def pp.num(+s: String, +d: U32) -> U32:
  +ds = pp.digits(s, pp.digit.v(s), "")
  Bool.pick(U32, String.is_empty(ds), d, U32.from_nat(Maybe.default(&2, Nat, Nat.read(ds), U32.to_nat(d))))

# two texts: a head and its rest
type pp.Two is Data:
  pp.Two{a: String, b: String}

# what the next character does to a take of n columns: 0 none left, 1 it
# fits, 2 it does not

def pp.take.v(s: String, +col: U32, +n: U32) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, U32.is_le((col + pp.cw(c) : U32), n), 1n, 2n)

def pp.take.go(n: Nat, s: String, v: Nat, +col: U32, +w: U32, +acc: String) -> pp.Two:
  match n s v:
    case 1n+f SCon{Chr{+c}, +t} 1n:
      +col2 = (col + pp.cw(c) : U32)
      pp.take.go(f, t, pp.take.v(t, col2, w), col2, w, SCon{Chr{c}, acc})
    case _ SCon{+c, +t} _:
      pp.Two{String.reverse(acc), SCon{c, t}}
    case _ _ _:
      pp.Two{String.reverse(acc), ""}

# the head of a text that fits in w columns, and the rest
def pp.take(+s: String, +w: U32) -> pp.Two:
  pp.take.go(pp.fuel(), s, pp.take.v(s, 0, w), 0, w, "")

def pp.fst(p: pp.Two) -> String:
  match p:
    case pp.Two{a, b}:
      a

def pp.snd(p: pp.Two) -> String:
  match p:
    case pp.Two{a, b}:
      b

# the text in w columns, an ellipsis at its end if it was cut
def pp.fit(+s: String, +w: U32) -> String:
  Bool.pick(String, U32.is_le(pp.width(s), w), s, pp.fst(pp.take(s, (w - 1 : U32))) ++ "\u{2026}")

# Wrapping ------------------------------------------------------------------------
#
# A line is spans of one style each; it fills rows of `room` columns. In
# prose (word) a word that does not fit starts a row, and a row that wraps
# drops its leading spaces; else (code, output) rows are filled to the brim.
# A word wider than a row is cut where the row ends.

type pp.Sp is Data:
  pp.Sp{st: String, tx: String}

# a run of one style: its text, columns, and whether it is spaces
type pp.Tk is Data:
  pp.Tk{st: String, tx: String, w: U32, sp: Bool}

def pp.tk(+st: String, +rev: String, +sp: Bool) -> pp.Tk:
  +tx = String.reverse(rev)
  pp.Tk{st, tx, pp.width(tx), sp}

# 0 nothing, 1 a space, 2 any other character
def pp.sp.v(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{32}, t}:
      1n
    case _:
      2n

# a span's words and spaces, onto acc (reversed)
def pp.runs.go(s: String, v: Nat, +st: String, +cur: String, +insp: Bool, +acc: List<&2, pp.Tk>) -> List<&2, pp.Tk>:
  match s v:
    case SCon{+c, +t} 1n:
      +flush = Bool.and(Bool.not(insp), Bool.not(String.is_empty(cur)))
      pp.runs.go(t, pp.sp.v(t), st, SCon{c, Bool.pick(String, flush, "", cur)}, True{}, Bool.pick(List<&2, pp.Tk>, flush, pp.tk(st, cur, False{}) <> acc, acc))
    case SCon{+c, +t} 2n:
      +flush = Bool.and(insp, Bool.not(String.is_empty(cur)))
      pp.runs.go(t, pp.sp.v(t), st, SCon{c, Bool.pick(String, flush, "", cur)}, False{}, Bool.pick(List<&2, pp.Tk>, flush, pp.tk(st, cur, True{}) <> acc, acc))
    case _ _:
      Bool.pick(List<&2, pp.Tk>, String.is_empty(cur), acc, pp.tk(st, cur, insp) <> acc)

def pp.span(word: Bool, +st: String, +tx: String, +acc: List<&2, pp.Tk>) -> List<&2, pp.Tk>:
  match word:
    case True{}:
      pp.runs.go(tx, pp.sp.v(tx), st, "", False{}, acc)
    case False{}:
      Bool.pick(List<&2, pp.Tk>, String.is_empty(tx), acc, pp.Tk{st, tx, pp.width(tx), False{}} <> acc)

def pp.tokens.go(sps: List<&2, pp.Sp>, +word: Bool, +acc: List<&2, pp.Tk>) -> List<&2, pp.Tk>:
  match sps:
    case []:
      List.reverse(&2, pp.Tk, acc)
    case pp.Sp{+st, +tx} <> rest:
      pp.tokens.go(rest, word, pp.span(word, st, tx, acc))

# What the next token does to the row: 0 none left, 1 it goes on the row, 2
# it is dropped (spaces starting a wrapped row), 3 the row ends first, 4 it
# is cut where the row ends
def pp.fill.v(tks: List<&2, pp.Tk>, +room: U32, +word: Bool, +cont: Bool, +col: U32) -> Nat:
  match tks:
    case []:
      0n
    case pp.Tk{st, tx, +w, +sp} <> t:
      Bool.pick(Nat, Bool.and(sp, Bool.and(cont, U32.is_eq(col, 0))), 2n,
        Bool.pick(Nat, U32.is_le((col + w : U32), room), 1n,
          Bool.pick(Nat, Bool.and(sp, U32.is_gt(col, 0)), 3n,
            Bool.pick(Nat, Bool.or(U32.is_ge(col, room), Bool.and(word, Bool.and(U32.is_le(w, room), U32.is_gt(col, 0)))), 3n, 4n))))

# a cut's head: what fits, else (an empty row) one character
def pp.cut.head(+tx: String, +n: U32) -> pp.Two:
  +p = pp.take(tx, n)
  Bool.pick(pp.Two, String.is_empty(pp.fst(p)), pp.Two{String.take(tx, 1n), String.drop(tx, 1n)}, p)

# The row so far (painted), and its last run of one style (st, its text
# cur), painted once it ends
def pp.run.end(+row: String, +st: String, +cur: String) -> String:
  row ++ pp.paint(st, cur)

def pp.fill(n: Nat, tks: List<&2, pp.Tk>, v: Nat, +room: U32, +word: Bool, +cont: Bool, +row: String, +st: String, +cur: String, +col: U32, +rows: List<&2, String>) -> List<&2, String>:
  match n tks v:
    case 1n+f pp.Tk{+st2, +tx, +w, +sp} <> +t 1n:
      +col2 = (col + w : U32)
      +same = String.eq(st, st2)
      pp.fill(f, t, pp.fill.v(t, room, word, cont, col2), room, word, cont, Bool.pick(String, same, row, pp.run.end(row, st, cur)), st2, Bool.pick(String, same, cur ++ tx, tx), col2, rows)
    case 1n+f tk <> +t 2n:
      pp.fill(f, t, pp.fill.v(t, room, word, cont, col), room, word, cont, row, st, cur, col, rows)
    case 1n+f +tk <> +t 3n:
      pp.fill(f, tk <> t, pp.fill.v(tk <> t, room, word, True{}, 0), room, word, True{}, "", "", "", 0, pp.run.end(row, st, cur) <> rows)
    case 1n+f pp.Tk{+st2, +tx, +w, +sp} <> +t 4n:
      +p = pp.cut.head(tx, (room - col : U32))
      +rest = pp.snd(p)
      +more = Bool.pick(List<&2, pp.Tk>, String.is_empty(rest), t, pp.Tk{st2, rest, pp.width(rest), sp} <> t)
      +same = String.eq(st, st2)
      +last = Bool.pick(String, same, pp.run.end(row, st, cur ++ pp.fst(p)), pp.run.end(pp.run.end(row, st, cur), st2, pp.fst(p)))
      pp.fill(f, more, pp.fill.v(more, room, word, True{}, 0), room, word, True{}, "", "", "", 0, last <> rows)
    case _ _ _:
      List.reverse(&2, String, pp.run.end(row, st, cur) <> rows)

# a line's rows in `room` columns (four at least)
def pp.rows(+sps: List<&2, pp.Sp>, +room0: U32, +word: Bool) -> List<&2, String>:
  +tks = pp.tokens.go(sps, word, [])
  +room = U32.max(room0, 4)
  pp.fill(pp.fuel(), tks, pp.fill.v(tks, room, word, False{}, 0), room, word, False{}, "", "", "", 0, [])

# rows with a prefix: p1 the first's, p2 the others'
def pp.pre(rs: List<&2, String>, +p1: String, +p2: String) -> List<&2, String>:
  match rs:
    case []:
      []
    case r <> rest:
      (p1 ++ r) <> pp.pre(rest, p2, p2)

def pp.cat(+a: List<&2, String>, +b: List<&2, String>) -> List<&2, String>:
  List.append(&2, String, a, b)

# lines of one style, each wrapped: the first row after p1, the rest after
# p2 (both pw columns)
def pp.para(ls: List<&2, String>, +p1: String, +p2: String, +pw: U32, +st: String, +word: Bool, +w: U32) -> List<&2, String>:
  match ls:
    case []:
      []
    case l <> rest:
      pp.cat(pp.pre(pp.rows([pp.Sp{st, l}], (w - pw : U32), word), p1, p2), pp.para(rest, p2, p2, pw, st, word, w))

# the first n of the lines, and how many are left out
def pp.head(+ls: List<&2, String>, +open: Bool, +n: Nat) -> List<&2, String>:
  Bool.pick(List<&2, String>, open, ls, List.take(&2, String, ls, n))

def pp.hidden(+ls: List<&2, String>, +open: Bool, +n: Nat) -> Nat:
  Bool.pick(Nat, open, 0n, Nat.sub(pp.len(ls), n))

# the row saying lines are folded away
def pp.more(+k: Nat, +gut: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, Nat.is_eq(k, 0n), [], [gut ++ pp.paint("2", "\u{2026} +" ++ Nat.show(k) ++ Bool.pick(String, Nat.is_eq(k, 1n), " line", " lines") ++ " (click to open)")])

# rows folded to n, the rest said in a row of their own
def pp.fold(+rs: List<&2, String>, +open: Bool, +n: Nat, +gut: String) -> List<&2, String>:
  +k = pp.len(rs)
  Bool.pick(List<&2, String>, Bool.or(open, Nat.is_le(k, Nat.add(n, 1n))), rs, pp.cat(List.take(&2, String, rs, n), pp.more(Nat.sub(k, n), gut)))

def pp.ltrim(s: String) -> String:
  match s:
    case SCon{Chr{32}, +t}:
      pp.ltrim(t)
    case _:
      s

def pp.tilde(+home: String, +p: String) -> String:
  Bool.pick(String, Bool.and(Bool.not(String.is_empty(home)), String.starts_with(p, home)), "~" ++ String.drop(p, String.length(home)), p)

# Markdown ------------------------------------------------------------------------

# what an inline character does: 0 it is text, 1 a backtick (code on or
# off), 2 "**" (bold on or off, not in code), 3 nothing left
def pp.inl.v(s: String, +st: U32) -> Nat:
  match s:
    case SNil{}:
      3n
    case SCon{Chr{96}, t}:
      1n
    case SCon{Chr{42}, SCon{Chr{42}, t}}:
      Bool.pick(Nat, U32.is_eq(st, 1), 0n, 2n)
    case _:
      0n

def pp.inl.st(+st: U32) -> String:
  Bool.pick(String, U32.is_eq(st, 1), "36", Bool.pick(String, U32.is_eq(st, 2), "1", ""))

def pp.inl.flush(+st: U32, +cur: String, +acc: List<&2, pp.Sp>) -> List<&2, pp.Sp>:
  Bool.pick(List<&2, pp.Sp>, String.is_empty(cur), acc, pp.Sp{pp.inl.st(st), String.reverse(cur)} <> acc)

def pp.inl.go(n: Nat, s: String, v: Nat, +st: U32, +cur: String, +acc: List<&2, pp.Sp>) -> List<&2, pp.Sp>:
  match n s v:
    case 1n+f SCon{c, +t} 1n:
      +st2 = Bool.pick(U32, U32.is_eq(st, 1), 0, 1)
      pp.inl.go(f, t, pp.inl.v(t, st2), st2, "", pp.inl.flush(st, cur, acc))
    case 1n+f SCon{c, SCon{d, +t}} 2n:
      +st2 = Bool.pick(U32, U32.is_eq(st, 2), 0, 2)
      pp.inl.go(f, t, pp.inl.v(t, st2), st2, "", pp.inl.flush(st, cur, acc))
    case 1n+f SCon{+c, +t} 0n:
      pp.inl.go(f, t, pp.inl.v(t, st), st, SCon{c, cur}, acc)
    case _ _ _:
      List.reverse(&2, pp.Sp, pp.inl.flush(st, cur, acc))

# a line's `code` and **bold**
def pp.inline(+s: String) -> List<&2, pp.Sp>:
  pp.inl.go(pp.fuel(), s, pp.inl.v(s, 0), 0, "", [])

def pp.diff.st(+l: String) -> String:
  Bool.pick(String, String.starts_with(l, "@@"), "36", Bool.pick(String, String.starts_with(l, "+"), "32", Bool.pick(String, String.starts_with(l, "-"), "31", "")))

# 0 a fence, 1 a line of code, 2 a heading, 3 a bullet, 4 prose
def pp.md.k(+tl: String, +code: Bool) -> Nat:
  Bool.pick(Nat, String.starts_with(tl, "```"), 0n, Bool.pick(Nat, code, 1n,
    Bool.pick(Nat, String.starts_with(tl, "#"), 2n, Bool.pick(Nat, Bool.or(String.starts_with(tl, "- "), String.starts_with(tl, "* ")), 3n, 4n))))

def pp.hashes(s: String) -> String:
  match s:
    case SCon{Chr{35}, +t}:
      pp.hashes(t)
    case _:
      pp.ltrim(s)

def pp.md.line(k: Nat, +l: String, +tl: String, +lang: String, +p1: String, +w: U32) -> List<&2, String>:
  match k:
    case 0n:
      [p1 ++ pp.paint("2", pp.fit(l, (w - 2 : U32)))]
    case 1n:
      +bar = pp.paint("2", "\u{2502} ")
      pp.pre(pp.rows([pp.Sp{Bool.pick(String, String.eq(lang, "diff"), pp.diff.st(l), ""), l}], (w - 4 : U32), False{}), p1 ++ bar, "  " ++ bar)
    case 2n:
      pp.pre(pp.rows([pp.Sp{"1", pp.hashes(tl)}], (w - 2 : U32), True{}), p1, "  ")
    case 3n:
      +ind = (U32.from_nat(String.length(l)) - U32.from_nat(String.length(tl)) : U32)
      pp.pre(pp.rows(pp.inline(String.drop(tl, 2n)), (w - (ind + 4 : U32) : U32), True{}), p1 ++ pp.spaces(ind) ++ "\u{2022} ", "  " ++ pp.spaces((ind + 2 : U32)))
    case _:
      pp.pre(pp.rows(pp.inline(l), (w - 2 : U32), True{}), p1, "  ")

# a reply's lines: in a code fence (of a language) or not; p1 the first
# row's prefix
def pp.md(ls: List<&2, String>, +code: Bool, +lang: String, +p1: String, +w: U32) -> List<&2, String>:
  match ls:
    case []:
      []
    case +l <> rest:
      +tl = pp.ltrim(l)
      +k = pp.md.k(tl, code)
      +fence = Nat.is_eq(k, 0n)
      pp.cat(pp.md.line(k, l, tl, lang, p1, w),
        pp.md(rest, Bool.xor(code, fence), Bool.pick(String, fence, Bool.pick(String, code, "", pp.ltrim(String.drop(tl, 3n))), lang), "  ", w))

# Tools ---------------------------------------------------------------------------

def pp.tool.name(+text: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(text, ' '), 0n), text)

def pp.tool.input(+text: String) -> J.Json:
  Maybe.default(&2, J.Json, J.js.read(String.drop(text, Nat.add(String.length(pp.tool.name(text)), 1n))), J.JObj{[]})

def pp.val.of(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{J.JStr{s}}:
      s
    case Some{x}:
      J.js.write(x)
    case None{}:
      ""

def pp.val(+j: J.Json, +k: String) -> String:
  pp.val.of(J.js.field(j, k))

# a text's first line, an ellipsis if more follow
def pp.line1(+s: String) -> String:
  +ls = pp.split(s)
  Maybe.default(&2, String, List.get(&2, String, ls, 0n), "") ++ Bool.pick(String, Nat.is_gt(pp.len(ls), 1n), " \u{2026}", "")

def pp.edits.first(es: List<&2, J.Json>, +home: String) -> String:
  match es:
    case []:
      ""
    case +e <> +rest:
      pp.tilde(home, pp.val(e, "path")) ++ Bool.pick(String, List.is_empty(&2, J.Json, rest), "", " (+" ++ Nat.show(List.length(&2, J.Json, rest)) ++ " edits)")

def pp.or.json(+s: String, +j: J.Json) -> String:
  Bool.pick(String, String.is_empty(s), J.js.write(j), s)

# what a call asked, in a line
def pp.summary(+name: String, +j: J.Json, +home: String) -> String:
  Bool.pick(String, String.eq(name, "shell"), pp.line1(pp.val(j, "command")),
    Bool.pick(String, Bool.or(String.eq(name, "read"), String.eq(name, "write")),
      pp.tilde(home, pp.val(j, "path")) ++ Bool.pick(String, String.is_empty(pp.val(j, "offset")), "", " :" ++ pp.val(j, "offset")),
      Bool.pick(String, String.eq(name, "edit"), pp.edits.first(J.js.arr(j, "edits"), home),
        Bool.pick(String, String.eq(name, "zoom"), pp.val(j, "id") ++ Bool.pick(String, String.is_empty(pp.val(j, "n")), "", "+" ++ pp.val(j, "n")),
          Bool.pick(String, String.eq(name, "tell"), pp.val(j, "name") ++ ": " ++ pp.line1(pp.val(j, "message")),
            Bool.pick(String, String.eq(name, "spawn"), Nat.show(List.length(&2, J.Json, J.js.arr(j, "tasks"))) ++ " tasks",
              pp.or.json(pp.val(j, "query") ++ pp.val(j, "url") ++ pp.val(j, "id"), j)))))))

# how a call went: the badge on its header's right, and its arrow's style
type pp.Bd is Data:
  pp.Bd{text: String, w: U32, st: String}

def pp.bd(+st: String, +tx: String) -> pp.Bd:
  pp.Bd{pp.paint(st, tx), pp.width(tx), st}

def pp.last(+ls: List<&2, String>) -> String:
  Maybe.default(&2, String, List.get(&2, String, ls, Nat.sub(pp.len(ls), 1n)), "")

def pp.but.last(+ls: List<&2, String>) -> List<&2, String>:
  List.take(&2, String, ls, Nat.sub(pp.len(ls), 1n))

# a shell's last line, "(exit 0 in 0.4 s)" and its kin
def pp.shell.bd(+last: String) -> pp.Bd:
  +inner = String.drop(String.take(last, Nat.sub(String.length(last), 1n)), 1n)
  +ws = String.split(inner, ' ')
  +w0 = Maybe.default(&2, String, List.get(&2, String, ws, 0n), "")
  +time = String.join(List.drop(&2, String, ws, Nat.sub(pp.len(ws), 2n)), " ")
  Bool.pick(pp.Bd, Bool.not(String.starts_with(last, "(")), pp.bd("32", "\u{2713}"),
    Bool.pick(pp.Bd, String.eq(w0, "exit"), Bool.pick(pp.Bd, String.eq(Maybe.default(&2, String, List.get(&2, String, ws, 1n), ""), "0"), pp.bd("32", "\u{2713} " ++ time), pp.bd("31", "\u{2717} " ++ String.join(List.take(&2, String, ws, 2n), " ") ++ " \u{b7} " ++ time)),
      Bool.pick(pp.Bd, String.eq(w0, "cut"), pp.bd("33", "\u{2702} cut \u{b7} " ++ time),
        Bool.pick(pp.Bd, String.eq(w0, "stopped"), pp.bd("33", "\u{25a0} stopped \u{b7} " ++ time), pp.bd("31", "\u{2717} " ++ w0 ++ " \u{b7} " ++ time)))))

def pp.count(ls: List<&2, String>, +plus: Bool, +n: U32) -> U32:
  match ls:
    case []:
      n
    case +l <> rest:
      +hit = Bool.pick(Bool, plus, Bool.and(String.starts_with(l, "+"), Bool.not(String.starts_with(l, "+++ "))), Bool.and(String.starts_with(l, "-"), Bool.not(String.starts_with(l, "--- "))))
      pp.count(rest, plus, Bool.pick(U32, hit, (n + 1 : U32), n))

def pp.diff.bd(+res: String) -> pp.Bd:
  +ls = pp.split(res)
  +a = U32.show(pp.count(ls, True{}, 0))
  +d = U32.show(pp.count(ls, False{}, 0))
  pp.Bd{pp.paint("32", "+" ++ a) ++ " " ++ pp.paint("31", "\u{2212}" ++ d), (pp.width(a) + (pp.width(d) + 3 : U32) : U32), "32"}

# 0 running, 1 failed, 2 a shell's, 3 an edit's or a write's, 4 a read's, 5 done
def pp.bd.k(+name: String, +res: String) -> Nat:
  Bool.pick(Nat, String.is_empty(res), 0n, Bool.pick(Nat, String.eq(name, "shell"), 2n,
    Bool.pick(Nat, String.starts_with(res, "error: "), 1n, Bool.pick(Nat, Bool.or(String.eq(name, "edit"), String.eq(name, "write")), 3n,
      Bool.pick(Nat, String.eq(name, "read"), 4n, 5n)))))

def pp.badge(k: Nat, +res: String, +run: Bool) -> pp.Bd:
  match k:
    case 0n:
      Bool.pick(pp.Bd, run, pp.bd("33", "running\u{2026}"), pp.bd("2", "no result"))
    case 1n:
      pp.bd("31", "\u{2717} failed")
    case 2n:
      pp.shell.bd(pp.last(pp.lines(Bool.pick(String, String.starts_with(res, "error: "), String.drop(res, 7n), res))))
    case 3n:
      pp.diff.bd(res)
    case 4n:
      pp.bd("2", pp.fit(pp.last(pp.lines(res)), 40))
    case _:
      pp.bd("32", "\u{2713}")

# Diffs ---------------------------------------------------------------------------

def pp.gut() -> String:
  pp.paint("2", "  \u{2502} ")

def pp.word.n(+l: String, +k: Nat) -> U32:
  pp.num(String.drop(Maybe.default(&2, String, List.get(&2, String, String.split(l, ' '), k), ""), 1n), 1)

# 0 a file's old name, 1 its new name, 2 a hunk's head, 3 a line added, 4 a
# line taken out, 5 a line kept, 6 anything else
def pp.diff.k(+l: String) -> Nat:
  Bool.pick(Nat, String.starts_with(l, "--- "), 0n, Bool.pick(Nat, String.starts_with(l, "+++ "), 1n, Bool.pick(Nat, String.starts_with(l, "@@"), 2n,
    Bool.pick(Nat, String.starts_with(l, "+"), 3n, Bool.pick(Nat, String.starts_with(l, "-"), 4n, Bool.pick(Nat, String.starts_with(l, " "), 5n, 6n))))))

def pp.diff.code(+num: U32, +sign: String, +st: String, +text: String, +w: U32) -> List<&2, String>:
  pp.pre(pp.rows([pp.Sp{st, text}], (w - 12 : U32), False{}), pp.gut() ++ pp.paint("2", pp.pad.left(U32.show(num), 5)) ++ pp.paint(st, sign), pp.gut() ++ pp.spaces(8))

def pp.diff.line(k: Nat, +l: String, +old: U32, +new: U32, +w: U32, +home: String) -> List<&2, String>:
  match k:
    case 0n:
      []
    case 1n:
      [pp.gut() ++ pp.paint("1", pp.fit(pp.tilde(home, String.drop(l, 4n)), (w - 4 : U32)))]
    case 2n:
      [pp.gut() ++ pp.paint("36", pp.fit(l, (w - 4 : U32)))]
    case 3n:
      pp.diff.code(new, " + ", "32", String.drop(l, 1n), w)
    case 4n:
      pp.diff.code(old, " - ", "31", String.drop(l, 1n), w)
    case 5n:
      pp.diff.code(new, "   ", "", String.drop(l, 1n), w)
    case _:
      [pp.gut() ++ pp.paint("2", pp.fit(l, (w - 4 : U32)))]

# a diff's rows, numbering its lines as its hunks say
def pp.diff.go(ls: List<&2, String>, +old: U32, +new: U32, +w: U32, +home: String) -> List<&2, String>:
  match ls:
    case []:
      []
    case +l <> rest:
      +k = pp.diff.k(l)
      +hunk = Nat.is_eq(k, 2n)
      +old2 = Bool.pick(U32, hunk, pp.word.n(l, 1n), Bool.pick(U32, Bool.or(Nat.is_eq(k, 4n), Nat.is_eq(k, 5n)), (old + 1 : U32), old))
      +new2 = Bool.pick(U32, hunk, pp.word.n(l, 2n), Bool.pick(U32, Bool.or(Nat.is_eq(k, 3n), Nat.is_eq(k, 5n)), (new + 1 : U32), new))
      pp.cat(pp.diff.line(k, l, old, new, w, home), pp.diff.go(rest, old2, new2, w, home))

# Blocks --------------------------------------------------------------------------

# a tool's output: 0 none yet, 1 a diff, 2 text
def pp.body.k(+name: String, +res: String) -> Nat:
  Bool.pick(Nat, String.is_empty(res), 0n,
    Bool.pick(Nat, Bool.and(Bool.or(String.eq(name, "edit"), String.eq(name, "write")), Bool.not(String.starts_with(res, "error: "))), 1n, 2n))

def pp.out.n(+name: String, +err: Bool) -> Nat:
  Bool.pick(Nat, err, 8n, Bool.pick(Nat, String.eq(name, "shell"), 6n, 4n))

def pp.body(k: Nat, +name: String, +j: J.Json, +res: String, +open: Bool, +w: U32, +home: String) -> List<&2, String>:
  match k:
    case 0n:
      []
    case 1n:
      +ls = pp.lines(pp.clean(res))
      pp.cat(pp.diff.go(pp.head(ls, open, 30n), 0, 0, w, home), pp.more(pp.hidden(ls, open, 30n), pp.gut()))
    case _:
      +err = String.starts_with(res, "error: ")
      +shell = String.eq(name, "shell")
      +ls0 = pp.lines(pp.clean(Bool.pick(String, err, String.drop(res, 7n), res)))
      +ls = Bool.pick(List<&2, String>, Bool.or(shell, Bool.and(String.eq(name, "read"), Bool.not(err))), pp.but.last(ls0), ls0)
      +n = pp.out.n(name, Bool.and(err, Bool.not(shell)))
      +cmd = Bool.pick(List<&2, String>, Bool.and(open, shell), pp.para(pp.lines(pp.val(j, "command")), pp.gut() ++ pp.paint("2", "$ "), pp.gut() ++ "  ", 6, "2", False{}, w), [])
      pp.cat(cmd, pp.cat(pp.para(pp.head(ls, open, n), pp.gut(), pp.gut(), 4, Bool.pick(String, Bool.and(err, Bool.not(shell)), "31", ""), False{}, w), pp.more(pp.hidden(ls, open, n), pp.gut())))

def pp.who(+who: String) -> String:
  Bool.pick(String, String.is_empty(who), "", "[" ++ who ++ "] ")

def pp.bd.w.of(b: pp.Bd) -> U32:
  match b:
    case pp.Bd{t, w, s}:
      w

def pp.bd.st.of(b: pp.Bd) -> String:
  match b:
    case pp.Bd{t, w, s}:
      s

def pp.bd.text.of(b: pp.Bd) -> String:
  match b:
    case pp.Bd{t, w, s}:
      t

# a tool call and its result: the header, then the output
def pp.tool(+who: String, +text: String, +res: String, +open: Bool, +run: Bool, +w: U32, +home: String) -> List<&2, String>:
  +name = pp.tool.name(text)
  +j = pp.tool.input(text)
  +bd = pp.badge(pp.bd.k(name, res), res, run)
  +left = (2 + (pp.width(pp.who(who)) + (pp.width(name) + 2 : U32) : U32) : U32)
  +room = (w - U32.min(w, (left + (pp.bd.w.of(bd) + 2 : U32) : U32)) : U32)
  +sum = pp.fit(pp.clean(pp.summary(name, j, home)), room)
  +gap = (w - U32.min(w, (left + (pp.width(sum) + pp.bd.w.of(bd) : U32) : U32)) : U32)
  +head = pp.paint(pp.bd.st.of(bd), Bool.pick(String, open, "\u{25be} ", "\u{25b8} ")) ++ pp.paint("36", pp.who(who)) ++ pp.paint("1", name) ++ "  " ++ sum ++ pp.spaces(gap) ++ pp.bd.text.of(bd)
  head <> pp.body(pp.body.k(name, res), name, j, res, open, w, home)

# 1 the user's, 2 a reply, 3 a thought, 4 a tool call, 5 a result alone, 6
# a note, 7 an agent's report, 8 a call's tokens, 9 mugen's word, 10 mugen's
# own text (SGR kept), 0 any other
def pp.kind(+kind: String) -> Nat:
  Bool.pick(Nat, String.eq(kind, "user"), 1n, Bool.pick(Nat, String.eq(kind, "unii"), 2n, Bool.pick(Nat, String.eq(kind, "mind"), 3n,
    Bool.pick(Nat, String.eq(kind, "tool"), 4n, Bool.pick(Nat, String.eq(kind, "echo"), 5n, Bool.pick(Nat, String.eq(kind, "note"), 6n,
      Bool.pick(Nat, String.eq(kind, "work"), 7n, Bool.pick(Nat, String.eq(kind, "usage"), 8n, Bool.pick(Nat, String.eq(kind, "say"), 9n,
        Bool.pick(Nat, String.eq(kind, "info"), 10n, 0n))))))))))

def pp.info(ls: List<&2, String>, +w: U32) -> List<&2, String>:
  match ls:
    case []:
      []
    case l <> rest:
      pp.sgr.cut(l, w) <> pp.info(rest, w)

# an agent's report: "[Name]", its reply, the zoom that opens its chat
def pp.work(+text: String, +open: Bool, +w: U32) -> List<&2, String>:
  +ls = pp.lines(pp.clean(text))
  +name = Maybe.default(&2, String, List.get(&2, String, ls, 0n), "")
  (pp.paint("36", "\u{25c6} ") ++ pp.paint("1;36", name) ++ pp.paint("2", " reports")) <> pp.fold(pp.md(List.drop(&2, String, ls, 1n), False{}, "", "  ", w), open, 8n, "  ")

def pp.block.go(k: Nat, +who: String, +text: String, +res: String, +open: Bool, +run: Bool, +w: U32, +home: String) -> List<&2, String>:
  match k:
    case 1n:
      +rs = pp.para(pp.lines(pp.clean(pp.who(who) ++ text)), pp.paint("1;35", "\u{276f} "), "  ", 2, "1", True{}, w)
      "" <> pp.fold(rs, open, 12n, "  ")
    case 2n:
      "" <> pp.md(pp.lines(pp.clean(text)), False{}, "", pp.paint("1", "\u{25cf} ") ++ pp.paint("36", pp.who(who)), w)
    case 3n:
      +rs = pp.para(pp.lines(pp.clean(pp.who(who) ++ text)), pp.paint("2", "\u{273b} "), "  ", 2, "2;3", True{}, w)
      "" <> pp.fold(rs, open, 3n, "  ")
    case 4n:
      pp.tool(who, text, res, open, run, w, home)
    case 5n:
      pp.para(pp.head(pp.lines(pp.clean(text)), open, 4n), pp.gut(), pp.gut(), 4, "", False{}, w)
    case 6n:
      "" <> pp.para(pp.lines(pp.clean(pp.who(who) ++ text)), pp.paint("33", "\u{203b} "), "  ", 2, "33", True{}, w)
    case 7n:
      "" <> pp.work(text, open, w)
    case 8n:
      [pp.paint("2", pp.fit("  \u{b7} " ++ pp.who(who) ++ text, w))]
    case 9n:
      pp.para(pp.lines(pp.clean(text)), "  ", "  ", 2, "2", True{}, w)
    case 10n:
      pp.info(pp.lines(text), w)
    case _:
      pp.para(pp.lines(pp.clean(pp.who(who) ++ text)), "  ", "  ", 2, "", True{}, w)

# An entry's rows: who ("" Unii's), its kind and text; a tool call's
# result ("" none yet) and whether it runs; open (unfolded); w columns;
# home, said as ~ in paths
def pp.block(+kind: String, +who: String, +text: String, +res: String, +open: Bool, +run: Bool, +w: U32, +home: String) -> List<&2, String>:
  pp.block.go(pp.kind(kind), who, text, res, open, run, w, home)

# whether a click can open or fold it
def pp.foldable(+kind: String, +text: String, +res: String) -> Bool:
  +k = pp.kind(kind)
  Bool.or(Bool.or(Nat.is_eq(k, 4n), Nat.is_eq(k, 5n)), Bool.or(Bool.or(Nat.is_eq(k, 3n), Nat.is_eq(k, 7n)), Nat.is_eq(k, 1n)))
