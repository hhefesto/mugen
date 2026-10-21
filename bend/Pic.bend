
import Base
import ./Sys.bend as S
import ./Json.bend as J
import ./View.bend as V
import ./Text.bend as T

# Pic: images, for the model to see (UniiChat's Img). An image the user
# attaches (/image, Screen.bend) is kept in the mugen dir's docs/images/ by
# its hash, NAME a 16 hex digits and its kind, and its message says so on a
# line of its own: "[image docs/images/NAME]". A turn's call takes the
# images its new messages name; zoom(id, 1) gives a message's images, and
# read an image file's; summaries keep the line, not the image.
#
# An image on its way to a call is a pic: its media type, a space, its bytes
# in base64. Pics ride in texts after a \u{1}, each after one: a block's
# text that starts with it is an image block, a tool result's text carries
# its pics after its own (Ev.ev.Out); pc.text drops them where the text is
# logged or shown.
#
# Every def is prefixed `pc.` (a program's defs share one namespace).

def pc.sep() -> String:
  "\u{1}"

# the line naming an image, and the dir images are kept in
def pc.head() -> String:
  "[image docs/images/"

def pc.line(+name: String) -> String:
  pc.head() ++ name ++ "]"

def pc.dir(+mugen: String) -> String:
  mugen ++ "/docs/images"

# the most base64 an image may be (the API's 5 MB)
def pc.max() -> U32:
  5242880

# an image's kind by its first bytes, in base64: png, jpeg, gif, webp (RIFF
# and, at byte 8, WEBP); "" none of them
def pc.kind(+b: String) -> String:
  Bool.pick(String, String.starts_with(b, "iVBORw0KGgo"), "image/png",
    Bool.pick(String, String.starts_with(b, "/9j/"), "image/jpeg",
      Bool.pick(String, String.starts_with(b, "R0lGOD"), "image/gif",
        Bool.pick(String, Bool.and(String.starts_with(b, "UklGR"), String.starts_with(String.drop(b, 12n), "RUJQ")), "image/webp", ""))))

# the kind's file extension
def pc.ext(+kind: String) -> String:
  String.drop(kind, 6n)

# why the base64 is no image to send ("" it is one)
def pc.why(+b: String) -> String:
  Bool.pick(String, String.is_empty(pc.kind(b)), "it is no image: images are png, jpeg, gif or webp",
    Bool.pick(String, U32.is_gt(T.tx.units(b), pc.max()), "it is too large: " ++ U32.show(T.tx.units(b)) ++ " bytes in base64, past the 5 MB a model takes", ""))

# the pic of an image's base64
def pc.of(+b: String) -> String:
  pc.kind(b) ++ " " ++ b

def pc.b64.of(o: S.mu.Out) -> String:
  match o:
    case S.mu.Out{st, out, err}:
      Bool.pick(String, U32.is_eq(st, 0), out, "")

# a file's bytes in base64 ("" unreadable)
def pc.b64(+file: String) -> IO(String):
  IO.bind(S.mu.Out, String, S.mu.run("base64", ["-w0", "--", file], "", 16777216, 30000), o => IO.pure(String, pc.b64.of(o)))

# The text and its pics ------------------------------------------------------
#
# (the walks are tail calls: a pic is megabytes)

# a text cut at each \u{1}: its pieces, in order
def pc.cut(s: String, cur: String, acc: List<&2, String>) -> List<&2, String>:
  match s:
    case SNil{}:
      List.reverse(&2, String, String.reverse(cur) <> acc)
    case SCon{Chr{1}, t}:
      pc.cut(t, "", String.reverse(cur) <> acc)
    case SCon{c, t}:
      pc.cut(t, SCon{c, cur}, acc)

# a text up to its first \u{1} (acc reversed), and past it
def pc.upto(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{1}, t}:
      String.reverse(acc)
    case SCon{c, t}:
      pc.upto(t, SCon{c, acc})

def pc.past(s: String) -> Maybe<&2, String>:
  match s:
    case SNil{}:
      None{}
    case SCon{Chr{1}, t}:
      Some{t}
    case SCon{c, t}:
      pc.past(t)

# the text without its pics, and its pics
def pc.text(s: String) -> String:
  pc.upto(s, "")

def pc.pics.of(m: Maybe<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      []
    case Some{r}:
      pc.cut(r, "", [])

def pc.pics(s: String) -> List<&2, String>:
  pc.pics.of(pc.past(s))

# a text with pics after it
def pc.with.go(ps: List<&2, String>, +text: String) -> String:
  match ps:
    case []:
      text
    case +p <> t:
      pc.with.go(t, text ++ pc.sep() ++ p)

def pc.with(+text: String, ps: List<&2, String>) -> String:
  pc.with.go(ps, text)

# a pic's media type (up to its space), and data (past it)
def pc.media.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{Chr{32}, t}:
      String.reverse(acc)
    case SCon{c, t}:
      pc.media.go(t, SCon{c, acc})

def pc.data.go(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{32}, t}:
      t
    case SCon{c, t}:
      pc.data.go(t)

def pc.media(p: String) -> String:
  pc.media.go(p, "")

def pc.data(p: String) -> String:
  pc.data.go(p)

# a pic as a content block, the API's (and Claude Code's stream-json's)
def pc.json(+p: String) -> J.Json:
  J.JObj{[J.JKv{"type", J.JStr{"image"}}, J.JKv{"source", J.JObj{[J.JKv{"type", J.JStr{"base64"}}, J.JKv{"media_type", J.JStr{pc.media(p)}}, J.JKv{"data", J.JStr{pc.data(p)}}]}}]}

def pc.jsons(ps: List<&2, String>) -> List<&2, J.Json>:
  match ps:
    case []:
      []
    case +p <> t:
      pc.json(p) <> pc.jsons(t)

# a pic as MCP's image content
def pc.mcp(+p: String) -> J.Json:
  J.JObj{[J.JKv{"type", J.JStr{"image"}}, J.JKv{"data", J.JStr{pc.data(p)}}, J.JKv{"mimeType", J.JStr{pc.media(p)}}]}

def pc.mcps(ps: List<&2, String>) -> List<&2, J.Json>:
  match ps:
    case []:
      []
    case +p <> t:
      pc.mcp(p) <> pc.mcps(t)

# a block that is an image, and whether a block's text is one
def pc.block(+p: String) -> V.vw.B:
  V.vw.B{pc.sep() ++ p, False{}}

def pc.blocks(ps: List<&2, String>) -> List<&2, V.vw.B>:
  match ps:
    case []:
      []
    case +p <> t:
      pc.block(p) <> pc.blocks(t)

def pc.is.block(+text: String) -> Bool:
  String.starts_with(text, pc.sep())

def pc.block.json(+text: String) -> J.Json:
  pc.json(String.drop(text, 1n))

# Names ----------------------------------------------------------------------

def pc.hex(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102))), pc.hex(t))

def pc.letters(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, SNil{}}:
      Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122))
    case SCon{Chr{+c}, t}:
      Bool.and(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), pc.letters(t))

# a name as kept: 16 hex digits, a dot, an extension of letters
def pc.name.ok(+n: String) -> Bool:
  Bool.and(Nat.is_eq(String.length(String.take(n, 17n)), 17n),
    Bool.and(pc.hex(String.take(n, 16n)), Bool.and(String.starts_with(String.drop(n, 16n), "."), pc.letters(String.drop(n, 17n)))))

# a line from its "[image docs/images/" on ("" none: the line's end)
def pc.seek(s: String, hit: Bool) -> String:
  match s hit:
    case SNil{} _:
      ""
    case SCon{c, t} True{}:
      SCon{c, t}
    case SCon{c, +t} False{}:
      pc.seek(t, String.starts_with(t, pc.head()))

# the name a line ends on (a zoom's "id+n|user: " may come before), "" none
def pc.name.of(+l: String) -> String:
  +t = String.trim(pc.seek(l, String.starts_with(l, pc.head())))
  +n = String.drop(String.take(t, Nat.sub(String.length(t), 1n)), String.length(pc.head()))
  Bool.pick(String, Bool.and(Bool.and(String.starts_with(t, pc.head()), String.ends_with(t, "]")), pc.name.ok(n)), n, "")

def pc.elem(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case []:
      False{}
    case +y <> t:
      Bool.or(String.eq(x, y), pc.elem(t, x))

# the images a text names, in order, each once
def pc.names.go(ls: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match ls:
    case []:
      List.reverse(&2, String, acc)
    case +l <> t:
      +n = pc.name.of(l)
      pc.names.go(t, Bool.pick(List<&2, String>, Bool.or(String.is_empty(n), pc.elem(acc, n)), acc, n <> acc))

def pc.names(+text: String) -> List<&2, String>:
  pc.names.go(String.lines(text), [])

# the most images a call takes (the API's, for a request of many)
def pc.most() -> Nat:
  20n

# the pics of the images a text names (the last pc.most of them), from the
# mugen dir; an image gone or spoilt is left out
def pc.load(+mugen: String, ns: List<&2, String>) -> IO(List<&2, String>):
  match ns:
    case []:
      IO.pure(List<&2, String>, [])
    case +n <> t:
      do IO<List<&2, String>>:
        +b : String <- pc.b64(pc.dir(mugen) ++ "/" ++ n)
        +ps : List<&2, String> <- pc.load(mugen, t)
        return Bool.pick(List<&2, String>, String.is_empty(pc.why(b)), pc.of(b) <> ps, ps)

def pc.named(+mugen: String, +text: String) -> IO(List<&2, String>):
  +ns = pc.names(text)
  pc.load(mugen, List.drop(&2, String, ns, Nat.sub(List.length(&2, String, ns), pc.most())))

# Attaching ------------------------------------------------------------------

# a path as typed or dropped: quotes around it dropped, ~ the home
def pc.path(+home: String, +arg: String) -> String:
  +a = String.trim(arg)
  +n = String.length(a)
  +q = Bool.and(Nat.is_ge(n, 2n), Bool.or(Bool.and(String.starts_with(a, "'"), String.ends_with(a, "'")), Bool.and(String.starts_with(a, "\""), String.ends_with(a, "\""))))
  +b = Bool.pick(String, q, String.drop(String.take(a, Nat.sub(n, 1n)), 1n), a)
  Bool.pick(String, Bool.or(String.eq(b, "~"), String.starts_with(b, "~/")), home ++ String.drop(b, 1n), b)

# copies the file in as NAME (its hash, its kind's extension), printing it
def pc.keep.sh() -> String:
  "set -e; mkdir -p \"$2\"; n=$(sha256sum < \"$1\" | cut -c1-16).$3; [ -e \"$2/$n\" ] || cp -- \"$1\" \"$2/$n\"; printf %s \"$n\""

# the clipboard's image (X's, by xclip) put in a file
def pc.clip.sh() -> String:
  "command -v xclip >/dev/null || { echo 'no xclip'; exit 1; }; [ -n \"$DISPLAY\" ] || { echo 'no X display'; exit 1; }; xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -q '^image/png$' || { echo 'no image in the clipboard'; exit 1; }; mkdir -p \"$(dirname \"$1\")\"; xclip -selection clipboard -t image/png -o > \"$1\""

# an attachment: its name ("" none), what to tell the user
type pc.Got is Data:
  pc.Got{name: String, note: String}

def pc.got.name(g: pc.Got) -> String:
  match g:
    case pc.Got{n, t}:
      n

def pc.got.note(g: pc.Got) -> String:
  match g:
    case pc.Got{n, t}:
      t

def pc.kept(+shown: String, o: S.mu.Out) -> pc.Got:
  match o:
    case S.mu.Out{st, +out, err}:
      Bool.pick(pc.Got, Bool.and(U32.is_eq(st, 0), pc.name.ok(out)), pc.Got{out, "attached " ++ shown ++ ": it goes with this message"},
        pc.Got{"", "not attached: " ++ shown ++ " could not be kept (" ++ String.trim(err) ++ ")"})

# keeps the image in `file` (shown as `shown`) in the mugen dir
def pc.keep.b(+mugen: String, +file: String, +shown: String, +b: String) -> IO(pc.Got):
  +why = Bool.pick(String, String.is_empty(b), "no file " ++ shown, pc.why(b))
  Bool.pick(IO(pc.Got), String.is_empty(why),
    IO.bind(S.mu.Out, pc.Got, S.mu.run("sh", ["-c", pc.keep.sh(), "sh", file, pc.dir(mugen), pc.ext(pc.kind(b))], "", 4096, 30000), o => IO.pure(pc.Got, pc.kept(shown, o))),
    IO.pure(pc.Got, pc.Got{"", "not attached: " ++ Bool.pick(String, String.is_empty(b), why, shown ++ ": " ++ why)}))

# keeps the image in `file` (shown as `shown`) in the mugen dir
def pc.keep(+mugen: String, +file: String, +shown: String) -> IO(pc.Got):
  IO.bind(String, pc.Got, pc.b64(file), b => pc.keep.b(mugen, file, shown, b))

def pc.clipped(+mugen: String, +file: String, o: S.mu.Out) -> IO(pc.Got):
  match o:
    case S.mu.Out{st, +out, err}:
      Bool.pick(IO(pc.Got), U32.is_eq(st, 0), pc.keep(mugen, file, "the clipboard's image"), IO.pure(pc.Got, pc.Got{"", "not attached: " ++ String.trim(out)}))

# /image PATH: the image at PATH; /image alone: the clipboard's
def pc.attach(+mugen: String, +home: String, +arg: String) -> IO(pc.Got):
  +file = pc.path(home, arg)
  +clip = mugen ++ "/run/clip.png"
  Bool.pick(IO(pc.Got), String.is_empty(file),
    IO.bind(S.mu.Out, pc.Got, S.mu.run("sh", ["-c", pc.clip.sh(), "sh", clip], "", 4096, 10000), o => pc.clipped(mugen, clip, o)),
    pc.keep(mugen, file, String.trim(arg)))
