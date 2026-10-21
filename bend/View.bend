
import Base
import ./Text.bend as T
import ./IMap.bend as I
import ./Tree.bend as R

# View: a list of nodes covering the chat to its end, oldest first, each a
# line of what a call reads (Memory.ts). Each message a view reaches appends
# its node; past `high` bytes a batch merges the most due adjacent siblings
# whose parent is built, down to half. All of it is pure: the nodes built are
# the map `nodes` (slot to text and size), handed in.
#
# Every def is prefixed `vw.` (a program's defs share one namespace).

type vw.Node is Data:
  vw.Node{text: String, size: U32}

type vw.V is Data:
  vw.V{parts: List<&2, R.tr.P>, size: U32, batch: Bool, high: U32}

# a block of a call's input, and whether the cache mark goes on it
type vw.B is Data:
  vw.B{text: String, mark: Bool}

def vw.wait() -> String:
  "(not summarized yet: zoom it)"

def vw.none() -> U32:
  4294967295

def vw.built(nodes: I.im.M<vw.Node>, +p: R.tr.P) -> Bool:
  I.im.has(vw.Node, nodes, R.tr.slot.of(p))

def vw.node.size(m: Maybe<&2, vw.Node>) -> U32:
  match m:
    case Some{vw.Node{t, s}}:
      s
    case None{}:
      0

def vw.node.text(m: Maybe<&2, vw.Node>) -> String:
  match m:
    case Some{vw.Node{t, s}}:
      t
    case None{}:
      vw.wait()

# a line's bytes as calls get it: none until built (Memory.size)
def vw.size(nodes: I.im.M<vw.Node>, +p: R.tr.P) -> U32:
  vw.node.size(I.im.get(vw.Node, nodes, R.tr.slot.of(p)))

# its text if built, else the wait note (Memory.text)
def vw.text(nodes: I.im.M<vw.Node>, +p: R.tr.P) -> String:
  vw.node.text(I.im.get(vw.Node, nodes, R.tr.slot.of(p)))

def vw.parts(v: vw.V) -> List<&2, R.tr.P>:
  match v:
    case vw.V{parts, size, batch, high}:
      parts

# Ends and covers ------------------------------------------------------------

def vw.end.go(ps: List<&2, R.tr.P>, +last: U32) -> U32:
  match ps:
    case []:
      last
    case p <> t:
      vw.end.go(t, (R.tr.last(p) + 1 : U32))

# the message after a view's last line (Memory.end)
def vw.end(ps: List<&2, R.tr.P>) -> U32:
  vw.end.go(ps, 0)

# the index of the line holding message id (past the end: the length)
def vw.cover(ps: List<&2, R.tr.P>, +id: U32) -> Nat:
  match ps:
    case []:
      0n
    case +p <> t:
      Bool.pick(Nat, U32.is_lt(R.tr.last(p), id), 1n+vw.cover(t, id), 0n)

def vw.sizes(+nodes: I.im.M<vw.Node>, ps: List<&2, R.tr.P>) -> U32:
  match ps:
    case []:
      0
    case p <> t:
      (vw.size(nodes, p) + vw.sizes(nodes, t) : U32)

# the messages [a, z) as level-0 parts
def vw.msgs(n: Nat, +a: U32) -> List<&2, R.tr.P>:
  match n:
    case 0n:
      []
    case 1n+k:
      R.tr.P{0, a} <> vw.msgs(k, (a + 1 : U32))

# a view to message `end`: its lines from it dropped, the messages to it
# appended (Memory.reach)
def vw.reach(+nodes: I.im.M<vw.Node>, v: vw.V, +end: U32) -> vw.V:
  match v:
    case vw.V{+parts, +size, batch, high}:
      +k = vw.cover(parts, end)
      +kept = List.take(&2, R.tr.P, parts, k)
      +from = vw.end(kept)
      +more = vw.msgs(U32.to_nat((end - U32.min(end, from) : U32)), from)
      vw.V{List.append(&2, R.tr.P, kept, more),
        ((size - vw.sizes(nodes, List.drop(&2, R.tr.P, parts, k)) : U32) + vw.sizes(nodes, more) : U32), batch, high}

def vw.before(+ps: List<&2, R.tr.P>, +first: U32) -> Bool:
  match ps:
    case []:
      False{}
    case p <> t:
      U32.is_lt(R.tr.last(p), first)

# whether the view holds node p or one under it, or will (Memory.held):
# the line covering p's first message is at p's level or below (none: will)
def vw.held.in(ps: List<&2, R.tr.P>, past: Bool, +first: U32, +l: U32) -> Bool:
  match ps past:
    case Nil{} _:
      True{}
    case p <> +t True{}:
      vw.held.in(t, vw.before(t, first), first, l)
    case p <> t False{}:
      U32.is_le(R.tr.l(p), l)

def vw.held(+a: List<&2, R.tr.P>, +b: List<&2, R.tr.P>, +p: R.tr.P) -> Bool:
  Bool.or(vw.held.in(a, vw.before(a, R.tr.first(p)), R.tr.first(p), R.tr.l(p)), vw.held.in(b, vw.before(b, R.tr.first(p)), R.tr.first(p), R.tr.l(p)))

# Merging -------------------------------------------------------------------
#
# A pair (a, b) of adjacent siblings at view position k is due by
# (T + 1) / 2^l - i, T the view's end: its age from its last message, in
# halves of its level. That is w + r / 2^l with w = (T + 1) >> l minus i and
# r = (T + 1) mod 2^l; compared exactly as w, then r scaled to 2^31, then the
# position (the oldest first).

type vw.Ent is Data:
  vw.Ent{w: U32, f: U32, k: U32, a: R.tr.P, b: R.tr.P}

def vw.over(x: vw.Ent, y: vw.Ent) -> Bool:
  match x y:
    case vw.Ent{+w1, +f1, +k1, a1, b1} vw.Ent{+w2, +f2, +k2, a2, b2}:
      Bool.or(U32.is_gt(w1, w2), Bool.and(U32.is_eq(w1, w2),
        Bool.or(U32.is_gt(f1, f2), Bool.and(U32.is_eq(f1, f2), U32.is_lt(k1, k2)))))

# a leftist heap, the most due on top
type vw.H is Data:
  vw.HE{}
  vw.HN{rank: U32, e: vw.Ent, l: vw.H, r: vw.H}

def vw.h.rank(+h: vw.H) -> U32:
  match h:
    case vw.HE{}:
      0
    case vw.HN{r, e, x, y}:
      r

def vw.h.mk(+e: vw.Ent, +x: vw.H, +y: vw.H) -> vw.H:
  Bool.pick(vw.H, U32.is_ge(vw.h.rank(x), vw.h.rank(y)), vw.HN{(vw.h.rank(y) + 1 : U32), e, x, y},
    vw.HN{(vw.h.rank(x) + 1 : U32), e, y, x})

# whether a's top goes before b's (a heap with no top never does)
def vw.h.wins(+a: vw.H, +b: vw.H) -> Bool:
  match a b:
    case _ vw.HE{}:
      True{}
    case vw.HE{} _:
      False{}
    case vw.HN{r1, e1, x1, y1} vw.HN{r2, e2, x2, y2}:
      vw.over(e1, e2)

def vw.h.meld(fuel: Nat, a: vw.H, b: vw.H, aw: Bool) -> vw.H:
  match fuel a b aw:
    case _ vw.HE{} _ _:
      b
    case _ vw.HN{ra, ea, xa, ya} vw.HE{} _:
      vw.HN{ra, ea, xa, ya}
    case 1n+f vw.HN{ra, ea, xa, +ya} vw.HN{rb, eb, xb, yb} True{}:
      +bb = {vw.HN{rb, eb, xb, yb} : vw.H}
      vw.h.mk(ea, xa, vw.h.meld(f, ya, bb, vw.h.wins(ya, bb)))
    case 1n+f vw.HN{ra, ea, xa, ya} vw.HN{rb, eb, xb, +yb} False{}:
      +aa = {vw.HN{ra, ea, xa, ya} : vw.H}
      vw.h.mk(eb, xb, vw.h.meld(f, aa, yb, vw.h.wins(aa, yb)))
    case 0n vw.HN{ra, ea, xa, ya} vw.HN{rb, eb, xb, yb} _:
      vw.HN{ra, ea, xa, ya}

def vw.h.fuel() -> Nat:
  64n

def vw.h.push(+h: vw.H, e: vw.Ent) -> vw.H:
  +one = {vw.HN{1, e, vw.HE{}, vw.HE{}} : vw.H}
  vw.h.meld(vw.h.fuel(), h, one, vw.h.wins(h, one))

# the heap without its top
def vw.h.pop(h: vw.H) -> vw.H:
  match h:
    case vw.HE{}:
      vw.HE{}
    case vw.HN{r, e, +x, +y}:
      vw.h.meld(vw.h.fuel(), x, y, vw.h.wins(x, y))

# A position of the view being merged: its part, whether it is still there
# (a part merged into its left sibling's is not), its neighbours.
type vw.Cell is Data:
  vw.Cell{p: R.tr.P, alive: Bool, next: U32, prev: U32}

def vw.cell(cells: I.im.M<vw.Cell>, +k: U32) -> Maybe<&2, vw.Cell>:
  I.im.get(vw.Cell, cells, k)

def vw.cells.go(ps: List<&2, R.tr.P>, +k: U32, acc: I.im.M<vw.Cell>) -> I.im.M<vw.Cell>:
  match ps:
    case []:
      acc
    case p <> t:
      vw.cells.go(t, (k + 1 : U32), I.im.set(vw.Cell, acc, k, vw.Cell{p, True{}, (k + 1 : U32), Bool.pick(U32, U32.is_eq(k, 0), vw.none(), (k - 1 : U32))}))

# what a pair offers, if it is one: a's index even, b its right sibling, their
# parent built
def vw.offer.pair(+nodes: I.im.M<vw.Node>, +t1: U32, +k: U32, a: R.tr.P, b: R.tr.P) -> Maybe<&2, vw.Ent>:
  match a b:
    case R.tr.P{+la, +ia} R.tr.P{+lb, +ib}:
      Bool.pick(Maybe<&2, vw.Ent>,
        Bool.and(Bool.and(U32.is_eq(U32.and(ia, 1), 0), U32.is_eq(lb, la)),
          Bool.and(U32.is_eq(ib, (ia + 1 : U32)), vw.built(nodes, R.tr.P{(la + 1 : U32), U32.shr(ia)}))),
        Some{vw.Ent{(U32.shrn(t1, U32.to_nat(la)) - ia : U32), U32.shln(U32.and(t1, (R.tr.pow(la) - 1 : U32)), U32.to_nat((31 - la : U32))), k, R.tr.P{la, ia}, R.tr.P{lb, ib}}},
        None{})

def vw.offer.b(+nodes: I.im.M<vw.Node>, +t1: U32, +k: U32, pa: R.tr.P, b: Maybe<&2, vw.Cell>) -> Maybe<&2, vw.Ent>:
  match b:
    case Some{vw.Cell{pb, True{}, nx, pv}}:
      vw.offer.pair(nodes, t1, k, pa, pb)
    case _:
      None{}

def vw.offer.at(+nodes: I.im.M<vw.Node>, +t1: U32, +k: U32, a: Maybe<&2, vw.Cell>, +cells: I.im.M<vw.Cell>) -> Maybe<&2, vw.Ent>:
  match a:
    case Some{vw.Cell{pa, True{}, +nx, pv}}:
      vw.offer.b(nodes, t1, k, pa, vw.cell(cells, nx))
    case _:
      None{}

def vw.offer.push(+h: vw.H, m: Maybe<&2, vw.Ent>) -> vw.H:
  match m:
    case Some{e}:
      vw.h.push(h, e)
    case None{}:
      h

# the heap with position k's pair, if it makes one (Memory.merge offer)
def vw.offer(+nodes: I.im.M<vw.Node>, +t1: U32, +cells: I.im.M<vw.Cell>, +h: vw.H, +k: U32) -> vw.H:
  Bool.pick(vw.H, U32.is_eq(k, vw.none()), h,
    vw.offer.push(h, vw.offer.at(nodes, t1, k, vw.cell(cells, k), cells)))

def vw.offers(+nodes: I.im.M<vw.Node>, +t1: U32, +cells: I.im.M<vw.Cell>, n: Nat, +k: U32, +h: vw.H) -> vw.H:
  match n:
    case 0n:
      h
    case 1n+m:
      vw.offers(nodes, t1, cells, m, (k + 1 : U32), vw.offer(nodes, t1, cells, h, k))

# A merge under way: the positions, the heap, the bytes, the parts merged
# away, and whether it is done.
type vw.Mg is Data:
  vw.Mg{cells: I.im.M<vw.Cell>, heap: vw.H, size: U32, gone: List<&2, R.tr.P>, done: Bool}

def vw.cell.set(+cells: I.im.M<vw.Cell>, +k: U32, c: vw.Cell) -> I.im.M<vw.Cell>:
  I.im.set(vw.Cell, cells, k, c)

def vw.cell.kill(+cells: I.im.M<vw.Cell>, +j: U32, c: Maybe<&2, vw.Cell>) -> I.im.M<vw.Cell>:
  match c:
    case Some{vw.Cell{p, a, n, v}}:
      I.im.set(vw.Cell, cells, j, vw.Cell{p, False{}, n, v})
    case None{}:
      cells

def vw.cell.prev(+cells: I.im.M<vw.Cell>, +j: U32, +k: U32, c: Maybe<&2, vw.Cell>) -> I.im.M<vw.Cell>:
  match c:
    case Some{vw.Cell{p, a, n, v}}:
      I.im.set(vw.Cell, cells, j, vw.Cell{p, a, n, k})
    case None{}:
      cells

def vw.cell.next(c: Maybe<&2, vw.Cell>) -> U32:
  match c:
    case Some{vw.Cell{p, a, n, v}}:
      n
    case None{}:
      vw.none()

def vw.cell.prev.of(c: Maybe<&2, vw.Cell>) -> U32:
  match c:
    case Some{vw.Cell{p, a, n, v}}:
      v
    case None{}:
      vw.none()

def vw.fresh.c(+b: R.tr.P, c: Maybe<&2, vw.Cell>) -> Bool:
  match c:
    case Some{vw.Cell{pb, True{}, nx, pv}}:
      R.tr.eq(pb, b)
    case _:
      False{}

def vw.fresh.b(+cells: I.im.M<vw.Cell>, +a: R.tr.P, +b: R.tr.P, c: Maybe<&2, vw.Cell>) -> Bool:
  match c:
    case Some{vw.Cell{pa, True{}, +nx, pv}}:
      Bool.and(R.tr.eq(pa, a), vw.fresh.c(b, vw.cell(cells, nx)))
    case _:
      False{}

# is the pair (a at k, b after it) still there
def vw.fresh(+cells: I.im.M<vw.Cell>, +k: U32, +a: R.tr.P, +b: R.tr.P) -> Bool:
  vw.fresh.b(cells, a, b, vw.cell(cells, k))

# the pair at k merged: k holds their parent, j = next[k] goes, the links
# close over it, both halves are gone, and the pairs either side are offered
def vw.mg.apply(+nodes: I.im.M<vw.Node>, +t1: U32, +cells: I.im.M<vw.Cell>, h: vw.H, +size: U32, gone: List<&2, R.tr.P>, +k: U32, +a: R.tr.P, +b: R.tr.P) -> vw.Mg:
  +ck = vw.cell(cells, k)
  +j = vw.cell.next(ck)
  +cj = vw.cell(cells, j)
  +nj = vw.cell.next(cj)
  +up = R.tr.up(a)
  +c1 = vw.cell.set(cells, k, vw.Cell{up, True{}, nj, vw.cell.prev.of(ck)})
  +c2 = vw.cell.kill(c1, j, cj)
  +c3 = vw.cell.prev(c2, nj, k, vw.cell(c2, nj))
  +h1 = vw.offer(nodes, t1, c3, h, vw.cell.prev.of(ck))
  vw.Mg{c3, vw.offer(nodes, t1, c3, h1, k), ((size - vw.size(nodes, a) - vw.size(nodes, b) : U32) + vw.size(nodes, up) : U32), a <> b <> gone, False{}}

def vw.mg.take(fresh: Bool, +nodes: I.im.M<vw.Node>, +t1: U32, +cells: I.im.M<vw.Cell>, h: vw.H, +size: U32, gone: List<&2, R.tr.P>, e: vw.Ent) -> vw.Mg:
  match fresh e:
    case True{} vw.Ent{w, f, +k, +a, +b}:
      vw.mg.apply(nodes, t1, cells, h, size, gone, k, a, b)
    case False{} _:
      vw.Mg{cells, h, size, gone, False{}}

def vw.mg.fresh(+cells: I.im.M<vw.Cell>, e: vw.Ent) -> Bool:
  match e:
    case vw.Ent{w, f, +k, +a, +b}:
      vw.fresh(cells, k, a, b)

def vw.mg.top(go: Bool, +nodes: I.im.M<vw.Node>, +t1: U32, +cells: I.im.M<vw.Cell>, h: vw.H, +size: U32, gone: List<&2, R.tr.P>) -> vw.Mg:
  match go h:
    case True{} vw.HN{r, +e, x, y}:
      vw.mg.take(vw.mg.fresh(cells, e), nodes, t1, cells, vw.h.pop(vw.HN{r, e, x, y}), size, gone, e)
    case _ _:
      vw.Mg{cells, vw.HE{}, size, gone, True{}}

# one step: the most due pair merged if it is still there, while the view is
# over `low` bytes and pairs are left
def vw.mg.step(+nodes: I.im.M<vw.Node>, +t1: U32, +low: U32, m: vw.Mg) -> vw.Mg:
  match m:
    case vw.Mg{+cells, +h, +size, gone, done}:
      vw.mg.top(Bool.and(U32.is_gt(size, low), Bool.not(U32.is_eq(vw.h.rank(h), 0))), nodes, t1, cells, h, size, gone)

def vw.mg.go(fuel: Nat, +nodes: I.im.M<vw.Node>, +t1: U32, +low: U32, m: vw.Mg) -> vw.Mg:
  match fuel m:
    case _ vw.Mg{c, h, s, g, True{}}:
      vw.Mg{c, h, s, g, True{}}
    case 0n vw.Mg{c, h, s, g, d}:
      vw.Mg{c, h, s, g, True{}}
    case 1n+f vw.Mg{c, h, s, g, False{}}:
      vw.mg.go(f, nodes, t1, low, vw.mg.step(nodes, t1, low, vw.Mg{c, h, s, g, False{}}))

def vw.mg.keep(c: Maybe<&2, vw.Cell>, rest: List<&2, R.tr.P>) -> List<&2, R.tr.P>:
  match c:
    case Some{vw.Cell{p, True{}, n, v}}:
      p <> rest
    case _:
      rest

# the parts still there, in order
def vw.mg.parts(n: Nat, +cells: I.im.M<vw.Cell>, +k: U32) -> List<&2, R.tr.P>:
  match n:
    case 0n:
      []
    case 1n+m:
      vw.mg.keep(vw.cell(cells, k), vw.mg.parts(m, cells, (k + 1 : U32)))

# A view merged: its parts, size, and the parts merged away.
type vw.Merged is Data:
  vw.Merged{parts: List<&2, R.tr.P>, size: U32, gone: List<&2, R.tr.P>}

def vw.mg.fin(+n: Nat, m: vw.Mg) -> vw.Merged:
  match m:
    case vw.Mg{+c, h, s, g, d}:
      vw.Merged{vw.mg.parts(n, c, 0), s, g}

# a view's most due pairs merged down to half, as their parents allow
# (Memory.merge)
def vw.merge(+nodes: I.im.M<vw.Node>, v: vw.V) -> vw.Merged:
  match v:
    case vw.V{+parts, size, batch, +high}:
      +n = List.length(&2, R.tr.P, parts)
      +t1 = (vw.end(parts) + 1 : U32)
      +cells = vw.cells.go(parts, 0, I.im.new(vw.Cell))
      +h = vw.offers(nodes, t1, cells, n, 0, vw.HE{})
      vw.mg.fin(n, vw.mg.go(Nat.add(Nat.mul(n, 4n), 4n), nodes, t1, U32.shr(high), vw.Mg{cells, h, size, [], False{}}))

# Blocks ----------------------------------------------------------------------

def vw.lines.put(ok: Bool, +nodes: I.im.M<vw.Node>, +p: R.tr.P, rest: List<&2, String>) -> List<&2, String>:
  match ok:
    case True{}:
      String.append(R.tr.line(p, vw.text(nodes, p)), "\n") <> rest
    case False{}:
      rest

# the lines of parts built that end before message `end`, each "line\n"
def vw.lines(+nodes: I.im.M<vw.Node>, ps: List<&2, R.tr.P>, +end: U32) -> List<&2, String>:
  match ps:
    case []:
      []
    case +p <> t:
      vw.lines.put(Bool.and(U32.is_lt(R.tr.last(p), end), vw.built(nodes, p)), nodes, p, vw.lines(nodes, t, end))

# the whole groups of four lines, the last one marked, then the rest
def vw.groups(n: Nat, xs: List<&2, String>, +whole: Nat, +k: Nat) -> List<&2, vw.B>:
  match n:
    case 0n:
      [vw.B{String.append(T.tx.concat(xs), "</chat>\n"), False{}}]
    case 1n+m:
      +x = xs
      vw.B{T.tx.concat(List.take(&2, String, x, 4n)), Nat.is_eq(1n+k, whole)} <> vw.groups(m, List.drop(&2, String, x, 4n), whole, 1n+k)

# the view's lines built before message `end`, in blocks of four (the last
# cut short), one marked: the last whole one, else the opening one
# (Memory.view)
def vw.blocks(+nodes: I.im.M<vw.Node>, ps: List<&2, R.tr.P>, +end: U32) -> List<&2, vw.B>:
  +lines = vw.lines(nodes, ps, end)
  +whole = Nat.div(List.length(&2, String, lines), 4n)
  vw.B{"<chat>\n", Nat.is_eq(whole, 0n)} <> vw.groups(whole, lines, whole, 0n)
