
import Base
import ./Pretty.bend as P

# Spell: the input's words checked as they are written. The screen
# (Screen.bend) asks hunspell (`hunspell -a`, en_US) about the words it has
# not asked about yet, five times a second at most and only when the text
# changed, and keeps the answers here: the words asked, and those hunspell
# knows not with what it offers. A word known bad is underlined in red where
# it shows; its suggestions show in a box over it while the mouse points at
# it, or while the cursor is on it. Your words (hunspell's own list,
# ~/.hunspell_en_US) are known too: M-a adds one, or takes it out.
#
# Not checked: the word being written (the one the cursor ends), code
# between backticks (a fence too), a shell command (`!` first), a run of
# text with a path's, a URL's or an address's marks (/ \ @ ~ = < > { } [ ] |
# $ # % ^ & +, or a dot inside), words with a digit or _ in them, camelCase,
# single letters.
#
# Every def is prefixed `sp.` (a program's defs share one namespace).

# a word of the text: its characters and where it starts (from 0)
type sp.W is Data:
  sp.W{text: String, at: Nat}

# a word hunspell knows not, and what it offers, best first
type sp.Bad is Data:
  sp.Bad{word: String, sugg: List<&2, String>}

# a word of the text found bad: its characters, where it starts, what is
# offered for it
type sp.F is Data:
  sp.F{text: String, at: Nat, sugg: List<&2, String>}

# a text and the cursor in it (the characters before it)
type sp.Ed is Data:
  sp.Ed{text: String, cur: Nat}

# a place on the input's layout: a row (from 0, of all its rows) and a column
type sp.Pt is Data:
  sp.Pt{row: U32, col: U32}

# The checker: on; the words asked about (newest first), and those found bad;
# what it last looked at (the text and the cursor); whether a call to
# hunspell is under way; the word the mouse points at and the word whose
# box Esc closed (each where it starts, plus 1; 0 none); the box as last
# drawn (sp.box.key)
type sp.Sp is Data:
  sp.Sp{on: Bool, seen: List<&2, String>, bad: List<&2, sp.Bad>, last: String, busy: Bool, mx: Nat, shut: Nat, drawn: String}

def sp.new() -> sp.Sp:
  sp.Sp{True{}, [], [], "", False{}, 0n, 0n, ""}

# Fields -------------------------------------------------------------------------

def sp.w.text(w: sp.W) -> String:
  match w:
    case sp.W{t, a}:
      t

def sp.w.at(w: sp.W) -> Nat:
  match w:
    case sp.W{t, a}:
      a

def sp.bad.word(b: sp.Bad) -> String:
  match b:
    case sp.Bad{w, s}:
      w

def sp.bad.sugg(b: sp.Bad) -> List<&2, String>:
  match b:
    case sp.Bad{w, s}:
      s

def sp.f.text(f: sp.F) -> String:
  match f:
    case sp.F{t, a, s}:
      t

def sp.f.at(f: sp.F) -> Nat:
  match f:
    case sp.F{t, a, s}:
      a

def sp.f.sugg(f: sp.F) -> List<&2, String>:
  match f:
    case sp.F{t, a, s}:
      s

def sp.ed.text(x: sp.Ed) -> String:
  match x:
    case sp.Ed{t, c}:
      t

def sp.ed.cur(x: sp.Ed) -> Nat:
  match x:
    case sp.Ed{t, c}:
      c

def sp.pt.row(p: sp.Pt) -> U32:
  match p:
    case sp.Pt{r, c}:
      r

def sp.pt.col(p: sp.Pt) -> U32:
  match p:
    case sp.Pt{r, c}:
      c

def sp.on(x: sp.Sp) -> Bool:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      on

def sp.seen(x: sp.Sp) -> List<&2, String>:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      se

def sp.bad(x: sp.Sp) -> List<&2, sp.Bad>:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      b

def sp.last(x: sp.Sp) -> String:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      l

def sp.busy(x: sp.Sp) -> Bool:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      bu

def sp.mx(x: sp.Sp) -> Nat:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      mx

def sp.shut(x: sp.Sp) -> Nat:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      sh

def sp.drawn(x: sp.Sp) -> String:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      d

# on or off: off, what it was asking about is dropped (on again, it looks anew)
def sp.with.on(x: sp.Sp, +on2: Bool) -> sp.Sp:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      sp.Sp{on2, se, b, "", False{}, 0n, 0n, d}

# a call under way about the text and cursor `key`
def sp.with.asking(x: sp.Sp, +key: String) -> sp.Sp:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      sp.Sp{on, se, b, key, True{}, mx, sh, d}

# looked at, nothing new to ask
def sp.with.last(x: sp.Sp, +key: String) -> sp.Sp:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      sp.Sp{on, se, b, key, bu, mx, sh, d}

# hunspell's answers: the words asked (each kept, good or bad), the bad ones
def sp.with.got(x: sp.Sp, +ws: List<&2, String>, +bs: List<&2, sp.Bad>) -> sp.Sp:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      sp.Sp{on, List.take(&2, String, List.append(&2, String, ws, se), 4000n), List.take(&2, sp.Bad, List.append(&2, sp.Bad, bs, b), 1000n), l, False{}, mx, sh, d}

def sp.with.mx(x: sp.Sp, +mx2: Nat) -> sp.Sp:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      sp.Sp{on, se, b, l, bu, mx2, sh, d}

def sp.with.shut(x: sp.Sp, +sh2: Nat) -> sp.Sp:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      sp.Sp{on, se, b, l, bu, mx, sh2, d}

def sp.with.drawn(x: sp.Sp, +d2: String) -> sp.Sp:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      sp.Sp{on, se, b, l, bu, mx, sh, d2}

# Characters -----------------------------------------------------------------------

# a letter: ASCII's, and Latin's with marks (À to ɏ, but × and ÷)
def sp.letter(+c: U32) -> Bool:
  Bool.or(Bool.or(P.pp.in(c, 65, 90), P.pp.in(c, 97, 122)), Bool.and(P.pp.in(c, 192, 591), Bool.and(U32.is_ne(c, 215), U32.is_ne(c, 247))))

def sp.apos(+c: U32) -> Bool:
  Bool.or(U32.is_eq(c, 39), U32.is_eq(c, 8217))

# a word's character: a letter, a digit, _ or an apostrophe
def sp.wordy(+c: U32) -> Bool:
  Bool.or(Bool.or(sp.letter(c), P.pp.in(c, 48, 57)), Bool.or(U32.is_eq(c, 95), sp.apos(c)))

def sp.space(+c: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(c, 32), U32.is_eq(c, 10)), Bool.or(U32.is_eq(c, 9), U32.is_eq(c, 13)))

# a mark of a path, a URL, an address or code: / \ @ ~ = < > { } [ ] | $ # % ^ & +
def sp.mark(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.or(Bool.or(U32.is_eq(c, 47), U32.is_eq(c, 92)), Bool.or(U32.is_eq(c, 64), U32.is_eq(c, 126))),
    Bool.or(Bool.or(U32.is_eq(c, 61), U32.is_eq(c, 60)), Bool.or(U32.is_eq(c, 62), U32.is_eq(c, 123)))),
    Bool.or(Bool.or(Bool.or(U32.is_eq(c, 125), U32.is_eq(c, 91)), Bool.or(U32.is_eq(c, 93), U32.is_eq(c, 124))),
      Bool.or(Bool.or(U32.is_eq(c, 36), U32.is_eq(c, 35)), Bool.or(Bool.or(U32.is_eq(c, 37), U32.is_eq(c, 94)), Bool.or(U32.is_eq(c, 38), U32.is_eq(c, 43))))))

# whether s's head is a letter or a digit
def sp.alnum.head(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, t}:
      Bool.or(sp.letter(c), P.pp.in(c, 48, 57))

def sp.upper.head(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, t}:
      P.pp.in(c, 65, 90)

# Words ---------------------------------------------------------------------------

# the text with its code (between backticks, the backticks too) as spaces,
# its newlines kept: as long as it was
def sp.uncode(s: String, +code: Bool) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{96}, +t}:
      SCon{Chr{32}, sp.uncode(t, Bool.not(code))}
    case SCon{Chr{10}, +t}:
      SCon{Chr{10}, sp.uncode(t, code)}
    case SCon{Chr{+c}, +t}:
      SCon{Chr{Bool.pick(U32, code, 32, c)}, sp.uncode(t, code)}

# 1 when s's head is in a run of mode m (0 a chunk: no space; 1 a word:
# sp.wordy), else 0
def sp.in.v(s: String, +m: Nat) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, Bool.pick(Bool, Nat.is_eq(m, 0n), Bool.not(sp.space(c)), sp.wordy(c)), 1n, 0n)

def sp.push(+cur: String, +from: Nat, +acc: List<&2, sp.W>) -> List<&2, sp.W>:
  Bool.pick(List<&2, sp.W>, String.is_empty(cur), acc, sp.W{String.reverse(cur), from} <> acc)

# s's runs (sp.in.v, of mode m), each with where it starts (s starts at at)
def sp.runs(s: String, v: Nat, +m: Nat, +at: Nat, +cur: String, +from: Nat, +acc: List<&2, sp.W>) -> List<&2, sp.W>:
  match s v:
    case SCon{+c, +t} 1n:
      sp.runs(t, sp.in.v(t, m), m, Nat.add(at, 1n), SCon{c, cur}, Bool.pick(Nat, String.is_empty(cur), at, from), acc)
    case SCon{c, +t} _:
      sp.runs(t, sp.in.v(t, m), m, Nat.add(at, 1n), "", 0n, sp.push(cur, from, acc))
    case _ _:
      List.reverse(&2, sp.W, sp.push(cur, from, acc))

# whether a chunk has a path's, a URL's or an address's marks: one of
# sp.mark, or a dot with a letter or digit after it
def sp.marked(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{46}, +t}:
      Bool.or(sp.alnum.head(t), sp.marked(t))
    case SCon{Chr{+c}, +t}:
      Bool.or(sp.mark(c), sp.marked(t))

def sp.chunk.words(marked: Bool, +c: sp.W) -> List<&2, sp.W>:
  match marked:
    case True{}:
      []
    case False{}:
      +t = sp.w.text(c)
      sp.runs(t, sp.in.v(t, 1n), 1n, sp.w.at(c), "", 0n, [])

# the words of the chunks with no marks
def sp.chunks.words(cs: List<&2, sp.W>) -> List<&2, sp.W>:
  match cs:
    case []:
      []
    case +c <> rest:
      List.append(&2, sp.W, sp.chunk.words(sp.marked(sp.w.text(c)), c), sp.chunks.words(rest))

def sp.apos.v(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, sp.apos(c), 1n, 0n)

# the apostrophes at a word's head dropped (where it starts moves on)
def sp.trim.lead(s: String, v: Nat, +at: Nat) -> sp.W:
  match s v:
    case SCon{c, +t} 1n:
      sp.trim.lead(t, sp.apos.v(t), Nat.add(at, 1n))
    case SCon{+c, +t} _:
      sp.W{SCon{c, t}, at}
    case _ _:
      sp.W{"", at}

# a word without the apostrophes around it ('quoted', dogs')
def sp.trim(+w: sp.W) -> sp.W:
  +t = sp.w.text(w)
  +a = sp.trim.lead(t, sp.apos.v(t), sp.w.at(w))
  +r = String.reverse(sp.w.text(a))
  +b = sp.trim.lead(r, sp.apos.v(r), 0n)
  sp.W{String.reverse(sp.w.text(b)), sp.w.at(a)}

# no digit, no _, and no lower letter before an upper one (camelCase)
def sp.plain(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, +t}:
      Bool.and(Bool.and(Bool.not(Bool.or(P.pp.in(c, 48, 57), U32.is_eq(c, 95))), Bool.not(Bool.and(P.pp.in(c, 97, 122), sp.upper.head(t)))), sp.plain(t))

# a word to check: two characters or more, plain, and not the one being
# written (the one that ends where the cursor is)
def sp.keep(+w: sp.W, +cur: Nat) -> Bool:
  +t = sp.w.text(w)
  +n = String.length(t)
  Bool.and(Bool.and(Nat.is_ge(n, 2n), sp.plain(t)), Bool.not(Nat.is_eq(Nat.add(sp.w.at(w), n), cur)))

def sp.filter(ws: List<&2, sp.W>, +cur: Nat) -> List<&2, sp.W>:
  match ws:
    case []:
      []
    case +w <> rest:
      +t = sp.trim(w)
      List.append(&2, sp.W, Bool.pick(List<&2, sp.W>, sp.keep(t, cur), [t], []), sp.filter(rest, cur))

def sp.words.go(bang: Bool, +t: String, +cur: Nat) -> List<&2, sp.W>:
  match bang:
    case True{}:
      []
    case False{}:
      +u = sp.uncode(t, False{})
      sp.filter(sp.chunks.words(sp.runs(u, sp.in.v(u, 0n), 0n, 0n, "", 0n, [])), cur)

# the words of a text to check, in order, the cursor at cur
def sp.words(+t: String, +cur: Nat) -> List<&2, sp.W>:
  sp.words.go(String.starts_with(String.trim(t), "!"), t, cur)

# Asking ---------------------------------------------------------------------------

def sp.has(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case []:
      False{}
    case +y <> rest:
      Bool.or(String.eq(x, y), sp.has(rest, x))

# the words not asked about yet, each once, in order: 64 at most
def sp.fresh(ws: List<&2, sp.W>, +seen: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match ws:
    case []:
      List.take(&2, String, List.reverse(&2, String, acc), 64n)
    case +w <> rest:
      +t = sp.w.text(w)
      sp.fresh(rest, seen, Bool.pick(List<&2, String>, Bool.or(sp.has(seen, t), sp.has(acc, t)), acc, t <> acc))

# hunspell -a's input: a word a line, each after a ^ (so none reads as a
# command of its)
def sp.ask(ws: List<&2, String>) -> String:
  match ws:
    case []:
      ""
    case +w <> rest:
      "^" ++ w ++ "\n" ++ sp.ask(rest)

def sp.args() -> List<String>:
  ["-a", "-i", "utf-8", "-d", "en_US"]

# the same, the words file given (the tests'; mugen's is hunspell's default)
def sp.args.p(path: String) -> List<String>:
  ["-a", "-i", "utf-8", "-d", "en_US", "-p", path]

# whether hunspell ran: it exited well, its banner first
def sp.ran(+status: U32, +out: String) -> Bool:
  Bool.and(U32.is_eq(status, 0), String.starts_with(out, "@(#)"))

# The answer ------------------------------------------------------------------------
#
# After hunspell's banner, a line for each word it read in a line of the
# input, then an empty line: `*`, `+ ROOT` or `-` for one it knows; `& orig
# n off: s1, s2, ...` for one it knows not, with what it offers, or `# orig
# off` with nothing. orig may be a part of the word (off: where, from 1).

# a line's kind: 0 empty (a word's answer over), 1 & or # (bad), 2 any
# other, 3 no line left
def sp.line.k(ls: List<&2, String>) -> Nat:
  match ls:
    case []:
      3n
    case +l <> rest:
      Bool.pick(Nat, String.is_empty(l), 0n, Bool.pick(Nat, Bool.or(String.starts_with(l, "&"), String.starts_with(l, "#")), 1n, 2n))

# what follows ": "
def sp.after.colon(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{58}, SCon{Chr{32}, +t}}:
      t
    case SCon{c, +t}:
      sp.after.colon(t)

def sp.trims(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case []:
      []
    case +x <> rest:
      +t = String.trim(x)
      List.append(&2, String, Bool.pick(List<&2, String>, String.is_empty(t), [], [t]), sp.trims(rest))

# each suggestion for the part (orig, from at) put in the word in its place
def sp.spliced(ss: List<&2, String>, +w: String, +orig: String, +at: Nat) -> List<&2, String>:
  match ss:
    case []:
      []
    case +s <> rest:
      (String.take(w, at) ++ s ++ String.drop(w, Nat.add(at, String.length(orig)))) <> sp.spliced(rest, w, orig, at)

# an & line's suggestions for the word asked (# has none); 5 at most (the box shows them all)
def sp.sugg(+l: String, +w: String) -> List<&2, String>:
  +fs = String.split(l, ' ')
  +orig = Maybe.default(&2, String, List.get(&2, String, fs, 1n), "")
  +f3 = Maybe.default(&2, String, List.get(&2, String, fs, 3n), "")
  +off = Maybe.default(&2, Nat, Nat.read(Maybe.default(&2, String, List.get(&2, String, String.split(f3, ':'), 0n), "1")), 1n)
  +ss = sp.trims(String.split(sp.after.colon(l), ','))
  +at = Nat.sub(off, 1n)
  +same = Bool.or(String.eq(orig, w), Bool.not(String.eq(String.take(String.drop(w, at), String.length(orig)), orig)))
  List.take(&2, String, Bool.pick(List<&2, String>, String.starts_with(l, "&"), Bool.pick(List<&2, String>, same, ss, sp.spliced(ss, w, orig, at)), []), 5n)

def sp.keep.bad(m: Maybe<&2, List<&2, String>>, +w: String, +acc: List<&2, sp.Bad>) -> List<&2, sp.Bad>:
  match m:
    case Some{+ss}:
      sp.Bad{w, ss} <> acc
    case None{}:
      acc

def sp.first.got(m: Maybe<&2, List<&2, String>>, +ss: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match m:
    case Some{+x}:
      Some{x}
    case None{}:
      Some{ss}

# the answer's lines (k: the head's kind, sp.line.k) read against the words
# asked: the bad ones, each with the suggestions of its first & or # line
def sp.read(ls: List<&2, String>, k: Nat, ws: List<&2, String>, +got: Maybe<&2, List<&2, String>>, +acc: List<&2, sp.Bad>) -> List<&2, sp.Bad>:
  match ls k ws:
    case l <> +rest 0n +w <> +wr:
      sp.read(rest, sp.line.k(rest), wr, None{}, sp.keep.bad(got, w, acc))
    case +l <> +rest 1n +w <> +wr:
      sp.read(rest, sp.line.k(rest), w <> wr, sp.first.got(got, sp.sugg(l, w)), acc)
    case l <> +rest _ +ws2:
      sp.read(rest, sp.line.k(rest), ws2, got, acc)
    case _ _ _:
      List.reverse(&2, sp.Bad, acc)

# hunspell -a's output for the words asked: those it knows not
def sp.parse(+out: String, +ws: List<&2, String>) -> List<&2, sp.Bad>:
  +ls0 = String.lines(out)
  +ls = Bool.pick(List<&2, String>, String.starts_with(out, "@(#)"), List.drop(&2, String, ls0, 1n), ls0)
  sp.read(ls, sp.line.k(ls), ws, None{}, [])

# Showing -----------------------------------------------------------------------------

def sp.bad.of(bs: List<&2, sp.Bad>, +w: String) -> Maybe<&2, List<&2, String>>:
  match bs:
    case []:
      None{}
    case +b <> rest:
      Bool.pick(Maybe<&2, List<&2, String>>, String.eq(sp.bad.word(b), w), Some{sp.bad.sugg(b)}, sp.bad.of(rest, w))

def sp.bad.words(bs: List<&2, sp.Bad>) -> List<&2, String>:
  match bs:
    case []:
      []
    case +b <> rest:
      sp.bad.word(b) <> sp.bad.words(rest)

def sp.flag.one(m: Maybe<&2, List<&2, String>>, +w: sp.W) -> List<&2, sp.F>:
  match m:
    case Some{+ss}:
      [sp.F{sp.w.text(w), sp.w.at(w), ss}]
    case None{}:
      []

# the words known bad, in order
def sp.flag(ws: List<&2, sp.W>, +bs: List<&2, sp.Bad>) -> List<&2, sp.F>:
  match ws:
    case []:
      []
    case +w <> rest:
      List.append(&2, sp.F, sp.flag.one(sp.bad.of(bs, sp.w.text(w)), w), sp.flag(rest, bs))

# a character for each of the text's: 1 in a bad word, 0 not (n long, the
# words in order, from pos on)
def sp.mask(fs: List<&2, sp.F>, +pos: Nat, +n: Nat) -> String:
  match fs:
    case []:
      String.repeat("0", Nat.sub(n, pos))
    case +f <> rest:
      +at = sp.f.at(f)
      +k = String.length(sp.f.text(f))
      String.repeat("0", Nat.sub(at, pos)) ++ String.repeat("1", k) ++ sp.mask(rest, Nat.add(at, k), n)

# the red curly underline (a plain one where the terminal knows no curl), and its end
def sp.sgr.on() -> String:
  "\u{1B}[4m\u{1B}[4:3m\u{1B}[58:2::255:0:0m"

def sp.sgr.off() -> String:
  "\u{1B}[24m\u{1B}[59m"

def sp.sgr(+was: Bool, +bad: Bool) -> String:
  Bool.pick(String, Bool.xor(was, bad), Bool.pick(String, bad, sp.sgr.on(), sp.sgr.off()), "")

# a row's characters underlined where its mask says (on: they are so far)
def sp.paint.row(r: String, m: String, +on: Bool) -> String:
  match r m:
    case SCon{c, +t} SCon{Chr{+f}, +u}:
      +bad = U32.is_eq(f, 49)
      sp.sgr(on, bad) ++ SCon{c, sp.paint.row(t, u, bad)}
    case _ _:
      Bool.pick(String, on, sp.sgr.off(), "")

def sp.nl.k(s: String) -> Nat:
  match s:
    case SCon{Chr{10}, t}:
      1n
    case _:
      0n

# the input's rows as laid out (Edit.bend ed.lay: each the text's next
# characters, a newline that ends one dropped), the bad words underlined
def sp.paint(rows: List<&2, String>, +text: String, +mask: String) -> List<&2, String>:
  match rows:
    case []:
      []
    case +r <> rest:
      +n = String.length(r)
      +t2 = String.drop(text, n)
      +k = sp.nl.k(t2)
      sp.paint.row(r, String.take(mask, n), False{}) <> sp.paint(rest, String.drop(t2, k), String.drop(String.drop(mask, n), k))

# where each row starts in the text
def sp.starts(rows: List<&2, String>, +text: String, +at: Nat) -> List<&2, Nat>:
  match rows:
    case []:
      []
    case +r <> rest:
      +n = String.length(r)
      +t2 = String.drop(text, n)
      +k = sp.nl.k(t2)
      at <> sp.starts(rest, String.drop(t2, k), Nat.add(Nat.add(at, n), k))

# the character at column c of a row (from 0): its place in the row, or
# the row's length past its end
def sp.col.at(r: String, +c: U32, +x: U32, +k: Nat) -> Nat:
  match r:
    case SNil{}:
      k
    case SCon{Chr{+ch}, +t}:
      +x2 = (x + P.pp.cw(ch) : U32)
      Bool.pick(Nat, U32.is_lt(c, x2), k, sp.col.at(t, c, x2, Nat.add(k, 1n)))

# the text's character at row i, column c of the layout (None past a row's end)
def sp.spot(+rows: List<&2, String>, +sts: List<&2, Nat>, +i: U32, +c: U32) -> Maybe<&2, Nat>:
  +r = Maybe.default(&2, String, List.get(&2, String, rows, U32.to_nat(i)), "")
  +s = Maybe.default(&2, Nat, List.get(&2, Nat, sts, U32.to_nat(i)), 0n)
  +k = sp.col.at(r, c, 0, 0n)
  Bool.pick(Maybe<&2, Nat>, Bool.and(Nat.is_lt(U32.to_nat(i), List.length(&2, String, rows)), Nat.is_lt(k, String.length(r))), Some{Nat.add(s, k)}, None{})

# where the text's character at sits on the layout
def sp.place(rows: List<&2, String>, sts: List<&2, Nat>, +at: Nat, +i: U32) -> sp.Pt:
  match rows sts:
    case +r <> rest +s <> srest:
      +n = String.length(r)
      Bool.pick(sp.Pt, Bool.and(Nat.is_ge(at, s), Nat.is_lt(at, Nat.add(s, n))), sp.Pt{i, P.pp.width(String.take(r, Nat.sub(at, s)))}, sp.place(rest, srest, at, (i + 1 : U32)))
    case _ _:
      sp.Pt{i, 0}

# the bad word that has the character at in it
def sp.over(fs: List<&2, sp.F>, +at: Nat) -> Maybe<&2, sp.F>:
  match fs:
    case []:
      None{}
    case +f <> rest:
      +a = sp.f.at(f)
      Bool.pick(Maybe<&2, sp.F>, Bool.and(Nat.is_ge(at, a), Nat.is_lt(at, Nat.add(a, String.length(sp.f.text(f))))), Some{f}, sp.over(rest, at))

# the bad word that starts at at
def sp.from(fs: List<&2, sp.F>, +at: Nat) -> Maybe<&2, sp.F>:
  match fs:
    case []:
      None{}
    case +f <> rest:
      Bool.pick(Maybe<&2, sp.F>, Nat.is_eq(sp.f.at(f), at), Some{f}, sp.from(rest, at))

# where a word starts, plus 1 (0 none)
def sp.key.of(m: Maybe<&2, sp.F>) -> Nat:
  match m:
    case Some{f}:
      Nat.add(sp.f.at(f), 1n)
    case None{}:
      0n

# the word the keys fix: the one the mouse points at (mx: where it starts,
# plus 1), else the one the cursor is on (not at its end: there it is being
# written, and is no bad word)
def sp.target(+fs: List<&2, sp.F>, +cur: Nat, +mx: Nat) -> Maybe<&2, sp.F>:
  +m = Bool.pick(Maybe<&2, sp.F>, Nat.is_eq(mx, 0n), None{}, sp.from(fs, Nat.sub(mx, 1n)))
  Bool.pick(Maybe<&2, sp.F>, Maybe.is_some(&2, sp.F, m), m, sp.over(fs, cur))

# Your words ----------------------------------------------------------------------------
#
# Your words are hunspell's own list, ~/.hunspell_en_US, read by each call
# of it (so a word added counts at the next): a word a line (`word/FLAGS`
# too). A line `*word` makes a word wrong; mugen writes none, and takes
# none out. A word is kept in lowercase, unless a capital follows its first
# letter (GitHub, OAuth, NASA): hunspell lets a lowercase word come
# capitalized, not the other way.

def sp.dict.file() -> String:
  "/.hunspell_en_US"

# an upper letter: ASCII's, or Latin-1's (À to Þ, but ×)
def sp.upper(+c: U32) -> Bool:
  Bool.or(P.pp.in(c, 65, 90), Bool.and(P.pp.in(c, 192, 222), U32.is_ne(c, 215)))

def sp.lower(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{+c}, +t}:
      SCon{Chr{Bool.pick(U32, sp.upper(c), (c + 32 : U32), c)}, sp.lower(t)}

def sp.caps(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, +t}:
      Bool.or(sp.upper(c), sp.caps(t))

# the form a word is kept in
def sp.dict.form(+w: String) -> String:
  Bool.pick(String, sp.caps(String.drop(w, 1n)), w, sp.lower(w))

# a line's word ("" none: an empty line, a `*word`)
def sp.dict.key(+l: String) -> String:
  +t = String.trim(l)
  +k = String.trim(Maybe.default(&2, String, List.get(&2, String, String.split(t, '/'), 0n), ""))
  Bool.pick(String, String.starts_with(t, "*"), "", k)

# whether a line holds the word (w in its form)
def sp.dict.is(+l: String, +w: String) -> Bool:
  +k = sp.dict.key(l)
  Bool.and(Bool.not(String.is_empty(k)), String.eq(sp.dict.form(k), w))

def sp.dict.has(ls: List<&2, String>, +w: String) -> Bool:
  match ls:
    case []:
      False{}
    case +l <> rest:
      Bool.or(sp.dict.is(l, w), sp.dict.has(rest, w))

# the lines but those holding the word
def sp.dict.drop(ls: List<&2, String>, +w: String) -> List<&2, String>:
  match ls:
    case []:
      []
    case +l <> rest:
      List.append(&2, String, Bool.pick(List<&2, String>, sp.dict.is(l, w), [], [l]), sp.dict.drop(rest, w))

# the file's lines, the empty ones dropped
def sp.dict.nonempty(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case []:
      []
    case +l <> rest:
      List.append(&2, String, Bool.pick(List<&2, String>, String.is_empty(String.trim(l)), [], [l]), sp.dict.nonempty(rest))

def sp.dict.lines(+text: String) -> List<&2, String>:
  sp.dict.nonempty(String.lines(text))

# the file's text, each line ended
def sp.dict.text(ls: List<&2, String>) -> String:
  match ls:
    case []:
      ""
    case +l <> rest:
      l ++ "\n" ++ sp.dict.text(rest)

# the words, in the file's order
def sp.dict.words(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case []:
      []
    case +l <> rest:
      +k = sp.dict.key(l)
      List.append(&2, String, Bool.pick(List<&2, String>, String.is_empty(k), [], [k]), sp.dict.words(rest))

# a word one may keep: not empty, no / (hunspell's flags), no * first
def sp.dict.ok(+w: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(w)), Bool.and(Bool.not(String.starts_with(w, "*")), Nat.is_eq(List.length(&2, String, String.split(w, '/')), 1n)))

# A change to the words: the file's lines after it, the words it changed
# (in their form), those it left (already in, or not in, or no word)
type sp.Dx is Data:
  sp.Dx{lines: List<&2, String>, done: List<&2, String>, left: List<&2, String>}

def sp.dx.lines(x: sp.Dx) -> List<&2, String>:
  match x:
    case sp.Dx{l, d, f}:
      l

def sp.dx.done(x: sp.Dx) -> List<&2, String>:
  match x:
    case sp.Dx{l, d, f}:
      d

def sp.dx.left(x: sp.Dx) -> List<&2, String>:
  match x:
    case sp.Dx{l, d, f}:
      f

def sp.dx.new(+ls: List<&2, String>) -> sp.Dx:
  sp.Dx{ls, [], []}

# 0 the word changes, 1 it is left
def sp.dx.k(+go: Bool) -> Nat:
  Bool.pick(Nat, go, 0n, 1n)

def sp.dx.step(k: Nat, x: sp.Dx, +ls2: List<&2, String>, +w: String) -> sp.Dx:
  match k x:
    case 0n sp.Dx{l, +d, f}:
      sp.Dx{ls2, List.append(&2, String, d, [w]), f}
    case _ sp.Dx{+l, d, +f}:
      sp.Dx{l, d, List.append(&2, String, f, [w])}

# words added, each in its form (one already in is left)
def sp.dict.add(ws: List<&2, String>, +x: sp.Dx) -> sp.Dx:
  match ws:
    case []:
      x
    case +w <> rest:
      +f = sp.dict.form(w)
      +ls = sp.dx.lines(x)
      +go = Bool.and(sp.dict.ok(w), Bool.not(sp.dict.has(ls, f)))
      sp.dict.add(rest, sp.dx.step(sp.dx.k(go), x, List.append(&2, String, ls, [f]), f))

# words taken out (one not in is left)
def sp.dict.rm(ws: List<&2, String>, +x: sp.Dx) -> sp.Dx:
  match ws:
    case []:
      x
    case +w <> rest:
      +f = sp.dict.form(w)
      +ls = sp.dx.lines(x)
      sp.dict.rm(rest, sp.dx.step(sp.dx.k(sp.dict.has(ls, f)), x, sp.dict.drop(ls, f), f))

# Words known: those hunspell answered (seen) found good
def sp.known(+x: sp.Sp, +w: String) -> Bool:
  Bool.and(sp.has(sp.seen(x), w), Maybe.is_none(&2, List<&2, String>, sp.bad.of(sp.bad(x), w)))

def sp.not.of(xs: List<&2, String>, +lw: String) -> List<&2, String>:
  match xs:
    case []:
      []
    case +x <> rest:
      List.append(&2, String, Bool.pick(List<&2, String>, String.eq(sp.lower(x), lw), [], [x]), sp.not.of(rest, lw))

def sp.bad.not.of(bs: List<&2, sp.Bad>, +lw: String) -> List<&2, sp.Bad>:
  match bs:
    case []:
      []
    case +b <> rest:
      List.append(&2, sp.Bad, Bool.pick(List<&2, sp.Bad>, String.eq(sp.lower(sp.bad.word(b)), lw), [], [b]), sp.bad.not.of(rest, lw))

# a word's answers forgotten (in any case), and the input looked at anew:
# the next tick asks hunspell about it again, which reads the words then
def sp.forget(x: sp.Sp, +w: String) -> sp.Sp:
  match x:
    case sp.Sp{on, se, b, l, bu, mx, sh, d}:
      +lw = sp.lower(w)
      sp.Sp{on, sp.not.of(se, lw), sp.bad.not.of(b, lw), "", bu, mx, sh, d}

def sp.forget.all(ws: List<&2, String>, +x: sp.Sp) -> sp.Sp:
  match ws:
    case []:
      x
    case +w <> rest:
      sp.forget.all(rest, sp.forget(x, w))

# the word the cursor is in or just after, of any (checked or not)
def sp.at.cur(ws: List<&2, sp.W>, +cur: Nat) -> Maybe<&2, sp.W>:
  match ws:
    case []:
      None{}
    case +w <> rest:
      +a = sp.w.at(w)
      Bool.pick(Maybe<&2, sp.W>, Bool.and(Nat.is_ge(cur, a), Nat.is_le(cur, Nat.add(a, String.length(sp.w.text(w))))), Some{w}, sp.at.cur(rest, cur))

# the text's word the cursor is on (None: none)
def sp.cur.word(+t: String, +cur: Nat) -> Maybe<&2, sp.W>:
  sp.at.cur(sp.words(t, Nat.add(String.length(t), 1n)), cur)

# The box ------------------------------------------------------------------------------
#
# Over the word: its suggestions numbered (5 at most), the first lit (M-s
# takes it), and the keys.

def sp.box.n(+f: sp.F) -> Nat:
  Nat.min(List.length(&2, String, sp.f.sugg(f)), 5n)

def sp.box.items(ss: List<&2, String>, +i: Nat) -> List<&2, String>:
  match ss:
    case []:
      []
    case +s <> rest:
      (" " ++ Nat.show(Nat.add(i, 1n)) ++ " " ++ s ++ " ") <> sp.box.items(rest, Nat.add(i, 1n))

def sp.box.keys(+n: Nat) -> String:
  Bool.pick(String, Nat.is_eq(n, 0n), " no suggestion \u{b7} Esc ", " M-s \u{b7} M-1.." ++ Nat.show(n) ++ " \u{b7} M-S all \u{b7} Esc ")

def sp.widest(xs: List<&2, String>, +w: U32) -> U32:
  match xs:
    case []:
      w
    case +x <> rest:
      sp.widest(rest, U32.max(w, P.pp.width(x)))

def sp.box.paint(xs: List<&2, String>, +w: U32, +first: Bool) -> List<&2, String>:
  match xs:
    case []:
      []
    case +x <> rest:
      +pad = x ++ P.pp.spaces((w - U32.min(w, P.pp.width(x)) : U32))
      ("\u{1B}[0m" ++ Bool.pick(String, first, "\u{1B}[1;97;44m", "\u{1B}[97;48;5;238m") ++ pad ++ "\u{1B}[0m") <> sp.box.paint(rest, w, False{})

# the row that adds the word to your words (M-a, or a click)
def sp.box.add(+f: sp.F) -> String:
  " + add \u{ab}" ++ sp.dict.form(sp.f.text(f)) ++ "\u{bb} to your words \u{b7} M-a "

def sp.box.row(+st: String, +x: String, +w: U32) -> String:
  "\u{1B}[0m\u{1B}[" ++ st ++ "m" ++ x ++ P.pp.spaces((w - U32.min(w, P.pp.width(x)) : U32)) ++ "\u{1B}[0m"

# its rows, as drawn: the suggestions, the row that adds, the keys
def sp.box.rows(+f: sp.F) -> List<&2, String>:
  +n = sp.box.n(f)
  +items = sp.box.items(List.take(&2, String, sp.f.sugg(f), n), 0n)
  +add = sp.box.add(f)
  +keys = sp.box.keys(n)
  +w = sp.widest(add <> keys <> items, 0)
  List.append(&2, String, sp.box.paint(items, w, True{}), [sp.box.row("36;48;5;238", add, w), sp.box.row("2;37;48;5;238", keys, w)])

def sp.box.width(+f: sp.F) -> U32:
  +n = sp.box.n(f)
  sp.widest(sp.box.add(f) <> sp.box.keys(n) <> sp.box.items(List.take(&2, String, sp.f.sugg(f), n), 0n), 0)

# Fixing --------------------------------------------------------------------------------

# n characters from at replaced by r, the cursor where it was in the text
# around (in the word: after its new end)
def sp.replace(x: sp.Ed, +at: Nat, +n: Nat, +r: String) -> sp.Ed:
  match x:
    case sp.Ed{+t, +c}:
      +m = String.length(r)
      +end = Nat.add(at, n)
      +c2 = Bool.pick(Nat, Nat.is_ge(c, end), Nat.add(Nat.sub(c, n), m), Bool.pick(Nat, Nat.is_gt(c, at), Nat.add(at, m), c))
      sp.Ed{String.take(t, at) ++ r ++ String.drop(t, end), c2}

def sp.fix.with(m: Maybe<&2, String>, +x: sp.Ed, +f: sp.F) -> sp.Ed:
  match m:
    case Some{+r}:
      sp.replace(x, sp.f.at(f), String.length(sp.f.text(f)), r)
    case None{}:
      x

# a bad word replaced by suggestion i (none: as it was)
def sp.fix(+x: sp.Ed, +f: sp.F, +i: Nat) -> sp.Ed:
  sp.fix.with(List.get(&2, String, sp.f.sugg(f), i), x, f)

def sp.fix.rev(fs: List<&2, sp.F>, +x: sp.Ed) -> sp.Ed:
  match fs:
    case []:
      x
    case +f <> rest:
      sp.fix.rev(rest, sp.fix(x, f, 0n))

# every bad word (in order, none overlapping) replaced by its first
# suggestion, from the last (so where the others start holds)
def sp.fix.all(+fs: List<&2, sp.F>, +x: sp.Ed) -> sp.Ed:
  sp.fix.rev(List.reverse(&2, sp.F, fs), x)

# how many have a suggestion
def sp.fixable(fs: List<&2, sp.F>) -> Nat:
  match fs:
    case []:
      0n
    case +f <> rest:
      Nat.add(Bool.pick(Nat, List.is_empty(&2, String, sp.f.sugg(f)), 0n, 1n), sp.fixable(rest))
