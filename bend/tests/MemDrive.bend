import Base
import ../Sys.bend as S
import ../Text.bend as T
import ../Json.bend as J
import ../Clock.bend as C
import ../IMap.bend as I
import ../Tree.bend as R
import ../View.bend as V
import ../Store.bend as St
import ../Memory.bend as M

# The Bend side of the differential test (tools/memdiff): Memory.bend runs
# steps [FROM, TO) of a stream (tools/memdiff/gen.ts) on DIR, printing the
# trace tools/memdiff/harness.ts prints running UniiChat's own Memory.ts,
# line for line (that file says what each line means):
#
#   memdrive DIR STREAM_DIR FROM TO > trace
#
# The compactor is the same fake (md.answer), its jobs finished oldest first
# as each step says. Run with TZ=UTC. Every def is prefixed `md.`.

# Hashes: FNV-1a over u32 units (a text's code points) -------------------------

def md.basis() -> U32:
  2166136261

def md.fu(+h: U32, +x: U32) -> U32:
  U32.mul(U32.xor(h, x), 16777619)

def md.fs(s: String, +h: U32) -> U32:
  match s:
    case SNil{}:
      h
    case SCon{Chr{+c}, t}:
      md.fs(t, md.fu(h, c))

def md.hparts(ps: List<&2, R.tr.P>, +h: U32) -> U32:
  match ps:
    case []:
      h
    case R.tr.P{+l, +i} <> t:
      md.hparts(t, md.fu(md.fu(h, l), i))

def md.mark(b: Bool) -> U32:
  match b:
    case True{}:
      77
    case False{}:
      85

def md.hblocks(bs: List<&2, V.vw.B>, +h: U32) -> U32:
  match bs:
    case []:
      h
    case V.vw.B{text, mark} <> t:
      md.hblocks(t, md.fs(text, md.fu(h, md.mark(mark))))

# The fake compactor ------------------------------------------------------------
#
# Try t of node (l,i), nh the hash of the note a retry adds (0 on the first):
# by a hash of (l,i), white space only (no line: the source is clipped),
# always too long (the shortest is kept), too long twice, or the source
# flattened and cut to 300 bytes.

def md.kind(+h: U32, +t: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(U32.mod(h, 13), 0), 0n,
    Bool.pick(Nat, U32.is_eq(U32.mod(h, 17), 0), 1n,
      Bool.pick(Nat, Bool.and(U32.is_eq(U32.mod(h, 7), 0), U32.is_le(t, 2)), 2n, 3n)))

def md.answer.of(k: Nat, +tag: String, +text: String, +t: U32) -> String:
  match k:
    case 0n:
      " \n\t "
    case 1n:
      "  " ++ tag ++ " " ++ T.tx.repeat("ζ", U32.to_nat((300 - 10 * t : U32))) ++ "\n"
    case 2n:
      tag ++ " " ++ T.tx.repeat("ζ", 280n)
    case _:
      "\n " ++ T.tx.cut(tag ++ ": " ++ T.tx.flat(text), 300) ++ " "

def md.answer(+l: U32, +i: U32, +text: String, +t: U32, +nh: U32) -> String:
  +h = md.fu(md.fu(md.basis(), l), i)
  +tag = "L" ++ U32.show(l) ++ "/" ++ U32.show(i) ++ " t" ++ U32.show(t) ++ " n" ++ U32.show(nh)
  md.answer.of(md.kind(h, t), tag, text, t)

# Memory.build's loop over the fake: each try's answer trimmed; none (white
# space) ends it, as does a line that fits or the TRIES-th; else the next try
# adds the note on the last line (Tree.bend tr.over). The shortest line is
# kept (the first of equals); none: the source flattened and cut.

def md.shorter(+a: String, b: Maybe<&2, String>) -> String:
  match b:
    case None{}:
      a
    case Some{+x}:
      Bool.pick(String, U32.is_lt(T.tx.bytes(a), T.tx.bytes(x)), a, x)

def md.best(b: Maybe<&2, String>, +text: String) -> String:
  match b:
    case None{}:
      T.tx.cut(T.tx.flat(text), R.tr.node())
    case Some{x}:
      x

# 0: no line; 1: a line to keep, the last; 2: a line too long, to try again
def md.verdict(+a: String, +t: U32) -> Nat:
  Bool.pick(Nat, String.is_empty(a), 0n, Bool.pick(Nat, Bool.or(U32.is_le(T.tx.bytes(a), R.tr.node()), U32.is_eq(t, 5)), 1n, 2n))

# try t answered a, judged v
def md.tries(n: Nat, v: Nat, +l: U32, +i: U32, +text: String, +t: U32, +a: String, +best: Maybe<&2, String>) -> String:
  match n v:
    case 0n _:
      md.best(best, text)
    case 1n+k 0n:
      md.best(best, text)
    case 1n+k 1n:
      md.shorter(a, best)
    case 1n+k _:
      +b2 = {Some{md.shorter(a, best)} : Maybe<&2, String>}
      +t2 = (t + 1 : U32)
      +a2 = T.tx.trim(md.answer(l, i, text, t2, U32.mod(md.fs(R.tr.over(a), md.basis()), 1000)))
      md.tries(k, md.verdict(a2, t2), l, i, text, t2, a2, b2)

def md.build(+l: U32, +i: U32, +text: String) -> String:
  +a = T.tx.trim(md.answer(l, i, text, 1, 0))
  md.tries(6n, md.verdict(a, 1), l, i, text, 1, a, None{})

# The trace ---------------------------------------------------------------------

def md.b(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def md.view(v: V.vw.V) -> String:
  match v:
    case V.vw.V{+ps, size, batch, high}:
      U32.show(size) ++ " " ++ md.b(batch) ++ " " ++ Nat.show(List.length(&2, R.tr.P, ps)) ++ " " ++ U32.show(md.hparts(ps, md.basis()))

def md.state(m: M.me.Mem) -> String:
  match m:
    case M.me.Mem{d, sy, jb, +c, o, n, v, s, r, b, nb, k, e}:
      "V " ++ U32.show(c) ++ " " ++ U32.show(o) ++ " " ++ md.view(v) ++ " " ++ md.view(s) ++ " " ++ Nat.show(I.im.size(V.vw.Node, n)) ++ " " ++ U32.show(nb) ++ " " ++ U32.show(M.me.first(r, c, 0n))

def md.say.jobs(js: List<&2, M.me.Job>) -> IO(Unit):
  match js:
    case []:
      IO.pure(Unit, Unit{})
    case M.me.Job{+l, +i, bs, text} <> t:
      do IO<Unit>:
        Unit <- IO.print("J " ++ U32.show(l) ++ " " ++ U32.show(i) ++ " " ++ U32.show(md.hblocks(bs, md.basis())) ++ " " ++ U32.show(T.tx.bytes(text)))
        md.say.jobs(t)

# The driver --------------------------------------------------------------------

# the memory and the jobs waiting to finish, oldest first
type md.S is Data:
  md.S{mem: M.me.Mem, fifo: List<&2, M.me.Job>}

def md.num(+j: J.Json, +k: String) -> Nat:
  Maybe.default(&2, Nat, J.js.num(j, k), 0n)

def md.nat(+s: String) -> U32:
  U32.from_nat(Maybe.default(&2, Nat, Nat.read(s), 0n))

def md.msg(+j: J.Json) -> M.me.Msg:
  M.me.Msg{Maybe.default(&2, String, J.js.str(j, "kind"), ""), Maybe.default(&2, String, J.js.str(j, "text"), ""), J.js.str(j, "line"), Maybe.default(&2, Bool, J.js.bool(j, "more"), False{})}

def md.w(+ws: List<&2, U32>, +k: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ws, k), 0)

# step k of the stream
def md.rec(+streams: String, +k: U32) -> IO(J.Json):
  do IO<J.Json>:
    +ws : List<&2, U32> <- S.mu.must(List<&2, U32>, "stream.idx", S.mu.slots(streams ++ "/stream.idx", U32.to_nat(k), 1))
    line : String <- S.mu.must(String, "stream.jsonl", S.mu.pread_text(streams ++ "/stream.jsonl", U32.to_nat(md.w(ws, 0n)), md.w(ws, 1n)))
    return Maybe.default(&2, J.Json, J.js.read(line), J.JNull{})

def md.loaded(+m: M.me.Mem) -> IO(md.S):
  do IO<md.S>:
    Unit <- IO.print("R")
    Unit <- IO.print(md.state(m))
    return md.S{m, []}

# the jobs a change started, after those waiting
def md.queue(fifo: List<&2, M.me.Job>, +m: M.me.Mem, +jobs: List<&2, M.me.Job>) -> IO(md.S):
  do IO<md.S>:
    Unit <- md.say.jobs(jobs)
    Unit <- IO.print(md.state(m))
    return md.S{m, List.append(&2, M.me.Job, fifo, jobs)}

def md.pushed(fifo: List<&2, M.me.Job>, r: M.me.Mem & (List<&2, St.st.Root> & List<&2, M.me.Job>)) -> IO(md.S):
  match r:
    case (m, (rs, jobs)):
      md.queue(fifo, m, jobs)

def md.after(rest: List<&2, M.me.Job>, r: M.me.Mem & List<&2, M.me.Job>) -> IO(md.S):
  match r:
    case (m, jobs):
      md.queue(rest, m, jobs)

# the oldest job finished: its line in
def md.done1(+day: U32, m: M.me.Mem, j: M.me.Job, rest: List<&2, M.me.Job>) -> IO(md.S):
  match j:
    case M.me.Job{+l, +i, bs, +text}:
      do IO<md.S>:
        Unit <- IO.print("D " ++ U32.show(l) ++ " " ++ U32.show(i))
        r : M.me.Mem & List<&2, M.me.Job> <- M.me.done.job(m, day, l, i, md.build(l, i, text))
        md.after(rest, r)

# up to d of the oldest jobs finished, one after another
def md.drain(d: Nat, +day: U32, s: md.S) -> IO(md.S):
  match d s:
    case 0n _:
      IO.pure(md.S, s)
    case 1n+e md.S{m, Nil{}}:
      IO.pure(md.S, md.S{m, []})
    case 1n+e md.S{m, j <> rest}:
      IO.bind(md.S, md.S, md.done1(day, m, j, rest), s2 => md.drain(e, day, s2))

def md.reads.go(z: List<&2, J.Json>, +date: Nat, +m: M.me.Mem, f: List<&2, M.me.Job>) -> IO(md.S):
  match z:
    case [J.JNum{+a}, J.JNum{+b}, J.JNum{+c}]:
      do IO<md.S>:
        w : U32 <- M.me.whole(m, 0)
        t : U32 <- M.me.turn(m)
        Unit <- IO.print("W " ++ U32.show(w) ++ " " ++ U32.show(t))
        zt : String <- M.me.zoom(m, md.nat(a), md.nat(b), md.nat(c))
        Unit <- IO.print("Z " ++ a ++ " " ++ b ++ " " ++ c ++ " " ++ U32.show(md.fs(zt, md.basis())))
        dt : String <- M.me.date(m, U32.from_nat(date))
        Unit <- IO.print("T " ++ Nat.show(date) ++ " " ++ dt)
        return md.S{m, f}
    case _:
      IO.pure(md.S, md.S{m, f})

# what the step reads back: whole, turn, a zoom, a date
def md.reads(+j: J.Json, s: md.S) -> IO(md.S):
  match s:
    case md.S{m, f}:
      md.reads.go(J.js.arr(j, "zoom"), md.num(j, "date"), m, f)

def md.reload(b: Bool, +dir: String, s: md.S) -> IO(md.S):
  match b:
    case True{}:
      IO.bind(M.me.Mem, md.S, M.me.load(dir, 0, 64), m => md.loaded(m))
    case False{}:
      IO.pure(md.S, s)

def md.step(+dir: String, +streams: String, +k: U32, s: md.S) -> IO(md.S):
  match s:
    case md.S{m, fifo}:
      do IO<md.S>:
        +j : J.Json <- md.rec(streams, k)
        +now : Nat = md.num(j, "now")
        tz : U32 <- S.mu.tzoff(now)
        +day : U32 = C.ck.local_day(now, tz)
        Unit <- IO.print("P " ++ U32.show(k))
        r : M.me.Mem & (List<&2, St.st.Root> & List<&2, M.me.Job>) <- M.me.push(m, now, day, [md.msg(j)])
        s1 : md.S <- md.pushed(fifo, r)
        s2 : md.S <- md.drain(md.num(j, "drain"), day, s1)
        s3 : md.S <- md.reads(j, s2)
        md.reload(Maybe.default(&2, Bool, J.js.bool(j, "reload"), False{}), dir, s3)

def md.steps(n: Nat, +dir: String, +streams: String, +k: U32, s: md.S) -> IO(md.S):
  match n:
    case 0n:
      IO.pure(md.S, s)
    case 1n+e:
      IO.bind(md.S, md.S, md.step(dir, streams, k, s), s2 => md.steps(e, dir, streams, (k + 1 : U32), s2))

def md.run(+dir: String, +streams: String, +from: U32, +to: U32) -> IO(Unit):
  do IO<Unit>:
    m : M.me.Mem <- M.me.load(dir, 0, 64)
    s : md.S <- md.loaded(m)
    s2 : md.S <- md.steps(U32.to_nat((to - from : U32)), dir, streams, from, s)
    return Unit{}

def md.main(argv: List<String>) -> IO(Unit):
  match argv:
    case [p, dir, streams, from, to]:
      md.run(dir, streams, md.nat(from), md.nat(to))
    case _:
      IO.die(Unit, 2, "usage: memdrive DIR STREAM_DIR FROM TO")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), argv => md.main(argv))
