
import Base
import ../Sys.bend as S
import ../Keys.bend as K
import ../Edit.bend as E
import ../Spell.bend as Sp
import ../Screen.bend as Sc
import ../Pretty.bend as P

# The spellcheck's pure parts (Spell.bend: the words, hunspell's answer
# read, the fixes, the underline, the layout's places), the keys it and
# Shift-Tab and Home take (Keys.bend's decoding, Screen.bend's map), then
# the real hunspell asked about a few words. Prints a FAIL line a case
# that fails, then PASS: n / m.

type T is Data:
  T{name: String, got: String, want: String}

def ws.show(ws: List<&2, Sp.sp.W>) -> String:
  match ws:
    case []:
      ""
    case +w <> +rest:
      Sp.sp.w.text(w) ++ "@" ++ Nat.show(Sp.sp.w.at(w)) ++ Bool.pick(String, List.is_empty(&2, Sp.sp.W, rest), "", " ") ++ ws.show(rest)

def bads.show(bs: List<&2, Sp.sp.Bad>) -> String:
  match bs:
    case []:
      ""
    case +b <> +rest:
      Sp.sp.bad.word(b) ++ ":" ++ String.join(Sp.sp.bad.sugg(b), ",") ++ Bool.pick(String, List.is_empty(&2, Sp.sp.Bad, rest), "", ";") ++ bads.show(rest)

def ed.show(+x: Sp.sp.Ed) -> String:
  Sp.sp.ed.text(x) ++ "|" ++ Nat.show(Sp.sp.ed.cur(x))

def nats.strs(ns: List<&2, Nat>) -> List<&2, String>:
  match ns:
    case []:
      []
    case +n <> rest:
      Nat.show(n) <> nats.strs(rest)

def nats.show(ns: List<&2, Nat>) -> String:
  String.join(nats.strs(ns), ",")

def key.show(k: K.ky.Key) -> String:
  match k:
    case K.ky.Char{c}:
      "Char " ++ U32.show(c)
    case K.ky.Ctrl{c}:
      "Ctrl " ++ U32.show(c)
    case K.ky.Meta{c}:
      "Meta " ++ U32.show(c)
    case K.ky.Enter{}:
      "Enter"
    case K.ky.Newline{}:
      "Newline"
    case K.ky.Tab{}:
      "Tab"
    case K.ky.BackTab{}:
      "BackTab"
    case K.ky.Back{}:
      "Back"
    case K.ky.MetaBack{}:
      "MetaBack"
    case K.ky.Esc{}:
      "Esc"
    case K.ky.Nav{n, m}:
      "Nav " ++ U32.show(n) ++ "/" ++ U32.show(m)
    case K.ky.Paste{t}:
      "Paste"
    case K.ky.Mouse{b, x, y, up}:
      "Mouse " ++ U32.show(b) ++ " " ++ U32.show(x) ++ " " ++ U32.show(y) ++ Bool.pick(String, up, " up", " down")
    case K.ky.Focus{on}:
      "Focus"
    case K.ky.Other{}:
      "Other"

def keys.show(ks: List<&2, K.ky.Key>) -> String:
  match ks:
    case []:
      ""
    case k <> +rest:
      key.show(k) ++ Bool.pick(String, List.is_empty(&2, K.ky.Key, rest), "", ", ") ++ keys.show(rest)

# what a terminal's bytes decode as
def dec(+s: String) -> String:
  keys.show(K.ky.out.keys(K.ky.feed(K.ky.start(), s)))

def esc() -> String:
  "\u{1B}"

# what the screen does with a key (Screen.bend sc.key.k), on an empty input
# or not
def act(+k: K.ky.Key, +empty: Bool) -> String:
  Nat.show(Sc.sc.key.k(k, False{}, empty, False{}, False{}))

# hunspell's answer to teh, quikc, brown, xyzzyq, well-known, 'tis
def out1() -> String:
  "@(#) International Ispell Version 3.2.06 (but really Hunspell 1.7.3)\n& teh 10 1: the, eh, tech, tee, tea, ten, tel, ted, meh, t eh\n\n& quikc 1 1: quick\n\n*\n\n# xyzzyq 1\n\n*\n*\n\n& tis 1 2: tees\n\n"

def bads1() -> List<&2, Sp.sp.Bad>:
  [Sp.sp.Bad{"teh", ["the", "eh"]}, Sp.sp.Bad{"quikc", ["quick"]}, Sp.sp.Bad{"dgo", ["dog", "do"]}]

def fixall(+t: String, +cur: Nat) -> String:
  ed.show(Sp.sp.fix.all(Sp.sp.flag(Sp.sp.words(t, cur), bads1()), Sp.sp.Ed{t, cur}))

def place.show(+p: Sp.sp.Pt) -> String:
  U32.show(Sp.sp.pt.row(p)) ++ ":" ++ U32.show(Sp.sp.pt.col(p))

# a box's rows, as text and width each
def box.show(rs: List<&2, String>) -> String:
  match rs:
    case []:
      ""
    case +r <> +rest:
      String.trim(P.pp.clean(r)) ++ ":" ++ U32.show(P.pp.vis(r)) ++ Bool.pick(String, List.is_empty(&2, String, rest), "", "|") ++ box.show(rest)

def lay.rows(+t: String, +room: U32) -> List<&2, String>:
  E.ed.lay.rows(E.ed.lay(E.ed.set(E.ed.new([]), t), room))

def on() -> String:
  Sp.sp.sgr.on()

def off() -> String:
  Sp.sp.sgr.off()

# a words file: a word, a *word, flags, spaces, an empty line
def dict1() -> String:
  "mugen\n*color\nfoo/AB\n  bar \n\nTelomare\n"

def dx.show(+x: Sp.sp.Dx) -> String:
  String.join(Sp.sp.dx.lines(x), ",") ++ "|" ++ String.join(Sp.sp.dx.done(x), ",") ++ "|" ++ String.join(Sp.sp.dx.left(x), ",")

def sp.show(+x: Sp.sp.Sp) -> String:
  String.join(Sp.sp.seen(x), ",") ++ "|" ++ String.join(Sp.sp.bad.words(Sp.sp.bad(x)), ",") ++ "|" ++ Sp.sp.last(x)

def cw.show(m: Maybe<&2, Sp.sp.W>) -> String:
  match m:
    case Some{+w}:
      Sp.sp.w.text(w) ++ "@" ++ Nat.show(Sp.sp.w.at(w))
    case None{}:
      "-"

def pure() -> List<&2, T>:
  +t1 = {"teh ok quikc" : String}
  +r1 = lay.rows(t1, 7)
  +s1 = Sp.sp.starts(r1, t1, 0n)
  +f1 = Sp.sp.flag(Sp.sp.words(t1, 0n), bads1())
  [T{"words: the one being written skipped", ws.show(Sp.sp.words("teh quikc brown", 15n)), "teh@0 quikc@4"},
   T{"words: cursor at the start", ws.show(Sp.sp.words("teh quikc brown", 0n)), "teh@0 quikc@4 brown@10"},
   T{"words: inside a word, it is checked", ws.show(Sp.sp.words("teh quikc brown", 2n)), "teh@0 quikc@4 brown@10"},
   T{"words: code in backticks and fences", ws.show(Sp.sp.words("see `fooo bar` and ```\nqzx wrds\n``` ok", 0n)), "see@0 and@15 ok@36"},
   T{"words: URLs, paths, addresses", ws.show(Sp.sp.words("visit https://exampel.com or ~/src/mugne and me@hhefesto.dev now", 0n)), "visit@0 or@26 and@41 now@61"},
   T{"words: digits, _, camelCase, one letter", ws.show(Sp.sp.words("abc123 foo_bar camelCase Fine iPhone ok x", 0n)), "Fine@25 ok@37"},
   T{"words: a shell command", ws.show(Sp.sp.words("  !ls teh", 0n)), ""},
   T{"words: a command's name", ws.show(Sp.sp.words("/spell on", 0n)), "on@7"},
   T{"words: apostrophes", ws.show(Sp.sp.words("'quoted' dogs' don't", 0n)), "quoted@1 dogs@9 don't@15"},
   T{"words: dots inside, a sentence's end", ws.show(Sp.sp.words("end. Next e.g. file.txt v1.2 done.", 0n)), "end@0 Next@5 done@29"},
   T{"words: accents", ws.show(Sp.sp.words("café naïve", 0n)), "café@0 naïve@5"},
   T{"fresh: once each, not seen", String.join(Sp.sp.fresh(Sp.sp.words("teh teh the ok quikc", 0n), ["the"], []), " "), "teh ok quikc"},
   T{"ask", Sp.sp.ask(["teh", "ok"]), "^teh\n^ok\n"},
   T{"parse: hunspell -a's answer", bads.show(Sp.sp.parse(out1(), ["teh", "quikc", "brown", "xyzzyq", "well-known", "'tis"])), "teh:the,eh,tech,tee,tea;quikc:quick;xyzzyq:;'tis:'tees"},
   T{"parse: fewer answers than words", bads.show(Sp.sp.parse("@(#) x\n& teh 1 1: the\n\n", ["teh", "abc"])), "teh:the"},
   T{"ran", Bool.pick(String, Bool.and(Sp.sp.ran(0, out1()), Bool.not(Sp.sp.ran(1, ""))), "yes", "no"), "yes"},
   T{"fix all", fixall("teh quikc brown", 15n), "the quick brown|15"},
   T{"fix all: the cursor in a word", fixall("I sea teh dgo now", 7n), "I sea the dog now|9"},
   T{"fix all: the one being written kept", fixall("teh quikc", 9n), "the quikc|9"},
   T{"fix one: the second suggestion", ed.show(Sp.sp.fix(Sp.sp.Ed{"x teh y", 7n}, Sp.sp.F{"teh", 2n, ["the", "eh"]}, 1n)), "x eh y|6"},
   T{"fix one: no such suggestion", ed.show(Sp.sp.fix(Sp.sp.Ed{"x teh y", 7n}, Sp.sp.F{"teh", 2n, ["the"]}, 3n)), "x teh y|7"},
   T{"fixable", Nat.show(Sp.sp.fixable([Sp.sp.F{"a", 0n, []}, Sp.sp.F{"b", 2n, ["c"]}])), "1"},
   T{"mask", Sp.sp.mask(f1, 0n, String.length(t1)), "111000011111"},
   T{"layout rows", String.join(r1, "|"), "teh ok |quikc"},
   T{"starts", nats.show(s1), "0,7"},
   T{"starts: a newline", nats.show(Sp.sp.starts(lay.rows("ab\ncd", 10), "ab\ncd", 0n)), "0,3"},
   T{"paint", String.join(Sp.sp.paint(r1, t1, Sp.sp.mask(f1, 0n, String.length(t1))), "|"), on() ++ "teh" ++ off() ++ " ok |" ++ on() ++ "quikc" ++ off()},
   T{"place", place.show(Sp.sp.place(r1, s1, 9n, 0)), "1:2"},
   T{"spot", Nat.show(Maybe.default(&2, Nat, Sp.sp.spot(r1, s1, 1, 2), 99n)), "9"},
   T{"spot: past a row's end", Nat.show(Maybe.default(&2, Nat, Sp.sp.spot(r1, s1, 1, 7), 99n)), "99"},
   T{"target: the mouse's word first", Nat.show(Sp.sp.key.of(Sp.sp.target(f1, 1n, 8n))), "8"},
   T{"target: else the cursor's", Nat.show(Sp.sp.key.of(Sp.sp.target(f1, 1n, 0n))), "1"},
   T{"target: none", Nat.show(Sp.sp.key.of(Sp.sp.target(f1, 4n, 0n))), "0"},
   T{"box", box.show(Sp.sp.box.rows(Sp.sp.F{"teh", 0n, ["the", "eh"]})), "1 the:33|2 eh:33|+ add \u{ab}teh\u{bb} to your words \u{b7} M-a:33|M-s \u{b7} M-1..2 \u{b7} M-S all \u{b7} Esc:33"},
   T{"box: the first lit", Bool.pick(String, String.starts_with(Maybe.default(&2, String, List.get(&2, String, Sp.sp.box.rows(Sp.sp.F{"teh", 0n, ["the", "eh"]}), 0n), ""), "\u{1B}[0m\u{1B}[1;97;44m 1 the "), "yes", "no"), "yes"},
   T{"box: no suggestion", box.show(Sp.sp.box.rows(Sp.sp.F{"xq", 0n, []})), "+ add \u{ab}xq\u{bb} to your words \u{b7} M-a:32|no suggestion \u{b7} Esc:32"},
   T{"box: five at most", Nat.show(List.length(&2, String, Sp.sp.box.rows(Sp.sp.F{"teh", 0n, ["a", "b", "c", "d", "e", "f", "g"]}))), "7"},
   T{"box: the + add row keeps the word's form", box.show(List.take(&2, String, Sp.sp.box.rows(Sp.sp.F{"Telomare", 0n, []}), 1n)), "+ add \u{ab}telomare\u{bb} to your words \u{b7} M-a:38"},
   T{"words: the form kept", String.join([Sp.sp.dict.form("Telomare"), Sp.sp.dict.form("GitHub"), Sp.sp.dict.form("NASA"), Sp.sp.dict.form("Café"), Sp.sp.dict.form("chekc")], " "), "telomare GitHub NASA café chekc"},
   T{"words: the file's words", String.join(Sp.sp.dict.words(Sp.sp.dict.lines(dict1())), ","), "mugen,foo,bar,Telomare"},
   T{"words: the file's text", Sp.sp.dict.text(["a", "b"]), "a\nb\n"},
   T{"words: has (any line's form)", Bool.pick(String, Bool.and(Sp.sp.dict.has(Sp.sp.dict.lines(dict1()), "telomare"), Bool.not(Sp.sp.dict.has(Sp.sp.dict.lines(dict1()), "color"))), "yes", "no"), "yes"},
   T{"words: add", dx.show(Sp.sp.dict.add(["Chekc", "mugen", "x/y", "*no", "OAuth"], Sp.sp.dx.new(Sp.sp.dict.lines(dict1())))), "mugen,*color,foo/AB,  bar ,Telomare,chekc,OAuth|chekc,OAuth|mugen,x/y,*no"},
   T{"words: add the same twice", dx.show(Sp.sp.dict.add(["teh", "Teh"], Sp.sp.dx.new([]))), "teh|teh|teh"},
   T{"words: rm (any case, flags too; a *word stays)", dx.show(Sp.sp.dict.rm(["Foo", "telomare", "color", "nope"], Sp.sp.dx.new(Sp.sp.dict.lines(dict1())))), "mugen,*color,  bar |foo,telomare|color,nope"},
   T{"words: forget a word (any case), look anew", sp.show(Sp.sp.forget(Sp.sp.with.last(Sp.sp.with.got(Sp.sp.new(), ["Teh", "teh", "the", "ok"], [Sp.sp.Bad{"teh", ["the"]}, Sp.sp.Bad{"Teh", ["The"]}, Sp.sp.Bad{"quikc", []}]), "key"), "teh")), "the,ok|quikc|"},
   T{"words: known (asked, good)", Bool.pick(String, Bool.and(Sp.sp.known(Sp.sp.with.got(Sp.sp.new(), ["the", "teh"], [Sp.sp.Bad{"teh", []}]), "the"), Bool.not(Sp.sp.known(Sp.sp.with.got(Sp.sp.new(), ["the", "teh"], [Sp.sp.Bad{"teh", []}]), "teh"))), "yes", "no"), "yes"},
   T{"words: the cursor's word, at its end too", cw.show(Sp.sp.cur.word("I sea teh", 9n)) ++ " " ++ cw.show(Sp.sp.cur.word("I sea teh", 3n)) ++ " " ++ cw.show(Sp.sp.cur.word("ab   cd", 3n)), "teh@6 sea@2 -"},
   T{"decode: Shift-Tab, CSI Z", dec(esc() ++ "[Z"), "BackTab"},
   T{"decode: Shift-Tab, CSI u", dec(esc() ++ "[9;2u"), "BackTab"},
   T{"decode: Shift-Tab, modifyOtherKeys", dec(esc() ++ "[27;2;9~"), "BackTab"},
   T{"decode: M-S, ESC S", dec(esc() ++ "S"), "Meta 83"},
   T{"decode: M-S, CSI u (s, Shift, Alt)", dec(esc() ++ "[115;4u"), "Meta 83"},
   T{"decode: M-s", dec(esc() ++ "s"), "Meta 115"},
   T{"decode: M-3", dec(esc() ++ "3"), "Meta 51"},
   T{"decode: Home, CSI H", dec(esc() ++ "[H"), "Nav 5/0"},
   T{"decode: Home, CSI 1~", dec(esc() ++ "[1~"), "Nav 5/0"},
   T{"decode: Home, CSI 7~", dec(esc() ++ "[7~"), "Nav 5/0"},
   T{"decode: Home, SS3 H", dec(esc() ++ "OH"), "Nav 5/0"},
   T{"decode: C-Home", dec(esc() ++ "[1;5H"), "Nav 5/4"},
   T{"decode: End, CSI F, 4~, 8~, SS3 F", dec(esc() ++ "[F" ++ esc() ++ "[4~" ++ esc() ++ "[8~" ++ esc() ++ "OF"), "Nav 6/0, Nav 6/0, Nav 6/0, Nav 6/0"},
   T{"decode: the mouse moved", dec(esc() ++ "[<35;4;40M"), "Mouse 35 4 40 down"},
   T{"screen: Shift-Tab", act(K.ky.BackTab{}, False{}), "27"},
   T{"screen: Tab", act(K.ky.Tab{}, False{}), "9"},
   T{"screen: Home on an empty input: the top", act(K.ky.Nav{5, 0}, True{}), "12"},
   T{"screen: Home in a text: its line's start", act(K.ky.Nav{5, 0}, False{}), "0"},
   T{"screen: End on an empty input: the end", act(K.ky.Nav{6, 0}, True{}), "13"},
   T{"screen: End in a text", act(K.ky.Nav{6, 0}, False{}), "0"},
   T{"screen: M-<", act(K.ky.Meta{60}, False{}), "12"},
   T{"screen: M-s", act(K.ky.Meta{115}, False{}), "23"},
   T{"screen: M-S", act(K.ky.Meta{83}, False{}), "24"},
   T{"screen: M-3", act(K.ky.Meta{51}, False{}), "25"},
   T{"screen: M-b stays an edit", act(K.ky.Meta{98}, False{}), "0"},
   T{"screen: M-o", act(K.ky.Meta{111}, False{}), "6"},
   T{"screen: the mouse moved", act(K.ky.Mouse{35, 4, 40, False{}}, False{}), "28"},
   T{"screen: a drag", act(K.ky.Mouse{32, 4, 40, False{}}, False{}), "18"},
   T{"screen: Esc", act(K.ky.Esc{}, False{}), "8"},
   T{"screen: M-a", act(K.ky.Meta{97}, False{}), "29"},
   T{"screen: M-?", act(K.ky.Meta{63}, False{}), "30"},
   T{"decode: M-a, M-?", dec(esc() ++ "a" ++ esc() ++ "?"), "Meta 97, Meta 63"}]

def bads.first(bs: List<&2, Sp.sp.Bad>) -> String:
  match bs:
    case []:
      ""
    case +b <> +rest:
      Sp.sp.bad.word(b) ++ ":" ++ Maybe.default(&2, String, List.get(&2, String, Sp.sp.bad.sugg(b), 0n), "") ++ Bool.pick(String, List.is_empty(&2, Sp.sp.Bad, rest), "", ";") ++ bads.first(rest)

# hunspell itself, asked about a few words
def real(o: S.mu.Out) -> List<&2, T>:
  match o:
    case S.mu.Out{+status, +out, +err}:
      +ws = {["teh", "quikc", "brown", "don't", "café"] : List<&2, String>}
      +bs = Sp.sp.parse(out, ws)
      [T{"hunspell ran", Bool.pick(String, Sp.sp.ran(status, out), "yes", "no: " ++ U32.show(status) ++ " " ++ err), "yes"},
       T{"hunspell: the bad words, the best suggestion first", bads.first(bs), "teh:the;quikc:quick;café:cafe"},
       T{"hunspell: fix all", ed.show(Sp.sp.fix.all(Sp.sp.flag(Sp.sp.words("teh quikc brown", 15n), bs), Sp.sp.Ed{"teh quikc brown", 15n})), "the quick brown|15"}]

def run(ts: List<&2, T>, +pass: Nat, +n: Nat) -> IO(Unit):
  match ts:
    case []:
      IO.print("PASS: " ++ Nat.show(pass) ++ " / " ++ Nat.show(n))
    case +t <> rest:
      match t:
        case T{+name, +got, +want}:
          +ok = String.eq(got, want)
          do IO<Unit>:
            Unit <- Bool.pick(IO(Unit), ok, IO.pure(Unit, Unit{}), IO.print("FAIL " ++ name ++ "\n  got:  " ++ got ++ "\n  want: " ++ want))
            run(rest, Nat.add(pass, Bool.pick(Nat, ok, 1n, 0n)), Nat.add(n, 1n))

# hunspell with a words file (-p, as ~/.hunspell_en_US is by default):
# a word kept lowercase comes capitalized too, not all in capitals
def real.words(o: S.mu.Out) -> List<&2, T>:
  match o:
    case S.mu.Out{+status, +out, +err}:
      +ws = {["chekc", "Chekc", "teh", "GitHub", "Github"] : List<&2, String>}
      [T{"hunspell with your words ran", Bool.pick(String, Sp.sp.ran(status, out), "yes", "no: " ++ U32.show(status) ++ " " ++ err), "yes"},
       T{"hunspell with your words: those left bad", String.join(Sp.sp.bad.words(Sp.sp.parse(out, ws)), ","), "teh,Github"}]

def main() -> IO(Unit):
  do IO<Unit>:
    o : S.mu.Out <- S.mu.run("hunspell", Sp.sp.args(), Sp.sp.ask(["teh", "quikc", "brown", "don't", "café"]), 1048576, 20000)
    tmp : String <- S.mu.env("TMPDIR", "/tmp")
    +p : String = tmp ++ "/spellcheck-words"
    r : Result<&1, &1, U32 & String, Unit> <- S.mu.save(p, Sp.sp.dict.text(Sp.sp.dx.lines(Sp.sp.dict.add(["Chekc", "GitHub"], Sp.sp.dx.new([])))), 0)
    o2 : S.mu.Out <- S.mu.run("hunspell", Sp.sp.args.p(p), Sp.sp.ask(["chekc", "Chekc", "teh", "GitHub", "Github"]), 1048576, 20000)
    run(List.concat(&2, T, [pure(), real(o), real.words(o2)]), 0n, 0n)
