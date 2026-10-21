
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./Clock.bend as C
import ./Tree.bend as R
import ./View.bend as V
import ./Store.bend as St

# Export: the whole memory written out, a piece at a time (a chat of years
# never sits in memory whole). /export (Memory.dump): the messages, the
# summaries, the agents' logs, as JSON. /tree (Memory.page): a page with a
# section for the view, the messages and each level of the tree.
#
# Every def is prefixed `ex.` (a program's defs share one namespace).

def ex.put(+file: String, +text: String) -> IO(Unit):
  IO.bind(Nat, Unit, S.mu.must(Nat, "write " ++ file, S.mu.append(file, text, 0)), n => IO.pure(Unit, Unit{}))

def ex.opt.more(m: Bool) -> List<&2, J.JKv>:
  match m:
    case True{}:
      [J.JKv{"more", J.JBool{True{}}}]
    case False{}:
      []

def ex.msg.json(r: St.st.Root) -> String:
  match r:
    case St.st.Root{i, k, t, s, d, l, m}:
      J.js.write(J.JObj{List.append(&2, J.JKv, [J.JKv{"id", J.js.u32(i)}, J.JKv{"kind", J.JStr{k}}, J.JKv{"text", J.JStr{t}}, J.JKv{"date", J.JStr{d}}], ex.opt.more(m))})

def ex.root.of(m: Maybe<&2, St.st.Root>, +i: U32) -> St.st.Root:
  match m:
    case Some{r}:
      r
    case None{}:
      St.st.Root{i, "note", "", 0, "", None{}, False{}}

# each message, as {id, kind, text, date, more}
def ex.messages(n: Nat, +dir: String, +file: String, +i: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        m : Maybe<&2, St.st.Root> <- St.st.message(dir, i)
        Unit <- ex.put(file, Bool.pick(String, U32.is_eq(i, 0), "\n", ",\n") ++ ex.msg.json(ex.root.of(m, i)))
        ex.messages(f, dir, file, (i + 1 : U32))

# the tree's levels: as many as the count's bits
def ex.bits(n: Nat, zero: Bool, +c: U32, +l: U32) -> U32:
  match n zero:
    case 1n+f False{}:
      ex.bits(f, U32.is_eq(U32.shr(c), 0), U32.shr(c), (l + 1 : U32))
    case _ _:
      l

def ex.levels(+count: U32, +l: U32) -> U32:
  ex.bits(32n, U32.is_eq(count, 0), count, l)

# what the walk over the tree writes: the comma before the next one
type ex.W is Data:
  ex.W{sep: String}

def ex.summary(+l: U32, +i: U32, m: Maybe<&2, String>, +sep: String) -> String:
  match m:
    case Some{+t}:
      sep ++ J.js.write(J.JObj{[J.JKv{"id", J.js.u32(R.tr.first(R.tr.P{l, i}))}, J.JKv{"n", J.js.u32(R.tr.pow(l))}, J.JKv{"text", J.JStr{t}}]})
    case None{}:
      ""

def ex.node.text(m: Maybe<&2, String>) -> Maybe<&2, String>:
  m

# level l's nodes built, in order, from node i (Memory.level)
def ex.level(n: Nat, +dir: String, +file: String, +l: U32, +i: U32, +sep: String) -> IO(String):
  match n:
    case 0n:
      IO.pure(String, sep)
    case 1n+f:
      do IO<String>:
        +m : Maybe<&2, String> <- St.st.node(dir, R.tr.slot(l, i))
        Unit <- ex.put(file, ex.summary(l, i, m, sep))
        ex.level(f, dir, file, l, (i + 1 : U32), Bool.pick(String, Maybe.is_some(&2, String, m), ",\n", sep))

def ex.summaries(n: Nat, +dir: String, +file: String, +count: U32, +l: U32, +sep: String) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        +sep2 : String <- ex.level(U32.to_nat(U32.div(count, R.tr.pow(l))), dir, file, l, 0, sep)
        ex.summaries(f, dir, file, count, (l + 1 : U32), sep2)

def ex.agent.entries(rs: List<&2, St.st.Root>) -> List<&2, J.Json>:
  match rs:
    case []:
      []
    case St.st.Root{i, k, t, s, d, l, m} <> rest:
      J.JObj{[J.JKv{"id", J.js.u32(i)}, J.JKv{"kind", J.JStr{k}}, J.JKv{"text", J.JStr{t}}, J.JKv{"date", J.JStr{d}}]} <> ex.agent.entries(rest)

def ex.agent.json(+name: String, m: Maybe<&2, List<&2, St.st.Root>>) -> String:
  match m:
    case Some{rs}:
      J.js.quote(name) ++ ": " ++ J.js.write(J.JArr{ex.agent.entries(rs)})
    case None{}:
      ""

def ex.agents(ns: List<&2, String>, +dir: String, +file: String, +sep: String) -> IO(Unit):
  match ns:
    case []:
      IO.pure(Unit, Unit{})
    case +f <> rest:
      +name = String.take(f, Nat.sub(String.length(f), 6n))
      do IO<Unit>:
        log : Maybe<&2, List<&2, St.st.Root>> <- St.st.agent(dir, name)
        Unit <- ex.put(file, sep ++ ex.agent.json(name, log))
        ex.agents(rest, dir, file, ",\n")

def ex.names.of(r: Result<&1, &1, U32 & String, List<&2, String>>) -> List<&2, String>:
  match r:
    case Done{ns}:
      ns
    case Fail{e}:
      []

# /export: the memory, as JSON, written to `file` anew
def ex.export(+dir: String, +count: U32, +file: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- S.mu.must(Unit, "write " ++ file, S.mu.save(file, "{\"messages\": [", 0))
    Unit <- ex.messages(U32.to_nat(count), dir, file, 0)
    Unit <- ex.put(file, "],\n\"summaries\": [\n")
    Unit <- ex.summaries(U32.to_nat(ex.levels(count, 0)), dir, file, count, 0, "")
    Unit <- ex.put(file, "],\n\"agents\": {\n")
    ns : Result<&1, &1, U32 & String, List<&2, String>> <- S.mu.ls(St.st.agents(dir))
    Unit <- ex.agents(ex.names.of(ns), dir, file, "")
    ex.put(file, "}}\n")

# The page ---------------------------------------------------------------------------

def ex.esc.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{38}, t}:
      ex.esc.go(t, String.reverse.go("&amp;", acc))
    case SCon{Chr{60}, t}:
      ex.esc.go(t, String.reverse.go("&lt;", acc))
    case SCon{c, t}:
      ex.esc.go(t, SCon{c, acc})

def ex.esc(+s: String) -> String:
  ex.esc.go(s, "")

def ex.item(+head: String, +text: String) -> String:
  "<h4>" ++ ex.esc(head) ++ "</h4><pre>" ++ ex.esc(text) ++ "</pre>"

def ex.date.of(m: Maybe<&2, St.st.Root>, +tz: U32) -> String:
  match m:
    case Some{r}:
      C.ck.show(C.ck.parse(St.st.root.date(r)), tz)
    case None{}:
      ""

def ex.date(+dir: String, +i: U32, +tz: U32) -> IO(String):
  IO.bind(Maybe<&2, St.st.Root>, String, St.st.message(dir, i), m => IO.pure(String, ex.date.of(m, tz)))

# a node's item: its level and span, when, its bytes
def ex.node(+dir: String, +p: R.tr.P, +text: String, +tz: U32) -> IO(String):
  +a = R.tr.first(p)
  +b = R.tr.last(p)
  do IO<String>:
    +da : String <- ex.date(dir, a, tz)
    +db : String <- ex.date(dir, b, tz)
    return ex.item("LVL" ++ U32.show(R.tr.l(p)) ++ " #" ++ U32.show(a) ++ "-" ++ U32.show(b) ++ " · " ++ da ++ Bool.pick(String, U32.is_eq(a, b), "", " – " ++ db) ++ " · " ++ U32.show(T.tx.bytes(text)) ++ " B", text)

def ex.view(ps: List<&2, R.tr.P>, +dir: String, +file: String, +nodes: List<&2, String>, +tz: U32) -> IO(Unit):
  match ps nodes:
    case +p <> rest +t <> ts:
      do IO<Unit>:
        +it : String <- ex.node(dir, p, t, tz)
        Unit <- ex.put(file, it)
        ex.view(rest, dir, file, ts, tz)
    case _ _:
      IO.pure(Unit, Unit{})

def ex.roots(n: Nat, +dir: String, +file: String, +i: U32, +tz: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        m : Maybe<&2, St.st.Root> <- St.st.message(dir, i)
        +r : St.st.Root = ex.root.of(m, i)
        +d : String <- ex.date(dir, i, tz)
        Unit <- ex.put(file, ex.item("ROOT #" ++ U32.show(i) ++ " · " ++ d ++ " · " ++ St.st.root.kind(r) ++ " · " ++ U32.show(St.st.root.size(r)) ++ " B", St.st.root.text(r)))
        ex.roots(f, dir, file, (i + 1 : U32), tz)

def ex.page.item(+dir: String, +l: U32, +i: U32, m: Maybe<&2, String>, +tz: U32) -> IO(String):
  match m:
    case Some{+t}:
      ex.node(dir, R.tr.P{l, i}, t, tz)
    case None{}:
      IO.pure(String, "")

def ex.page.level(n: Nat, +dir: String, +file: String, +l: U32, +i: U32, +tz: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        m : Maybe<&2, String> <- St.st.node(dir, R.tr.slot(l, i))
        +it : String <- ex.page.item(dir, l, i, m, tz)
        Unit <- ex.put(file, it)
        ex.page.level(f, dir, file, l, (i + 1 : U32), tz)

def ex.page.levels(n: Nat, +dir: String, +file: String, +count: U32, +l: U32, +tz: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        Unit <- ex.put(file, "</section>\n<section id=\"LVL" ++ U32.show(l) ++ "\">")
        Unit <- ex.page.level(U32.to_nat(U32.div(count, R.tr.pow(l))), dir, file, l, 0, tz)
        ex.page.levels(f, dir, file, count, (l + 1 : U32), tz)

def ex.menu(n: Nat, +l: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+f:
      ex.menu(f, (l + 1 : U32), acc ++ "<a href=\"#LVL" ++ U32.show(l) ++ "\">LVL" ++ U32.show(l) ++ "</a>")

# /tree: the page, written to `file` anew; `parts` the view's lines, `texts`
# their texts (built or not)
def ex.tree(+dir: String, +count: U32, +parts: List<&2, R.tr.P>, +texts: List<&2, String>, +tz: U32, +file: String) -> IO(Unit):
  +levels = ex.levels(count, 0)
  +head = "<!doctype html><meta charset=\"utf-8\"><title>mugen memory</title>\n<style>\nbody { font: 13px/1.4 ui-monospace, monospace; margin: 2em; } nav a { margin-right: 1em; }\nsection { display: none; } section:target { display: block; }\nh4 { margin: .8em 0 .2em; color: #888; font-weight: normal; } pre { margin: 0; white-space: pre-wrap; font: inherit; }\n</style>\n<script>location.hash = location.hash || \"VIEW\";</script>\n<nav><a href=\"#VIEW\">VIEW</a><a href=\"#ROOT\">ROOT</a>" ++ ex.menu(U32.to_nat(levels), 0, "") ++ "</nav>\n<section id=\"VIEW\">"
  do IO<Unit>:
    Unit <- S.mu.must(Unit, "write " ++ file, S.mu.save(file, head, 0))
    Unit <- ex.view(parts, dir, file, texts, tz)
    Unit <- ex.put(file, "</section>\n<section id=\"ROOT\">")
    Unit <- ex.roots(U32.to_nat(count), dir, file, 0, tz)
    Unit <- ex.page.levels(U32.to_nat(levels), dir, file, count, 0, tz)
    ex.put(file, "</section>\n")
