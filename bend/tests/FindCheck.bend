
import Base
import ../Keys.bend as K
import ../Pretty.bend as P
import ../Screen.bend as Sc

# Searching the chat (Screen.bend, "Searching the chat"): where a text is found
# in a row, over a wrap, the case rule, the walk up and down the rows from the
# chat's end, where the view goes, the rows painted, and the keys. Prints a
# FAIL line a case that fails, then PASS: n / m.

type T is Data:
  T{name: String, got: String, want: String}

def bl(+b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

def idx(m: Maybe<&2, Nat>) -> String:
  match m:
    case Some{i}:
      Nat.show(i)
    case None{}:
      "none"

# a block of plain text, a line a row, at a width that wraps none of these
def blk(+id: U32, +text: String) -> Sc.sc.Blk:
  Sc.sc.blk.new(id, "", "unii", text, False{}, 0n, 200, "/home/x")

# the rows from the end of the first row whose plain text holds s: what a walk
# must give for it (rows bottom up), 0 none
def row.of(rs: List<&2, String>, +s: String, +r: U32) -> U32:
  match rs:
    case []:
      0
    case x <> t:
      Bool.pick(U32, String.contains(P.pp.clean(x), s), r, row.of(t, s, (r + 1 : U32)))

# the chat, newest first: three blocks with "needle" in the oldest and the newest
def chat() -> List<&2, Sc.sc.Blk>:
  [blk(3, "the newest needle"), blk(2, "nothing here"), blk(1, "the oldest needle")]

def walk(+up: Bool, +q: String, +ref: U32) -> String:
  U32.show(Sc.sc.fd.blks(chat(), False{}, up, q, Sc.sc.fd.cased(q), ref, 0, 0, 200, "/home/x", ""))

def all.rows() -> List<&2, String>:
  List.concat(&2, String, [Sc.sc.blk.rows(blk(3, "the newest needle")), Sc.sc.blk.rows(blk(2, "nothing here")), Sc.sc.blk.rows(blk(1, "the oldest needle"))])

def bottom.hit() -> U32:
  row.of(all.rows(), "newest needle", 1)

def top.hit() -> U32:
  row.of(all.rows(), "oldest needle", 1)

def cases() -> List<&2, T>:
  +hi = bottom.hit()
  +lo = top.hit()
  [T{"found", idx(Sc.sc.fd.idx.of("hello world", "world", 0n)), "6"},
   T{"found at the start", idx(Sc.sc.fd.idx.of("hello", "hel", 0n)), "0"},
   T{"not found", idx(Sc.sc.fd.idx.of("hello", "x", 0n)), "none"},
   T{"longer than the text", idx(Sc.sc.fd.idx.of("he", "hello", 0n)), "none"},
   T{"all lowercase: any case", bl(Sc.sc.fd.cased("needle")), "no"},
   T{"one capital: exact", bl(Sc.sc.fd.cased("Needle")), "yes"},
   T{"a row holds it", bl(Sc.sc.fd.hit("a needle here", "", "needle")), "yes"},
   T{"over the wrap", bl(Sc.sc.fd.hit("a long nee", "  dle", "nee dle")), "yes"},
   T{"wholly in the row below: not this one's", bl(Sc.sc.fd.hit("nothing", "needle", "needle")), "no"},
   T{"the walk up from the end: the newest", walk(True{}, "needle", 0), U32.show(hi)},
   T{"up from it: the oldest", walk(True{}, "needle", hi), U32.show(lo)},
   T{"up past the last: none", walk(True{}, "needle", lo), "0"},
   T{"down from the oldest: the newest", walk(False{}, "needle", lo), U32.show(hi)},
   T{"down past the first: none", walk(False{}, "needle", hi), "0"},
   T{"nowhere", walk(True{}, "absent", 0), "0"},
   T{"an exact case that is not there", walk(True{}, "NEEDLE", 0), "0"},
   T{"a match showing keeps the view", U32.show(Sc.sc.fd.place(15, 10, 30)), "10"},
   T{"on the pinned row it moves", U32.show(Sc.sc.fd.place(40, 10, 30)), "20"},
   T{"above the view: a third down", U32.show(Sc.sc.fd.place(100, 10, 30)), "80"},
   T{"near the end: never past it", U32.show(Sc.sc.fd.place(3, 50, 30)), "0"},
   T{"the current match painted", Sc.sc.fd.mark("a needle b", "a needle b", "needle", True{}), "a \u{1B}[30;43mneedle\u{1B}[39;49m b"},
   T{"the others reversed, every one", Sc.sc.fd.mark("x x", "x x", "x", False{}), "\u{1B}[7mx\u{1B}[27m \u{1B}[7mx\u{1B}[27m"},
   T{"the case shown is the row's", Sc.sc.fd.mark("A Needle", "a needle", "needle", False{}), "A \u{1B}[7mNeedle\u{1B}[27m"},
   T{"a row with no match keeps its colors", Sc.sc.fd.row.show("\u{1B}[31mred\u{1B}[0m", "x", False{}, False{}), "\u{1B}[31mred\u{1B}[0m"},
   T{"C-r begins", Nat.show(Sc.sc.fd.start(K.ky.Ctrl{114}, False{}, False{})), "1"},
   T{"C-r with messages waiting begins", Nat.show(Sc.sc.fd.start(K.ky.Ctrl{114}, False{}, True{})), "1"},
   T{"C-r in the history's search does not", Nat.show(Sc.sc.fd.start(K.ky.Ctrl{114}, True{}, False{})), "0"},
   T{"C-s begins", Nat.show(Sc.sc.fd.start(K.ky.Ctrl{115}, False{}, False{})), "2"},
   T{"C-s with messages waiting sends them", Nat.show(Sc.sc.fd.start(K.ky.Ctrl{115}, False{}, True{})), "0"},
   T{"in a search a character", Nat.show(Sc.sc.fd.key.k(K.ky.Char{97})), "1"},
   T{"in a search Backspace", Nat.show(Sc.sc.fd.key.k(K.ky.Back{})), "2"},
   T{"in a search C-r", Nat.show(Sc.sc.fd.key.k(K.ky.Ctrl{114})), "3"},
   T{"in a search C-s", Nat.show(Sc.sc.fd.key.k(K.ky.Ctrl{115})), "4"},
   T{"in a search Enter", Nat.show(Sc.sc.fd.key.k(K.ky.Enter{})), "5"},
   T{"in a search C-g", Nat.show(Sc.sc.fd.key.k(K.ky.Ctrl{103})), "6"},
   T{"in a search Esc", Nat.show(Sc.sc.fd.key.k(K.ky.Esc{})), "6"},
   T{"the mouse's moves go on", Nat.show(Sc.sc.fd.key.k(K.ky.Mouse{35, 1, 1, False{}})), "8"},
   T{"another key ends it", Nat.show(Sc.sc.fd.key.k(K.ky.Meta{112})), "0"}]

def run(ts: List<&2, T>, +ok: Nat, +all: Nat) -> IO(Unit):
  match ts:
    case []:
      IO.print("PASS: " ++ Nat.show(ok) ++ " / " ++ Nat.show(all))
    case T{+name, +got, +want} <> rest:
      +same = String.eq(got, want)
      do IO<Unit>:
        IO.print(Bool.pick(String, same, "", "FAIL " ++ name ++ ": got [" ++ got ++ "], want [" ++ want ++ "]"))
        run(rest, Bool.pick(Nat, same, Nat.add(ok, 1n), ok), Nat.add(all, 1n))

def main() -> IO(Unit):
  run(cases(), 0n, 0n)
