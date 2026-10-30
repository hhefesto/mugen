
import Base
import ../Keys.bend as K
import ../Edit.bend as E
import ../Help.bend as H
import ../Screen.bend as Sc

# /help names everything: each command Tab completes (Edit.bend ed.words,
# its first word), and each key the screen takes (Screen.bend sc.key.k, any
# answer but 0, an edit, and 17, nothing), found in Help.bend's pages as
# `NAME`. The keys tried: C- and M- with every printable character, the
# arrows and Home, End, PgUp, PgDn (alone and with Alt), and Enter, Tab,
# Shift-Tab, Esc, Backspace, on an empty input and not, with messages
# waiting and tabs shown. Then the pages themselves. Prints a FAIL line a
# case that fails, then PASS: n / m.

type T is Data:
  T{name: String, got: String, want: String}

# a key and its name as the help says it (with Alt, Home, End, PgUp, PgDn
# are the keys alone)
type N is Data:
  N{name: String, key: K.ky.Key}

def nk.name(n: N) -> String:
  match n:
    case N{s, k}:
      s

def nk.key(n: N) -> K.ky.Key:
  match n:
    case N{s, k}:
      k

def chr(+c: U32) -> String:
  SCon{Chr{c}, ""}

def range(n: Nat, +lo: U32) -> List<&2, U32>:
  match n:
    case 0n:
      []
    case 1n+p:
      lo <> range(p, (lo + 1 : U32))

# M-1 to M-9 are one key of the help's ("M-1 to M-5", the box's numbers)
def meta.name(+c: U32) -> String:
  Bool.pick(String, Bool.and(U32.is_ge(c, 49), U32.is_le(c, 57)), "M-1", "M-" ++ chr(c))

def metas(cs: List<&2, U32>) -> List<&2, N>:
  match cs:
    case []:
      []
    case +c <> rest:
      N{meta.name(c), K.ky.Meta{c}} <> metas(rest)

def ctrls(cs: List<&2, U32>) -> List<&2, N>:
  match cs:
    case []:
      []
    case +c <> rest:
      N{"C-" ++ chr(c), K.ky.Ctrl{c}} <> ctrls(rest)

def navs() -> List<&2, N>:
  [N{"\u{2191}", K.ky.Nav{1, 0}}, N{"\u{2193}", K.ky.Nav{2, 0}}, N{"\u{2192}", K.ky.Nav{3, 0}}, N{"\u{2190}", K.ky.Nav{4, 0}},
   N{"Home", K.ky.Nav{5, 0}}, N{"End", K.ky.Nav{6, 0}}, N{"PgUp", K.ky.Nav{7, 0}}, N{"PgDn", K.ky.Nav{8, 0}},
   N{"M-\u{2191}", K.ky.Nav{1, 2}}, N{"M-\u{2193}", K.ky.Nav{2, 2}}, N{"M-\u{2192}", K.ky.Nav{3, 2}}, N{"M-\u{2190}", K.ky.Nav{4, 2}},
   N{"Home", K.ky.Nav{5, 2}}, N{"End", K.ky.Nav{6, 2}}, N{"PgUp", K.ky.Nav{7, 2}}, N{"PgDn", K.ky.Nav{8, 2}},
   N{"Enter", K.ky.Enter{}}, N{"Alt-Enter", K.ky.Newline{}}, N{"Tab", K.ky.Tab{}}, N{"Shift-Tab", K.ky.BackTab{}}, N{"Esc", K.ky.Esc{}},
   N{"Backspace", K.ky.Back{}}, N{"M-Backspace", K.ky.MetaBack{}}]

def keys() -> List<&2, N>:
  List.concat(&2, N, [metas(range(94n, 33)), ctrls(range(26n, 97)), navs()])

# what the screen does with it: empty, an empty input
def act(+k: K.ky.Key, +empty: Bool) -> Nat:
  Sc.sc.key.k(k, False{}, empty, True{}, True{})

def taken(+a: Nat) -> Bool:
  Bool.not(Bool.or(Nat.is_eq(a, 0n), Nat.is_eq(a, 17n)))

def elem(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case []:
      False{}
    case +y <> rest:
      Bool.or(String.eq(x, y), elem(rest, x))

def has(+text: String, +name: String) -> Bool:
  String.contains(text, "`" ++ name)

def pages() -> String:
  H.hl.index() ++ "\n\n" ++ H.hl.all()

def key.cases(ns: List<&2, N>, +text: String) -> List<&2, T>:
  match ns:
    case []:
      []
    case +n <> rest:
      +k = nk.key(n)
      +s = nk.name(n)
      +on = Bool.or(taken(act(k, True{})), taken(act(k, False{})))
      +ok = Bool.or(Bool.not(on), has(text, s))
      List.append(&2, T, Bool.pick(List<&2, T>, on, [T{"key " ++ s ++ " (" ++ Nat.show(act(k, True{})) ++ "/" ++ Nat.show(act(k, False{})) ++ ") is in the help", Bool.pick(String, ok, "yes", "no"), "yes"}], []), key.cases(rest, text))

def first.word(+w: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, String.split(w, ' '), 0n), w)

def cmd.cases(ws: List<&2, String>, +text: String) -> List<&2, T>:
  match ws:
    case []:
      []
    case +w <> rest:
      +c = first.word(w)
      T{"command " ++ w ++ " is in the commands page", Bool.pick(String, has(text, c), "yes", "no"), "yes"} <> cmd.cases(rest, text)

def topic.cases(ts: List<&2, H.hl.Topic>) -> List<&2, T>:
  match ts:
    case []:
      []
    case +t <> rest:
      +n = H.hl.topic.name(t)
      +x = H.hl.topic.text(t)
      List.append(&2, T, [T{"topic " ++ n ++ " in the index", Bool.pick(String, has(H.hl.index(), n ++ "`"), "yes", "no"), "yes"},
        T{"topic " ++ n ++ " is a page", Bool.pick(String, Bool.and(String.starts_with(x, "## "), String.eq(H.hl.page(n), x)), "yes", "no"), "yes"},
        T{"/help all has topic " ++ n, Bool.pick(String, String.contains(H.hl.page("all"), x), "yes", "no"), "yes"},
        T{"Tab completes /help " ++ n, Bool.pick(String, elem(E.ed.words(), "/help " ++ n), "yes", "no"), "yes"}], topic.cases(rest))

def cases() -> List<&2, T>:
  +text = pages()
  +cmds = H.hl.page("commands")
  List.concat(&2, T, [key.cases(keys(), text), cmd.cases(E.ed.words(), cmds), topic.cases(H.hl.topics()),
    [T{"/help alone: the index", Bool.pick(String, String.eq(H.hl.page("  "), H.hl.index()), "yes", "no"), "yes"},
     T{"/help of no topic", Bool.pick(String, String.starts_with(H.hl.page("nope"), "No help topic `nope`"), "yes", "no"), "yes"},
     T{"nine topics", Nat.show(List.length(&2, H.hl.Topic, H.hl.topics())), "9"}]])

def run(ts: List<&2, T>, +pass: Nat, +n: Nat) -> IO(Unit):
  match ts:
    case []:
      IO.print("PASS: " ++ Nat.show(pass) ++ " / " ++ Nat.show(n))
    case +t <> rest:
      match t:
        case T{+name, +got, +want}:
          +ok = String.eq(got, want)
          do IO<Unit>:
            Unit <- Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.print("FAIL " ++ name ++ "\n  got:  " ++ got ++ "\n  want: " ++ want))
            run(rest, Nat.add(pass, Bool.pick(Nat, ok, 1n, 0n)), Nat.add(n, 1n))

def main() -> IO(Unit):
  run(cases(), 0n, 0n)
