
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./Clock.bend as C
import ./IMap.bend as I
import ./Tree.bend as R
import ./View.bend as V
import ./Store.bend as St

# Memory: the chat, kept forever, and the views of it every call sees, as
# UniiChat's Memory.ts keeps them, each function ported one to one (the
# differential test, tools/memdiff, runs both side by side). Sizes are bytes
# of UTF-8.
#
# Over the messages grows the binary tree (Tree.bend). A node whose source
# fits in NODE bytes is its source; any other is a compaction's, a job this
# module only describes (Job): the hub runs it (Compact.bend) and hands the
# line back (me.built). Two views (View.bend): the chat's, to the last
# message, past 128 KB merged to half; the compactions', to the first node
# not built, past 32 KB. The memory holds only the views' nodes and those
# built above them; any other line is read by its index (Store.bend).
#
# mugen keeps one side: UniiChat's imports (side 1) come later. Every def
# is prefixed `me.` (a program's defs share one namespace).

def me.high() -> U32:
  128000

def me.seen.high() -> U32:
  32000

# What view.json keeps besides the views: the chat's model pick, the user's
# goal, the work that ran.
type me.Kept is Data:
  me.Kept{pick: J.Json, goal: Maybe<&2, String>, work: List<&2, String>}

# how far each log is indexed
type me.Ends is Data:
  me.Ends{main: St.st.End, tree: St.st.End}

# The memory: its directory, whether writes are fsynced, the jobs at once;
# the messages logged whole and the pages open after them; the nodes kept
# (slot to text); the two views; the nodes ready to build by level; those
# building; what view.json keeps; how far each log is indexed.
type me.Mem is Data:
  me.Mem{dir: String, sync: U32, jobs: U32, count: U32, open: U32, nodes: I.im.M<V.vw.Node>, view: V.vw.V, seen: V.vw.V, ready: List<&2, List<&2, U32>>, busy: I.im.M<Unit>, nbusy: U32, kept: me.Kept, ends: me.Ends}

# a message to log: its kind, text, the line it logs with (its node, if its
# own), whether more pages follow
type me.Msg is Data:
  me.Msg{kind: String, text: String, line: Maybe<&2, String>, more: Bool}

def me.msg(+kind: String, text: String) -> me.Msg:
  me.Msg{kind, text, None{}, False{}}

# A compaction to run: its node, its call's blocks (the compactions' view
# to it, then its task), its source (clipped to NODE bytes if no line comes).
type me.Job is Data:
  me.Job{l: U32, i: U32, blocks: List<&2, V.vw.B>, text: String}

# a node whose source fits: built at once, no call
type me.Free is Data:
  me.Free{p: R.tr.P, text: String}

# Fields --------------------------------------------------------------------

def me.dir(m: me.Mem) -> String:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      d

def me.count(m: me.Mem) -> U32:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      c

def me.nodes(m: me.Mem) -> I.im.M<V.vw.Node>:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      n

def me.view(m: me.Mem) -> V.vw.V:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      v

def me.seen(m: me.Mem) -> V.vw.V:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      s

def me.kept(m: me.Mem) -> me.Kept:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      k

def me.ready.of(m: me.Mem) -> List<&2, List<&2, U32>>:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      r

def me.nbusy(m: me.Mem) -> U32:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      nb

def me.with.kept(m: me.Mem, k2: me.Kept) -> me.Mem:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k2, e}

def me.kept.goal(k: me.Kept) -> Maybe<&2, String>:
  match k:
    case me.Kept{p, g, w}:
      g

def me.kept.pick(k: me.Kept) -> J.Json:
  match k:
    case me.Kept{p, g, w}:
      p

def me.kept.work(k: me.Kept) -> List<&2, String>:
  match k:
    case me.Kept{p, g, w}:
      w

# Ready queues ----------------------------------------------------------------
#
# The nodes not built whose halves are, by level, each level's in order
# (Memory.ready): a sorted list, one per level.

def me.q.cmp(+xs: List<&2, U32>, +i: U32) -> Cmp:
  match xs:
    case []:
      GT{}
    case x <> t:
      U32.cmp(x, i)

def me.q.set(xs: List<&2, U32>, c: Cmp, +i: U32, +on: Bool) -> List<&2, U32>:
  match xs c:
    case Nil{} _:
      Bool.pick(List<&2, U32>, on, [i], [])
    case +x <> +t LT{}:
      x <> me.q.set(t, me.q.cmp(t, i), i, on)
    case +x <> +t EQ{}:
      Bool.pick(List<&2, U32>, on, x <> t, t)
    case +x <> +t GT{}:
      Bool.pick(List<&2, U32>, on, i <> x <> t, x <> t)

# node (l,i) ready (on), or no more (built)
def me.lv.set(l: Nat, lv: List<&2, List<&2, U32>>, +i: U32, +on: Bool) -> List<&2, List<&2, U32>>:
  match l lv:
    case 0n Nil{}:
      [me.q.set([], GT{}, i, on)]
    case 0n +q <> t:
      me.q.set(q, me.q.cmp(q, i), i, on) <> t
    case 1n+k Nil{}:
      [] <> me.lv.set(k, [], i, on)
    case 1n+k q <> t:
      q <> me.lv.set(k, t, i, on)

def me.ready.set(lv: List<&2, List<&2, U32>>, p: R.tr.P, +on: Bool) -> List<&2, List<&2, U32>>:
  match p:
    case R.tr.P{l, +i}:
      me.lv.set(U32.to_nat(l), lv, i, on)

# the message of the (k+1)th node of level 0 not built, else the count
# (Memory.first)
def me.first(+lv: List<&2, List<&2, U32>>, +count: U32, +k: Nat) -> U32:
  match lv:
    case []:
      count
    case q <> t:
      Maybe.default(&2, U32, List.get(&2, U32, q, k), count)

# Nodes -----------------------------------------------------------------------

def me.built(+nodes: I.im.M<V.vw.Node>, +l: U32, +i: U32) -> Bool:
  I.im.has(V.vw.Node, nodes, R.tr.slot(l, i))

def me.node.got(m: Maybe<&2, V.vw.Node>) -> Maybe<&2, String>:
  match m:
    case Some{V.vw.Node{t, s}}:
      Some{t}
    case None{}:
      None{}

def me.node.or(+dir: String, +slot: U32, m: Maybe<&2, String>) -> IO(Maybe<&2, String>):
  match m:
    case Some{t}:
      IO.pure(Maybe<&2, String>, Some{t})
    case None{}:
      St.st.node(dir, slot)

# node p's text, kept or from its file; None: not built (Memory.node)
def me.node(+dir: String, +nodes: I.im.M<V.vw.Node>, +p: R.tr.P) -> IO(Maybe<&2, String>):
  me.node.or(dir, R.tr.slot.of(p), me.node.got(I.im.get(V.vw.Node, nodes, R.tr.slot.of(p))))

def me.source.root(m: Maybe<&2, St.st.Root>) -> Maybe<&2, String>:
  match m:
    case Some{r}:
      Some{St.st.source(r)}
    case None{}:
      None{}

def me.source.two(a: Maybe<&2, String>, b: Maybe<&2, String>) -> Maybe<&2, String>:
  match a b:
    case Some{+x} Some{+y}:
      Some{String.append(T.tx.flat(x), "\n" ++ T.tx.flat(y))}
    case _ _:
      None{}

# what node (l,i) compresses: its message's line (level 0), else its halves'
# lines, flattened, one under the other (Memory.source)
def me.source(+dir: String, +nodes: I.im.M<V.vw.Node>, +p: R.tr.P) -> IO(Maybe<&2, String>):
  match p:
    case R.tr.P{+l, +i}:
      Bool.pick(IO(Maybe<&2, String>), U32.is_eq(l, 0),
        IO.bind(Maybe<&2, St.st.Root>, Maybe<&2, String>, St.st.message(dir, i), r => IO.pure(Maybe<&2, String>, me.source.root(r))),
        do IO<Maybe<&2, String>>:
          a : Maybe<&2, String> <- me.node(dir, nodes, R.tr.P{(l - 1 : U32), (2 * i : U32)})
          b : Maybe<&2, String> <- me.node(dir, nodes, R.tr.P{(l - 1 : U32), (2 * i + 1 : U32)})
          return me.source.two(a, b))


# The nodes under the roots not built whose sources are (Memory.todo): only
# nodes not built and their halves are visited (a stack, left half first).
def me.halves.built(+nodes: I.im.M<V.vw.Node>, hs: List<&2, R.tr.P>) -> Bool:
  match hs:
    case []:
      True{}
    case h <> t:
      Bool.and(V.vw.built(nodes, h), me.halves.built(nodes, t))

def me.todo.add(b: Bool, +nodes: I.im.M<V.vw.Node>, +p: R.tr.P, +acc: List<&2, R.tr.P>) -> List<&2, R.tr.P>:
  match b:
    case True{}:
      acc
    case False{}:
      Bool.pick(List<&2, R.tr.P>, me.halves.built(nodes, R.tr.halves(p)), p <> acc, acc)

def me.todo.push(b: Bool, +p: R.tr.P, t: List<&2, R.tr.P>) -> List<&2, R.tr.P>:
  match b:
    case True{}:
      t
    case False{}:
      List.append(&2, R.tr.P, R.tr.halves(p), t)

def me.todo.go(fuel: Nat, +nodes: I.im.M<V.vw.Node>, work: List<&2, R.tr.P>, acc: List<&2, R.tr.P>) -> List<&2, R.tr.P>:
  match fuel work:
    case _ Nil{}:
      acc
    case 0n _:
      acc
    case 1n+f +p <> t:
      +b = V.vw.built(nodes, p)
      me.todo.go(f, nodes, me.todo.push(b, p, t), me.todo.add(b, nodes, p, acc))

def me.todo(+count: U32, +nodes: I.im.M<V.vw.Node>) -> List<&2, R.tr.P>:
  me.todo.go(Nat.add(Nat.mul(U32.to_nat(count), 3n), 64n), nodes, R.tr.roots(count), [])

# The view under the roots, down from them, keeping the built nodes met:
# those of `keys` (none: any built), or messages (Memory.down).
def me.keys.has(+keys: Maybe<&2, I.im.M<Unit>>, +slot: U32) -> Bool:
  match keys:
    case None{}:
      True{}
    case Some{k}:
      I.im.has(Unit, k, slot)

def me.down.keep(+nodes: I.im.M<V.vw.Node>, +slot: U32, t: Maybe<&2, String>) -> I.im.M<V.vw.Node>:
  match t:
    case Some{+x}:
      I.im.set(V.vw.Node, nodes, slot, V.vw.Node{x, T.tx.bytes(x)})
    case None{}:
      nodes

def me.down.leaf(+keys: Maybe<&2, I.im.M<Unit>>, +p: R.tr.P, t: Maybe<&2, String>) -> Bool:
  match t:
    case Some{x}:
      Bool.or(U32.is_eq(R.tr.l(p), 0), me.keys.has(keys, R.tr.slot.of(p)))
    case None{}:
      U32.is_eq(R.tr.l(p), 0)

type me.Dv is Data:
  me.Dv{nodes: I.im.M<V.vw.Node>, parts: List<&2, R.tr.P>}

type me.Dn is Data:
  me.Dn{work: List<&2, R.tr.P>, out: List<&2, R.tr.P>}

def me.down.step(leaf: Bool, +p: R.tr.P, t: List<&2, R.tr.P>, out: List<&2, R.tr.P>) -> me.Dn:
  match leaf:
    case True{}:
      me.Dn{t, p <> out}
    case False{}:
      me.Dn{List.append(&2, R.tr.P, R.tr.halves(p), t), out}

def me.dn.work(d: me.Dn) -> List<&2, R.tr.P>:
  match d:
    case me.Dn{w, o}:
      w

def me.dn.out(d: me.Dn) -> List<&2, R.tr.P>:
  match d:
    case me.Dn{w, o}:
      o

def me.down.go(fuel: Nat, +dir: String, +keys: Maybe<&2, I.im.M<Unit>>, work: List<&2, R.tr.P>, +nodes: I.im.M<V.vw.Node>, out: List<&2, R.tr.P>) -> IO(me.Dv):
  match fuel work:
    case _ Nil{}:
      IO.pure(me.Dv, me.Dv{nodes, List.reverse(&2, R.tr.P, out)})
    case 0n _:
      IO.pure(me.Dv, me.Dv{nodes, List.reverse(&2, R.tr.P, out)})
    case 1n+f +p <> t:
      do IO<me.Dv>:
        +text : Maybe<&2, String> <- me.node(dir, nodes, p)
        +d : me.Dn = me.down.step(me.down.leaf(keys, p, text), p, t, out)
        me.down.go(f, dir, keys, me.dn.work(d), me.down.keep(nodes, R.tr.slot.of(p), text), me.dn.out(d))

# Views ---------------------------------------------------------------------

def me.view.with(v: V.vw.V, +parts: List<&2, R.tr.P>, +size: U32, +batch: Bool) -> V.vw.V:
  match v:
    case V.vw.V{p, s, b, high}:
      V.vw.V{parts, size, batch, high}

def me.v.size(v: V.vw.V) -> U32:
  match v:
    case V.vw.V{p, s, b, h}:
      s

def me.v.batch(v: V.vw.V) -> Bool:
  match v:
    case V.vw.V{p, s, b, h}:
      b

def me.v.high(v: V.vw.V) -> U32:
  match v:
    case V.vw.V{p, s, b, h}:
      h

def me.v.len(v: V.vw.V) -> Nat:
  match v:
    case V.vw.V{p, s, b, h}:
      List.length(&2, R.tr.P, p)

# A view fitted: it, the parts merged away, whether its lines or batch changed.
type me.Fit is Data:
  me.Fit{v: V.vw.V, gone: List<&2, R.tr.P>, changed: Bool}

def me.merged.size(m: V.vw.Merged) -> U32:
  match m:
    case V.vw.Merged{p, s, g}:
      s

def me.fit.apply(take: Bool, +v: V.vw.V, m: V.vw.Merged) -> V.vw.V & List<&2, R.tr.P>:
  match take m:
    case True{} V.vw.Merged{parts, size, gone}:
      (me.view.with(v, parts, size, me.v.batch(v)), gone)
    case False{} V.vw.Merged{parts, size, gone}:
      (v, [])

def me.fit.batch(+v: V.vw.V) -> V.vw.V:
  me.view.with(v, V.vw.parts(v), me.v.size(v), U32.is_gt(me.v.size(v), U32.shr(me.v.high(v))))

def me.fit.fin(+len0: Nat, +batch0: Bool, r: V.vw.V & List<&2, R.tr.P>) -> me.Fit:
  match r:
    case (+v0, gone):
      +v = me.fit.batch(v0)
      me.Fit{v, gone, Bool.or(Bool.not(Nat.is_eq(me.v.len(v), len0)), Bool.xor(me.v.batch(v), batch0))}

def me.fit.merge(go: Bool, +nodes: I.im.M<V.vw.Node>, +v: V.vw.V, +next: Bool) -> me.Fit:
  match go:
    case False{}:
      me.Fit{v, [], False{}}
    case True{}:
      +m = V.vw.merge(nodes, v)
      +size = me.v.size(v)
      +high = me.v.high(v)
      +bound = U32.max(U32.shr(high), Bool.pick(U32, U32.is_gt(size, high), (size - high : U32), 0))
      me.fit.fin(me.v.len(v), me.v.batch(v), me.fit.apply(Bool.or(next, U32.is_le(me.merged.size(m), bound)), v, m))

# one view fitted: past its high a batch merges it to half; a batch under
# way goes on at a message (Memory.fit)
def me.fit.one(+nodes: I.im.M<V.vw.Node>, +v: V.vw.V, +next: Bool) -> me.Fit:
  me.fit.merge(Bool.or(U32.is_gt(me.v.size(v), me.v.high(v)), Bool.and(next, me.v.batch(v))), nodes, v, next)

def me.fit.v(f: me.Fit) -> V.vw.V:
  match f:
    case me.Fit{v, g, c}:
      v

def me.fit.gone(f: me.Fit) -> List<&2, R.tr.P>:
  match f:
    case me.Fit{v, g, c}:
      g

def me.fit.changed(f: me.Fit) -> Bool:
  match f:
    case me.Fit{v, g, c}:
      c

# the nodes merged away that no view holds, let go
def me.let.go(gone: List<&2, R.tr.P>, +nodes: I.im.M<V.vw.Node>, +a: List<&2, R.tr.P>, +b: List<&2, R.tr.P>) -> I.im.M<V.vw.Node>:
  match gone:
    case []:
      nodes
    case +p <> t:
      me.let.go(t, Bool.pick(I.im.M<V.vw.Node>, V.vw.held(a, b, p), nodes, I.im.del(V.vw.Node, nodes, R.tr.slot.of(p))), a, b)

# Saving ----------------------------------------------------------------------

def me.parts.json(ps: List<&2, R.tr.P>) -> List<&2, J.Json>:
  match ps:
    case []:
      []
    case R.tr.P{l, i} <> t:
      J.JArr{[J.js.u32(l), J.js.u32(i)]} <> me.parts.json(t)

def me.goal.json(g: Maybe<&2, String>) -> J.Json:
  match g:
    case Some{x}:
      J.JStr{x}
    case None{}:
      J.JNull{}

def me.strs.json(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case []:
      []
    case x <> t:
      J.JStr{x} <> me.strs.json(t)

def me.end.json(e: St.st.End) -> J.Json:
  match e:
    case St.st.End{d, a}:
      J.JArr{[J.js.u32(d), J.js.u32(a)]}

# view.json as UniiChat writes it, but "main" and "tree" [0, 0]: mugen's
# indexes are its own, so UniiChat makes its own anew on load
def me.view.json(v: V.vw.V, s: V.vw.V, k: me.Kept) -> String:
  match v s k:
    case V.vw.V{vp, vs, vb, vh} V.vw.V{sp, ss, sb, sh} me.Kept{pick, goal, work}:
      J.js.write(J.JObj{[J.JKv{"parts", J.JArr{me.parts.json(vp)}}, J.JKv{"batch", J.JBool{vb}},
        J.JKv{"seen", J.JObj{[J.JKv{"parts", J.JArr{me.parts.json(sp)}}, J.JKv{"batch", J.JBool{sb}}]}},
        J.JKv{"pick", pick}, J.JKv{"goal", me.goal.json(goal)}, J.JKv{"work", J.JArr{me.strs.json(work)}},
        J.JKv{"main", J.JArr{[J.js.u32(0), J.js.u32(0)]}}, J.JKv{"tree", J.JArr{[J.js.u32(0), J.js.u32(0)]}}]})

def me.idx.json(e: me.Ends) -> String:
  match e:
    case me.Ends{a, b}:
      J.js.write(J.JObj{[J.JKv{"v", J.js.u32(1)}, J.JKv{"main", me.end.json(a)}, J.JKv{"tree", me.end.json(b)}]})

# view.json and idx.json, each written whole, then moved in place
def me.save(+m: me.Mem) -> IO(Unit):
  match m:
    case me.Mem{+d, +sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      do IO<Unit>:
        Unit <- S.mu.must(Unit, "save view.json", S.mu.save(d ++ "/view.json", me.view.json(v, s, k), sy))
        S.mu.must(Unit, "save idx.json", S.mu.save(d ++ "/idx.json", me.idx.json(e), sy))

def me.save.if(changed: Bool, +m: me.Mem) -> IO(me.Mem):
  match changed:
    case True{}:
      IO.bind(Unit, me.Mem, me.save(m), u => IO.pure(me.Mem, m))
    case False{}:
      IO.pure(me.Mem, m)

# each view to its end; past its high, or at a message while a batch is under
# way, merged; the nodes merged away let go; view.json saved if a view's lines
# changed (Memory.fit)
def me.fit(m: me.Mem, +next: Bool) -> IO(me.Mem):
  match m:
    case me.Mem{d, sy, jb, +c, o, +n, v, s, +r, b, nb, k, e}:
      +v1 = V.vw.reach(n, v, c)
      +s1 = V.vw.reach(n, s, U32.min(c, me.first(r, c, 0n)))
      +fv = me.fit.one(n, v1, next)
      +fs = me.fit.one(n, s1, next)
      +v2 = me.fit.v(fv)
      +s2 = me.fit.v(fs)
      +n2 = me.let.go(me.fit.gone(fs), me.let.go(me.fit.gone(fv), n, V.vw.parts(v2), V.vw.parts(s2)), V.vw.parts(v2), V.vw.parts(s2))
      me.save.if(Bool.or(me.fit.changed(fv), me.fit.changed(fs)), me.Mem{d, sy, jb, c, o, n2, v2, s2, r, b, nb, k, e})

# Storing ---------------------------------------------------------------------

def me.free.recs(fs: List<&2, me.Free>) -> List<&2, St.st.Rec>:
  match fs:
    case []:
      []
    case me.Free{R.tr.P{+l, +i}, +text} <> t:
      +size = T.tx.bytes(text)
      St.st.Rec{R.tr.slot(l, i), J.js.write(St.st.node.json(l, i, text, size)), size} <> me.free.recs(t)

# a view's size grows by a message's node built (its line was there, empty)
def me.grow(+v: V.vw.V, +p: R.tr.P, +bytes: U32) -> V.vw.V:
  Bool.pick(V.vw.V, Bool.and(U32.is_eq(R.tr.l(p), 0), U32.is_lt(R.tr.i(p), V.vw.end(V.vw.parts(v)))),
    me.view.with(v, V.vw.parts(v), (me.v.size(v) + bytes : U32), me.v.batch(v)), v)

type me.Kp is Data:
  me.Kp{nodes: I.im.M<V.vw.Node>, ready: List<&2, List<&2, U32>>, view: V.vw.V, seen: V.vw.V}

# the nodes built kept, out of their queues, and the views' sizes grown
def me.keep(fs: List<&2, me.Free>, +n: I.im.M<V.vw.Node>, +r: List<&2, List<&2, U32>>, +v: V.vw.V, +s: V.vw.V) -> me.Kp:
  match fs:
    case []:
      me.Kp{n, r, v, s}
    case me.Free{+p, +text} <> t:
      +size = T.tx.bytes(text)
      me.keep(t, I.im.set(V.vw.Node, n, R.tr.slot.of(p), V.vw.Node{text, size}), me.ready.set(r, p, False{}), me.grow(v, p, size), me.grow(s, p, size))

# each node built whose sibling is: its parent ready, if not built
def me.ups(fs: List<&2, me.Free>, +n: I.im.M<V.vw.Node>, +r: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match fs:
    case []:
      r
    case me.Free{+p, text} <> t:
      +up = R.tr.up(p)
      me.ups(t, n, Bool.pick(List<&2, List<&2, U32>>, Bool.and(V.vw.built(n, R.tr.sibling(p)), Bool.not(V.vw.built(n, up))), me.ready.set(r, up, True{}), r))

def me.store.fin(m: me.Mem, +fs: List<&2, me.Free>, kp: me.Kp, +tree: St.st.End) -> me.Mem:
  match m kp:
    case me.Mem{d, sy, jb, c, o, n0, v0, s0, r0, b, nb, k, me.Ends{main, t0}} me.Kp{+n, r, v, s}:
      me.Mem{d, sy, jb, c, o, n, v, s, me.ups(fs, n, r), b, nb, k, me.Ends{main, tree}}

# nodes built: logged in one write, kept (Memory.store)
def me.store(m: me.Mem, +day: U32, +fs: List<&2, me.Free>) -> IO(me.Mem):
  match m:
    case me.Mem{+d, +sy, jb, c, o, +n, +v, +s, +r, b, nb, k, e}:
      do IO<me.Mem>:
        +at : U32 <- St.st.log(d, "tree", day, sy, me.free.recs(fs))
        return me.store.fin(me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}, fs, me.keep(fs, n, r, v, s), St.st.End{day, at})

# Jobs ------------------------------------------------------------------------

# the nodes of each level ready up to message `end`, as (ctx, part)
def me.cands.q(+l: U32, q: List<&2, U32>, +end: U32) -> List<&2, R.tr.P>:
  match q:
    case []:
      []
    case +i <> t:
      Bool.pick(List<&2, R.tr.P>, U32.is_le(R.tr.ctx(l, i), end), R.tr.P{l, i} <> me.cands.q(l, t, end), [])

def me.cands(lv: List<&2, List<&2, U32>>, +l: U32, +end: U32) -> List<&2, R.tr.P>:
  match lv:
    case []:
      []
    case q <> t:
      List.append(&2, R.tr.P, me.cands.q(l, q, end), me.cands(t, (l + 1 : U32), end))

# in the order the messages came (ctx), a merge first at a tie
def me.cands.le(a: R.tr.P, b: R.tr.P) -> Bool:
  match a b:
    case R.tr.P{+la, +ia} R.tr.P{+lb, +ib}:
      +ca = R.tr.ctx(la, ia)
      +cb = R.tr.ctx(lb, ib)
      Bool.or(U32.is_lt(ca, cb), Bool.and(U32.is_eq(ca, cb), U32.is_ge(la, lb)))

# node (l,i)'s job: its source, its task after the compactions' view up to
# it (Memory.build's blocks, as job starts it)
def me.job.of(+nodes: I.im.M<V.vw.Node>, +seen: V.vw.V, +first: U32, +p: R.tr.P, +text: String) -> me.Job:
  +upto = U32.min(R.tr.ctx(R.tr.l(p), R.tr.i(p)), first)
  me.Job{R.tr.l(p), R.tr.i(p), List.append(&2, V.vw.B, V.vw.blocks(nodes, V.vw.parts(seen), upto), [V.vw.B{R.tr.task(p) ++ text ++ "\n</input>", False{}}]), text}

# What starts gathers: the memory, the nodes whose sources fit (newest first),
# the jobs started (newest first).
type me.Sx is Data:
  me.Sx{mem: me.Mem, free: List<&2, me.Free>, jobs: List<&2, me.Job>}

def me.start.got(+p: R.tr.P, t: Maybe<&2, String>, x: me.Sx) -> me.Sx:
  match t x:
    case None{} _:
      x
    case Some{+text} me.Sx{me.Mem{+d, +sy, +jb, +c, +o, +n, +v, +s, +r, +b, +nb, +k, +e}, +free, +jobs}:
      Bool.pick(me.Sx, U32.is_le(T.tx.bytes(text), R.tr.node()),
        me.Sx{me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}, me.Free{p, text} <> free, jobs},
        me.Sx{me.Mem{d, sy, jb, c, o, n, v, s, r, I.im.set(Unit, b, R.tr.slot.of(p), Unit{}), (nb + 1 : U32), k, e}, free,
          me.job.of(n, s, me.first(r, c, 0n), p, text) <> jobs})

# whether node p may start: JOBS not all running, and it is not one of them
def me.start.may(+x: me.Sx, +p: R.tr.P) -> Bool:
  match x:
    case me.Sx{me.Mem{d, sy, +jb, c, o, n, v, s, r, +b, +nb, k, e}, free, jobs}:
      Bool.and(U32.is_lt(nb, jb), Bool.not(I.im.has(Unit, b, R.tr.slot.of(p))))

def me.sx.dir(x: me.Sx) -> String:
  match x:
    case me.Sx{m, f, j}:
      me.dir(m)

def me.sx.nodes(x: me.Sx) -> I.im.M<V.vw.Node>:
  match x:
    case me.Sx{m, f, j}:
      me.nodes(m)

def me.start.go(ps: List<&2, R.tr.P>, +x: me.Sx) -> IO(me.Sx):
  match ps:
    case []:
      IO.pure(me.Sx, x)
    case +p <> +t:
      Bool.pick(IO(me.Sx), me.start.may(x, p),
        do IO<me.Sx>:
          text : Maybe<&2, String> <- me.source(me.sx.dir(x), me.sx.nodes(x), p)
          me.start.go(t, me.start.got(p, text, x)),
        me.start.go(t, x))

# the nodes ready up to the JOBS-th message not built, in the order the
# messages came, while JOBS run: the jobs started, the nodes whose source
# fits (Memory.starts)
def me.starts(+m: me.Mem) -> IO(me.Sx):
  match m:
    case me.Mem{d, sy, +jb, +c, o, n, v, s, +r, b, nb, k, e}:
      +end = me.first(r, c, U32.to_nat((jb - 1 : U32)))
      me.start.go(List.sort(~R.tr.P, ~me.cands.le, me.cands(r, 0, end)), me.Sx{m, [], []})

def me.sx.mem(x: me.Sx) -> me.Mem:
  match x:
    case me.Sx{m, f, j}:
      m

def me.sx.free(x: me.Sx) -> List<&2, me.Free>:
  match x:
    case me.Sx{m, f, j}:
      List.reverse(&2, me.Free, f)

def me.sx.jobs(x: me.Sx) -> List<&2, me.Job>:
  match x:
    case me.Sx{m, f, j}:
      j

# The jobs started so far (newest first), and whether a node was built.
type me.Pm is Data:
  me.Pm{mem: me.Mem, jobs: List<&2, me.Job>, built: Bool}

def me.pump.fit(p: me.Pm) -> IO(me.Mem & List<&2, me.Job>):
  match p:
    case me.Pm{m, jobs, True{}}:
      IO.bind(me.Mem, me.Mem & List<&2, me.Job>, me.fit(m, False{}), m2 => IO.pure(me.Mem & List<&2, me.Job>, (m2, List.reverse(&2, me.Job, jobs))))
    case me.Pm{m, jobs, False{}}:
      IO.pure(me.Mem & List<&2, me.Job>, (m, List.reverse(&2, me.Job, jobs)))

# starts, the nodes that fit stored, again till none fit (Memory.pump)
def me.pump.go(fuel: Nat, +day: U32, free: List<&2, me.Free>, p: me.Pm) -> IO(me.Mem & List<&2, me.Job>):
  match fuel free p:
    case 0n _ _:
      me.pump.fit(p)
    case 1n+f Nil{} _:
      me.pump.fit(p)
    case 1n+f +fs me.Pm{m, jobs, b}:
      do IO<me.Mem & List<&2, me.Job>>:
        m2 : me.Mem <- me.store(m, day, fs)
        +x : me.Sx <- me.starts(m2)
        me.pump.go(f, day, me.sx.free(x), me.Pm{me.sx.mem(x), List.append(&2, me.Job, me.sx.jobs(x), jobs), True{}})

def me.pump(+m: me.Mem, +day: U32) -> IO(me.Mem & List<&2, me.Job>):
  do IO<me.Mem & List<&2, me.Job>>:
    +x : me.Sx <- me.starts(m)
    me.pump.go(Nat.add(Nat.mul(U32.to_nat(me.count(m)), 2n), 64n), day, me.sx.free(x), me.Pm{me.sx.mem(x), me.sx.jobs(x), False{}})

# Pushing ---------------------------------------------------------------------

# a message's pages: its text in pages (Clip.ts), its line on the first, all
# but the last more (Memory.pages)
def me.pages.go(ps: List<&2, String>, +kind: String, line: Maybe<&2, String>, +more: Bool) -> List<&2, me.Msg>:
  match ps:
    case []:
      []
    case [p]:
      [me.Msg{kind, p, line, more}]
    case p <> t:
      me.Msg{kind, p, line, True{}} <> me.pages.go(t, kind, None{}, more)

def me.pages(m: me.Msg) -> List<&2, me.Msg>:
  match m:
    case me.Msg{+k, +t, l, mo}:
      me.pages.go(T.tx.pages(t), k, l, mo)

def me.pages.all(ms: List<&2, me.Msg>) -> List<&2, me.Msg>:
  match ms:
    case []:
      []
    case m <> t:
      List.append(&2, me.Msg, me.pages(m), me.pages.all(t))

# a message to log as its root: index i, dated now (Memory.root)
def me.root(+i: U32, +date: String, m: me.Msg) -> St.st.Root:
  match m:
    case me.Msg{+k, +t, l, mo}:
      St.st.Root{i, k, t, T.tx.bytes(k ++ ": " ++ t), date, l, mo}

def me.roots(ms: List<&2, me.Msg>, +i: U32, +date: String) -> List<&2, St.st.Root>:
  match ms:
    case []:
      []
    case m <> t:
      me.root(i, date, m) <> me.roots(t, (i + 1 : U32), date)

def me.root.recs(rs: List<&2, St.st.Root>) -> List<&2, St.st.Rec>:
  match rs:
    case []:
      []
    case +r <> t:
      St.st.Rec{St.st.root.i(r), J.js.write(St.st.root.json(r)), St.st.root.meta(r)} <> me.root.recs(t)

# how many roots up to the last one more pages don't follow
def me.done(rs: List<&2, St.st.Root>, +k: U32, +last: U32) -> U32:
  match rs:
    case []:
      last
    case +r <> t:
      me.done(t, (k + 1 : U32), Bool.pick(U32, St.st.root.more(r), last, (k + 1 : U32)))

def me.ready.l0(n: Nat, +i: U32, +r: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      r
    case 1n+k:
      me.ready.l0(k, (i + 1 : U32), me.ready.set(r, R.tr.P{0, i}, True{}))

def me.push.log(m: me.Mem, +day: U32, +rs: List<&2, St.st.Root>) -> IO(me.Mem):
  match m:
    case me.Mem{+d, +sy, jb, +c, +o, n, v, s, r, b, nb, k, me.Ends{main0, tree}}:
      +done = me.done(rs, 0, 0)
      +ids = Bool.pick(U32, U32.is_eq(done, 0), 0, (o + done : U32))
      do IO<me.Mem>:
        +at : U32 <- St.st.log(d, "main", day, sy, me.root.recs(rs))
        return me.Mem{d, sy, jb, (c + ids : U32), ((o + U32.from_nat(List.length(&2, St.st.Root, rs)) : U32) - ids : U32), n, v, s, me.ready.l0(U32.to_nat(ids), c, r), b, nb, k, me.Ends{St.st.End{day, at}, tree}}

def me.open(m: me.Mem) -> U32:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      o

def me.push.fin(rs: List<&2, St.st.Root>, r: me.Mem & List<&2, me.Job>) -> me.Mem & (List<&2, St.st.Root> & List<&2, me.Job>):
  match r:
    case (m, jobs):
      (m, (rs, jobs))

# The pages logged; those `more` stay open, past the count, till one that
# isn't. The jobs this starts are the hub's to run (Memory.push).
def me.push(+m: me.Mem, +now: Nat, +day: U32, ms: List<&2, me.Msg>) -> IO(me.Mem & (List<&2, St.st.Root> & List<&2, me.Job>)):
  +rs = me.roots(me.pages.all(ms), (me.count(m) + me.open(m) : U32), C.ck.iso(now))
  do IO<me.Mem & (List<&2, St.st.Root> & List<&2, me.Job>)>:
    m1 : me.Mem <- me.push.log(m, day, rs)
    m2 : me.Mem <- me.fit(m1, True{})
    r : me.Mem & List<&2, me.Job> <- me.pump(m2, day)
    return me.push.fin(rs, r)

def me.unbusy(m: me.Mem, +slot: U32) -> me.Mem:
  match m:
    case me.Mem{d, sy, jb, c, o, n, v, s, r, b, nb, k, e}:
      me.Mem{d, sy, jb, c, o, n, v, s, r, I.im.del(Unit, b, slot), (nb - 1 : U32), k, e}

def me.built.fin(r: me.Mem & List<&2, me.Job>) -> IO(me.Mem & List<&2, me.Job>):
  match r:
    case (m, jobs):
      IO.bind(me.Mem, me.Mem & List<&2, me.Job>, me.fit(m, False{}), m2 => IO.pure(me.Mem & List<&2, me.Job>, (m2, jobs)))

# a job's line in: the node stored, its job done, the next started
# (Memory.build's end, then job's finally)
def me.done.job(m: me.Mem, +day: U32, +l: U32, +i: U32, +line: String) -> IO(me.Mem & List<&2, me.Job>):
  do IO<me.Mem & List<&2, me.Job>>:
    m1 : me.Mem <- me.store(m, day, [me.Free{R.tr.P{l, i}, line}])
    r : me.Mem & List<&2, me.Job> <- me.pump(me.unbusy(m1, R.tr.slot(l, i)), day)
    me.built.fin(r)

# Loading ---------------------------------------------------------------------

def me.strs.of(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case []:
      []
    case J.JStr{x} <> t:
      x <> me.strs.of(t)
    case x <> t:
      me.strs.of(t)

def me.kept.of(s: Maybe<&2, J.Json>) -> me.Kept:
  match s:
    case Some{+j}:
      me.Kept{Maybe.default(&2, J.Json, J.js.field(j, "pick"), J.JNull{}), J.js.str(j, "goal"), me.strs.of(J.js.arr(j, "work"))}
    case None{}:
      me.Kept{J.JNull{}, None{}, []}

def me.end.of(+j: Maybe<&2, J.Json>) -> St.st.End:
  match j:
    case Some{J.JArr{[J.JNum{d}, J.JNum{a}]}}:
      St.st.End{U32.from_nat(Maybe.default(&2, Nat, Nat.read(d), 0n)), U32.from_nat(Maybe.default(&2, Nat, Nat.read(a), 0n))}
    case _:
      St.st.End{0, 0}

def me.ends.of(m: Maybe<&2, J.Json>) -> me.Ends:
  match m:
    case Some{+j}:
      me.Ends{me.end.of(J.js.field(j, "main")), me.end.of(J.js.field(j, "tree"))}
    case None{}:
      me.Ends{St.st.End{0, 0}, St.st.End{0, 0}}

# the keys of a kept view's parts (none: no view kept)
def me.keys.go(xs: List<&2, J.Json>, acc: I.im.M<Unit>) -> I.im.M<Unit>:
  match xs:
    case []:
      acc
    case J.JArr{[J.JNum{l}, J.JNum{i}]} <> t:
      me.keys.go(t, I.im.set(Unit, acc, R.tr.slot(U32.from_nat(Maybe.default(&2, Nat, Nat.read(l), 0n)), U32.from_nat(Maybe.default(&2, Nat, Nat.read(i), 0n))), Unit{}))
    case x <> t:
      me.keys.go(t, acc)

def me.keys.of(m: Maybe<&2, J.Json>) -> Maybe<&2, I.im.M<Unit>>:
  match m:
    case Some{+j}:
      Some{me.keys.go(J.js.arr(j, "parts"), I.im.new(Unit))}
    case None{}:
      None{}

def me.batch.of(m: Maybe<&2, J.Json>) -> Bool:
  match m:
    case Some{+j}:
      Maybe.default(&2, Bool, J.js.bool(j, "batch"), False{})
    case None{}:
      False{}

# the compactions' view kept, or (none) the chat's
def me.seen.of(m: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match m:
    case Some{+j}:
      Maybe.or(&2, J.Json, J.js.field(j, "seen"), Some{j})
    case None{}:
      None{}

def me.saved.got(r: Result<&1, &1, U32 & String, String>) -> Maybe<&2, J.Json>:
  match r:
    case Done{t}:
      J.js.read(t)
    case Fail{e}:
      None{}

def me.json.file(+path: String) -> IO(Maybe<&2, J.Json>):
  IO.bind(Result<&1, &1, U32 & String, String>, Maybe<&2, J.Json>, S.mu.read_file(path), r => IO.pure(Maybe<&2, J.Json>, me.saved.got(r)))

def me.pair.fst(p: me.Dv) -> I.im.M<V.vw.Node>:
  match p:
    case me.Dv{a, b}:
      a

def me.pair.snd(p: me.Dv) -> List<&2, R.tr.P>:
  match p:
    case me.Dv{a, b}:
      b

def me.ready.all(ps: List<&2, R.tr.P>, +r: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match ps:
    case []:
      r
    case p <> t:
      me.ready.all(t, me.ready.set(r, p, True{}))

def me.ends.main(e: me.Ends) -> St.st.End:
  match e:
    case me.Ends{a, b}:
      a

def me.ends.tree(e: me.Ends) -> St.st.End:
  match e:
    case me.Ends{a, b}:
      b

def me.cn.fst(p: U32 & U32) -> U32:
  match p:
    case (a, b):
      a

# the memory of a directory: its logs indexed past where they were, its
# views as kept (or the highest nodes built), the nodes to build ready
# (Memory.load)
def me.load(+dir: String, +sync: U32, +jobs: U32) -> IO(me.Mem):
  do IO<me.Mem>:
    +saved : Maybe<&2, J.Json> <- me.json.file(dir ++ "/view.json")
    +ends : me.Ends <- IO.bind(Maybe<&2, J.Json>, me.Ends, me.json.file(dir ++ "/idx.json"), j => IO.pure(me.Ends, me.ends.of(j)))
    +main : St.st.End <- St.st.index(dir, "main", me.ends.main(ends))
    +tree : St.st.End <- St.st.index(dir, "tree", me.ends.tree(ends))
    cn : U32 & U32 <- St.st.count(dir)
    +count : U32 = me.cn.fst(cn)
    +dv : me.Dv <- me.down.go(Nat.add(Nat.mul(U32.to_nat(count), 3n), 64n), dir, me.keys.of(saved), R.tr.roots(count), I.im.new(V.vw.Node), [])
    +nodes1 : I.im.M<V.vw.Node> = me.pair.fst(dv)
    +vparts : List<&2, R.tr.P> = me.pair.snd(dv)
    +ds : me.Dv <- me.down.go(Nat.add(Nat.mul(U32.to_nat(count), 3n), 64n), dir, me.keys.of(me.seen.of(saved)), R.tr.roots(count), nodes1, [])
    +nodes : I.im.M<V.vw.Node> = me.pair.fst(ds)
    +sparts : List<&2, R.tr.P> = me.pair.snd(ds)
    +view : V.vw.V = V.vw.V{vparts, V.vw.sizes(nodes, vparts), me.batch.of(saved), me.high()}
    +seen : V.vw.V = V.vw.V{sparts, V.vw.sizes(nodes, sparts), me.batch.of(me.seen.of(saved)), me.seen.high()}
    +ready : List<&2, List<&2, U32>> = me.ready.all(me.todo(count, nodes), [])
    +m : me.Mem <- me.fit(me.Mem{dir, sync, jobs, count, 0, nodes, view, seen, ready, I.im.new(Unit), 0, me.kept.of(saved), me.Ends{main, tree}}, False{})
    Unit <- me.save(m)
    return m

# Reading -------------------------------------------------------------------

def me.slot.size(s: St.st.Slot) -> U32:
  match s:
    case St.st.Slot{a, d, l, m}:
      U32.and(m, 2147483647)

type me.Wh is Data:
  me.Wh{found: Bool, k: U32, size: U32}

# newest first: each message's size added; past HIGH (but the last), found
def me.whole.walk(ss: List<&2, St.st.Slot>, +k: U32, +size: U32, +count: U32, stop: Bool) -> me.Wh:
  match ss stop:
    case _ True{}:
      me.Wh{True{}, k, size}
    case Nil{} False{}:
      me.Wh{False{}, k, size}
    case s <> t False{}:
      +s2 = (size + me.slot.size(s) : U32)
      +k2 = Bool.pick(U32, Bool.and(U32.is_lt(k, count), U32.is_gt(s2, me.high())), k, (k - 1 : U32))
      me.whole.walk(t, k2, s2, count, Bool.and(U32.is_lt(k, count), U32.is_gt(s2, me.high())))

def me.whole.go(fuel: Nat, +dir: String, +from: U32, +count: U32, w: me.Wh) -> IO(U32):
  match fuel w:
    case _ me.Wh{True{}, k, s}:
      IO.pure(U32, k)
    case 0n me.Wh{f, k, s}:
      IO.pure(U32, k)
    case 1n+f me.Wh{False{}, +k, +s}:
      +n = U32.min(256, (k - U32.min(k, from) : U32))
      Bool.pick(IO(U32), U32.is_eq(n, 0), IO.pure(U32, k),
        do IO<U32>:
          ss : List<&2, St.st.Slot> <- St.st.slots(dir, "main", (k - n : U32), n)
          me.whole.go(f, dir, from, count, me.whole.walk(List.reverse(&2, St.st.Slot, ss), k, s, count, False{})))

# the first message, from `from` on, from which those to the end go whole in
# a call: HIGH bytes (the last always) (Memory.whole)
def me.whole(+m: me.Mem, +from: U32) -> IO(U32):
  me.whole.go(U32.to_nat(me.count(m)), me.dir(m), from, me.count(m), me.Wh{False{}, me.count(m), 0})

def me.text.of(m: Maybe<&2, St.st.Root>) -> String:
  match m:
    case Some{r}:
      St.st.root.text(r)
    case None{}:
      ""

# the pages [a, b) of a message as a model gets them: one text (Memory.say)
def me.say.go(n: Nat, +dir: String, +a: U32, acc: String) -> IO(String):
  match n:
    case 0n:
      IO.pure(String, acc)
    case 1n+k:
      do IO<String>:
        r : Maybe<&2, St.st.Root> <- St.st.message(dir, a)
        me.say.go(k, dir, (a + 1 : U32), String.append(acc, me.text.of(r)))

def me.say(+m: me.Mem, +a: U32, +b: U32) -> IO(String):
  me.say.go(U32.to_nat((b - U32.min(a, b) : U32)), me.dir(m), a, "")

def me.refs(ps: List<&2, R.tr.P>) -> List<&2, String>:
  match ps:
    case []:
      []
    case +p <> t:
      R.tr.ref(p) <> me.refs(t)

def me.is.pow2(+n: U32) -> Bool:
  Bool.and(U32.is_ne(n, 0), U32.is_eq(U32.and(n, (n - 1 : U32)), 0))

def me.zoom.msg(+id: U32, +at: U32, m: Maybe<&2, St.st.Root>) -> String:
  match m:
    case Some{St.st.Root{i, k, +t, s, d, l, mo}}:
      U32.show(id) ++ "+0|" ++ k ++ ": " ++ T.tx.page.at(t, at)
    case None{}:
      "No message " ++ U32.show(id) ++ "."

def me.zoom.line(+p: R.tr.P, t: Maybe<&2, String>) -> String:
  R.tr.line(p, Maybe.default(&2, String, t, V.vw.wait()))

# a message (n = 1) whole, a long one a page from `at` (Clip.ts); else the
# two lines under id+n (Memory.zoom)
def me.zoom(+m: me.Mem, +id: U32, +n: U32, +at: U32) -> IO(String):
  +ok = Bool.and(Bool.and(me.is.pow2(n), U32.is_eq(U32.mod(id, n), 0)), U32.is_le((id + n : U32), me.count(m)))
  +p = {R.tr.P{U32.from_nat(U32.log2(n)), U32.div(id, n)} : R.tr.P}
  Bool.pick(IO(String), Bool.not(ok),
    IO.pure(String, "No line " ++ U32.show(id) ++ "+" ++ U32.show(n) ++ ": n is a power of 2, id a multiple of n. The tree's roots: " ++ T.tx.join(me.refs(R.tr.roots(me.count(m))), ", ") ++ "."),
    Bool.pick(IO(String), U32.is_eq(n, 1),
      IO.bind(Maybe<&2, St.st.Root>, String, St.st.message(me.dir(m), id), r => IO.pure(String, me.zoom.msg(id, at, r))),
      do IO<String>:
        a : Maybe<&2, String> <- me.node(me.dir(m), me.nodes(m), R.tr.P{(R.tr.l(p) - 1 : U32), (2 * R.tr.i(p) : U32)})
        b : Maybe<&2, String> <- me.node(me.dir(m), me.nodes(m), R.tr.P{(R.tr.l(p) - 1 : U32), (2 * R.tr.i(p) + 1 : U32)})
        return String.append(me.zoom.line(R.tr.P{(R.tr.l(p) - 1 : U32), (2 * R.tr.i(p) : U32)}, a), "\n" ++ me.zoom.line(R.tr.P{(R.tr.l(p) - 1 : U32), (2 * R.tr.i(p) + 1 : U32)}, b))))

def me.date.of(+id: U32, m: Maybe<&2, St.st.Root>) -> IO(String):
  match m:
    case Some{r}:
      +t = C.ck.parse(St.st.root.date(r))
      IO.bind(U32, String, S.mu.tzoff(t), tz => IO.pure(String, C.ck.show(t, tz)))
    case None{}:
      IO.pure(String, "No message " ++ U32.show(id) ++ ".")

# the date and time of message id, local (Memory.date)
def me.date(+m: me.Mem, +id: U32) -> IO(String):
  IO.bind(Maybe<&2, St.st.Root>, String, St.st.message(me.dir(m), id), r => me.date.of(id, r))

# the view's lines after its last summary: its messages whole
def me.tail(ps: List<&2, R.tr.P>, acc: List<&2, R.tr.P>) -> List<&2, R.tr.P>:
  match ps:
    case []:
      List.reverse(&2, R.tr.P, acc)
    case +p <> t:
      me.tail(t, Bool.pick(List<&2, R.tr.P>, U32.is_gt(R.tr.l(p), 0), [], p <> acc))

def me.kind.of(m: Maybe<&2, St.st.Root>) -> String:
  match m:
    case Some{r}:
      St.st.root.kind(r)
    case None{}:
      ""

def me.turn.kind(+k: String) -> Bool:
  Bool.or(String.eq(k, "user"), String.eq(k, "work"))

def me.turn.go(ps: List<&2, R.tr.P>, +dir: String, +last: Maybe<&2, U32>) -> IO(Maybe<&2, U32>):
  match ps:
    case []:
      IO.pure(Maybe<&2, U32>, last)
    case +p <> t:
      do IO<Maybe<&2, U32>>:
        r : Maybe<&2, St.st.Root> <- St.st.message(dir, R.tr.i(p))
        me.turn.go(t, dir, Bool.pick(Maybe<&2, U32>, me.turn.kind(me.kind.of(r)), Some{R.tr.i(p)}, last))

def me.turn.first(ps: List<&2, R.tr.P>, +count: U32) -> U32:
  match ps:
    case []:
      count
    case p <> t:
      R.tr.i(p)

# where a page of the chat starts: the last message starting a turn (the
# user's or a report) the view holds whole; none: the first, or the end
# (Memory.turn)
def me.turn(+m: me.Mem) -> IO(U32):
  +whole = me.tail(V.vw.parts(me.view(m)), [])
  IO.bind(Maybe<&2, U32>, U32, me.turn.go(whole, me.dir(m), None{}), u => IO.pure(U32, Maybe.default(&2, U32, u, me.turn.first(whole, me.count(m)))))

# Agents ----------------------------------------------------------------------

def me.agent.root(+n: U32, +kind: String, +text: String, +now: Nat) -> St.st.Root:
  St.st.Root{n, kind, text, T.tx.bytes(kind ++ ": " ++ text), C.ck.iso(now), None{}, False{}}

def me.agent.line(r: St.st.Root) -> String:
  match r:
    case St.st.Root{i, k, t, s, d, l, m}:
      U32.show(i) ++ "|" ++ k ++ ": " ++ t

def me.agent.lines(rs: List<&2, St.st.Root>) -> List<&2, String>:
  match rs:
    case []:
      []
    case r <> t:
      me.agent.line(r) <> me.agent.lines(t)

def me.agent.got(+name: String, m: Maybe<&2, List<&2, St.st.Root>>) -> String:
  match m:
    case Some{rs}:
      T.tx.join(me.agent.lines(rs), "\n\n")
    case None{}:
      "No agent " ++ name ++ "."

# an agent's whole chat (zoom("Name"))
def me.agent.show(+dir: String, +name: String) -> IO(String):
  IO.bind(Maybe<&2, List<&2, St.st.Root>>, String, St.st.agent(dir, name), r => IO.pure(String, me.agent.got(name, r)))
