import Base
import ./Text.bend as T

# Tree: the summary tree's arithmetic (Memory.ts). Node (0,i) is message i in
# at most NODE bytes; node (l,i) merges (l-1,2i) and (l-1,2i+1), so it covers
# messages i*2^l to (i+1)*2^l - 1. A node is a part of a view, a line of it.
#
# Every def is prefixed `tr.` (a program's defs share one namespace).

type tr.P is Data:
  tr.P{l: U32, i: U32}

def tr.node() -> U32:
  512

def tr.pow(+l: U32) -> U32:
  U32.shln(1, U32.to_nat(l))

def tr.l(p: tr.P) -> U32:
  match p:
    case tr.P{l, i}:
      l

def tr.i(p: tr.P) -> U32:
  match p:
    case tr.P{l, i}:
      i

def tr.eq(a: tr.P, b: tr.P) -> Bool:
  match a b:
    case tr.P{l1, i1} tr.P{l2, i2}:
      Bool.and(U32.is_eq(l1, l2), U32.is_eq(i1, i2))

# where node (l,i) lives in tree.idx: (2i+1)*2^l - 1, every node its own slot
def tr.slot(+l: U32, +i: U32) -> U32:
  ((2 * i + 1 : U32) * tr.pow(l) - 1 : U32)

def tr.slot.of(p: tr.P) -> U32:
  match p:
    case tr.P{+l, +i}:
      tr.slot(l, i)

# the first message a node covers, and its last
def tr.first(p: tr.P) -> U32:
  match p:
    case tr.P{+l, +i}:
      (i * tr.pow(l) : U32)

def tr.last(p: tr.P) -> U32:
  match p:
    case tr.P{+l, +i}:
      ((i + 1 : U32) * tr.pow(l) - 1 : U32)

# the message a node's summary sees the chat up to (Memory.ctx)
def tr.ctx(+l: U32, +i: U32) -> U32:
  Bool.pick(U32, U32.is_eq(l, 0), i, ((i + 1 : U32) * tr.pow(l) : U32))

# the two nodes a node merges (none for a message's)
def tr.halves(p: tr.P) -> List<&2, tr.P>:
  match p:
    case tr.P{+l, +i}:
      Bool.pick(List<&2, tr.P>, U32.is_eq(l, 0), [],
        [tr.P{(l - 1 : U32), (2 * i : U32)}, tr.P{(l - 1 : U32), (2 * i + 1 : U32)}])

def tr.up(p: tr.P) -> tr.P:
  match p:
    case tr.P{+l, +i}:
      tr.P{(l + 1 : U32), U32.shr(i)}

def tr.sibling(p: tr.P) -> tr.P:
  match p:
    case tr.P{+l, +i}:
      tr.P{l, U32.xor(i, 1)}

# the tree's roots: a node per power of two in the count, largest first
def tr.roots.go(n: Nat, +l: U32, +id: U32, +count: U32) -> List<&2, tr.P>:
  match n:
    case 0n:
      []
    case 1n+k:
      +fits = U32.is_le((id + tr.pow(l) : U32), count)
      +rest = tr.roots.go(k, (l - 1 : U32), Bool.pick(U32, fits, (id + tr.pow(l) : U32), id), count)
      Bool.pick(List<&2, tr.P>, fits, tr.P{l, U32.div(id, tr.pow(l))} <> rest, rest)

def tr.roots(+count: U32) -> List<&2, tr.P>:
  tr.roots.go(31n, 30, 0, count)

# its zoom target, "id+n"
def tr.ref(+p: tr.P) -> String:
  U32.show(tr.first(p)) ++ "+" ++ U32.show(tr.pow(tr.l(p)))

# a view's line: "id+n|text", newlines flattened
def tr.line(+p: tr.P, text: String) -> String:
  tr.ref(p) ++ "|" ++ T.tx.flat(text)

# Tasks ---------------------------------------------------------------------
#
# A compaction's task, before its <input>: one message to compress (level 0),
# or two lines to merge. The ruler is NODE dashes (the compactor copied a
# sample line's content).

def tr.ruler() -> String:
  T.tx.repeat("-", U32.to_nat(tr.node()))

def tr.leaf(+id: String) -> String:
  "Compaction: compress message " ++ id ++ " into one line of at most " ++ U32.show(tr.node()) ++ " bytes\n(about 70 words), the length of this ruler:\n" ++ tr.ruler() ++ "\n<input>\n"

def tr.merge(+a: String, +b: String, +id: String, +end: String) -> String:
  "Compaction: merge lines " ++ a ++ " and " ++ b ++ ", adjacent, into one line of at most\n" ++ U32.show(tr.node()) ++ " bytes (about 70 words), the length of this ruler:\n" ++ tr.ruler() ++ "\n<chat> may hold their messages, " ++ id ++ " to " ++ end ++ ", in more detail: take details\nof them from there too.\n<input>\n"

# node (l,i)'s task, but its input (Memory.task)
def tr.task(+p: tr.P) -> String:
  +a = tr.first(p)
  +n = U32.shr(tr.pow(tr.l(p)))
  Bool.pick(String, U32.is_eq(tr.l(p), 0), tr.leaf(U32.show(a)),
    tr.merge(U32.show(a) ++ "+" ++ U32.show(n), U32.show((a + n : U32)) ++ "+" ++ U32.show(n), U32.show(a), U32.show(tr.last(p))))

# "Too long" (Memory.over): a retry's note for a line past NODE bytes
def tr.over(+line: String) -> String:
  "Too long: your last line for this <input> was " ++ U32.show(T.tx.bytes(line)) ++ " bytes,\nover the " ++ U32.show(tr.node()) ++ "-byte limit. Write the whole line again, cutting just\nenough of the least valuable items to fit before this cut:\n" ++ T.tx.cut(line, tr.node()) ++ "| \u{2190} LIMIT"
