
import Base
import ./Text.bend as T
import ./Ev.bend as E

# Term: the terminal, in line mode. A reader (its own computation) turns
# stdin into the user's messages: a line each, or the lines between two
# lines of """ (one message with its newlines); then Eof. The hub prints
# what the chat logs as it comes: on a terminal, replies plain, tool calls
# and results dimmed and cut to a line, thoughts dimmed, notes and reports
# in color; else (a pipe, as tests run it) every message whole, as "kind:
# text", an agent's prefixed by its name.
#
# Every def is prefixed `tm.` (a program's defs share one namespace).

# Reading ------------------------------------------------------------------------
#
# What the reader holds between reads: the line cut short (reversed), and the
# lines of a """ block open (newest first; None: none open).

type tm.In is Data:
  tm.In{cur: String, block: Maybe<&2, List<&2, String>>}

# what a line does: one message, a block opened, a block line, a block closed
type tm.Fed is Data:
  tm.Fed{in: tm.In, msgs: List<&2, String>}

def tm.quote() -> String:
  "\"\"\""

def tm.chomp.cr(+l: String) -> String:
  Bool.pick(String, String.ends_with(l, "\r"), String.reverse(String.drop(String.reverse(l), 1n)), l)

# a whole line in: a message, or into the block (a """ line opens or closes it)
def tm.line.q(b: Maybe<&2, List<&2, String>>, +l: String, +q: Bool, +msgs: List<&2, String>) -> tm.Fed:
  match b:
    case None{}:
      Bool.pick(tm.Fed, q, tm.Fed{tm.In{"", Some{[]}}, msgs}, tm.Fed{tm.In{"", None{}}, List.append(&2, String, msgs, [l])})
    case Some{+ls}:
      Bool.pick(tm.Fed, q, tm.Fed{tm.In{"", None{}}, List.append(&2, String, msgs, [T.tx.join(List.reverse(&2, String, ls), "\n")])},
        tm.Fed{tm.In{"", Some{l <> ls}}, msgs})

def tm.line(+l: String, b: Maybe<&2, List<&2, String>>, +msgs: List<&2, String>) -> tm.Fed:
  tm.line.q(b, l, String.eq(T.tx.trim(l), tm.quote()), msgs)

def tm.fed.in(f: tm.Fed) -> tm.In:
  match f:
    case tm.Fed{i, m}:
      i

def tm.fed.msgs(f: tm.Fed) -> List<&2, String>:
  match f:
    case tm.Fed{i, m}:
      m

def tm.in.block(i: tm.In) -> Maybe<&2, List<&2, String>>:
  match i:
    case tm.In{c, b}:
      b

# a chunk read, char by char: lines ended go in, the last kept
def tm.feed(s: String, st: tm.In, +msgs: List<&2, String>) -> tm.Fed:
  match s st:
    case SNil{} _:
      tm.Fed{st, msgs}
    case SCon{Chr{10}, t} tm.In{+cur, b}:
      +f = tm.line(tm.chomp.cr(String.reverse(cur)), b, msgs)
      tm.feed(t, tm.fed.in(f), tm.fed.msgs(f))
    case SCon{c, t} tm.In{cur, b}:
      tm.feed(t, tm.In{SCon{c, cur}, b}, msgs)

def tm.say(ms: List<&2, String>, +out: Chan(E.ev.Ev)) -> IO(Unit):
  match ms:
    case []:
      IO.pure(Unit, Unit{})
    case m <> t:
      IO.bind(Unit, Unit, E.ev.send(out, E.ev.Line{m}), u => tm.say(t, out))

# at the end, a last line without its newline, then a block left open, are
# messages too
def tm.rest(st: tm.In) -> List<&2, String>:
  match st:
    case tm.In{SNil{}, None{}}:
      []
    case tm.In{+cur, None{}}:
      [String.reverse(cur)]
    case tm.In{+cur, Some{+ls}}:
      [T.tx.join(List.reverse(&2, String, Bool.pick(List<&2, String>, String.is_empty(cur), ls, String.reverse(cur) <> ls)), "\n")]

# the reader: the last read's answer is a parameter, so the loop matches it
def tm.read(fuel: Nat, +out: Chan(E.ev.Ev), st: tm.In, r: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match fuel r:
    case 1n+f Tuple{file, Done{SCon{h, t}}}:
      +fed = tm.feed(SCon{h, t}, st, [])
      do IO<Unit>:
        Unit <- tm.say(tm.fed.msgs(fed), out)
        r2 : File & Result<&1, &1, U32 & String, String> <- File.read(file, 65536)
        tm.read(f, out, tm.fed.in(fed), r2)
    case _ Tuple{file, _}:
      do IO<Unit>:
        Unit <- tm.say(tm.rest(st), out)
        Unit <- E.ev.send(out, E.ev.Eof{})
        File.close(file)

def tm.reader.got(+out: Chan(E.ev.Ev), r: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match r:
    case Done{file}:
      IO.bind(File & Result<&1, &1, U32 & String, String>, Unit, File.read(file, 65536), r2 => tm.read(U32.to_nat(4294967295), out, tm.In{"", None{}}, r2))
    case Fail{e}:
      E.ev.send(out, E.ev.Eof{})

# stdin read to its end, as messages to `out`
def tm.reader(+out: Chan(E.ev.Ev)) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open("/dev/stdin", "r"), r => tm.reader.got(out, r))

# Printing -----------------------------------------------------------------------

def tm.esc(+code: String, +s: String) -> String:
  "\u{1B}[" ++ code ++ "m" ++ s ++ "\u{1B}[0m"

def tm.first.line(s: String, +acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{10}, t}:
      String.reverse(acc)
    case SCon{c, t}:
      tm.first.line(t, SCon{c, acc})

def tm.count.lines(s: String, +n: U32) -> U32:
  match s:
    case SNil{}:
      n
    case SCon{Chr{+c}, t}:
      tm.count.lines(t, (n + Bool.pick(U32, U32.is_eq(c, 10), 1, 0) : U32))

# a text as one line of at most n characters
def tm.short(+s: String, +n: Nat) -> String:
  +l = tm.first.line(s, "")
  +more = U32.is_gt(tm.count.lines(s, 0), 0)
  +cut = Nat.is_lt(n, String.length(l))
  String.take(l, n) ++ Bool.pick(String, Bool.or(cut, more), " …", "") ++ Bool.pick(String, more, " (+" ++ U32.show(tm.count.lines(s, 0)) ++ " lines)", "")

def tm.who(+who: String) -> String:
  Bool.pick(String, String.is_empty(who), "", "[" ++ who ++ "] ")

# an entry as printed on a terminal
def tm.tty(+who: String, +kind: String, +text: String) -> String:
  +w = tm.who(who)
  Bool.pick(String, String.eq(kind, "tool"), tm.esc("2", w ++ "› " ++ tm.short(text, 160n)),
    Bool.pick(String, String.eq(kind, "echo"), tm.esc("2", w ++ "  ⎿ " ++ tm.short(text, 160n)),
      Bool.pick(String, String.eq(kind, "mind"), tm.esc("2;3", w ++ text),
        Bool.pick(String, String.eq(kind, "note"), tm.esc("33", w ++ "note: " ++ text),
          Bool.pick(String, String.eq(kind, "work"), tm.esc("36", text),
            Bool.pick(String, String.eq(kind, "user"), tm.esc("1", w ++ "> " ++ text), w ++ text))))))

# an entry as printed into a pipe: whole
def tm.plain(+who: String, +kind: String, +text: String) -> String:
  tm.who(who) ++ kind ++ ": " ++ text

def tm.render(tty: Bool, +who: String, +kind: String, +text: String) -> String:
  match tty:
    case True{}:
      tm.tty(who, kind, text)
    case False{}:
      tm.plain(who, kind, text)

def tm.status(tty: Bool, +text: String) -> String:
  match tty:
    case True{}:
      tm.esc("2", "[" ++ text ++ "]")
    case False{}:
      "[" ++ text ++ "]"

def tm.help() -> String:
  "mugen: one chat that never ends. Type a message and press Enter; Alt-Enter makes a new line (Shift-Enter and C-j only where the terminal sends them apart from Enter), and a paste comes whole. Off the full screen, a message of many lines goes between two lines of \"\"\".\n/stop [name]   stop mugen's turn and the agents (or the agent named); C-g, or an empty line off the full screen\n/now           send the messages waiting at once: mugen's running command is cut (it reads them with its output), else its turn stops and one starts with them (C-s)\n/goal TEXT     a goal mugen works toward till a check finds it met; /halt drops it\n/model LABEL   opus-5.5, sonnet-5.5, haiku-5.5 (or a model id); /effort low|medium|high|xhigh|max\n/plan, /auto   plan mode (mugen reads and proposes, changing nothing); auto mode (it acts)\n/status        the account, limits, view, model, mode, summaries and agents\n/tree          the memory tree as a page; /export: the memory as ./mugen-memory.json\n/mouse         on the full screen: the mouse selects text (or, again, scrolls and opens blocks)\n/image [path]  on the full screen: the image at path (or the clipboard's) goes with the message being written\n/quit          leave (what runs goes on at the next start); Esc Esc, C-d, or C-c on an empty input\nOn the full screen: PgUp, PgDn and the wheel scroll (M-> back to the end); a click opens or folds a block, M-o (or C-o) all of them; Up on an empty input takes a message still waiting back to edit; while agents work, a click on a tab after the status line or M-Left/M-Right shows only one's blocks; the input has emacs' keys, C-r searches the history, Tab completes a command."
