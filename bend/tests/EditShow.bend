import Base
import ../Keys.bend as K
import ../Edit.bend as E

# a look at Edit's keys (not a check: for the eye)
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

def show(+tag: String, +e: E.ed.Ed) -> IO(Unit):
  +l = E.ed.lay(e, 10)
  IO.print(tag ++ ": [" ++ String.reverse(E.ed.pre(e)) ++ "|" ++ E.ed.post(e) ++ "] rows " ++ String.join(E.ed.lay.rows(l), "/") ++ " cursor " ++ U32.show(E.ed.lay.row(l)) ++ "," ++ U32.show(E.ed.lay.col(l)))

def main() -> IO(Unit):
  +e0 = E.ed.new(["older entry", "newest entry"])
  +e1 = keys(chars("hello world"), e0)
  +e2 = keys([K.ky.Meta{98}, K.ky.Ctrl{107}], e1)
  +e3 = keys([K.ky.Ctrl{121}, K.ky.Newline{}], e2)
  +e4 = keys(List.concat(&2, K.ky.Key, [chars("second line long enough"), [K.ky.Nav{1, 0}]]), e3)
  +e5 = keys([K.ky.Ctrl{97}, K.ky.Ctrl{102}, K.ky.Ctrl{102}, K.ky.Nav{2, 0}], e4)
  +e6 = keys([K.ky.Ctrl{117}], e5)
  +e7 = keys([K.ky.Ctrl{119}], e1)
  +p = E.ed.sent(e1)
  +h1 = keys([K.ky.Nav{1, 0}], p)
  +h2 = keys([K.ky.Nav{1, 0}, K.ky.Nav{1, 0}], p)
  +h3 = keys([K.ky.Nav{1, 0}, K.ky.Nav{1, 0}, K.ky.Nav{2, 0}, K.ky.Nav{2, 0}, K.ky.Nav{2, 0}], p)
  +s1 = keys(List.concat(&2, K.ky.Key, [[K.ky.Ctrl{114}], chars("old")]), p)
  +c1 = E.ed.complete(keys(chars("/mo"), e0))
  +c2 = E.ed.complete(keys(chars("/model s"), e0))
  do IO<Unit>:
    Unit <- show("typed", e1)
    Unit <- show("M-b C-k", e2)
    Unit <- show("C-y C-j", e3)
    Unit <- show("line 2, up", e4)
    Unit <- show("C-a C-f C-f down", e5)
    Unit <- show("C-u", e6)
    Unit <- show("C-w", e7)
    Unit <- show("sent", p)
    Unit <- show("up", h1)
    Unit <- show("up up", h2)
    Unit <- show("up up down down down", h3)
    Unit <- show("C-r old", s1)
    Unit <- show("tab /mo", c1)
    Unit <- show("tab /model s", c2)
    show("paste", E.ed.key(e0, K.ky.Paste{"a\r\nb\rc"}))
