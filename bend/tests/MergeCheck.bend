import Base
import ../Sys.bend as S
import ../Json.bend as J
import ../IMap.bend as I
import ../Tree.bend as R
import ../View.bend as V

# The cases of tools/memdiff/merge.ts (random views merged by UniiChat's own
# Memory.merge), each merged by View.bend and compared as JSON text:
# `mergecheck CASES.jsonl` prints every mismatch, then PASS: n / m.
# Every def is prefixed `mc.`.

def mc.nat(j: J.Json) -> U32:
  match j:
    case J.JNum{s}:
      U32.from_nat(Maybe.default(&2, Nat, Nat.read(s), 0n))
    case _:
      0

def mc.parts(xs: List<&2, J.Json>) -> List<&2, R.tr.P>:
  match xs:
    case []:
      []
    case J.JArr{[l, i]} <> t:
      R.tr.P{mc.nat(l), mc.nat(i)} <> mc.parts(t)
    case x <> t:
      mc.parts(t)

def mc.nodes(xs: List<&2, J.Json>, acc: I.im.M<V.vw.Node>) -> I.im.M<V.vw.Node>:
  match xs:
    case []:
      acc
    case J.JArr{[s, n]} <> t:
      mc.nodes(t, I.im.set(V.vw.Node, acc, mc.nat(s), V.vw.Node{"", mc.nat(n)}))
    case x <> t:
      mc.nodes(t, acc)

def mc.json(ps: List<&2, R.tr.P>) -> List<&2, J.Json>:
  match ps:
    case []:
      []
    case R.tr.P{l, i} <> t:
      J.JArr{[J.js.u32(l), J.js.u32(i)]} <> mc.json(t)

def mc.le(a: R.tr.P, b: R.tr.P) -> Bool:
  match a b:
    case R.tr.P{+la, +ia} R.tr.P{+lb, ib}:
      Bool.or(U32.is_lt(la, lb), Bool.and(U32.is_eq(la, lb), U32.is_le(ia, ib)))

def mc.out(m: V.vw.Merged) -> String:
  match m:
    case V.vw.Merged{parts, size, gone}:
      J.js.write(J.JObj{[J.JKv{"parts", J.JArr{mc.json(parts)}}, J.JKv{"size", J.js.u32(size)}, J.JKv{"gone", J.JArr{mc.json(List.sort(~R.tr.P, ~mc.le, gone))}}]})

# one case: "" if it passes, else what went wrong
def mc.case.of(+c: J.Json) -> String:
  +nodes = mc.nodes(J.js.arr(c, "nodes"), I.im.new(V.vw.Node))
  +parts = mc.parts(J.js.arr(c, "parts"))
  +v = {V.vw.V{parts, V.vw.sizes(nodes, parts), False{}, U32.from_nat(Maybe.default(&2, Nat, J.js.num(c, "high"), 0n))} : V.vw.V}
  +got = mc.out(V.vw.merge(nodes, v))
  +want = J.js.write(Maybe.default(&2, J.Json, J.js.field(c, "out"), J.JNull{}))
  Bool.pick(String, String.eq(got, want), "", "\n  want " ++ String.take(want, 400n) ++ "\n  got  " ++ String.take(got, 400n))

def mc.case(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{+c}:
      mc.case.of(c)
    case None{}:
      "a line that is not JSON"

def mc.report(+why: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(why), IO.pure(Unit, Unit{}), IO.print("FAIL" ++ why))

def mc.loop(lines: List<&2, String>, +pass: Nat, +total: Nat) -> IO(Unit):
  match lines:
    case []:
      IO.print("PASS: " ++ Nat.show(pass) ++ " / " ++ Nat.show(total))
    case SNil{} <> rest:
      mc.loop(rest, pass, total)
    case l <> rest:
      +why = mc.case(J.js.read(l))
      do IO<Unit>:
        Unit <- mc.report(why)
        mc.loop(rest, Nat.add(pass, Bool.pick(Nat, String.is_empty(why), 1n, 0n)), 1n+total)

def main() -> IO(Unit):
  do IO<Unit>:
    argv : List<String> <- IO.args()
    path : String = Maybe.default(&1, String, List.get(&1, String, argv, 1n), "merge.jsonl")
    text : String <- S.mu.must(String, "read cases", S.mu.read_file(path))
    mc.loop(String.lines(text), 0n, 0n)
