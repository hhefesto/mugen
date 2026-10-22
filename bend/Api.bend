
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./View.bend as V
import ./Pic.bend as Pc
import ./Code.bend as C

# Api: the Messages API by curl, as UniiChat's Anthropic.ts and Agent.ts
# shape and read it, but not streamed (v1): a request is one Process.run of
# curl, its body on stdin, the key read by curl from the environment (never
# in argv); or (the default wire) one call of Claude Code's CLI, a turn
# with no tools (Code.bend cc.once), read into the same step; or, for an
# OpenAI model on either wire, the Responses API by curl (UniiChat's
# OpenAI.ts: below, OpenAI). A step sends every item and reads one message; an error is
# `busy` (no connection, a retry status) and asked again, TRIES times at
# most, after its retry-after or a doubling wait, else `down`; a refusal or
# a stop reason is `fail` (the input's doing: asked again, it fails alike).
# A patient call (a summary's) asks anew every minute while the API is down,
# so an outage only delays it.
#
# Every def is prefixed `ap.` (a program's defs share one namespace).

# Settings ------------------------------------------------------------------

# the curl to run (MUGEN_CURL: a stand-in for tests), the endpoint, the
# most tokens a reply writes, the web search tool's type, how many ms a
# second of waiting takes (1000; tests make waits short), Claude Code's
# settings (its wire, when on, the calls'); OpenAI's endpoint, whether its
# key is in the environment (OPENAI_API_KEY), else the file it is read from
type ap.Cfg is Data:
  ap.Cfg{curl: String, url: String, max: U32, web: String, unit: U32, cc: C.cc.Cfg, ourl: String, okey: Bool, ofile: String}

def ap.cfg.curl(c: ap.Cfg) -> String:
  match c:
    case ap.Cfg{curl, url, max, web, unit, cc, ourl, okey, ofile}:
      curl

def ap.cfg.url(c: ap.Cfg) -> String:
  match c:
    case ap.Cfg{curl, url, max, web, unit, cc, ourl, okey, ofile}:
      url

def ap.cfg.max(c: ap.Cfg) -> U32:
  match c:
    case ap.Cfg{curl, url, max, web, unit, cc, ourl, okey, ofile}:
      max

def ap.cfg.web(c: ap.Cfg) -> String:
  match c:
    case ap.Cfg{curl, url, max, web, unit, cc, ourl, okey, ofile}:
      web

def ap.cfg.unit(c: ap.Cfg) -> U32:
  match c:
    case ap.Cfg{curl, url, max, web, unit, cc, ourl, okey, ofile}:
      unit

def ap.cfg.cc(c: ap.Cfg) -> C.cc.Cfg:
  match c:
    case ap.Cfg{curl, url, max, web, unit, cc, ourl, okey, ofile}:
      cc

def ap.cfg.ourl(c: ap.Cfg) -> String:
  match c:
    case ap.Cfg{curl, url, max, web, unit, cc, ourl, okey, ofile}:
      ourl

def ap.cfg.okey(c: ap.Cfg) -> Bool:
  match c:
    case ap.Cfg{curl, url, max, web, unit, cc, ourl, okey, ofile}:
      okey

def ap.cfg.ofile(c: ap.Cfg) -> String:
  match c:
    case ap.Cfg{curl, url, max, web, unit, cc, ourl, okey, ofile}:
      ofile

def ap.tries() -> U32:
  8

# a patient call's wait between tries, in seconds (AskAI.ts AGAIN)
def ap.again() -> U32:
  60

def ap.busy.text() -> String:
  "the AI service is busy or unavailable right now"

# What a call runs on (Pick.ts): a model by its label (opus-5.5, or an id
# as is), an effort, a speed. Its vendor is the model's: OpenAI's
# (openai-api) for gpt-6-astra, gpt-6.1-sol, gpt-6-luna and any id of
# theirs (gpt-..., o1..., o3..., o4..., codex-...), else Anthropic's
# (claude-api).
type ap.Pick is Data:
  ap.Pick{model: String, effort: String, speed: String}

# a model of OpenAI's, by its label or id
def ap.oai(+id: String) -> Bool:
  Bool.or(Bool.or(String.starts_with(id, "gpt-"), String.starts_with(id, "chatgpt-")),
    Bool.or(Bool.or(String.starts_with(id, "o1"), String.starts_with(id, "o3")), Bool.or(String.starts_with(id, "o4"), String.starts_with(id, "codex-"))))

# the vendor, as UniiChat's picks name it
def ap.vendor(+id: String) -> String:
  Bool.pick(String, ap.oai(id), "openai-api", "claude-api")

def ap.id(+label: String) -> String:
  Bool.pick(String, String.eq(label, "opus-5.5"), "claude-opus-5-5",
    Bool.pick(String, String.eq(label, "sonnet-5.5"), "claude-sonnet-5-5",
      Bool.pick(String, String.eq(label, "haiku-5.5"), "claude-haiku-5-5", label)))

# Opus and Sonnet take the server-side refusal fallback; Haiku has none (a
# fallbacks field 400s)
def ap.falls(+id: String) -> Bool:
  Bool.or(String.starts_with(id, "claude-opus"), String.starts_with(id, "claude-sonnet"))

def ap.fast(+p: ap.Pick) -> Bool:
  match p:
    case ap.Pick{m, e, +s}:
      String.eq(s, "fast")

# A call: what it runs on, its system prompt, the blocks of its message
# (marked: a cache entry ends after it), its tools' definitions, the most web
# searches it runs (0: none), whether it is patient.
type ap.Ask is Data:
  ap.Ask{pick: ap.Pick, system: String, blocks: List<&2, V.vw.B>, tools: List<&2, J.Json>, searches: U32, patient: Bool}

# a tool's result: its call's id, its text, whether it failed
type ap.Bk is Data:
  ap.Bk{id: String, text: String, fail: Bool}

# what the conversation holds: the user's blocks, a model's output as the
# API gave it (passed back verbatim: thinking blocks keep their
# signatures), tool results
type ap.Item is Data:
  ap.User{parts: List<&2, V.vw.B>}
  ap.Turn{out: List<&2, J.Json>}
  ap.Back{backs: List<&2, ap.Bk>}

# The body --------------------------------------------------------------------

def ap.mark() -> J.Json:
  J.JObj{[J.JKv{"type", J.JStr{"ephemeral"}}]}

def ap.text(+text: String, mark: Bool) -> J.Json:
  match mark:
    case True{}:
      J.JObj{[J.JKv{"type", J.JStr{"text"}}, J.JKv{"text", J.JStr{text}}, J.JKv{"cache_control", ap.mark()}]}
    case False{}:
      J.JObj{[J.JKv{"type", J.JStr{"text"}}, J.JKv{"text", J.JStr{text}}]}

# the blocks with text, each marked as it is
def ap.parts(bs: List<&2, V.vw.B>) -> List<&2, J.Json>:
  match bs:
    case []:
      []
    case V.vw.B{SNil{}, mark} <> t:
      ap.parts(t)
    case V.vw.B{SCon{Chr{1}, p}, mark} <> t:
      Pc.pc.json(p) <> ap.parts(t)
    case V.vw.B{text, mark} <> t:
      ap.text(text, mark) <> ap.parts(t)

def ap.content(+text: String) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, String.is_empty(text), [], [J.JObj{[J.JKv{"type", J.JStr{"text"}}, J.JKv{"text", J.JStr{text}}]}])

def ap.backs(bs: List<&2, ap.Bk>) -> List<&2, J.Json>:
  match bs:
    case []:
      []
    case ap.Bk{id, +text, fail} <> t:
      J.JObj{[J.JKv{"type", J.JStr{"tool_result"}}, J.JKv{"tool_use_id", J.JStr{id}}, J.JKv{"content", J.JArr{List.append(&2, J.Json, ap.content(Pc.pc.text(text)), Pc.pc.jsons(Pc.pc.pics(text)))}}, J.JKv{"is_error", J.JBool{fail}}]} <> ap.backs(t)

# an item's role (true: the user's) and content
def ap.role(+it: ap.Item) -> Bool:
  match it:
    case ap.Turn{out}:
      False{}
    case _:
      True{}

def ap.blocks(it: ap.Item) -> List<&2, J.Json>:
  match it:
    case ap.User{parts}:
      ap.parts(parts)
    case ap.Turn{out}:
      out
    case ap.Back{backs}:
      ap.backs(backs)

def ap.msg(user: Bool, content: List<&2, J.Json>) -> J.Json:
  match user:
    case True{}:
      J.JObj{[J.JKv{"role", J.JStr{"user"}}, J.JKv{"content", J.JArr{content}}]}
    case False{}:
      J.JObj{[J.JKv{"role", J.JStr{"assistant"}}, J.JKv{"content", J.JArr{content}}]}

# the messages, items of one role in a row joined (Anthropic.body): `user`
# and `acc` the message being gathered
def ap.msgs(its: List<&2, ap.Item>, +user: Bool, +acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match its:
    case []:
      Bool.pick(List<&2, J.Json>, List.is_empty(&2, J.Json, acc), [], [ap.msg(user, acc)])
    case +it <> t:
      +r = ap.role(it)
      +join = Bool.or(Bool.not(Bool.xor(r, user)), List.is_empty(&2, J.Json, acc))
      +bs = ap.blocks(it)
      List.append(&2, J.Json, Bool.pick(List<&2, J.Json>, join, [], [ap.msg(user, acc)]),
        ap.msgs(t, r, Bool.pick(List<&2, J.Json>, join, List.append(&2, J.Json, acc, bs), bs)))

def ap.last.mark(bs: List<&2, V.vw.B>, +m: Bool) -> Bool:
  match bs:
    case []:
      m
    case V.vw.B{text, mark} <> t:
      ap.last.mark(t, mark)

# the tools: ours, then web search if any
def ap.tools(+cfg: ap.Cfg, +defs: List<&2, J.Json>, +searches: U32) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, U32.is_eq(searches, 0), defs,
    List.append(&2, J.Json, defs, [J.JObj{[J.JKv{"type", J.JStr{ap.cfg.web(cfg)}}, J.JKv{"name", J.JStr{"web_search"}}, J.JKv{"max_uses", J.js.u32(searches)}]}]))

def ap.opt(b: Bool, kv: J.JKv) -> List<&2, J.JKv>:
  match b:
    case True{}:
      [kv]
    case False{}:
      []

# the request's body (Anthropic.body), not streamed: adaptive thinking,
# summarized; the system prompt marked, and the top level as the last block
# is; the refusal fallback where the model takes it
def ap.body(+cfg: ap.Cfg, a: ap.Ask, its: List<&2, ap.Item>) -> String:
  match a:
    case ap.Ask{+p, system, +blocks, defs, +searches, patient}:
      match p:
        case ap.Pick{+label, effort, +speed}:
          +id = ap.id(label)
          +tools = ap.tools(cfg, defs, searches)
          J.js.write(J.JObj{List.concat(&2, J.JKv, [
            [J.JKv{"model", J.JStr{id}}, J.JKv{"max_tokens", J.js.u32(ap.cfg.max(cfg))},
              J.JKv{"system", J.JArr{[ap.text(system, True{})]}},
              J.JKv{"thinking", J.JObj{[J.JKv{"type", J.JStr{"adaptive"}}, J.JKv{"display", J.JStr{"summarized"}}]}},
              J.JKv{"output_config", J.JObj{[J.JKv{"effort", J.JStr{effort}}]}}],
            ap.opt(ap.last.mark(blocks, False{}), J.JKv{"cache_control", ap.mark()}),
            ap.opt(Bool.not(List.is_empty(&2, J.Json, tools)), J.JKv{"tools", J.JArr{tools}}),
            ap.opt(String.eq(speed, "fast"), J.JKv{"speed", J.JStr{"fast"}}),
            ap.opt(ap.falls(id), J.JKv{"fallbacks", J.JStr{"default"}}),
            [J.JKv{"messages", J.JArr{ap.msgs(its, True{}, [])}}]])})

# The request -------------------------------------------------------------------

def ap.betas(+id: String, +fast: Bool) -> List<&2, String>:
  List.append(&2, String, Bool.pick(List<&2, String>, ap.falls(id), ["server-side-fallback-2026-07-01"], []),
    Bool.pick(List<&2, String>, fast, ["fast-mode-2026-02-01"], []))

def ap.beta.args(bs: List<&2, String>) -> List<String>:
  match bs:
    case []:
      []
    case _:
      ["-H", "anthropic-beta: " ++ T.tx.join(bs, ",")]

def ap.list(xs: List<&2, String>) -> List<String>:
  match xs:
    case []:
      []
    case x <> t:
      x <> ap.list(t)

# curl's arguments: the key from the environment into its header (curl
# >= 8.3), the body from stdin, after it a line of the status, retry-after
# and x-should-retry
def ap.args(+url: String, betas: List<&2, String>) -> List<String>:
  List.append(&1, String, ["-sS", "--variable", "%ANTHROPIC_API_KEY", "--expand-header", "x-api-key: {{ANTHROPIC_API_KEY}}",
      "-H", "anthropic-version: 2023-06-01", "-H", "content-type: application/json"],
    List.append(&1, String, ap.beta.args(betas),
      ["--connect-timeout", "30", "--max-time", "900", "--data-binary", "@-",
        "-w", "\n%{http_code} %header{retry-after} %header{x-should-retry}", url]))

# A response: curl's status (999: it could not run), the HTTP status, the
# retry-after seconds (0: none), x-should-retry ("" none), the body, curl's
# complaint.
type ap.Res is Data:
  ap.Res{exit: U32, code: U32, after: U32, should: String, body: String, err: String}

# the body and the last line, split at the last newline: r is the output
# reversed, acc the last line so far
def ap.split.go(r: String, +acc: String) -> String & String:
  match r:
    case SNil{}:
      ("", acc)
    case SCon{Chr{10}, t}:
      (String.reverse(t), acc)
    case SCon{c, t}:
      ap.split.go(t, SCon{c, acc})

def ap.words(s: String, +cur: String, acc: List<&2, String>) -> List<&2, String>:
  match s:
    case SNil{}:
      List.reverse(&2, String, String.reverse(cur) <> acc)
    case SCon{Chr{32}, t}:
      ap.words(t, "", String.reverse(cur) <> acc)
    case SCon{c, t}:
      ap.words(t, SCon{c, cur}, acc)

def ap.word(+ws: List<&2, String>, +k: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ws, k), "")

def ap.num(+s: String) -> U32:
  U32.from_nat(Maybe.default(&2, Nat, Nat.read(s), 0n))

def ap.res.ws(+exit: U32, body: String, +ws: List<&2, String>, +err: String) -> ap.Res:
  ap.Res{exit, ap.num(ap.word(ws, 0n)), ap.num(ap.word(ws, 1n)), ap.word(ws, 2n), body, err}

def ap.res.of(+exit: U32, parts: String & String, +err: String) -> ap.Res:
  match parts:
    case (body, last):
      ap.res.ws(exit, body, ap.words(last, "", []), err)

def ap.res(o: S.mu.Out) -> ap.Res:
  match o:
    case S.mu.Out{+status, out, err}:
      ap.res.of(status, ap.split.go(String.reverse(out), ""), T.tx.trim(err))

# curl as run: itself, or (a call that can be stopped: ctl, its control
# files' prefix) by an sh that names its pid in ctl.pid, then becomes it
def ap.argv(wrap: Bool, +ctl: String, +curl: String, args: List<String>) -> List<String>:
  match wrap:
    case False{}:
      args
    case True{}:
      List.append(&1, String, ["-c", "echo $$ > \"$0\"; exec \"$@\"", ctl ++ ".pid", curl], args)

# one request, its body on curl's stdin (64 MiB at most back, 16 minutes)
def ap.send(+cfg: ap.Cfg, +id: String, +fast: Bool, +ctl: String, body: String) -> IO(ap.Res):
  +curl = ap.cfg.curl(cfg)
  IO.bind(S.mu.Out, ap.Res, S.mu.run(Bool.pick(String, String.is_empty(ctl), curl, "sh"), ap.argv(Bool.not(String.is_empty(ctl)), ctl, curl, ap.args(ap.cfg.url(cfg), ap.betas(id, fast))), body, 67108864, 960000), o => IO.pure(ap.Res, ap.res(o)))

# a stop was asked (ctl.stop is there); never for a call that can't be stopped
def ap.stopped.of(r: Result<&1, &1, U32 & String, Nat>) -> Bool:
  match r:
    case Done{n}:
      True{}
    case Fail{e}:
      False{}

def ap.stopped(+ctl: String) -> IO(Bool):
  Bool.pick(IO(Bool), String.is_empty(ctl), IO.pure(Bool, False{}),
    IO.bind(Result<&1, &1, U32 & String, Nat>, Bool, S.mu.size(ctl ++ ".stop"), r => IO.pure(Bool, ap.stopped.of(r))))

# a wait of `left` ms, a quarter second at a time, cut short by a stop
def ap.nap(n: Nat, go: Bool, +left: U32, +ctl: String) -> IO(Unit):
  match n go:
    case 1n+f True{}:
      do IO<Unit>:
        Unit <- IO.sleep(U32.min(left, 250))
        st : Bool <- ap.stopped(ctl)
        ap.nap(f, Bool.and(Bool.not(st), U32.is_gt(left, 250)), (left - 250 : U32), ctl)
    case _ _:
      IO.pure(Unit, Unit{})

# Reading a response --------------------------------------------------------------
#
# A step: the output (its text blocks with text), the tool calls in it, the
# messages it shows (Entry), how it stopped and why, the retry-after of a
# busy one.

type ap.Use is Data:
  ap.Use{id: String, name: String, input: J.Json}

# a message the output shows: a reply (unii), a thought (mind), a tool call
# (tool: "name {json}") or a server tool's result (echo); of: the call's id
type ap.Entry is Data:
  ap.Entry{kind: String, text: String, of: String}

# 0 done, 1 tools, 2 again (pause_turn), 3 busy, 4 down, 5 lost, 6 fail
type ap.Step is Data:
  ap.Step{out: List<&2, J.Json>, uses: List<&2, ap.Use>, entries: List<&2, ap.Entry>, stop: U32, why: String, after: U32}

def ap.fail(+why: String, +stop: U32, +after: U32) -> ap.Step:
  ap.Step{[], [], [], stop, why, after}

def ap.ty(+b: J.Json) -> String:
  Maybe.default(&2, String, J.js.str(b, "type"), "")

# a server tool's result as text (Anthropic.result)
def ap.titles(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case []:
      []
    case +x <> t:
      (Maybe.default(&2, String, J.js.str(x, "title"), "undefined") ++ " " ++ Maybe.default(&2, String, J.js.str(x, "url"), "undefined")) <> ap.titles(t)

def ap.result(+c: Maybe<&2, J.Json>) -> String:
  match c:
    case Some{J.JArr{xs}}:
      T.tx.join(ap.titles(xs), "\n")
    case Some{+o}:
      +ty = ap.ty(o)
      +err = Maybe.default(&2, String, J.js.str(o, "stderr"), "")
      Bool.pick(String, String.starts_with(ty, "encrypted"), T.tx.trim("(output encrypted by the API)\n" ++ err),
        Bool.pick(String, Maybe.is_some(&2, String, J.js.str(o, "stdout")), T.tx.trim(Maybe.default(&2, String, J.js.str(o, "stdout"), "") ++ err), J.js.write(o)))
    case None{}:
      "undefined"

def ap.is.result(+ty: String) -> Bool:
  String.ends_with(ty, "_tool_result")

def ap.nonempty(+e: ap.Entry) -> List<&2, ap.Entry>:
  match e:
    case ap.Entry{+k, +t, +o}:
      Bool.pick(List<&2, ap.Entry>, String.is_empty(T.tx.trim(t)), [], [ap.Entry{k, T.tx.trim(t), o}])

# a block's message, if any (Anthropic.entry)
def ap.or.none(+t: String) -> String:
  Bool.pick(String, String.is_empty(t), "(no output)", t)

def ap.s(+b: J.Json, +k: String) -> String:
  Maybe.default(&2, String, J.js.str(b, k), "")

def ap.entry(+b: J.Json) -> List<&2, ap.Entry>:
  +ty = ap.ty(b)
  Bool.pick(List<&2, ap.Entry>, String.eq(ty, "text"), [ap.Entry{"unii", ap.s(b, "text"), ""}],
    Bool.pick(List<&2, ap.Entry>, String.eq(ty, "thinking"), [ap.Entry{"mind", ap.s(b, "thinking"), ""}],
      Bool.pick(List<&2, ap.Entry>, Bool.or(String.eq(ty, "tool_use"), String.eq(ty, "server_tool_use")),
        [ap.Entry{"tool", ap.s(b, "name") ++ " " ++ J.js.write(Maybe.default(&2, J.Json, J.js.field(b, "input"), J.JObj{[]})), ap.s(b, "id")}],
        Bool.pick(List<&2, ap.Entry>, ap.is.result(ty),
          [ap.Entry{"echo", ap.or.none(ap.result(J.js.field(b, "content"))), ap.s(b, "tool_use_id")}], []))))

# the messages of an output, in order: a run of replies is one (split where
# citations go), each trimmed, none empty (Anthropic.entries)
def ap.join.go(es: List<&2, ap.Entry>, +top: Maybe<&2, ap.Entry>) -> List<&2, ap.Entry>:
  match es top:
    case [] None{}:
      []
    case [] Some{e}:
      ap.nonempty(e)
    case ap.Entry{+k, +t, +o} <> rest None{}:
      ap.join.go(rest, Some{ap.Entry{k, t, o}})
    case ap.Entry{+k, +t, +o} <> rest Some{ap.Entry{+k0, +t0, +o0}}:
      +same = Bool.and(String.eq(k, "unii"), String.eq(k0, "unii"))
      List.append(&2, ap.Entry, Bool.pick(List<&2, ap.Entry>, same, [], ap.nonempty(ap.Entry{k0, t0, o0})),
        ap.join.go(rest, Some{Bool.pick(ap.Entry, same, ap.Entry{k0, t0 ++ t, o0}, ap.Entry{k, t, o})}))

def ap.entries.all(bs: List<&2, J.Json>) -> List<&2, ap.Entry>:
  match bs:
    case []:
      []
    case +b <> t:
      List.append(&2, ap.Entry, ap.entry(b), ap.entries.all(t))

def ap.entries(+out: List<&2, J.Json>) -> List<&2, ap.Entry>:
  ap.join.go(ap.entries.all(out), None{})

# the output kept: a text block only with text
def ap.out(bs: List<&2, J.Json>) -> List<&2, J.Json>:
  match bs:
    case []:
      []
    case +b <> t:
      +empty = Bool.and(String.eq(ap.ty(b), "text"), String.is_empty(Maybe.default(&2, String, J.js.str(b, "text"), "")))
      List.append(&2, J.Json, Bool.pick(List<&2, J.Json>, empty, [], [b]), ap.out(t))

def ap.uses(bs: List<&2, J.Json>) -> List<&2, ap.Use>:
  match bs:
    case []:
      []
    case +b <> t:
      List.append(&2, ap.Use, Bool.pick(List<&2, ap.Use>, String.eq(ap.ty(b), "tool_use"),
        [ap.Use{ap.s(b, "id"), ap.s(b, "name"), Maybe.default(&2, J.Json, J.js.field(b, "input"), J.JObj{[]})}], []), ap.uses(t))

def ap.paren(x: Maybe<&2, String>) -> String:
  match x:
    case Some{x}:
      " (" ++ x ++ ")"
    case None{}:
      ""

def ap.explain(+d: Maybe<&2, J.Json>) -> String:
  match d:
    case Some{+o}:
      ap.paren(J.js.str(o, "explanation"))
    case None{}:
      ""

# a message's step (Anthropic.step)
def ap.step.of(+m: J.Json) -> ap.Step:
  +out = ap.out(J.js.arr(m, "content"))
  +uses = ap.uses(out)
  +stop = Maybe.default(&2, String, J.js.str(m, "stop_reason"), "")
  +turn = Bool.or(String.eq(stop, "end_turn"), String.eq(stop, "tool_use"))
  +code = Bool.pick(U32, turn, Bool.pick(U32, List.is_empty(&2, ap.Use, uses), 0, 1), Bool.pick(U32, String.eq(stop, "pause_turn"), 2, 6))
  +why = Bool.pick(String, U32.is_eq(code, 6), "stopped: " ++ stop ++ ap.explain(J.js.field(m, "stop_details")), "")
  ap.Step{out, uses, ap.entries(out), code, why, 0}

# an error body's why: the API's message, else the body's start (Agent.reason)
def ap.reason.of(+body: String, e: Maybe<&2, J.Json>) -> String:
  match e:
    case Some{+e}:
      Maybe.default(&2, String, J.js.str(e, "message"), String.take(body, 2000n))
    case None{}:
      String.take(body, 2000n)

def ap.reason.got(+body: String, j: Maybe<&2, J.Json>) -> String:
  match j:
    case Some{+j}:
      ap.reason.of(body, J.js.field(j, "error"))
    case None{}:
      String.take(body, 2000n)

def ap.reason(+body: String) -> String:
  ap.reason.got(body, J.js.read(body))

# a status asked again: x-should-retry says, else 408, 409, 429, 5xx
def ap.passing(+code: U32, +should: String) -> Bool:
  Bool.or(String.eq(should, "true"), Bool.and(Bool.not(String.eq(should, "false")),
    Bool.or(Bool.or(U32.is_eq(code, 408), U32.is_eq(code, 409)), Bool.or(U32.is_eq(code, 429), U32.is_ge(code, 500)))))

def ap.ok.body(m: Maybe<&2, J.Json>) -> ap.Step:
  match m:
    case Some{+j}:
      ap.step.of(j)
    case None{}:
      ap.fail("the response was not JSON", 3, 0)

# a response's step: curl failed (no connection, a timeout): busy; an HTTP
# error: busy if passing, else down; a message: its step
def ap.read(r: ap.Res) -> ap.Step:
  match r:
    case ap.Res{+exit, +code, +after, +should, +body, +err}:
      Bool.pick(ap.Step, Bool.not(U32.is_eq(exit, 0)), ap.fail(Bool.pick(String, String.is_empty(err), "curl exited " ++ U32.show(exit), err), 3, 0),
        Bool.pick(ap.Step, U32.is_eq(code, 200), ap.ok.body(J.js.read(body)),
          ap.fail("HTTP " ++ U32.show(code) ++ ": " ++ ap.reason(body), Bool.pick(U32, ap.passing(code, should), 3, 4), after)))

# Claude Code's run read into a step: no result (it could not run, or died):
# busy; a result's error: busy for a retry status, else down; an answer: its
# blocks' step, as a message of them would be
def ap.cc.why(+status: U32, +why: String) -> String:
  Bool.pick(String, Bool.or(U32.is_eq(status, 401), String.contains(why, "/login")), "Claude Code is not signed in (run `mugen login` in another window; this chat goes on once you have): " ++ why,
    "Claude Code: " ++ why)

def ap.cc.res(+exit: U32, +err: String, o: C.cc.Once) -> ap.Step:
  match o:
    case C.cc.Once{+out, C.cc.Res{got, ok, +status, +stop, +why}}:
      +said = String.take(T.tx.trim(err), 2000n)
      Bool.pick(ap.Step, Bool.not(got), ap.fail(Bool.pick(String, String.is_empty(said), "claude exited " ++ U32.show(exit), said), 3, 0),
        Bool.pick(ap.Step, ok, ap.step.of(J.JObj{[J.JKv{"content", J.JArr{out}}, J.JKv{"stop_reason", J.JStr{Bool.pick(String, String.is_empty(stop), "end_turn", stop)}}]}),
          ap.fail(ap.cc.why(status, why), Bool.pick(U32, ap.passing(status, ""), 3, 4), 0)))

def ap.cc.read(o: S.mu.Out) -> ap.Step:
  match o:
    case S.mu.Out{+status, out, +err}:
      ap.cc.res(status, err, C.cc.once.read(out))

# OpenAI ------------------------------------------------------------------------
#
# openai-api, UniiChat's OpenAI.ts: the Responses API by curl, not streamed
# (as the Messages API's here), store off, so a step sends every item and an
# output goes back as it came (its reasoning items keep their encrypted
# content). Reasoning keeps all turns (else a message sent mid-run drops it
# and misses the cache); the speed is a service tier (fast: OpenAI's fast,
# the priority tier). A marked block is an explicit cache breakpoint; the
# end is cached implicitly only if marked. Our tools are functions (not
# strict: their schemas are Anthropic's), web search the API's own. A
# failed response is busy if the server's error, else it fails, as one
# incomplete or refused does. The key is curl's to read, never in argv:
# OPENAI_API_KEY from the environment, else the key file (read at each
# call, so a key written there works at once).

def ap.oai.mark() -> J.Json:
  J.JObj{[J.JKv{"mode", J.JStr{"explicit"}}]}

def ap.oai.tier(+speed: String) -> String:
  Bool.pick(String, String.eq(speed, "fast"), "fast", Bool.pick(String, String.eq(speed, "ultrafast"), "ultrafast", "default"))

def ap.oai.input.text(+text: String) -> J.Json:
  J.JObj{[J.JKv{"type", J.JStr{"input_text"}}, J.JKv{"text", J.JStr{text}}]}

def ap.oai.text(+text: String, mark: Bool) -> J.Json:
  match mark:
    case True{}:
      J.JObj{[J.JKv{"type", J.JStr{"input_text"}}, J.JKv{"text", J.JStr{text}}, J.JKv{"prompt_cache_breakpoint", ap.oai.mark()}]}
    case False{}:
      ap.oai.input.text(text)

# a pic as an input image, its data URL
def ap.oai.image(+p: String) -> J.Json:
  J.JObj{[J.JKv{"type", J.JStr{"input_image"}}, J.JKv{"image_url", J.JStr{"data:" ++ Pc.pc.media(p) ++ ";base64," ++ Pc.pc.data(p)}}]}

def ap.oai.images(ps: List<&2, String>) -> List<&2, J.Json>:
  match ps:
    case []:
      []
    case p <> t:
      ap.oai.image(p) <> ap.oai.images(t)

# the blocks with text, each marked as it is (ap.parts)
def ap.oai.parts(bs: List<&2, V.vw.B>) -> List<&2, J.Json>:
  match bs:
    case []:
      []
    case V.vw.B{SNil{}, mark} <> t:
      ap.oai.parts(t)
    case V.vw.B{SCon{Chr{1}, p}, mark} <> t:
      ap.oai.image(p) <> ap.oai.parts(t)
    case V.vw.B{text, mark} <> t:
      ap.oai.text(text, mark) <> ap.oai.parts(t)

# a result's words: a failure's said so
def ap.oai.said(+text: String, fail: Bool) -> J.Json:
  match fail:
    case True{}:
      ap.oai.input.text("error: " ++ text)
    case False{}:
      ap.oai.input.text(Bool.pick(String, String.is_empty(text), "(no output)", text))

def ap.oai.backs(bs: List<&2, ap.Bk>) -> List<&2, J.Json>:
  match bs:
    case []:
      []
    case ap.Bk{id, +text, fail} <> t:
      J.JObj{[J.JKv{"type", J.JStr{"function_call_output"}}, J.JKv{"call_id", J.JStr{id}},
        J.JKv{"output", J.JArr{ap.oai.said(Pc.pc.text(text), fail) <> ap.oai.images(Pc.pc.pics(text))}}]} <> ap.oai.backs(t)

# an item as input: the user's message; an output, as it came; results
def ap.oai.item(it: ap.Item) -> List<&2, J.Json>:
  match it:
    case ap.User{parts}:
      [J.JObj{[J.JKv{"role", J.JStr{"user"}}, J.JKv{"content", J.JArr{ap.oai.parts(parts)}}]}]
    case ap.Turn{out}:
      out
    case ap.Back{backs}:
      ap.oai.backs(backs)

def ap.oai.items(its: List<&2, ap.Item>) -> List<&2, J.Json>:
  match its:
    case []:
      []
    case it <> t:
      List.append(&2, J.Json, ap.oai.item(it), ap.oai.items(t))

# our tools as functions
def ap.oai.tool(+d: J.Json) -> J.Json:
  J.JObj{[J.JKv{"type", J.JStr{"function"}}, J.JKv{"name", J.JStr{ap.s(d, "name")}}, J.JKv{"description", J.JStr{ap.s(d, "description")}},
    J.JKv{"parameters", Maybe.default(&2, J.Json, J.js.field(d, "input_schema"), J.JObj{[]})}, J.JKv{"strict", J.JBool{False{}}}]}

def ap.oai.tools(ds: List<&2, J.Json>) -> List<&2, J.Json>:
  match ds:
    case []:
      []
    case d <> t:
      ap.oai.tool(d) <> ap.oai.tools(t)

# the tools: ours, then web search if any
def ap.oai.web(+defs: List<&2, J.Json>, +searches: U32) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, U32.is_eq(searches, 0), defs, List.append(&2, J.Json, defs, [J.JObj{[J.JKv{"type", J.JStr{"web_search"}}]}]))

# the request's body (OpenAI.body), not streamed: the system prompt a
# developer message, then the items
def ap.oai.body(+cfg: ap.Cfg, a: ap.Ask, its: List<&2, ap.Item>) -> String:
  match a:
    case ap.Ask{p, system, blocks, defs, +searches, patient}:
      match p:
        case ap.Pick{label, effort, speed}:
          +tools = ap.oai.web(ap.oai.tools(defs), searches)
          J.js.write(J.JObj{List.concat(&2, J.JKv, [
            [J.JKv{"model", J.JStr{ap.id(label)}}, J.JKv{"stream", J.JBool{False{}}}, J.JKv{"store", J.JBool{False{}}}],
            ap.opt(Bool.not(List.is_empty(&2, J.Json, tools)), J.JKv{"tools", J.JArr{tools}}),
            [J.JKv{"reasoning", J.JObj{[J.JKv{"effort", J.JStr{effort}}, J.JKv{"summary", J.JStr{"auto"}}, J.JKv{"context", J.JStr{"all_turns"}}]}},
              J.JKv{"max_output_tokens", J.js.u32(ap.cfg.max(cfg))}],
            ap.opt(U32.is_gt(searches, 0), J.JKv{"max_tool_calls", J.js.u32(searches)}),
            [J.JKv{"service_tier", J.JStr{ap.oai.tier(speed)}}],
            ap.opt(Bool.not(ap.last.mark(blocks, False{})), J.JKv{"prompt_cache_options", ap.oai.mark()}),
            [J.JKv{"input", J.JArr{J.JObj{[J.JKv{"role", J.JStr{"developer"}}, J.JKv{"content", J.JArr{[ap.oai.input.text(system)]}}]} <> ap.oai.items(its)}}]])})

# curl's arguments: the key, from the environment or its file, into the
# header (curl >= 8.3), the body from stdin, after it the status line
def ap.oai.key.args(env: Bool, +file: String) -> List<String>:
  match env:
    case True{}:
      ["--variable", "%OPENAI_API_KEY"]
    case False{}:
      ["--variable", "OPENAI_API_KEY@" ++ file]

def ap.oai.args(+cfg: ap.Cfg) -> List<String>:
  List.append(&1, String, ["-sS"],
    List.append(&1, String, ap.oai.key.args(ap.cfg.okey(cfg), ap.cfg.ofile(cfg)),
      ["--expand-header", "Authorization: Bearer {{OPENAI_API_KEY:trim}}", "-H", "content-type: application/json",
        "--connect-timeout", "30", "--max-time", "1800", "--data-binary", "@-",
        "-w", "\n%{http_code} %header{retry-after} %header{x-should-retry}", ap.cfg.ourl(cfg)]))

# one request (64 MiB at most back, 31 minutes: a model that thinks long
# says nothing till it is done)
def ap.oai.send(+cfg: ap.Cfg, +ctl: String, body: String) -> IO(ap.Res):
  +curl = ap.cfg.curl(cfg)
  IO.bind(S.mu.Out, ap.Res, S.mu.run(Bool.pick(String, String.is_empty(ctl), curl, "sh"), ap.argv(Bool.not(String.is_empty(ctl)), ctl, curl, ap.oai.args(cfg)), body, 67108864, 1860000), o => IO.pure(ap.Res, ap.res(o)))

# Reading a response: its output items' messages (OpenAI.entries) and calls

def ap.oai.texts(xs: List<&2, J.Json>, +k: String) -> List<&2, String>:
  match xs:
    case []:
      []
    case x <> t:
      ap.s(x, k) <> ap.oai.texts(t, k)

def ap.oai.urls(ns: List<&2, J.Json>) -> List<&2, String>:
  match ns:
    case []:
      []
    case +n <> t:
      List.append(&2, String, Bool.pick(List<&2, String>, String.eq(ap.ty(n), "url_citation"), [ap.s(n, "title") ++ " " ++ ap.s(n, "url")], []), ap.oai.urls(t))

# the web sources a message's content cites
def ap.oai.cites(cs: List<&2, J.Json>) -> List<&2, String>:
  match cs:
    case []:
      []
    case c <> t:
      List.append(&2, String, ap.oai.urls(J.js.arr(c, "annotations")), ap.oai.cites(t))

def ap.oai.has(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case []:
      False{}
    case +y <> t:
      Bool.or(String.eq(x, y), ap.oai.has(t, x))

# each once, in order (seen: those kept, reversed)
def ap.oai.uniq(xs: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match xs:
    case []:
      List.reverse(&2, String, seen)
    case +x <> t:
      ap.oai.uniq(t, Bool.pick(List<&2, String>, ap.oai.has(seen, x), seen, x <> seen))

def ap.oai.one(+text: String, +kind: String) -> List<&2, ap.Entry>:
  Bool.pick(List<&2, ap.Entry>, String.is_empty(text), [], [ap.Entry{kind, text, ""}])

def ap.oai.sources(+cited: List<&2, String>) -> List<&2, ap.Entry>:
  Bool.pick(List<&2, ap.Entry>, List.is_empty(&2, String, cited), [], [ap.Entry{"echo", "sources:\n" ++ T.tx.join(cited, "\n"), ""}])

# a call's arguments as JSON (written anew, as the API path writes an
# input), or as they came if they are none
def ap.oai.args.of(+raw: String, m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{j}:
      J.js.write(j)
    case None{}:
      raw

def ap.oai.args.text(+raw: String) -> String:
  ap.oai.args.of(raw, J.js.read(raw))

# 0 a thought, 1 a message, 2 a call of ours, 3 a web search, 4 else
def ap.oai.kind(+ty: String) -> Nat:
  Bool.pick(Nat, String.eq(ty, "reasoning"), 0n, Bool.pick(Nat, String.eq(ty, "message"), 1n,
    Bool.pick(Nat, String.eq(ty, "function_call"), 2n, Bool.pick(Nat, String.eq(ty, "web_search_call"), 3n, 4n))))

def ap.oai.entry(k: Nat, +o: J.Json) -> List<&2, ap.Entry>:
  match k:
    case 0n:
      ap.oai.one(T.tx.trim(T.tx.join(ap.oai.texts(J.js.arr(o, "summary"), "text"), "\n\n")), "mind")
    case 1n:
      List.append(&2, ap.Entry, ap.oai.one(T.tx.trim(T.tx.concat(ap.oai.texts(J.js.arr(o, "content"), "text"))), "unii"),
        ap.oai.sources(ap.oai.uniq(ap.oai.cites(J.js.arr(o, "content")), [])))
    case 2n:
      [ap.Entry{"tool", ap.s(o, "name") ++ " " ++ ap.oai.args.text(ap.s(o, "arguments")), ap.s(o, "call_id")}]
    case 3n:
      [ap.Entry{"tool", "web_search " ++ J.js.write(Maybe.default(&2, J.Json, J.js.field(o, "action"), J.JObj{[]})), ""}]
    case _:
      []

def ap.oai.entries(xs: List<&2, J.Json>) -> List<&2, ap.Entry>:
  match xs:
    case []:
      []
    case +x <> t:
      List.append(&2, ap.Entry, ap.oai.entry(ap.oai.kind(ap.ty(x)), x), ap.oai.entries(t))

# a call's input: its arguments parsed (none: an empty object), null if
# they are no JSON (Agent.parse)
def ap.oai.input(m: Maybe<&2, J.Json>) -> J.Json:
  match m:
    case Some{j}:
      j
    case None{}:
      J.JNull{}

def ap.oai.parse(+raw: String) -> J.Json:
  ap.oai.input(J.js.read(Bool.pick(String, String.is_empty(raw), "{}", raw)))

def ap.oai.uses(xs: List<&2, J.Json>) -> List<&2, ap.Use>:
  match xs:
    case []:
      []
    case +x <> t:
      List.append(&2, ap.Use, Bool.pick(List<&2, ap.Use>, String.eq(ap.ty(x), "function_call"),
        [ap.Use{ap.s(x, "call_id"), ap.s(x, "name"), ap.oai.parse(ap.s(x, "arguments"))}], []), ap.oai.uses(t))

def ap.oai.refused(cs: List<&2, J.Json>) -> List<&2, String>:
  match cs:
    case []:
      []
    case +c <> t:
      List.append(&2, String, Bool.pick(List<&2, String>, String.eq(ap.ty(c), "refusal"), [ap.s(c, "refusal")], []), ap.oai.refused(t))

# the refusals in an output's messages
def ap.oai.refusals(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case []:
      []
    case x <> t:
      List.append(&2, String, ap.oai.refused(J.js.arr(x, "content")), ap.oai.refusals(t))

def ap.oai.obj(m: Maybe<&2, J.Json>) -> J.Json:
  Maybe.default(&2, J.Json, m, J.JObj{[]})

# a response's step (OpenAI.step): failed, busy if the server's error, else
# a failure; incomplete or refused, a failure; else its calls, if any
def ap.oai.step.of(+r: J.Json) -> ap.Step:
  +out = J.js.arr(r, "output")
  +uses = ap.oai.uses(out)
  +status = ap.s(r, "status")
  +err = ap.oai.obj(J.js.field(r, "error"))
  +refused = ap.oai.refusals(out)
  +failed = String.eq(status, "failed")
  +cut = String.eq(status, "incomplete")
  +no = Bool.not(List.is_empty(&2, String, refused))
  +code = Bool.pick(U32, failed, Bool.pick(U32, String.eq(ap.s(err, "code"), "server_error"), 3, 6),
    Bool.pick(U32, Bool.or(cut, no), 6, Bool.pick(U32, List.is_empty(&2, ap.Use, uses), 0, 1)))
  +why = Bool.pick(String, failed, Bool.pick(String, String.is_empty(ap.s(err, "message")), "failed", ap.s(err, "message")),
    Bool.pick(String, cut, "incomplete: " ++ ap.s(ap.oai.obj(J.js.field(r, "incomplete_details")), "reason"),
      Bool.pick(String, no, "refused: " ++ T.tx.join(refused, " "), "")))
  ap.Step{out, uses, ap.oai.entries(out), code, why, 0}

def ap.oai.ok.body(m: Maybe<&2, J.Json>) -> ap.Step:
  match m:
    case Some{+j}:
      ap.oai.step.of(j)
    case None{}:
      ap.fail("the response was not JSON", 3, 0)

# a response's step, as ap.read reads the Messages API's, but an error of
# the request's (a 4xx not asked again: a bad key, an unknown model) fails,
# so the user reads why
def ap.oai.read(r: ap.Res) -> ap.Step:
  match r:
    case ap.Res{+exit, +code, +after, +should, +body, +err}:
      +ours = Bool.and(U32.is_ge(code, 400), U32.is_lt(code, 500))
      Bool.pick(ap.Step, Bool.not(U32.is_eq(exit, 0)), ap.fail(Bool.pick(String, String.is_empty(err), "curl exited " ++ U32.show(exit), err), 3, 0),
        Bool.pick(ap.Step, U32.is_eq(code, 200), ap.oai.ok.body(J.js.read(body)),
          ap.fail("OpenAI's API: HTTP " ++ U32.show(code) ++ ": " ++ ap.reason(body), Bool.pick(U32, ap.passing(code, should), 3, Bool.pick(U32, ours, 6, 4)), after)))

# The key: the environment's, else its file's if there (or a curl of a
# test's, which needs none); none, said
def ap.oai.there(r: Result<&1, &1, U32 & String, Nat>) -> Bool:
  match r:
    case Done{n}:
      True{}
    case Fail{e}:
      False{}

def ap.oai.nokey(+cfg: ap.Cfg) -> String:
  "no OpenAI API key: set OPENAI_API_KEY, or write the key to " ++ ap.cfg.ofile(cfg) ++ " (MUGEN_OPENAI_KEY_FILE names another file)"

def ap.oai.keyed(+cfg: ap.Cfg) -> IO(Bool):
  IO.bind(Result<&1, &1, U32 & String, Nat>, Bool, S.mu.size(ap.cfg.ofile(cfg)), r =>
    IO.pure(Bool, Bool.or(ap.cfg.okey(cfg), Bool.or(ap.oai.there(r), Bool.not(String.eq(ap.cfg.curl(cfg), "curl"))))))

# where the key comes from, said ("" none)
def ap.oai.key.from(+cfg: ap.Cfg) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, Nat>, String, S.mu.size(ap.cfg.ofile(cfg)), r =>
    IO.pure(String, Bool.pick(String, ap.cfg.okey(cfg), "OPENAI_API_KEY", Bool.pick(String, ap.oai.there(r), ap.cfg.ofile(cfg), ""))))

def ap.oai.go(keyed: Bool, +cfg: ap.Cfg, +ctl: String, body: String) -> IO(ap.Step):
  match keyed:
    case True{}:
      IO.bind(ap.Res, ap.Step, ap.oai.send(cfg, ctl, body), r => IO.pure(ap.Step, ap.oai.read(r)))
    case False{}:
      IO.pure(ap.Step, ap.fail(ap.oai.nokey(cfg), 6, 0))

# one try on OpenAI's API
def ap.oai.try(+cfg: ap.Cfg, +ctl: String, body: String) -> IO(ap.Step):
  IO.bind(Bool, ap.Step, ap.oai.keyed(cfg), k => ap.oai.go(k, cfg, ctl, body))

# a call's wire: 0 the Messages API by curl, 1 Claude Code, 2 OpenAI's
# Responses API by curl (an OpenAI model's, whatever the wire)
def ap.wire(+cfg: ap.Cfg, +id: String) -> Nat:
  Bool.pick(Nat, ap.oai(id), 2n, Bool.pick(Nat, C.cc.on(ap.cfg.cc(cfg)), 1n, 0n))

def ap.step.stop(s: ap.Step) -> U32:
  match s:
    case ap.Step{o, u, e, stop, w, a}:
      stop

def ap.step.why(s: ap.Step) -> String:
  match s:
    case ap.Step{o, u, e, stop, w, a}:
      w

# The retries -------------------------------------------------------------------

# a busy step at try k: down once TRIES are spent
def ap.final(+s: ap.Step, +k: U32) -> Bool:
  Bool.or(Bool.not(U32.is_eq(ap.step.stop(s), 3)), U32.is_ge(k, ap.tries()))

def ap.down(s: ap.Step) -> ap.Step:
  match s:
    case ap.Step{o, u, e, +stop, w, a}:
      ap.Step{o, u, e, Bool.pick(U32, U32.is_eq(stop, 3), 4, stop), w, a}

def ap.wait.of(s: ap.Step, +k: U32) -> U32:
  match s:
    case ap.Step{o, u, e, stop, w, +a}:
      Bool.pick(U32, U32.is_gt(a, 0), a, U32.shln(1, U32.to_nat(k)))

# a busy note told without waiting: dropped if nobody has room for it
def ap.note(+notes: Chan(String), +text: String) -> IO(Unit):
  IO.bind(Poll<&1, &1, Result<&1, &1, String, Unit>, String>, Unit, Chan.try_send(String, notes, text, 0), r => IO.pure(Unit, Unit{}))

def ap.ask.system(a: ap.Ask) -> String:
  match a:
    case ap.Ask{p, sy, b, t, se, pa}:
      sy

def ap.pick.effort(p: ap.Pick) -> String:
  match p:
    case ap.Pick{m, e, s}:
      e

def ap.ask.pick(a: ap.Ask) -> ap.Pick:
  match a:
    case ap.Ask{p, sy, b, t, se, pa}:
      p

def ap.ask.blocks(a: ap.Ask) -> List<&2, V.vw.B>:
  match a:
    case ap.Ask{p, sy, b, t, se, pa}:
      b

# one try on the call's wire (ap.wire): the body by curl, or the ask (its
# one message) by Claude Code
def ap.try.on(w: Nat, +cfg: ap.Cfg, +a: ap.Ask, +id: String, +fast: Bool, +ctl: String, +body: String) -> IO(ap.Step):
  match w:
    case 1n:
      IO.bind(S.mu.Out, ap.Step, C.cc.once(ap.cfg.cc(cfg), id, ap.pick.effort(ap.ask.pick(a)), ap.ask.system(a), ap.ask.blocks(a), ctl), o => IO.pure(ap.Step, ap.cc.read(o)))
    case 2n:
      ap.oai.try(cfg, ctl, body)
    case _:
      IO.bind(ap.Res, ap.Step, ap.send(cfg, id, fast, ctl, body), r => IO.pure(ap.Step, ap.read(r)))

# One step: the request sent, asked again while busy, TRIES in all, each
# wait told as a thought on `notes` (Agent.step); a stop (ctl) ends it at the
# next try or within a wait. v: what comes next (this loop's previous verdict
# as a parameter: no mutual recursion): 0 a try, if no stop came; 4 the try;
# 1 the end (the last step `s`, try k); 2 a wait; 3 stopped.
def ap.step.go(n: Nat, v: Nat, +cfg: ap.Cfg, +a: ap.Ask, +id: String, +fast: Bool, +body: String, +notes: Chan(String), +ctl: String, +k: U32, +s: ap.Step) -> IO(ap.Step):
  match n v:
    case 0n _:
      IO.pure(ap.Step, ap.down(s))
    case 1n+f 0n:
      do IO<ap.Step>:
        st : Bool <- ap.stopped(ctl)
        ap.step.go(f, Bool.pick(Nat, st, 3n, 4n), cfg, a, id, fast, body, notes, ctl, k, s)
    case 1n+f 4n:
      do IO<ap.Step>:
        +s2 : ap.Step <- ap.try.on(ap.wire(cfg, id), cfg, a, id, fast, ctl, body)
        st : Bool <- ap.stopped(ctl)
        ap.step.go(f, Bool.pick(Nat, st, 3n, Bool.pick(Nat, ap.final(s2, k), 1n, 2n)), cfg, a, id, fast, body, notes, ctl, k, s2)
    case 1n+f 1n:
      IO.pure(ap.Step, ap.down(s))
    case 1n+f 3n:
      IO.pure(ap.Step, ap.fail("stopped", 5, 0))
    case 1n+f _:
      +w = ap.wait.of(s, k)
      +ms = (w * ap.cfg.unit(cfg) : U32)
      do IO<ap.Step>:
        Unit <- ap.note(notes, "The AI service is busy: asking again in " ++ U32.show(w) ++ " s.")
        Unit <- ap.nap(U32.to_nat((U32.div(ms, 250) + 2 : U32)), True{}, ms, ctl)
        ap.step.go(f, 0n, cfg, a, id, fast, body, notes, ctl, (k + 1 : U32), s)

def ap.pick.id(p: ap.Pick) -> String:
  match p:
    case ap.Pick{m, e, s}:
      ap.id(m)

# the body, for curl only: the Messages API's or OpenAI's
def ap.body.if(w: Nat, +cfg: ap.Cfg, +a: ap.Ask, its: List<&2, ap.Item>) -> String:
  match w:
    case 1n:
      ""
    case 2n:
      ap.oai.body(cfg, a, its)
    case _:
      ap.body(cfg, a, its)

# a step of a call: its body sent, as often as busy calls for
def ap.step(+cfg: ap.Cfg, +a: ap.Ask, its: List<&2, ap.Item>, +notes: Chan(String), +ctl: String) -> IO(ap.Step):
  +p = ap.ask.pick(a)
  +id = ap.pick.id(p)
  ap.step.go(Nat.add(Nat.mul(U32.to_nat(ap.tries()), 4n), 4n), 0n, cfg, a, id, ap.fast(p), ap.body.if(ap.wire(cfg, id), cfg, a, its), notes, ctl, 1, ap.fail(ap.busy.text(), 3, 0))
