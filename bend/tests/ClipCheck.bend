
import Base
import ../Screen.bend as Sc

# Copying (Screen.bend, sc.clip, sc.clip.took, sc.copied): what a copy's
# line says for each answer of sc.clip, and when the login's link counts as
# copied. Prints a FAIL line a case that fails, then PASS: n / m. With any
# argument it prints sc.clip's shell instead, to try by hand where the user
# is: `printf hi | sh -c "$(clipcheck sh)"` answers where it went.

type T is Data:
  T{name: String, got: String, want: String}

def bl(+b: Bool) -> String:
  Bool.pick(String, b, "yes", "no")

# whether the line for answer `to` (2 lines copied) holds `part`
def says(+to: String, +part: String) -> String:
  bl(String.contains(Sc.sc.copied(2n, to), part))

def cases() -> List<&2, T>:
  [T{"X's clipboard took it", bl(Sc.sc.clip.took("xt")), "yes"},
   T{"X's, under VTE too", bl(Sc.sc.clip.took("xtv")), "yes"},
   T{"tmux's buffer, a terminal that may take OSC 52", bl(Sc.sc.clip.took("t")), "yes"},
   T{"tmux's buffer under VTE: not the clipboard", bl(Sc.sc.clip.took("tv")), "no"},
   T{"OSC 52 of ours under VTE: not the clipboard", bl(Sc.sc.clip.took("ov")), "no"},
   T{"OSC 52 of ours elsewhere", bl(Sc.sc.clip.took("o")), "yes"},
   T{"nowhere", bl(Sc.sc.clip.took("")), "no"},
   T{"VTE alone", bl(Sc.sc.clip.took("v")), "no"},
   T{"xt: to the clipboard", says("xt", "copied 2 lines to the clipboard"), "yes"},
   T{"xtv: to the clipboard", says("xtv", "copied 2 lines to the clipboard"), "yes"},
   T{"tv: tmux's buffer only", says("tv", "2 lines in tmux's buffer only (C-b ] pastes it), not the clipboard"), "yes"},
   T{"tv: never a check mark", says("tv", "\u{2713}"), "no"},
   T{"tv: why", says("tv", "drops OSC 52, and there is no X display for xclip"), "yes"},
   T{"t: tmux's buffer, the terminal's too if it takes OSC 52", says("t", "copied 2 lines to tmux's buffer (the terminal's clipboard too, if it takes OSC 52)"), "yes"},
   T{"o: sent by OSC 52", says("o", "sent 2 lines to the terminal's clipboard (by OSC 52, if it takes it)"), "yes"},
   T{"ov: not copied", says("ov", "\u{2717} not copied: this terminal (VTE's"), "yes"},
   T{"nowhere: not copied", says("", "\u{2717} not copied: no X display for xclip, no tmux, no terminal"), "yes"},
   T{"one line", bl(String.contains(Sc.sc.copied(1n, "x"), "copied 1 line to")), "yes"},
   T{"the Shift-drag hint stays", says("tv", "Shift-drag selects with the terminal"), "yes"}]

def run(ts: List<&2, T>, +ok: Nat, +all: Nat) -> IO(Unit):
  match ts:
    case []:
      IO.print("PASS: " ++ Nat.show(ok) ++ " / " ++ Nat.show(all))
    case T{+name, +got, +want} <> rest:
      +same = String.eq(got, want)
      do IO<Unit>:
        IO.print(Bool.pick(String, same, "", "FAIL " ++ name ++ ": got [" ++ got ++ "], want [" ++ want ++ "]"))
        run(rest, Bool.pick(Nat, same, Nat.add(ok, 1n), ok), Nat.add(all, 1n))

# the arguments after the program's name: none, the cases; any, the shell
def go(args: List<String>) -> IO(Unit):
  match args:
    case []:
      run(cases(), 0n, 0n)
    case a <> rest:
      IO.print(Sc.sc.clip())

def go.argv(argv: List<String>) -> IO(Unit):
  match argv:
    case []:
      go([])
    case p <> rest:
      go(rest)

def main() -> IO(Unit):
  do IO<Unit>:
    argv : List<String> <- IO.args()
    go.argv(argv)
