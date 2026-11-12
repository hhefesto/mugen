import Base
import ../Keys.bend as K
import ../Edit.bend as E

# The input's emacs keys (2026-11-12): the mark and the region (C-SPC, C-w,
# M-w, C-x C-x, C-x h, C-g), the kills (C-k twice is one kill, C-y, M-y), undo
# and redo (C-/, C-?), C-t, M-u, M-l, M-c, M-< and M->, and the keys as a
# terminal sends them (NUL, 31, CSI u). Prints `ok NAME` or `MISMATCH NAME:
# what it was`.

def keys(ks: List<&2, K.ky.Key>, +e: E.ed.Ed) -> E.ed.Ed:
  match ks:
    case []:
      e
    case +k <> t:
      keys(t, E.ed.key(e, k))

def chars(s: String) -> List<&2, K.ky.Key>:
  match s:
    case SNil{}:
      []
    case SCon{Chr{+c}, t}:
      K.ky.Char{c} <> chars(t)

# the text with a | at the cursor
def at(+e: E.ed.Ed) -> String:
  String.reverse(E.ed.pre(e)) ++ "|" ++ E.ed.post(e)

def ck(+name: String, +got: String, +want: String) -> String:
  Bool.pick(String, String.eq(got, want), "ok " ++ name, "MISMATCH " ++ name ++ ": " ++ got)

def typed(+s: String) -> E.ed.Ed:
  keys(chars(s), E.ed.new([]))

def c(+k: U32) -> K.ky.Key:
  K.ky.Ctrl{k}

def m(+k: U32) -> K.ky.Key:
  K.ky.Meta{k}

def key.name(ks: List<&2, K.ky.Key>) -> String:
  match ks:
    case K.ky.Ctrl{+k} <> rest:
      "C-" ++ U32.show(k)
    case K.ky.Meta{+k} <> rest:
      "M-" ++ U32.show(k)
    case _:
      "other"

def keys1(+s: String) -> String:
  key.name(K.ky.out.keys(K.ky.feed(K.ky.start(), s)))

# (each group its own def: one main with every case went past the native
# compiler's arity of 247)

# the region
def region() -> List<&2, String>:
  +e1 = typed("hello brave world")
  # C-a, C-f x6, C-SPC, M-f: the region "brave"; C-w cuts it, C-e C-y puts it back at the end
  +r1 = keys([c(97), c(102), c(102), c(102), c(102), c(102), c(102), c(64), m(102)], e1)
  +w1 = keys([c(119)], r1)
  +y1 = keys([c(101), c(121)], w1)
  # M-w copies (the text as it was, the region off); C-e C-y yanks the copy
  +mw = keys([m(119), c(101), c(121)], r1)
  [ck("C-SPC M-f: the region", E.ed.region.text(r1), "brave"),
   ck("C-w cuts the region", at(w1), "hello | world"),
   ck("C-y yanks it", at(y1), "hello  worldbrave|"),
   ck("M-w copies it", at(mw), "hello brave worldbrave|"),
   ck("M-w sets the mark off", Bool.pick(String, E.ed.region.on(keys([m(119)], r1)), "on", "off"), "off")]

# the kills
def kills() -> List<&2, String>:
  # two C-k after C-a: one kill (the line and its newline); C-y gives both back
  +l2 = typed("one\ntwo")
  +k2 = keys([K.ky.Nav{1, 0}, c(97), c(107), c(107)], l2)
  +ky2 = keys([c(121)], k2)
  # two C-w in a row are one kill; after a move, a new one: M-y after C-y gives the kill before it
  +q1 = keys([c(119), c(119)], typed("aa bb"))
  +p0 = typed("aa bb")
  +p1 = keys([c(119), c(98), c(119), c(101), c(121)], p0)
  +p2 = keys([m(121)], p1)
  [ck("C-k twice is one kill", at(ky2), "one\n|two"),
   ck("C-k C-k cut", E.ed.cutted(k2), "one\n"),
   ck("C-w twice is one kill", E.ed.cutted(q1), "aa bb"),
   ck("C-y", at(p1), " aa|"),
   ck("M-y the kill before", at(p2), " bb|")]

# undo, and the rest
def more() -> List<&2, String>:
  # undo: a word typed is one change; redo brings it back
  +u0 = typed("one two")
  +u1 = keys([c(95)], u0)
  +u2 = keys([c(95)], u1)
  +u3 = keys([c(63)], u2)
  # C-t, M-u, M-l, M-c
  +t1 = keys([c(98), c(116)], typed("ab"))
  +t2 = keys([c(97), c(102), c(116)], typed("abc"))
  +cs = keys([c(97), m(117), m(108), m(99)], typed("one TWO three"))
  # C-x C-x, C-x h, C-g
  +x1 = keys([c(97), c(64), c(101), c(120), c(120)], typed("abc"))
  +xh = keys([c(120), K.ky.Char{104}, c(119)], typed("all of it"))
  +g1 = keys([c(64), c(98), c(103), c(119)], typed("ab cd"))
  # M-< and M->
  +b1 = keys([m(60)], typed("x\ny"))
  +b2 = keys([m(62)], b1)
  [ck("undo a word", at(u1), "one|"),
   ck("undo again", at(u2), "|"),
   ck("redo", at(u3), "one|"),
   ck("C-t at a line's end", at(t1), "ba|"),
   ck("C-t", at(t2), "ba|c"),
   ck("M-u M-l M-c", at(cs), "ONE two Three|"),
   ck("C-x C-x", at(x1) ++ " " ++ Bool.pick(String, E.ed.region.on(x1), "on", "off"), "|abc on"),
   ck("C-x h C-w", at(xh), "|"),
   ck("C-g: the mark off (C-w then cuts a word)", at(g1), "ab |d"),
   ck("M-<", at(b1), "|x\ny"),
   ck("M->", at(b2), "x\ny|")]

# the keys as terminals send them
def sent() -> List<&2, String>:
  [ck("NUL is C-SPC", keys1("\u{0}"), "C-64"),
   ck("31 is C-/", keys1("\u{1F}"), "C-95"),
   ck("CSI 32;5u is C-SPC", keys1("\u{1B}[32;5u"), "C-64"),
   ck("CSI 47;5u is C-/", keys1("\u{1B}[47;5u"), "C-95"),
   ck("CSI 47;6u is C-?", keys1("\u{1B}[47;6u"), "C-63"),
   ck("ESC 31 is C-M-_", keys1("\u{1B}\u{1F}"), "M-31")]

def main() -> IO(Unit):
  IO.print(String.join(List.concat(&2, String, [region(), kills(), more(), sent()]), "\n"))
