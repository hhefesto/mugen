
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./Clock.bend as C

# Store: the chat on disk, as UniiChat keeps it (Memory.ts), so either can
# open the other's: main/ (the messages) and tree/ (the nodes), JSON lines in
# a file per local day, appended and flushed. Every line has a slot in its
# log's index: main.idx by message, tree.idx by node (Tree.bend tr.slot), 16
# bytes of four u32 each: where the line starts in its day's file, the day
# (days since 1970; 0 is no line), its length, and a word of meta (a
# message's size, bit 31 when more pages follow; a node's size). UniiChat's
# own index (main.index, f64 offsets) it rebuilds when view.json says
# "main": [0, 0]; mugen keeps how far its indexes go in idx.json.
#
# Every def is prefixed `st.` (a program's defs share one namespace).

# Paths ---------------------------------------------------------------------

def st.idx(+dir: String, +stream: String) -> String:
  dir ++ "/" ++ stream ++ ".idx"

def st.file(+dir: String, +stream: String, +day: U32) -> String:
  dir ++ "/" ++ stream ++ "/" ++ C.ck.civil(day) ++ ".jsonl"

def st.agents(+dir: String) -> String:
  dir ++ "/docs/agent"

# Records -------------------------------------------------------------------

# A message (a page of one): its index, kind, text, size (UTF-8 bytes of
# "kind: text"), date (ISO), the line it was logged with if any, and whether
# more pages of it follow.
type st.Root is Data:
  st.Root{i: U32, kind: String, text: String, size: U32, date: String, line: Maybe<&2, String>, more: Bool}

def st.root.kind(r: st.Root) -> String:
  match r:
    case st.Root{i, k, t, s, d, l, m}:
      k

def st.root.text(r: st.Root) -> String:
  match r:
    case st.Root{i, k, t, s, d, l, m}:
      t

def st.root.size(r: st.Root) -> U32:
  match r:
    case st.Root{i, k, t, s, d, l, m}:
      s

def st.root.date(r: st.Root) -> String:
  match r:
    case st.Root{i, k, t, s, d, l, m}:
      d

def st.root.more(r: st.Root) -> Bool:
  match r:
    case st.Root{i, k, t, s, d, l, m}:
      m

def st.root.i(r: st.Root) -> U32:
  match r:
    case st.Root{i, k, t, s, d, l, m}:
      i

# a message as models read it (Memory.show)
def st.show(r: st.Root) -> String:
  match r:
    case st.Root{i, k, t, s, d, l, m}:
      k ++ ": " ++ t

# the line a node of level 0 compresses: the one logged with it, else the
# message as models read it (Memory.source)
def st.source(r: st.Root) -> String:
  match r:
    case st.Root{i, k, t, s, d, Some{l}, m}:
      l
    case st.Root{i, k, t, s, d, None{}, m}:
      k ++ ": " ++ t

def st.opt.line(l: Maybe<&2, String>) -> List<&2, J.JKv>:
  match l:
    case Some{x}:
      [J.JKv{"line", J.JStr{x}}]
    case None{}:
      []

def st.opt.more(m: Bool) -> List<&2, J.JKv>:
  match m:
    case True{}:
      [J.JKv{"more", J.JBool{True{}}}]
    case False{}:
      []

# the record as JSON.stringify writes Memory.root's object: its message's
# keys first (kind, text, line, more), then i, size, date
def st.root.json(r: st.Root) -> J.Json:
  match r:
    case st.Root{i, k, t, s, d, l, m}:
      J.JObj{List.concat(&2, J.JKv, [[J.JKv{"kind", J.JStr{k}}, J.JKv{"text", J.JStr{t}}], st.opt.line(l), st.opt.more(m),
        [J.JKv{"i", J.js.u32(i)}, J.JKv{"size", J.js.u32(s)}, J.JKv{"date", J.JStr{d}}]])}

def st.root.of(+j: J.Json) -> st.Root:
  st.Root{U32.from_nat(Maybe.default(&2, Nat, J.js.num(j, "i"), 0n)),
    Maybe.default(&2, String, J.js.str(j, "kind"), "note"),
    Maybe.default(&2, String, J.js.str(j, "text"), ""),
    U32.from_nat(Maybe.default(&2, Nat, J.js.num(j, "size"), 0n)),
    Maybe.default(&2, String, J.js.str(j, "date"), "1970-01-01T00:00:00.000Z"),
    J.js.str(j, "line"),
    Maybe.default(&2, Bool, J.js.bool(j, "more"), False{})}

# message i, read off its index slot's line
def st.root.read(m: Maybe<&2, J.Json>) -> Maybe<&2, st.Root>:
  match m:
    case Some{+j}:
      Some{st.root.of(j)}
    case None{}:
      None{}

def st.root.meta(+r: st.Root) -> U32:
  U32.or(U32.and(st.root.size(r), 2147483647), Bool.pick(U32, st.root.more(r), 2147483648, 0))

# a node's record
def st.node.json(+l: U32, +i: U32, text: String, +size: U32) -> J.Json:
  J.JObj{[J.JKv{"l", J.js.u32(l)}, J.JKv{"i", J.js.u32(i)}, J.JKv{"text", J.JStr{text}}, J.JKv{"size", J.js.u32(size)}]}

# Slots ---------------------------------------------------------------------

type st.Slot is Data:
  st.Slot{at: U32, day: U32, len: U32, meta: U32}

def st.slots.of(ws: List<&2, U32>) -> List<&2, st.Slot>:
  match ws:
    case a <> b <> c <> d <> t:
      st.Slot{a, b, c, d} <> st.slots.of(t)
    case _:
      []

# n slots of a log's index from `first` (past its end: empty ones)
def st.slots(+dir: String, +stream: String, +first: U32, +n: U32) -> IO(List<&2, st.Slot>):
  IO.bind(List<&2, U32>, List<&2, st.Slot>, S.mu.must(List<&2, U32>, "read " ++ stream ++ ".idx", S.mu.slots(st.idx(dir, stream), U32.to_nat(first), n)),
    ws => IO.pure(List<&2, st.Slot>, st.slots.of(ws)))

def st.slot.one(xs: List<&2, st.Slot>) -> st.Slot:
  match xs:
    case x <> t:
      x
    case []:
      st.Slot{0, 0, 0, 0}

def st.slot(+dir: String, +stream: String, +slot: U32) -> IO(st.Slot):
  IO.bind(List<&2, st.Slot>, st.Slot, st.slots(dir, stream, slot, 1), xs => IO.pure(st.Slot, st.slot.one(xs)))

def st.line.at(+dir: String, +stream: String, s: st.Slot) -> IO(Maybe<&2, J.Json>):
  match s:
    case st.Slot{at, +day, len, meta}:
      Bool.pick(IO(Maybe<&2, J.Json>), U32.is_eq(day, 0), IO.pure(Maybe<&2, J.Json>, None{}),
        IO.bind(String, Maybe<&2, J.Json>, S.mu.must(String, "read " ++ stream, S.mu.pread_text(st.file(dir, stream, day), U32.to_nat(at), len)),
          t => IO.pure(Maybe<&2, J.Json>, J.js.read(t))))

# the record at a slot of a log, if any (Memory.read)
def st.read(+dir: String, +stream: String, +slot: U32) -> IO(Maybe<&2, J.Json>):
  IO.bind(st.Slot, Maybe<&2, J.Json>, st.slot(dir, stream, slot), s => st.line.at(dir, stream, s))

# message i, if logged
def st.message(+dir: String, +i: U32) -> IO(Maybe<&2, st.Root>):
  IO.bind(Maybe<&2, J.Json>, Maybe<&2, st.Root>, st.read(dir, "main", i), m => IO.pure(Maybe<&2, st.Root>, st.root.read(m)))

def st.node.text(m: Maybe<&2, J.Json>) -> Maybe<&2, String>:
  match m:
    case Some{+j}:
      J.js.str(j, "text")
    case None{}:
      None{}

# node (l,i)'s text from its log, if built
def st.node(+dir: String, +slot: U32) -> IO(Maybe<&2, String>):
  IO.bind(Maybe<&2, J.Json>, Maybe<&2, String>, st.read(dir, "tree", slot), m => IO.pure(Maybe<&2, String>, st.node.text(m)))

# Logging -------------------------------------------------------------------

# a record to log: its slot, its line, its meta word
type st.Rec is Data:
  st.Rec{slot: U32, line: String, meta: U32}

def st.recs.text(rs: List<&2, st.Rec>) -> String:
  match rs:
    case []:
      ""
    case st.Rec{s, l, m} <> t:
      String.append(l, "\n" ++ st.recs.text(t))

def st.place(+dir: String, +stream: String, +day: U32, rs: List<&2, st.Rec>, +at: U32) -> IO(U32):
  match rs:
    case []:
      IO.pure(U32, at)
    case st.Rec{+slot, +line, +meta} <> t:
      +len = T.tx.bytes(line)
      do IO<U32>:
        Unit <- S.mu.must(Unit, "write " ++ stream ++ ".idx", S.mu.slot_put(st.idx(dir, stream), U32.to_nat(slot), at, day, len, meta, 0))
        st.place(dir, stream, day, t, ((at + len : U32) + 1 : U32))

# records appended to the day's file in one write (fsynced when sync is 1),
# then given their slots; the file's end after them (Memory.log)
def st.log(+dir: String, +stream: String, +day: U32, +sync: U32, +rs: List<&2, st.Rec>) -> IO(U32):
  do IO<U32>:
    Unit <- S.mu.must(Unit, "mkdir " ++ stream, S.mu.mkdirs(dir ++ "/" ++ stream))
    at : Nat <- S.mu.must(Nat, "append " ++ stream, S.mu.append(st.file(dir, stream, day), st.recs.text(rs), sync))
    st.place(dir, stream, day, rs, U32.from_nat(at))

# Counting ------------------------------------------------------------------

def st.more.back(xs: List<&2, st.Slot>, +n: U32) -> U32:
  match xs:
    case []:
      n
    case st.Slot{a, d, l, +m} <> t:
      Bool.pick(U32, U32.is_ne(U32.and(m, 2147483648), 0), st.more.back(t, (n - 1 : U32)), n)

# the messages logged whole: main.idx's slots, less the pages at its end that
# more pages follow (Memory.load)
def st.count(+dir: String) -> IO(U32 & U32):
  do IO<U32 & U32>:
    +size : Nat <- S.mu.must(Nat, "size main.idx", S.mu.size(st.idx(dir, "main")))
    +n : U32 = U32.from_nat(Nat.div(size, 16n))
    +back : U32 = U32.min(n, 64)
    xs : List<&2, st.Slot> <- st.slots(dir, "main", (n - back : U32), back)
    +whole : U32 = st.more.back(List.reverse(&2, st.Slot, xs), n)
    return (whole, (n - whole : U32))

# Indexing ------------------------------------------------------------------
#
# What a crash left unindexed is indexed on load: every day file from the
# last one indexed, from where it was indexed to. A last line a crash cut
# short is skipped (and ended, so the next line starts clean).

type st.End is Data:
  st.End{day: U32, at: U32}

def st.rec.slot(+stream: String, +j: J.Json) -> U32:
  +i = U32.from_nat(Maybe.default(&2, Nat, J.js.num(j, "i"), 0n))
  Bool.pick(U32, String.eq(stream, "main"), i, ((2 * i + 1 : U32) * U32.shln(1, Maybe.default(&2, Nat, J.js.num(j, "l"), 0n)) - 1 : U32))

def st.rec.meta(+stream: String, +j: J.Json) -> U32:
  Bool.pick(U32, String.eq(stream, "main"), st.root.meta(st.root.of(j)), U32.from_nat(Maybe.default(&2, Nat, J.js.num(j, "size"), 0n)))

def st.scan.one(+dir: String, +stream: String, +day: U32, +at: U32, +len: U32, m: Maybe<&2, J.Json>) -> IO(Unit):
  match m:
    case Some{+j}:
      S.mu.must(Unit, "index " ++ stream, S.mu.slot_put(st.idx(dir, stream), U32.to_nat(st.rec.slot(stream, j)), at, day, len, st.rec.meta(stream, j), 0))
    case None{}:
      IO.print_err("mugen: skipped a line of " ++ st.file(dir, stream, day) ++ ": not JSON")

# the text past the file's last newline: none, or a line cut short
def st.scan.last(+dir: String, +stream: String, +day: U32, +last: String, +at: U32) -> IO(U32):
  Bool.pick(IO(U32), String.is_empty(last), IO.pure(U32, at),
    do IO<U32>:
      IO.print_err("mugen: skipped the last line of " ++ st.file(dir, stream, day) ++ ": cut short")
      Nat <- S.mu.must(Nat, "end " ++ stream, S.mu.append(st.file(dir, stream, day), "\n", 1))
      return ((at + T.tx.bytes(last) : U32) + 1 : U32))

def st.scan.go(+dir: String, +stream: String, +day: U32, lines: List<&2, String>, +at: U32) -> IO(U32):
  match lines:
    case []:
      IO.pure(U32, at)
    case [last]:
      st.scan.last(dir, stream, day, last, at)
    case +l <> t:
      +len = T.tx.bytes(l)
      do IO<U32>:
        Unit <- st.scan.one(dir, stream, day, at, len, J.js.read(l))
        st.scan.go(dir, stream, day, t, ((at + len : U32) + 1 : U32))

def st.scan(+dir: String, +stream: String, +day: U32, +from: U32) -> IO(U32):
  do IO<U32>:
    +size : Nat <- S.mu.must(Nat, "size " ++ stream, S.mu.size(st.file(dir, stream, day)))
    text : String <- S.mu.must(String, "read " ++ stream, S.mu.pread_text(st.file(dir, stream, day), U32.to_nat(from), U32.from_nat(Nat.sub(size, U32.to_nat(from)))))
    st.scan.go(dir, stream, day, String.split(text, '\n'), from)

def st.end.day(e: st.End) -> U32:
  match e:
    case st.End{d, a}:
      d

def st.end.at(e: st.End) -> U32:
  match e:
    case st.End{d, a}:
      a

# whether the first day file named is due: from the last day indexed on
def st.due(+names: List<&2, String>, +end: st.End) -> Bool:
  match names:
    case []:
      False{}
    case n <> t:
      U32.is_ge(C.ck.day_of(n), st.end.day(end))

def st.index.go(+dir: String, +stream: String, names: List<&2, String>, due: Bool, +end: st.End) -> IO(st.End):
  match names due:
    case Nil{} _:
      IO.pure(st.End, end)
    case +n <> +t True{}:
      +day = C.ck.day_of(n)
      do IO<st.End>:
        +at : U32 <- st.scan(dir, stream, day, Bool.pick(U32, U32.is_eq(day, st.end.day(end)), st.end.at(end), 0))
        st.index.go(dir, stream, t, st.due(t, st.End{day, at}), st.End{day, at})
    case n <> +t False{}:
      st.index.go(dir, stream, t, st.due(t, end), end)

def st.jsonl(+names: List<&2, String>) -> List<&2, String>:
  List.filter(~String, ~(n => String.ends_with(n, ".jsonl")), names)

def st.ls.got(r: Result<&1, &1, U32 & String, List<&2, String>>) -> List<&2, String>:
  match r:
    case Done{xs}:
      xs
    case Fail{e}:
      []

def st.exists(r: Result<&1, &1, U32 & String, Nat>) -> Bool:
  match r:
    case Done{n}:
      True{}
    case Fail{e}:
      False{}

# a log's lines past `from` indexed (no index file: all of them, in one made
# anew); how far it is indexed now (Memory.index)
def st.index(+dir: String, +stream: String, +from: st.End) -> IO(st.End):
  do IO<st.End>:
    Unit <- S.mu.must(Unit, "mkdir " ++ stream, S.mu.mkdirs(dir ++ "/" ++ stream))
    has : Result<&1, &1, U32 & String, Nat> <- S.mu.size(st.idx(dir, stream))
    +start : st.End = Bool.pick(st.End, st.exists(has), from, st.End{0, 0})
    Result<&1, &1, U32 & String, Nat> <- S.mu.append(st.idx(dir, stream), "", 0)
    ls : Result<&1, &1, U32 & String, List<&2, String>> <- S.mu.ls(dir ++ "/" ++ stream)
    +names : List<&2, String> = st.jsonl(st.ls.got(ls))
    st.index.go(dir, stream, names, st.due(names, start), start)

# Agents --------------------------------------------------------------------

def st.agent.file(+dir: String, +name: String) -> String:
  st.agents(dir) ++ "/" ++ name ++ ".jsonl"

def st.agent.put(m: Maybe<&2, J.Json>, rest: List<&2, st.Root>) -> List<&2, st.Root>:
  match m:
    case Some{+j}:
      st.root.of(j) <> rest
    case None{}:
      rest

def st.agent.recs(lines: List<&2, String>) -> List<&2, st.Root>:
  match lines:
    case []:
      []
    case l <> t:
      st.agent.put(J.js.read(l), st.agent.recs(t))

def st.agent.got(r: Result<&1, &1, U32 & String, String>) -> Maybe<&2, List<&2, st.Root>>:
  match r:
    case Done{t}:
      Some{st.agent.recs(String.split(t, '\n'))}
    case Fail{e}:
      None{}

# an agent's log, whole (none: no such agent) (Memory.agent)
def st.agent(+dir: String, +name: String) -> IO(Maybe<&2, List<&2, st.Root>>):
  IO.bind(Result<&1, &1, U32 & String, String>, Maybe<&2, List<&2, st.Root>>, S.mu.read_file(st.agent.file(dir, name)),
    r => IO.pure(Maybe<&2, List<&2, st.Root>>, st.agent.got(r)))

def st.agent.append(+dir: String, +name: String, r: st.Root) -> IO(Unit):
  do IO<Unit>:
    Unit <- S.mu.must(Unit, "mkdir agents", S.mu.mkdirs(st.agents(dir)))
    Nat <- S.mu.must(Nat, "append agent log", S.mu.append(st.agent.file(dir, name), String.append(J.js.write(st.root.json(r)), "\n"), 0))
    IO.pure(Unit, Unit{})
