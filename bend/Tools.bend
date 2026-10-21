
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./Diff.bend as D
import ./Ev.bend as E

# Tools: what Unii's calls may run, as UniiChat's Tools.ts and Machine.ts
# define them, word for word, but all on this computer: the device the
# prompts speak of is this one, named by its host. The hub's own (zoom, date,
# spawn, tell) it answers itself (Hub.bend); these run in the caller's
# computation: shell, read, write, edit, each in its agent's dir under the
# work dir.
#
# A shell job runs in a process group of its own (sh's job control), its
# output piped to a file, so the call waits until all that holds its output
# ends, a stop kills the whole group, and output of any size is read back as
# its head and tail. Each group is listed in run/groups, which mugen kills
# as it quits (no background job outlives it).
#
# Every def is prefixed `tl.` (a program's defs share one namespace).

def tl.cap() -> U32:
  30000

# Specs ---------------------------------------------------------------------

def tl.obj(kvs: List<&2, J.JKv>) -> J.Json:
  J.JObj{kvs}

def tl.ty(+t: String) -> J.Json:
  J.JObj{[J.JKv{"type", J.JStr{t}}]}

def tl.strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case []:
      []
    case x <> t:
      J.JStr{x} <> tl.strs(t)

# a tool whose input is an object of these fields, `need` required (Machine.ts
# spec), as the API takes it
def tl.spec(+name: String, +info: String, props: List<&2, J.JKv>, need: List<&2, String>) -> J.Json:
  J.JObj{[J.JKv{"name", J.JStr{name}}, J.JKv{"description", J.JStr{info}},
    J.JKv{"input_schema", J.JObj{[J.JKv{"type", J.JStr{"object"}}, J.JKv{"properties", J.JObj{props}}, J.JKv{"required", J.JArr{tl.strs(need)}}]}}]}

def tl.efforts() -> List<&2, String>:
  ["low", "medium", "high", "xhigh", "max"]

# everyone's (OWN)
def tl.own() -> List<&2, J.Json>:
  [tl.spec("zoom", "Open the line id+n of the view into the two lines of n/2 under it; n = 1 gives the message whole. With an agent's name as id, give that agent's whole chat. A long text comes in pages from character at, saying where to go on.",
      [J.JKv{"id", J.JObj{[J.JKv{"type", J.JArr{[J.JStr{"integer"}, J.JStr{"string"}]}}]}}, J.JKv{"n", tl.ty("integer")}, J.JKv{"at", tl.ty("integer")}], ["id"]),
    tl.spec("date", "The date and time of message id.", [J.JKv{"id", tl.ty("integer")}], ["id"])]

# the master's (BOSS)
def tl.boss() -> List<&2, J.Json>:
  [tl.spec("spawn", "Start one subagent per task, in parallel, and return their names at once. Each one's report reaches you as a message \"[Name] report\" when it finishes. A subagent sees the view and the user's instructions, but knows what you want only from its task.",
      [J.JKv{"tasks", J.JObj{[J.JKv{"type", J.JStr{"array"}}, J.JKv{"items", tl.ty("string")}]}},
        J.JKv{"effort", J.JObj{[J.JKv{"type", J.JStr{"string"}}, J.JKv{"enum", J.JArr{tl.strs(tl.efforts())}}, J.JKv{"description", J.JStr{"How hard they think; by default, as hard as you."}}]}}], ["tasks"]),
    tl.spec("tell", "Send a message to an agent (a subagent or a computer task), by name. One at work reads it between its tool calls, and its report answers it; an idle one goes on from its chat, and its reply reaches you as a message \"[Name] reply\".",
      [J.JKv{"name", tl.ty("string")}, J.JKv{"message", tl.ty("string")}], ["name", "message"])]

def tl.device() -> J.JKv:
  J.JKv{"device", J.JObj{[J.JKv{"type", J.JStr{"string"}}, J.JKv{"description", J.JStr{"The name of the device to run on, one listed under Devices."}}]}}

def tl.edit.item() -> J.Json:
  J.JObj{[J.JKv{"type", J.JStr{"object"}}, J.JKv{"properties", J.JObj{[J.JKv{"path", tl.ty("string")}, J.JKv{"old", tl.ty("string")}, J.JKv{"new", tl.ty("string")}, J.JKv{"all", tl.ty("boolean")}]}},
    J.JKv{"required", J.JArr{tl.strs(["path", "old", "new"])}}]}

# the tools that touch the device (Machine.ts TOOLS), for `who`'s dir (kit)
def tl.kit(+who: String) -> List<&2, J.Json>:
  +on = " It runs on the device named, in <work>/" ++ who ++ ", <work> being the work dir Devices lists for it."
  +cap = U32.show(tl.cap())
  [tl.spec("shell", "Run a command with the device's shell ($SHELL -c), stdout and stderr together, and return its output, then its exit code and time, as (exit 0 in 0.4 s); output past " ++ cap ++ " characters keeps its head and tail. Each call is a new shell. The call waits until the command and everything holding its output end, so give background jobs their own output file. Background jobs live only while unii is open on the device: closing it kills every process the calls started." ++ on,
      [tl.device(), J.JKv{"command", tl.ty("string")}], ["device", "command"]),
    tl.spec("read", "Read a text file. offset: the first line to show (from 1); limit: how many lines; at: the character of the first line to start from. It ends saying the lines shown, as [lines 4-7 of 15]; output past " ++ cap ++ " characters comes in pages, saying where to go on." ++ on,
      [tl.device(), J.JKv{"path", tl.ty("string")}, J.JKv{"offset", tl.ty("integer")}, J.JKv{"limit", tl.ty("integer")}, J.JKv{"at", tl.ty("integer")}], ["device", "path"]),
    tl.spec("write", "Write a whole file, making its directories. Answers a unified diff of what changed (a new file: all its lines added)." ++ on,
      [tl.device(), J.JKv{"path", tl.ty("string")}, J.JKv{"content", tl.ty("string")}], ["device", "path", "content"]),
    tl.spec("edit", "Replace text in files: the edits in order, each on its file as the edits before it left it. old must match exactly, whitespace included, and only once, unless all is true, which replaces every match. If any edit fails, no file is changed. Answers a unified diff of each file." ++ on,
      [tl.device(), J.JKv{"edits", J.JObj{[J.JKv{"type", J.JStr{"array"}}, J.JKv{"items", tl.edit.item()}, J.JKv{"minItems", J.JNum{"1"}}]}}], ["device", "edits"])]

# Unii's tools: OWN, BOSS, the kit (UniiChat's computer tasks come later)
def tl.main() -> List<&2, J.Json>:
  List.concat(&2, J.Json, [tl.own(), tl.boss(), tl.kit("main")])

# a subagent's: OWN and the kit
def tl.sub(+who: String) -> List<&2, J.Json>:
  List.append(&2, J.Json, tl.own(), tl.kit(who))

# Running ---------------------------------------------------------------------
#
# Where a tool runs: this device's name, the work dir, the caller (its dir
# is work/who), the user's shell, the caller's control files' prefix
# (run/<who>: .pid the process to stop, .stop set by a stop), the list of
# shell groups (run/groups).

type tl.Env is Data:
  tl.Env{host: String, work: String, who: String, shell: String, ctl: String, groups: String}

def tl.fail(+text: String) -> E.ev.Out:
  E.ev.Out{text, True{}}

def tl.ok(+text: String) -> E.ev.Out:
  E.ev.Out{text, False{}}

def tl.s.of(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{J.JStr{s}}:
      s
    case Some{J.JNum{n}}:
      n
    case Some{J.JBool{True{}}}:
      "true"
    case Some{J.JBool{False{}}}:
      "false"
    case Some{J.JNull{}}:
      "null"
    case Some{x}:
      J.js.write(x)
    case None{}:
      "undefined"

# a field as String(x) shows it
def tl.s(+j: J.Json, +k: String) -> String:
  tl.s.of(J.js.field(j, k))

def tl.n.of(m: Maybe<&2, Nat>, +d: U32) -> U32:
  match m:
    case Some{n}:
      U32.from_nat(n)
    case None{}:
      d

def tl.n(+j: J.Json, +k: String, +d: U32) -> U32:
  tl.n.of(J.js.num(j, k), d)

# a path as Node's path.resolve(cwd, p) finds it: absolute as is, else under cwd
def tl.path(+cwd: String, +p: String) -> String:
  Bool.pick(String, String.starts_with(p, "/"), p, cwd ++ "/" ++ p)

# a reversed path past its last name: from its last "/" back
def tl.dir.go(r: String) -> String:
  match r:
    case SNil{}:
      "."
    case SCon{Chr{47}, t}:
      String.reverse(SCon{Chr{47}, t})
    case SCon{c, t}:
      tl.dir.go(t)

# path.dirname, roughly: the path to its last "/" ("." if none)
def tl.dir.of(+p: String) -> String:
  tl.dir.go(String.reverse(p))

# Clip.ts clip(): past CAP units, the head's 15000 and the tail's 14936, the
# number cut between them; a pair split at a cut is U+FFFD
# what the next scalar of s does to a take of n more units: 0 none left (or
# no room: stop), 1 half a pair fits (U+FFFD, then stop), 2 it fits
def tl.take16.v(+s: String, +n: U32) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, U32.is_eq(n, 0), 0n, Bool.pick(Nat, U32.is_gt(T.tx.width16(c), n), 1n, 2n))

def tl.take16.go(s: String, v: Nat, +n: U32, acc: String) -> String:
  match s v:
    case SCon{Chr{+c}, +t} 2n:
      +m = (n - T.tx.width16(c) : U32)
      tl.take16.go(t, tl.take16.v(t, m), m, SCon{Chr{c}, acc})
    case _ 1n:
      String.reverse(SCon{Chr{65533}, acc})
    case _ _:
      String.reverse(acc)

def tl.take16(+s: String, +n: U32) -> String:
  tl.take16.go(s, tl.take16.v(s, n), n, "")

def tl.clip.go(short: Bool, +s: String, +u: U32) -> String:
  match short:
    case True{}:
      s
    case False{}:
      tl.take16(s, 15000) ++ "\n[... " ++ U32.show(((u - 15000 : U32) - 14936 : U32)) ++ " characters cut ...]\n" ++ T.tx.from(s, (u - 14936 : U32))

def tl.clip(+s: String) -> String:
  +u = T.tx.units(s)
  tl.clip.go(U32.is_le(u, tl.cap()), s, u)

# the last newline gone (text.replace(/\n$/, ""))
def tl.chomp(+s: String) -> String:
  Bool.pick(String, String.ends_with(s, "\n"), String.reverse(String.drop(String.reverse(s), 1n)), s)

# Shell ---------------------------------------------------------------------

# $1 the pid file, $2 the dir, $3 the shell, $4 the command, $5 the output,
# $6 the exit code's file, $7 the list of groups: the job, a pipeline in a
# group of its own (set -m) led by an sh that names it, runs $SHELL -c on
# "exec 2>&1" and the command, and keeps its status; cat takes the output
# till all that holds it ends
def tl.shell.script() -> String:
  "set -m\ncd \"$2\" || exit 125\nsh -c 'echo $$ > \"$1\"; echo $$ >> \"$5\"; \"$2\" -c \"exec 2>&1\n$3\" < /dev/null; echo $? > \"$4\"' sh \"$1\" \"$3\" \"$4\" \"$6\" \"$7\" 2>&1 | cat > \"$5\" &\nwait $!"

def tl.text.of(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{s}:
      s
    case Fail{e}:
      ""

# the output, clipped: whole, or its head and tail read from the file
def tl.out.read(small: Bool, +file: String, +units: Nat, +size: Nat) -> IO(String):
  match small:
    case True{}:
      IO.bind(Result<&1, &1, U32 & String, String>, String, S.mu.read_file(file), r => IO.pure(String, tl.text.of(r)))
    case False{}:
      do IO<String>:
        h : Result<&1, &1, U32 & String, String> <- S.mu.pread_text(file, 0n, 60000)
        t : Result<&1, &1, U32 & String, String> <- S.mu.pread_text(file, Nat.sub(size, 60000n), 60000)
        +tail : String = tl.text.of(t)
        return tl.take16(tl.text.of(h), 15000) ++ "\n[... " ++ Nat.show(Nat.sub(Nat.sub(units, 15000n), 14936n)) ++ " characters cut ...]\n" ++ T.tx.from(tail, (T.tx.units(tail) - 14936 : U32))

def tl.nat.of(r: Result<&1, &1, U32 & String, Nat>) -> Nat:
  match r:
    case Done{n}:
      n
    case Fail{e}:
      0n

# the time, as toFixed(1) seconds
def tl.secs(+ms: Nat) -> String:
  +t = Nat.div(Nat.add(ms, 50n), 100n)
  Nat.show(Nat.div(t, 10n)) ++ "." ++ Nat.show(Nat.mod(t, 10n)) ++ " s"

# how it ended: its status kept, else stopped (the stop file) or killed
def tl.exit(+code: String, +stopped: Bool) -> String:
  Bool.pick(String, stopped, "stopped", Bool.pick(String, String.is_empty(code), "killed", "exit " ++ code))

def tl.shell.out(+text: String, +exit: String, +ms: Nat) -> E.ev.Out:
  +body = tl.chomp(text)
  E.ev.Out{Bool.pick(String, String.is_empty(body), "", body ++ "\n") ++ "(" ++ exit ++ " in " ++ tl.secs(ms) ++ ")", Bool.not(String.eq(exit, "exit 0"))}

def tl.done(r: Result<&1, &1, U32 & String, Nat>) -> Bool:
  match r:
    case Done{n}:
      True{}
    case Fail{e}:
      False{}

def tl.exists(+path: String) -> IO(Bool):
  IO.bind(Result<&1, &1, U32 & String, Nat>, Bool, S.mu.size(path), r => IO.pure(Bool, tl.done(r)))

def tl.shell(+env: tl.Env, +cwd: String, +command: String) -> IO(E.ev.Out):
  match env:
    case tl.Env{host, work, who, +shell, +ctl, +groups}:
      +out = ctl ++ ".out"
      +code = ctl ++ ".code"
      do IO<E.ev.Out>:
        r : Result<&1, &1, U32 & String, Unit> <- S.mu.unlink(code)
        t0 : Nat <- IO.now()
        o : S.mu.Out <- S.mu.run("sh", ["-c", tl.shell.script(), "sh", ctl ++ ".pid", cwd, shell, command, out, code, groups], "", 65536, 4294967295)
        t1 : Nat <- IO.now()
        un : Result<&1, &1, U32 & String, Unit> <- S.mu.unlink(ctl ++ ".pid")
        +units : Nat <- IO.bind(Result<&1, &1, U32 & String, Nat>, Nat, S.mu.units(out), r => IO.pure(Nat, tl.nat.of(r)))
        +size : Nat <- IO.bind(Result<&1, &1, U32 & String, Nat>, Nat, S.mu.size(out), r => IO.pure(Nat, tl.nat.of(r)))
        +text : String <- tl.out.read(Nat.is_le(units, U32.to_nat(tl.cap())), out, units, size)
        +status : String <- IO.bind(Result<&1, &1, U32 & String, String>, String, S.mu.read_file(code), r => IO.pure(String, T.tx.trim(tl.text.of(r))))
        stopped : Bool <- tl.exists(ctl ++ ".stop")
        return tl.shell.out(text, tl.exit(status, stopped), Nat.sub(t1, t0))

# Read ----------------------------------------------------------------------

def tl.lines.go(s: String, +cur: String, acc: List<&2, String>) -> List<&2, String>:
  match s:
    case SNil{}:
      List.reverse(&2, String, String.reverse(cur) <> acc)
    case SCon{Chr{10}, t}:
      tl.lines.go(t, "", String.reverse(cur) <> acc)
    case SCon{c, t}:
      tl.lines.go(t, SCon{c, cur}, acc)

# text.split("\n")
def tl.split.lines(+s: String) -> List<&2, String>:
  tl.lines.go(s, "", [])

def tl.count.nl(s: String, +n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{Chr{+c}, t}:
      tl.count.nl(t, (n + Bool.pick(U32, U32.is_eq(c, 10), 1, 0) : U32))

# the units after the last newline
def tl.col(s: String, +n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{Chr{+c}, t}:
      tl.col(t, Bool.pick(U32, U32.is_eq(c, 10), 0, (n + T.tx.width16(c) : U32)))

def tl.page.of(p: String & String) -> String:
  match p:
    case (page, rest):
      page

# Machine.read: lines from `offset`, `limit` of them, from character `at`: a
# page of them, and past it where to go on
def tl.read.text(+text: String, +total: U32, +from: U32, +rows: U32, +at: U32) -> E.ev.Out:
  +page = tl.page.of(T.tx.page.cut(T.tx.from(text, at)))
  +end = (at + T.tx.units(page) : U32)
  +whole = U32.is_ge(end, T.tx.units(text))
  +head = tl.take16(text, end)
  +next = (from + tl.count.nl(head, 0) : U32)
  +col = tl.col(head, 0)
  +last = Bool.pick(U32, whole, ((from + rows : U32) - 1 : U32), Bool.pick(U32, U32.is_eq(col, 0), (next - 1 : U32), next))
  +go = Bool.pick(String, whole, "", "; go on with offset " ++ U32.show(next) ++ Bool.pick(String, U32.is_eq(col, 0), "", ", at " ++ U32.show(col)))
  tl.ok(tl.chomp(page) ++ "\n[lines " ++ U32.show(from) ++ "-" ++ U32.show(last) ++ " of " ++ U32.show(total) ++ go ++ "]")

def tl.read.rows(+lines: List<&2, String>, +from: U32, +limit: U32, +at: U32) -> E.ev.Out:
  +total = U32.from_nat(List.length(&2, String, lines))
  +rows = List.take(&2, String, List.drop(&2, String, lines, U32.to_nat((from - 1 : U32))), U32.to_nat(limit))
  +n = U32.from_nat(List.length(&2, String, rows))
  Bool.pick(E.ev.Out, U32.is_eq(n, 0), tl.fail("No lines from line " ++ U32.show(from) ++ ": the file has " ++ U32.show(total) ++ "."),
    tl.read.text(T.tx.join(rows, "\n"), total, from, n, at))

def tl.read.got(+file: String, +size: Nat, r: Result<&1, &1, U32 & String, String>, +from: U32, +limit: U32, +at: U32) -> E.ev.Out:
  match r:
    case Done{+data}:
      Bool.pick(E.ev.Out, T.tx.has(data, 0), tl.fail("A binary file of " ++ Nat.show(size) ++ " bytes."),
        tl.read.rows(tl.split.lines(tl.chomp(data)), U32.max(1, from), limit, at))
    case Fail{(code, why)}:
      tl.fail("ENOENT: no such file or directory, open '" ++ file ++ "'")

def tl.read(+file: String, +from: U32, +limit: U32, +at: U32) -> IO(E.ev.Out):
  do IO<E.ev.Out>:
    +size : Nat <- IO.bind(Result<&1, &1, U32 & String, Nat>, Nat, S.mu.size(file), r => IO.pure(Nat, tl.nat.of(r)))
    r : Result<&1, &1, U32 & String, String> <- S.mu.read_file(file)
    return tl.read.got(file, size, r, from, limit, at)

# Write and edit --------------------------------------------------------------

def tl.was.of(r: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match r:
    case Done{s}:
      Some{s}
    case Fail{e}:
      None{}

def tl.was(+file: String) -> IO(Maybe<&2, String>):
  IO.bind(Result<&1, &1, U32 & String, String>, Maybe<&2, String>, S.mu.read_file(file), r => IO.pure(Maybe<&2, String>, tl.was.of(r)))

def tl.put.got(r: Result<&1, &1, U32 & String, Unit>, +ok: E.ev.Out) -> E.ev.Out:
  match r:
    case Done{u}:
      ok
    case Fail{(code, why)}:
      tl.fail(why)

# a file written whole: its diff (a new one's, all its lines added)
def tl.write(+file: String, +shown: String, +content: String) -> IO(E.ev.Out):
  do IO<E.ev.Out>:
    was : Maybe<&2, String> <- tl.was(file)
    m : Result<&1, &1, U32 & String, Unit> <- S.mu.mkdirs(tl.dir.of(file))
    r : Result<&1, &1, U32 & String, Unit> <- S.mu.put(file, content)
    return tl.put.got(r, tl.ok(tl.clip(D.df.diff(shown, Maybe.default(&2, String, was, ""), content))))

# text.split(old): the pieces between the matches, left to right. here: s
# starts with old (a Bool.pick between two long strings would build both,
# each a copy of the rest: so the verdict is a parameter)
def tl.split.go(n: Nat, s: String, here: Bool, +old: String, +cur: String, acc: List<&2, String>) -> List<&2, String>:
  match n s here:
    case 1n+f SCon{c, t} True{}:
      +rest = String.drop(SCon{c, t}, String.length(old))
      tl.split.go(f, rest, String.starts_with(rest, old), old, "", String.reverse(cur) <> acc)
    case 1n+f SCon{c, +t} False{}:
      tl.split.go(f, t, String.starts_with(t, old), old, SCon{c, cur}, acc)
    case _ _ _:
      List.reverse(&2, String, String.reverse(cur) <> acc)

def tl.split(+s: String, +old: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(old), [s], tl.split.go(1n+String.length(s), s, String.starts_with(s, old), old, "", []))

# a file the edits change: its path, as first named, as it was, as it is
type tl.F is Data:
  tl.F{file: String, shown: String, was: String, text: String}

def tl.f.find(fs: List<&2, tl.F>, +file: String) -> Maybe<&2, tl.F>:
  match fs:
    case []:
      None{}
    case tl.F{+f, +s, +w, +t} <> rest:
      Bool.pick(Maybe<&2, tl.F>, String.eq(f, file), Some{tl.F{f, s, w, t}}, tl.f.find(rest, file))

def tl.f.set(fs: List<&2, tl.F>, +g: tl.F) -> List<&2, tl.F>:
  match fs g:
    case [] _:
      [g]
    case tl.F{+f, +s, +w, +t} <> +rest tl.F{+f2, s2, w2, t2}:
      Bool.pick(List<&2, tl.F>, String.eq(f, f2), g <> rest, tl.F{f, s, w, t} <> tl.f.set(rest, g))

# The edits, in order, each on its file as those before left it; every file
# is written only once all apply (Machine.edit). An edit's text so far: the
# file's (from fs, else the disk), checked, then replaced.
type tl.Ed is Data:
  tl.Ed{fs: List<&2, tl.F>, why: String}

def tl.edit.why(+k: U32, +path: String, +why: String) -> String:
  "Edit " ++ U32.show(k) ++ " (" ++ path ++ "): " ++ why ++ ". No file was changed."

def tl.edit.apply(+k: U32, +path: String, +old: String, +new: String, +all: Bool, f: tl.F, there: Bool, +fs: List<&2, tl.F>) -> tl.Ed:
  match f:
    case tl.F{+file, +shown, +was, +text}:
      +parts = tl.split(text, old)
      +count = Bool.pick(U32, String.is_empty(old), 0, (U32.from_nat(List.length(&2, String, parts)) - 1 : U32))
      +why = Bool.pick(String, Bool.not(there), "no such file", Bool.pick(String, U32.is_eq(count, 0), "old was not found",
        Bool.pick(String, Bool.and(U32.is_gt(count, 1), Bool.not(all)), "old matches " ++ U32.show(count) ++ " times; give more context, or all", "")))
      Bool.pick(tl.Ed, String.is_empty(why), tl.Ed{tl.f.set(fs, tl.F{file, shown, was, T.tx.join(parts, new)}), ""}, tl.Ed{fs, tl.edit.why(k, path, why)})

def tl.edit.on(+k: U32, +e: J.Json, f: tl.F, there: Bool, +fs: List<&2, tl.F>) -> tl.Ed:
  tl.edit.apply(k, tl.s(e, "path"), Maybe.default(&2, String, J.js.str(e, "old"), tl.s(e, "old")), Maybe.default(&2, String, J.js.str(e, "new"), tl.s(e, "new")),
    Maybe.default(&2, Bool, J.js.bool(e, "all"), False{}), f, there, fs)

def tl.edit.one(+k: U32, +e: J.Json, +file: String, known: Maybe<&2, tl.F>, disk: Maybe<&2, String>, +fs: List<&2, tl.F>) -> tl.Ed:
  match known disk:
    case Some{tl.F{f, +shown, +was, +text}} _:
      tl.edit.on(k, e, tl.F{file, shown, was, text}, True{}, fs)
    case None{} Some{+was}:
      tl.edit.on(k, e, tl.F{file, tl.s(e, "path"), was, was}, True{}, fs)
    case None{} None{}:
      tl.edit.on(k, e, tl.F{file, tl.s(e, "path"), "", ""}, False{}, fs)

def tl.edits.go(es: List<&2, J.Json>, +env: tl.Env, +cwd: String, +k: U32, d: tl.Ed) -> IO(tl.Ed):
  match es d:
    case [] _:
      IO.pure(tl.Ed, d)
    case +e <> rest tl.Ed{+fs, SNil{}}:
      +file = tl.path(cwd, tl.s(e, "path"))
      do IO<tl.Ed>:
        disk : Maybe<&2, String> <- tl.was(file)
        tl.edits.go(rest, env, cwd, (k + 1 : U32), tl.edit.one(k, e, file, tl.f.find(fs, file), disk, fs))
    case _ _:
      IO.pure(tl.Ed, d)

def tl.edits.write(fs: List<&2, tl.F>) -> IO(Unit):
  match fs:
    case []:
      IO.pure(Unit, Unit{})
    case tl.F{file, s, w, text} <> rest:
      IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, S.mu.put(file, text), r => tl.edits.write(rest))

def tl.diffs(fs: List<&2, tl.F>) -> List<&2, String>:
  match fs:
    case []:
      []
    case tl.F{f, +shown, +was, +text} <> rest:
      D.df.diff(shown, was, text) <> tl.diffs(rest)

def tl.edit.done(d: tl.Ed) -> IO(E.ev.Out):
  match d:
    case tl.Ed{[], SNil{}}:
      IO.pure(E.ev.Out, tl.fail("edits is empty: give a list of {path, old, new}."))
    case tl.Ed{+fs, SNil{}}:
      IO.bind(Unit, E.ev.Out, tl.edits.write(fs), u => IO.pure(E.ev.Out, tl.ok(tl.clip(T.tx.join(tl.diffs(fs), "\n")))))
    case tl.Ed{fs, why}:
      IO.pure(E.ev.Out, tl.fail(why))

def tl.edit(+env: tl.Env, +cwd: String, +input: J.Json) -> IO(E.ev.Out):
  IO.bind(tl.Ed, E.ev.Out, tl.edits.go(J.js.arr(input, "edits"), env, cwd, 1, tl.Ed{[], ""}), d => tl.edit.done(d))

# The tools that touch the device -------------------------------------------------

def tl.is.kit(+name: String) -> Bool:
  Bool.or(Bool.or(String.eq(name, "shell"), String.eq(name, "read")), Bool.or(String.eq(name, "write"), String.eq(name, "edit")))

def tl.kit.code(+name: String) -> Nat:
  Bool.pick(Nat, String.eq(name, "shell"), 0n, Bool.pick(Nat, String.eq(name, "read"), 1n, Bool.pick(Nat, String.eq(name, "write"), 2n, 3n)))

def tl.kit.go(k: Nat, +env: tl.Env, +cwd: String, +input: J.Json) -> IO(E.ev.Out):
  match k:
    case 0n:
      tl.shell(env, cwd, tl.s(input, "command"))
    case 1n:
      tl.read(tl.path(cwd, tl.s(input, "path")), tl.n(input, "offset", 1), tl.n(input, "limit", 4294967295), tl.n(input, "at", 0))
    case 2n:
      tl.write(tl.path(cwd, tl.s(input, "path")), tl.s(input, "path"), Maybe.default(&2, String, J.js.str(input, "content"), tl.s(input, "content")))
    case _:
      tl.edit(env, cwd, input)

def tl.env.host(e: tl.Env) -> String:
  match e:
    case tl.Env{h, w, who, sh, c, g}:
      h

def tl.env.cwd(e: tl.Env) -> String:
  match e:
    case tl.Env{h, w, who, sh, c, g}:
      w ++ "/" ++ who

# a kit tool's call on this device (another device named: none is open)
def tl.kit.run(+env: tl.Env, +name: String, +input: J.Json) -> IO(E.ev.Out):
  +host = tl.env.host(env)
  +device = tl.s(input, "device")
  +cwd = tl.env.cwd(env)
  Bool.pick(IO(E.ev.Out), String.eq(device, host),
    IO.bind(Result<&1, &1, U32 & String, Unit>, E.ev.Out, S.mu.mkdirs(cwd), r => tl.kit.go(tl.kit.code(name), env, cwd, input)),
    IO.pure(E.ev.Out, tl.fail("No device " ++ device ++ " is open (unii isn't running there). Open: " ++ host ++ ". Only the user opens it, so don't retry or wait: end your turn, saying what is left.")))

# the devices open now, at the start of each call's message (Tools.devices)
def tl.devices(+host: String, +work: String) -> String:
  "Devices open now:\n- " ++ host ++ ", work dir " ++ work ++ "\n\n"
