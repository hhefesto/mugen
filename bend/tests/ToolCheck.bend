
import Base
import ../Sys.bend as S
import ../Text.bend as T
import ../Json.bend as J
import ../Ev.bend as E
import ../Tools.bend as L

# The goldens of tools/golden/tools.ts (UniiChat's own Machine.run on a
# sequence of jobs), run by Tools.bend on a work dir of their own and
# compared, a shell's time and the work dir masked: `toolcheck CASES.jsonl
# WORK` prints every mismatch, then PASS: n / m. Every def is prefixed `tc.`.

# the last line's time masked: "(exit 0 in 0.4 s)" as "(exit 0 in T s)"
def tc.time.go(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case []:
      []
    case [+l]:
      +p = L.tl.split(l, " in ")
      Bool.pick(List<&2, String>, Bool.and(String.starts_with(l, "("), U32.is_gt(U32.from_nat(List.length(&2, String, p)), 1)),
        [Maybe.default(&2, String, List.get(&2, String, p, 0n), "") ++ " in T s)"], [l])
    case l <> t:
      l <> tc.time.go(t)

def tc.mask(+work: String, +s: String) -> String:
  T.tx.join(tc.time.go(L.tl.split.lines(T.tx.join(L.tl.split(s, work), "<work>"))), "\n")

def tc.out.json(+work: String, o: E.ev.Out) -> String:
  match o:
    case E.ev.Out{+text, fail}:
      J.js.write(J.JObj{[J.JKv{"text", J.JStr{tc.mask(work, text)}}, J.JKv{"fail", J.JBool{fail}}]})

def tc.with.device(j: J.Json) -> J.Json:
  match j:
    case J.JObj{kvs}:
      J.JObj{J.JKv{"device", J.JStr{"dev"}} <> kvs}
    case x:
      x

def tc.case(+env: L.tl.Env, +work: String, +c: J.Json) -> IO(String):
  +job = Maybe.default(&2, J.Json, J.js.field(c, "job"), J.JNull{})
  +name = Maybe.default(&2, String, J.js.str(job, "name"), "")
  +want = J.js.write(Maybe.default(&2, J.Json, J.js.field(c, "out"), J.JNull{}))
  do IO<String>:
    o : E.ev.Out <- L.tl.kit.run(env, name, tc.with.device(Maybe.default(&2, J.Json, J.js.field(job, "input"), J.JNull{})))
    +got : String = tc.out.json(work, o)
    return Bool.pick(String, String.eq(got, want), "", name ++ " " ++ String.take(J.js.write(job), 160n) ++ "\n  want " ++ String.take(want, 400n) ++ "\n  got  " ++ String.take(got, 400n))

def tc.report(+why: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(why), IO.pure(Unit, Unit{}), IO.print("FAIL " ++ why))

def tc.loop(lines: List<&2, String>, +env: L.tl.Env, +work: String, +pass: Nat, +total: Nat) -> IO(Unit):
  match lines:
    case []:
      IO.print("PASS: " ++ Nat.show(pass) ++ " / " ++ Nat.show(total))
    case SNil{} <> rest:
      tc.loop(rest, env, work, pass, total)
    case l <> rest:
      do IO<Unit>:
        t0 : Nat <- IO.now()
        +why : String <- tc.case(env, work, Maybe.default(&2, J.Json, J.js.read(l), J.JNull{}))
        t1 : Nat <- IO.now()
        Unit <- IO.print_err("case " ++ Nat.show(total) ++ ": " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
        Unit <- tc.report(why)
        tc.loop(rest, env, work, Nat.add(pass, Bool.pick(Nat, String.is_empty(why), 1n, 0n)), 1n+total)

def tc.main(argv: List<String>) -> IO(Unit):
  match argv:
    case [p, path, +work]:
      +env = {L.tl.Env{"dev", work, "main", "/bin/sh", work ++ "/ctl", work ++ "/groups"} : L.tl.Env}
      do IO<Unit>:
        text : String <- S.mu.must(String, "read cases", S.mu.read_file(path))
        tc.loop(String.lines(text), env, work, 0n, 0n)
    case _:
      IO.die(Unit, 2, "usage: toolcheck CASES.jsonl WORK")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), argv => tc.main(argv))
