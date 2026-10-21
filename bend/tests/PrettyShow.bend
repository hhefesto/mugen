import Base
import ../Pretty.bend as P

# a look at Pretty's blocks, at 72 columns (not a check: for the eye)
def show(rs: List<&2, String>) -> IO(Unit):
  match rs:
    case []:
      IO.pure(Unit, Unit{})
    case r <> t:
      IO.bind(Unit, Unit, IO.print("|" ++ r ++ "\u{1B}[0m"), u => show(t))

def diff() -> String:
  "--- /home/u/src/a.ts\n+++ /home/u/src/a.ts\n@@ -10,4 +10,5 @@ function f\n   const a = 1;\n-  const b = 2;\n+  const b = 3;\n+  const c = a + b; // a very long line that has to wrap because it is longer than the width of the screen here\n   return b;\n"

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- show(P.pp.block("user", "", "we will now work on yourself at ~/src/mugen . Note that I currently see no lambda prompt as I restarted mugen.\nSecond line.", "", False{}, False{}, 72, "/home/u"))
    Unit <- show(P.pp.block("unii", "", "Here is **bold** and `code`.\n\n# A heading\n- a bullet that is long enough to wrap around the edge of the screen, twice or so maybe\n```diff\n-old\n+new\n```\nDone.", "", False{}, False{}, 72, "/home/u"))
    Unit <- show(P.pp.block("mind", "", "I should check the file first, then edit it. This is a long thought that goes on and on and on to wrap several rows, more than three, so that it folds away nicely here.", "", False{}, False{}, 72, "/home/u"))
    Unit <- show(P.pp.block("tool", "", "shell {\"device\":\"olimpo\",\"command\":\"cd ~/src/bend2 && sed -n 200,260p bend.ts; echo ----; sed -n 3040,3200p bend.ts\"}", "line one\n\tindented\u{1B}[31mred\u{1B}[0m\nthree\nfour\nfive\nsix\nseven\neight\n(exit 0 in 0.1 s)", False{}, False{}, 72, "/home/u"))
    Unit <- show(P.pp.block("tool", "", "shell {\"device\":\"olimpo\",\"command\":\"false\"}", "error: (exit 1 in 0.0 s)", False{}, False{}, 72, "/home/u"))
    Unit <- show(P.pp.block("tool", "Brave", "edit {\"device\":\"olimpo\",\"edits\":[{\"path\":\"/home/u/src/a.ts\",\"old\":\"x\",\"new\":\"y\"}]}", diff(), False{}, False{}, 72, "/home/u"))
    Unit <- show(P.pp.block("tool", "", "read {\"device\":\"olimpo\",\"path\":\"/home/u/x.txt\"}", "a\nb\n[lines 1-2 of 2]", False{}, False{}, 72, "/home/u"))
    Unit <- show(P.pp.block("tool", "", "shell {\"device\":\"olimpo\",\"command\":\"sleep 100\"}", "", False{}, True{}, 72, "/home/u"))
    Unit <- show(P.pp.block("note", "", "Stopped by the user: mugen's turn.", "", False{}, False{}, 72, "/home/u"))
    Unit <- show(P.pp.block("usage", "", "cache: 3.9k read, 595 written, 2 new in, 30 out", "", False{}, False{}, 72, "/home/u"))
    Unit <- show(P.pp.block("work", "", "[BraveOtter]\nI looked at it.\n\nFull chat: zoom(\"BraveOtter\")", "", False{}, False{}, 72, "/home/u"))
    show(P.pp.block("info", "", "\u{1B}[1;35m\u{7121}\u{9650} mugen\u{1B}[0m\u{1B}[2m  one chat that never ends\u{1B}[0m and a lot more text past the edge of the screen to be cut away here", "", False{}, False{}, 72, "/home/u"))
