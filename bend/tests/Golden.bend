
import Base
import ../Sys.bend as S
import ../Text.bend as T
import ../Json.bend as J
import ../Diff.bend as D

# The goldens of tools/golden/gen.ts (UniiChat's own Clip.ts, Memory.flat,
# cut and bytes, JSON.stringify and parse), each computed here and compared
# as JSON text: `golden CASES.jsonl` prints every mismatch, then PASS: n / m.

def g.code(+fn: String) -> Nat:
  Bool.pick(Nat, String.eq(fn, "flat"), 0n, Bool.pick(Nat, String.eq(fn, "cut"), 1n,
    Bool.pick(Nat, String.eq(fn, "bytes"), 2n, Bool.pick(Nat, String.eq(fn, "units"), 3n,
      Bool.pick(Nat, String.eq(fn, "trim"), 4n, Bool.pick(Nat, String.eq(fn, "pages"), 5n,
        Bool.pick(Nat, String.eq(fn, "stringify"), 6n, Bool.pick(Nat, String.eq(fn, "page_at"), 7n,
          Bool.pick(Nat, String.eq(fn, "reparse"), 8n, Bool.pick(Nat, String.eq(fn, "diff"), 9n, 10n))))))))))

def g.str(j: Maybe<&2, J.Json>) -> String:
  Maybe.default(&2, String, J.js.as_str(j), "")

def g.arg(+ins: List<&2, J.Json>, +k: Nat) -> Maybe<&2, J.Json>:
  List.get(&2, J.Json, ins, k)

def g.at(+ins: List<&2, J.Json>) -> U32:
  U32.from_nat(Maybe.default(&2, Nat, J.js.as_nat(g.arg(ins, 1n)), 0n))

def g.strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case []:
      []
    case x <> t:
      J.JStr{x} <> g.strs(t)

def g.reparse(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{j}:
      J.js.write(j)
    case None{}:
      "PARSE FAILED"

# a diff as what any shortest one shares: its lines dropped and added (the
# lines kept, an LCS, may differ where several tie: UniiChat's is Myers'
# linear-space search, ours the greedy one)
def g.changes.go(ls: List<&2, String>, +minus: Nat, +plus: Nat) -> String:
  match ls:
    case []:
      "-" ++ Nat.show(minus) ++ " +" ++ Nat.show(plus)
    case +l <> t:
      +m = Bool.and(String.starts_with(l, "-"), Bool.not(String.starts_with(l, "---")))
      +p = Bool.and(String.starts_with(l, "+"), Bool.not(String.starts_with(l, "+++")))
      g.changes.go(t, Nat.add(minus, Bool.pick(Nat, m, 1n, 0n)), Nat.add(plus, Bool.pick(Nat, p, 1n, 0n)))

def g.changes(+d: String) -> String:
  Bool.pick(String, String.ends_with(d, " is unchanged."), d, g.changes.go(String.lines(d), 0n, 0n))

def g.want(k: Nat, +out: J.Json) -> J.Json:
  match k:
    case 9n:
      J.JStr{g.changes(Maybe.default(&2, String, J.js.as_str(Some{out}), ""))}
    case _:
      out

def g.run(k: Nat, +ins: List<&2, J.Json>) -> J.Json:
  match k:
    case 0n:
      J.JStr{T.tx.flat(g.str(g.arg(ins, 0n)))}
    case 1n:
      J.JStr{T.tx.cut(g.str(g.arg(ins, 0n)), 512)}
    case 2n:
      J.js.u32(T.tx.bytes(g.str(g.arg(ins, 0n))))
    case 3n:
      J.js.u32(T.tx.units(g.str(g.arg(ins, 0n))))
    case 4n:
      J.JStr{T.tx.trim(g.str(g.arg(ins, 0n)))}
    case 5n:
      J.JArr{g.strs(T.tx.pages(g.str(g.arg(ins, 0n))))}
    case 6n:
      J.JStr{J.js.quote(g.str(g.arg(ins, 0n)))}
    case 7n:
      J.JStr{T.tx.page.at(g.str(g.arg(ins, 0n)), g.at(ins))}
    case 8n:
      J.JStr{g.reparse(J.js.read(g.str(g.arg(ins, 0n))))}
    case 9n:
      J.JStr{g.changes(D.df.diff("f.txt", g.str(g.arg(ins, 0n)), g.str(g.arg(ins, 1n))))}
    case _:
      J.JStr{"unknown fn"}

# one case: "" if it passes, else what went wrong
def g.case.of(+c: J.Json) -> String:
  +fn = Maybe.default(&2, String, J.js.str(c, "fn"), "")
  +got = J.js.write(g.run(g.code(fn), J.js.arr(c, "in")))
  +want = J.js.write(g.want(g.code(fn), Maybe.default(&2, J.Json, J.js.field(c, "out"), J.JNull{})))
  Bool.pick(String, String.eq(got, want), "",
    fn ++ " " ++ String.take(J.js.write(J.JArr{J.js.arr(c, "in")}), 120n) ++ "\n  want " ++ String.take(want, 300n) ++ "\n  got  " ++ String.take(got, 300n))

def g.case(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{+c}:
      g.case.of(c)
    case None{}:
      "a line that is not JSON"

def g.report(+why: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(why), IO.pure(Unit, Unit{}), IO.print("FAIL " ++ why))

def g.loop(lines: List<&2, String>, +pass: Nat, +total: Nat) -> IO(Unit):
  match lines:
    case []:
      IO.print("PASS: " ++ Nat.show(pass) ++ " / " ++ Nat.show(total))
    case SNil{} <> rest:
      g.loop(rest, pass, total)
    case l <> rest:
      +why = g.case(J.js.read(l))
      do IO<Unit>:
        Unit <- g.report(why)
        g.loop(rest, Nat.add(pass, Bool.pick(Nat, String.is_empty(why), 1n, 0n)), 1n+total)

def main() -> IO(Unit):
  do IO<Unit>:
    argv : List<String> <- IO.args()
    path : String = Maybe.default(&1, String, List.get(&1, String, argv, 1n), "cases.jsonl")
    text : String <- S.mu.must(String, "read cases", S.mu.read_file(path))
    g.loop(String.lines(text), 0n, 0n)
