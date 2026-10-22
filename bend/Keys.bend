
import Base

# Keys: the terminal's input, read raw (Screen.bend), as keys. A read is a
# chunk of characters; it holds whole keys, but an escape sequence or a
# paste may be cut short at its end, and is kept for the next. A new line in
# the input is Shift-, Alt- or Ctrl-Enter, or Ctrl-J, in each encoding a
# terminal may use: plain (Alt is ESC first), xterm's modifyOtherKeys (CSI
# 27;m;13~) and the "CSI u" of kitty and of tmux's extended keys (CSI
# 13;mu). A paste comes whole, between bracketed paste's marks; the mouse
# comes as xterm's SGR reports.
#
# Every def is prefixed `ky.` (a program's defs share one namespace).

# Nav: 1 up, 2 down, 3 right, 4 left, 5 home, 6 end, 7 page up, 8 page down,
# 9 delete, 10 insert; m its modifiers (1 Shift, 2 Alt, 4 Ctrl). Ctrl: a
# control key, as the letter's code (97 for C-a); Meta: Alt and a character.
# Mouse: its button (0 left, 1 middle, 2 right, 64 wheel up, 65 wheel down;
# plus 4 Shift, 8 Alt, 16 Ctrl, 32 motion), its column and row from 1, and
# whether it was let go.
type ky.Key is Data:
  ky.Char{c: U32}
  ky.Ctrl{c: U32}
  ky.Meta{c: U32}
  ky.Enter{}
  ky.Newline{}
  ky.Tab{}
  ky.BackTab{}
  ky.Back{}
  ky.MetaBack{}
  ky.Esc{}
  ky.Nav{k: U32, m: U32}
  ky.Paste{text: String}
  ky.Mouse{b: U32, x: U32, y: U32, up: Bool}
  ky.Focus{on: Bool}
  ky.Other{}

# What the front of a chunk holds: a key and the rest; nothing; the start of
# a sequence, cut short (kept for the next read); a paste's opening mark and
# what follows it; a paste still open, its text so far (reversed) and the
# start of its closing mark, if the chunk ended inside it.
type ky.R is Data:
  ky.Got{key: ky.Key, rest: String}
  ky.End{}
  ky.Cut{rest: String}
  ky.Open{rest: String}
  ky.Pasting{acc: String, rest: String}

def ky.esc() -> String:
  "\u{1B}"

# Plain keys ---------------------------------------------------------------------

def ky.plain(+c: U32) -> ky.Key:
  Bool.pick(ky.Key, U32.is_eq(c, 13), ky.Enter{}, Bool.pick(ky.Key, U32.is_eq(c, 10), ky.Newline{},
    Bool.pick(ky.Key, U32.is_eq(c, 9), ky.Tab{}, Bool.pick(ky.Key, Bool.or(U32.is_eq(c, 127), U32.is_eq(c, 8)), ky.Back{},
      Bool.pick(ky.Key, Bool.and(U32.is_ge(c, 1), U32.is_le(c, 26)), ky.Ctrl{(c + 96 : U32)},
        Bool.pick(ky.Key, U32.is_lt(c, 32), ky.Other{}, ky.Char{c}))))))

# ESC, then a character: Alt and it
def ky.alt(+c: U32) -> ky.Key:
  Bool.pick(ky.Key, Bool.or(U32.is_eq(c, 13), U32.is_eq(c, 10)), ky.Newline{},
    Bool.pick(ky.Key, Bool.or(U32.is_eq(c, 127), U32.is_eq(c, 8)), ky.MetaBack{}, ky.Meta{c}))

def ky.letter(+c: U32) -> Bool:
  Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)))

def ky.lower(+c: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)), (c + 32 : U32), c)

# a key told by its code and modifiers (modifyOtherKeys, CSI u): m as the
# terminal sends it (1 none, then 1 + Shift 1, Alt 2, Ctrl 4)
def ky.mod(+code: U32, +m0: U32) -> ky.Key:
  +m = (U32.max(m0, 1) - 1 : U32)
  +alt = U32.is_ne(U32.and(m, 2), 0)
  +ctrl = U32.is_ne(U32.and(m, 4), 0)
  +shift = U32.is_ne(U32.and(m, 1), 0)
  Bool.pick(ky.Key, U32.is_eq(code, 13), Bool.pick(ky.Key, U32.is_eq(m, 0), ky.Enter{}, ky.Newline{}),
    Bool.pick(ky.Key, U32.is_eq(code, 9), Bool.pick(ky.Key, shift, ky.BackTab{}, ky.Tab{}),
      Bool.pick(ky.Key, U32.is_eq(code, 27), ky.Esc{},
        Bool.pick(ky.Key, Bool.or(U32.is_eq(code, 127), U32.is_eq(code, 8)), Bool.pick(ky.Key, alt, ky.MetaBack{}, ky.Back{}),
          Bool.pick(ky.Key, Bool.and(ctrl, ky.letter(code)), ky.Ctrl{ky.lower(code)},
            Bool.pick(ky.Key, Bool.and(alt, U32.is_ge(code, 32)), ky.Meta{code},
              Bool.pick(ky.Key, Bool.and(U32.is_ge(code, 32), U32.is_lt(code, 57344)), ky.Char{code}, ky.Other{})))))))

# Sequences ---------------------------------------------------------------------

# a parameter's number: its digits up to ":" (kitty's alternates), else d
def ky.digits(s: String, +acc: String) -> String:
  match s:
    case SCon{Chr{+c}, t}:
      Bool.pick(String, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), ky.digits(t, SCon{Chr{c}, acc}), String.reverse(acc))
    case SNil{}:
      String.reverse(acc)

def ky.num(+ps: List<&2, String>, +k: Nat, +d: U32) -> U32:
  +x = ky.digits(Maybe.default(&2, String, List.get(&2, String, ps, k), ""), "")
  Bool.pick(U32, String.is_empty(x), d, U32.from_nat(Maybe.default(&2, Nat, Nat.read(x), U32.to_nat(d))))

def ky.nav(+k: U32, +ps: List<&2, String>) -> ky.Key:
  ky.Nav{k, (U32.max(ky.num(ps, 1n, 1), 1) - 1 : U32)}

# CSI n ~
def ky.tilde(+n: U32, +ps: List<&2, String>, +rest: String) -> ky.R:
  Bool.pick(ky.R, U32.is_eq(n, 200), ky.Open{rest},
    ky.Got{Bool.pick(ky.Key, Bool.or(U32.is_eq(n, 1), U32.is_eq(n, 7)), ky.nav(5, ps),
      Bool.pick(ky.Key, Bool.or(U32.is_eq(n, 4), U32.is_eq(n, 8)), ky.nav(6, ps),
        Bool.pick(ky.Key, U32.is_eq(n, 2), ky.nav(10, ps), Bool.pick(ky.Key, U32.is_eq(n, 3), ky.nav(9, ps),
          Bool.pick(ky.Key, U32.is_eq(n, 5), ky.nav(7, ps), Bool.pick(ky.Key, U32.is_eq(n, 6), ky.nav(8, ps),
            Bool.pick(ky.Key, U32.is_eq(n, 27), ky.mod(ky.num(ps, 2n, 0), ky.num(ps, 1n, 1)), ky.Other{}))))))), rest})

# the mouse: <b;x;y, M (pressed) or m (let go). The button's modifier bits
# (4 Shift, 8 Meta, 16 Ctrl) dropped: some terminals set them where none is
# held (xterm.dart's, in phone apps such as Conduit, reports a swipe as the
# wheel with Shift, 68 and 69)
def ky.mouse(+ps: List<&2, String>, +up: Bool) -> ky.Key:
  ky.Mouse{U32.and(ky.num(ps, 0n, 0), 227), ky.num(ps, 1n, 1), ky.num(ps, 2n, 1), up}

# a CSI sequence's end: its parameters' text and its final byte
def ky.csi.end(+params: String, +f: U32, +rest: String) -> ky.R:
  +mouse = String.starts_with(params, "<")
  +ps = String.split(Bool.pick(String, mouse, String.drop(params, 1n), params), ';')
  Bool.pick(ky.R, Bool.and(mouse, Bool.or(U32.is_eq(f, 77), U32.is_eq(f, 109))), ky.Got{ky.mouse(ps, U32.is_eq(f, 109)), rest},
    Bool.pick(ky.R, U32.is_eq(f, 126), ky.tilde(ky.num(ps, 0n, 0), ps, rest),
      ky.Got{Bool.pick(ky.Key, U32.is_eq(f, 65), ky.nav(1, ps), Bool.pick(ky.Key, U32.is_eq(f, 66), ky.nav(2, ps),
        Bool.pick(ky.Key, U32.is_eq(f, 67), ky.nav(3, ps), Bool.pick(ky.Key, U32.is_eq(f, 68), ky.nav(4, ps),
          Bool.pick(ky.Key, U32.is_eq(f, 72), ky.nav(5, ps), Bool.pick(ky.Key, U32.is_eq(f, 70), ky.nav(6, ps),
            Bool.pick(ky.Key, U32.is_eq(f, 117), ky.mod(ky.num(ps, 0n, 0), ky.num(ps, 1n, 1)),
              Bool.pick(ky.Key, U32.is_eq(f, 90), ky.BackTab{},
                Bool.pick(ky.Key, U32.is_eq(f, 73), ky.Focus{True{}}, Bool.pick(ky.Key, U32.is_eq(f, 79), ky.Focus{False{}}, ky.Other{})))))))))), rest}))

# what the head of a CSI's rest is: 0 nothing, 1 a parameter or
# intermediate byte, 2 the final byte, 3 none of these (a broken sequence)
def ky.class(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+c}, t}:
      Bool.pick(Nat, Bool.and(U32.is_ge(c, 32), U32.is_le(c, 63)), 1n, Bool.pick(Nat, Bool.and(U32.is_ge(c, 64), U32.is_le(c, 126)), 2n, 3n))

def ky.csi.go(s: String, v: Nat, +ps: String) -> ky.R:
  match s v:
    case SCon{Chr{+c}, +t} 1n:
      ky.csi.go(t, ky.class(t), SCon{Chr{c}, ps})
    case SCon{Chr{+c}, +t} 2n:
      ky.csi.end(String.reverse(ps), c, t)
    case SCon{+c, +t} 3n:
      ky.Got{ky.Other{}, SCon{c, t}}
    case _ _:
      ky.Cut{ky.esc() ++ "[" ++ String.reverse(ps)}

# ESC O and a letter (the cursor keys in application mode); alone, Alt-O
def ky.ss3(s: String) -> ky.R:
  match s:
    case SNil{}:
      ky.Got{ky.Meta{79}, ""}
    case SCon{Chr{+c}, t}:
      ky.Got{Bool.pick(ky.Key, U32.is_eq(c, 65), ky.Nav{1, 0}, Bool.pick(ky.Key, U32.is_eq(c, 66), ky.Nav{2, 0},
        Bool.pick(ky.Key, U32.is_eq(c, 67), ky.Nav{3, 0}, Bool.pick(ky.Key, U32.is_eq(c, 68), ky.Nav{4, 0},
          Bool.pick(ky.Key, U32.is_eq(c, 72), ky.Nav{5, 0}, Bool.pick(ky.Key, U32.is_eq(c, 70), ky.Nav{6, 0},
            Bool.pick(ky.Key, U32.is_eq(c, 77), ky.Enter{}, ky.Other{}))))))), t}

# the key at the front of a chunk
def ky.next(s: String) -> ky.R:
  match s:
    case SNil{}:
      ky.End{}
    case SCon{Chr{27}, SNil{}}:
      ky.Got{ky.Esc{}, ""}
    case SCon{Chr{27}, SCon{Chr{27}, +t}}:
      ky.Got{ky.Esc{}, SCon{Chr{27}, t}}
    case SCon{Chr{27}, SCon{Chr{91}, +t}}:
      ky.csi.go(t, ky.class(t), "")
    case SCon{Chr{27}, SCon{Chr{79}, +t}}:
      ky.ss3(t)
    case SCon{Chr{27}, SCon{Chr{+c}, +t}}:
      ky.Got{ky.alt(c), t}
    case SCon{Chr{+c}, +t}:
      ky.Got{ky.plain(c), t}

# Pastes ------------------------------------------------------------------------

def ky.mark() -> String:
  "\u{1B}[201~"

# what a paste's rest starts with: 0 its closing mark, 1 the start of the
# mark (the chunk ends inside it), 2 any other character, 3 nothing
def ky.paste.v(+s: String) -> Nat:
  Bool.pick(Nat, String.is_empty(s), 3n, Bool.pick(Nat, String.starts_with(s, ky.mark()), 0n, Bool.pick(Nat, String.starts_with(ky.mark(), s), 1n, 2n)))

def ky.paste.go(s: String, v: Nat, +acc: String) -> ky.R:
  match s v:
    case SCon{+c, +t} 2n:
      ky.paste.go(t, ky.paste.v(t), SCon{c, acc})
    case SCon{+c, +t} 0n:
      ky.Got{ky.Paste{String.reverse(acc)}, String.drop(t, 5n)}
    case SCon{+c, +t} 1n:
      ky.Pasting{acc, SCon{c, t}}
    case _ _:
      ky.Pasting{acc, ""}

def ky.paste(+s: String, +acc: String) -> ky.R:
  ky.paste.go(s, ky.paste.v(s), acc)

# Reading -----------------------------------------------------------------------

# What a read leaves for the next: the start of a sequence cut short, and a
# paste still open (its text so far, reversed)
type ky.St is Data:
  ky.St{pend: String, paste: Maybe<&2, String>}

type ky.Out is Data:
  ky.Out{keys: List<&2, ky.Key>, st: ky.St}

def ky.keys(n: Nat, r: ky.R, +acc: List<&2, ky.Key>) -> ky.Out:
  match n r:
    case 1n+f ky.Got{+key, +rest}:
      ky.keys(f, ky.next(rest), key <> acc)
    case 1n+f ky.Open{+rest}:
      ky.keys(f, ky.paste(rest, ""), acc)
    case _ ky.Cut{+rest}:
      ky.Out{List.reverse(&2, ky.Key, acc), ky.St{rest, None{}}}
    case _ ky.Pasting{+a, +rest}:
      ky.Out{List.reverse(&2, ky.Key, acc), ky.St{rest, Some{a}}}
    case _ _:
      ky.Out{List.reverse(&2, ky.Key, acc), ky.St{"", None{}}}

def ky.start() -> ky.St:
  ky.St{"", None{}}

# a chunk read: its keys, and what is left for the next
def ky.feed(st: ky.St, +s: String) -> ky.Out:
  match st:
    case ky.St{+pend, None{}}:
      ky.keys(U32.to_nat(4294967295), ky.next(pend ++ s), [])
    case ky.St{+pend, Some{+a}}:
      ky.keys(U32.to_nat(4294967295), ky.paste(pend ++ s, a), [])

def ky.out.keys(o: ky.Out) -> List<&2, ky.Key>:
  match o:
    case ky.Out{ks, st}:
      ks

def ky.out.st(o: ky.Out) -> ky.St:
  match o:
    case ky.Out{ks, st}:
      st
