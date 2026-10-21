import Base

# Text: the string semantics UniiChat's TypeScript has, written from their
# definitions, since every byte a model reads is built from these. A Bend
# String is a list of Unicode scalars; JavaScript's are UTF-16 units, so
# lengths UniiChat measures in .length (Clip.ts) are counted here in UTF-16
# units, and byte sizes (Memory.bytes) in UTF-8.
#
# Bend has no mutual recursion and matches only parameters, so a loop that
# branches on its next scalar takes that branch's test as a parameter,
# computed by the caller (`sp`, `fits`, ...).
#
# Every def is prefixed `tx.` (a program's defs share one namespace).

# Chars ---------------------------------------------------------------------

def tx.code(c: Char) -> U32:
  match c:
    case Chr{n}:
      n

def tx.one(+n: U32) -> String:
  SCon{Chr{n}, SNil{}}

# UTF-8 bytes of one scalar
def tx.width8(+c: U32) -> U32:
  Bool.pick(U32, U32.is_lt(c, 128), 1, Bool.pick(U32, U32.is_lt(c, 2048), 2, Bool.pick(U32, U32.is_lt(c, 65536), 3, 4)))

# UTF-16 units of one scalar
def tx.width16(+c: U32) -> U32:
  Bool.pick(U32, U32.is_lt(c, 65536), 1, 2)

# JavaScript's \s: WhiteSpace and LineTerminator (ECMA-262 22.2.2.9)
def tx.is_space(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(c, 9), U32.is_le(c, 13)), U32.is_eq(c, 32)),
    Bool.or(Bool.or(U32.is_eq(c, 160), U32.is_eq(c, 5760)),
      Bool.or(Bool.and(U32.is_ge(c, 8192), U32.is_le(c, 8202)),
        Bool.or(Bool.or(U32.is_eq(c, 8232), U32.is_eq(c, 8233)),
          Bool.or(Bool.or(U32.is_eq(c, 8239), U32.is_eq(c, 8287)), Bool.or(U32.is_eq(c, 12288), U32.is_eq(c, 65279)))))))

# the first scalar, or 4294967295 for ""
def tx.head(+s: String) -> U32:
  match s:
    case SNil{}:
      4294967295
    case SCon{Chr{c}, t}:
      c

def tx.head.space(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, t}:
      tx.is_space(c)

# Lengths -------------------------------------------------------------------

def tx.bytes.go(s: String, +n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{Chr{+c}, t}:
      tx.bytes.go(t, (n + tx.width8(c) : U32))

# Buffer.byteLength(text, "utf8")
def tx.bytes(s: String) -> U32:
  tx.bytes.go(s, 0)

def tx.units.go(s: String, +n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{Chr{+c}, t}:
      tx.units.go(t, (n + tx.width16(c) : U32))

# .length
def tx.units(s: String) -> U32:
  tx.units.go(s, 0)

# does s hold the scalar x
def tx.has(s: String, +x: U32) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, t}:
      Bool.or(U32.is_eq(c, x), tx.has(t, x))

# Building ------------------------------------------------------------------

# xs joined by sep (Array.join), built right to left
def tx.join.go(+sep: String, xs: List<&2, String>, h: String) -> String:
  match xs:
    case []:
      h
    case x <> t:
      String.append(h, String.append(sep, tx.join.go(sep, t, x)))

def tx.join(xs: List<&2, String>, +sep: String) -> String:
  match xs:
    case []:
      ""
    case h <> t:
      tx.join.go(sep, t, h)

def tx.concat(xs: List<&2, String>) -> String:
  tx.join(xs, "")

# String.prototype.repeat
def tx.repeat(+s: String, n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+k:
      String.append(s, tx.repeat(s, k))

# Flat ----------------------------------------------------------------------
#
# Memory.flat: text.replace(/\s*\n\s*/g, " "). A greedy \s* backtracks to the
# last newline of a run of spaces, so every maximal run of \s that holds a
# newline becomes one space, and a run with none stays.

# the pending run (reversed) onto the output (reversed)
def tx.flat.flush(run: String, nl: Bool, out: String) -> String:
  match nl:
    case True{}:
      SCon{Chr{32}, out}
    case False{}:
      String.append(run, out)

# s: the rest; sp: whether its head is \s; run: the run of \s so far
# (reversed), nl: whether it holds a newline; out: the output (reversed)
def tx.flat.go(s: String, sp: Bool, run: String, +nl: Bool, out: String) -> String:
  match s sp:
    case SNil{} _:
      String.reverse(tx.flat.flush(run, nl, out))
    case SCon{Chr{+c}, +t} True{}:
      tx.flat.go(t, tx.head.space(t), SCon{Chr{c}, run}, Bool.or(nl, U32.is_eq(c, 10)), out)
    case SCon{Chr{+c}, +t} False{}:
      tx.flat.go(t, tx.head.space(t), "", False{}, SCon{Chr{c}, tx.flat.flush(run, nl, out)})

def tx.flat.if(nl: Bool, +s: String) -> String:
  match nl:
    case True{}:
      tx.flat.go(s, tx.head.space(s), "", False{}, "")
    case False{}:
      s

# newlines (and the spaces around them) as one space each
def tx.flat(+s: String) -> String:
  tx.flat.if(tx.has(s, 10), s)

# Trim ----------------------------------------------------------------------

def tx.trim_start.go(s: String, sp: Bool) -> String:
  match s sp:
    case SNil{} _:
      SNil{}
    case SCon{h, +t} True{}:
      tx.trim_start.go(t, tx.head.space(t))
    case SCon{h, t} False{}:
      SCon{h, t}

def tx.trim_start(+s: String) -> String:
  tx.trim_start.go(s, tx.head.space(s))

# String.prototype.trim (JavaScript's whitespace)
def tx.trim(s: String) -> String:
  String.reverse(tx.trim_start(String.reverse(tx.trim_start(s))))

# Cut -----------------------------------------------------------------------

def tx.fits8(+s: String, +room: U32) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, t}:
      U32.is_le(tx.width8(c), room)

def tx.take8.go(s: String, fits: Bool, +room: U32, acc: String) -> String:
  match s fits:
    case SCon{Chr{+c}, +t} True{}:
      +r = (room - tx.width8(c) : U32)
      tx.take8.go(t, tx.fits8(t, r), r, SCon{Chr{c}, acc})
    case _ _:
      String.reverse(acc)

# the whole scalars within the first n bytes
def tx.take8(+s: String, +n: U32) -> String:
  tx.take8.go(s, tx.fits8(s, n), n, "")

def tx.drop_fffd.go(s: String, bad: Bool) -> String:
  match s bad:
    case SNil{} _:
      SNil{}
    case SCon{h, +t} True{}:
      tx.drop_fffd.go(t, U32.is_eq(tx.head(t), 65533))
    case SCon{h, t} False{}:
      SCon{h, t}

def tx.drop_fffd(+s: String) -> String:
  tx.drop_fffd.go(s, U32.is_eq(tx.head(s), 65533))

# Memory.cut: Buffer.from(text).subarray(0, n).toString().replace(/�+$/, "")
# (a scalar the cut splits decodes to U+FFFD, and every U+FFFD at the end goes)
def tx.cut(s: String, +n: U32) -> String:
  String.reverse(tx.drop_fffd(String.reverse(tx.take8(s, n))))

# Pages (Clip.ts) -----------------------------------------------------------
#
# CAP UTF-16 units a page. A page of a text from `at` ends CAP units on,
# after its last newline if it has one, else where a scalar ends.

def tx.cap() -> U32:
  30000

# The window walked: the page so far (reversed) and its units, the page up
# to and with its last newline (reversed) if any, and what follows.
type tx.Pg is Data:
  tx.Pg{page: String, units: U32, nl: Maybe<&2, String>, rest: String}

def tx.fits16(+s: String, +n: U32) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, t}:
      U32.is_le((n + tx.width16(c) : U32), tx.cap())

def tx.page.nl(+c: U32, +acc: String, +nl: Maybe<&2, String>) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, U32.is_eq(c, 10), Some{acc}, nl)

def tx.page.go(s: String, fits: Bool, +n: U32, acc: String, +nl: Maybe<&2, String>) -> tx.Pg:
  match s fits:
    case SCon{Chr{+c}, +t} True{}:
      +a = {SCon{Chr{c}, acc} : String}
      +m = (n + tx.width16(c) : U32)
      tx.page.go(t, tx.fits16(t, m), m, a, tx.page.nl(c, a, nl))
    case SNil{} _:
      tx.Pg{acc, n, nl, SNil{}}
    case SCon{h, t} False{}:
      tx.Pg{acc, n, nl, SCon{h, t}}

# the scalars of the window past its last newline (the first `d` of the
# reversed page), back in front of the rest
def tx.page.back(full: String, +d: Nat, rest: String) -> String:
  String.reverse.go(String.take(full, d), rest)

def tx.page.pick(whole: Bool, s: String, page: String, nl: Maybe<&2, String>, rest: String) -> String & String:
  match whole nl:
    case True{} _:
      (s, "")
    case False{} None{}:
      (String.reverse(page), rest)
    case False{} Some{+keep}:
      +full = page
      (String.reverse(keep), tx.page.back(full, Nat.sub(String.length(full), String.length(keep)), rest))

def tx.page.fin(+units: U32, s: String, pg: tx.Pg) -> String & String:
  match pg:
    case tx.Pg{page, n, nl, rest}:
      tx.page.pick(U32.is_le(units, tx.cap()), s, page, nl, rest)

# a text's first page and what follows it (Clip.ts clip_end)
def tx.page.cut(+s: String) -> String & String:
  tx.page.fin(tx.units(s), s, tx.page.go(s, tx.fits16(s, 0), 0, "", None{}))

# Clip.ts clip_pages: a text in pages (at least one: "" for "")
def tx.pages.go(fuel: Nat, p: String & String) -> List<&2, String>:
  match fuel p:
    case 0n Tuple{page, rest}:
      [page]
    case 1n+f Tuple{page, SNil{}}:
      [page]
    case 1n+f Tuple{page, SCon{h, t}}:
      page <> tx.pages.go(f, tx.page.cut(SCon{h, t}))

def tx.pages(+s: String) -> List<&2, String>:
  tx.pages.go(1n+U32.to_nat(tx.units(s)), tx.page.cut(s))

# whether UTF-16 unit `at` falls within s's first scalar
def tx.from.here(+s: String, +at: U32) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      U32.is_lt(at, tx.width16(c))

def tx.from.go(s: String, here: Bool, +at: U32) -> String:
  match s here:
    case SNil{} _:
      SNil{}
    case SCon{Chr{+c}, +t} True{}:
      Bool.pick(String, U32.is_eq(at, 0), SCon{Chr{c}, t}, SCon{Chr{65533}, t})
    case SCon{Chr{+c}, +t} False{}:
      +a = (at - tx.width16(c) : U32)
      tx.from.go(t, tx.from.here(t, a), a)

# the text from UTF-16 unit `at` on: a unit inside a pair starts it with the
# pair's lone low surrogate, as String.slice does, here U+FFFD (one unit too)
def tx.from(+s: String, +at: U32) -> String:
  tx.from.go(s, tx.from.here(s, at), at)

def tx.page.at.on(+at: U32, +end: U32, +len: U32, +page: String) -> String:
  Bool.pick(String, U32.is_lt(end, len),
    page ++ "\n[characters " ++ U32.show((at + 1 : U32)) ++ "-" ++ U32.show(end) ++ " of " ++ U32.show(len) ++ "; go on with at " ++ U32.show(end) ++ "]",
    page)

def tx.page.at.fin(+at: U32, +len: U32, p: String & String) -> String:
  match p:
    case (+page, rest):
      tx.page.at.on(at, (at + tx.units(page) : U32), len, page)

# Clip.ts clip_page: a text's page from `at`, and past it where to go on
def tx.page.at(+s: String, +at: U32) -> String:
  tx.page.at.fin(at, tx.units(s), tx.page.cut(tx.from(s, at)))
