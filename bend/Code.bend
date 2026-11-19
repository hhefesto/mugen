
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./Clock.bend as K
import ./View.bend as V
import ./Pic.bend as Pc

# Code: the calls on Claude Code's CLI (`claude -p`), the default wire: a
# Claude plan's login runs it, where the Messages API wants a key (Api.bend,
# `mugen --api`). A call is one process: its message on stdin as stream-json,
# its events on stdout, a JSON a line. Our blocks keep one cache mark (the
# view's, the first): with Claude Code's three (its identity line, the system
# prompt, the last message) the four the API allows. Marks are an hour long,
# as Claude Code's are on a plan, so none follows a shorter one. Claude
# Code's own context is kept out (CLAUDE.md, memory, git status, attachments,
# tool search), so the prefix stays the same from call to call.
#
# A chat call (a turn, an agent's, a goal check) is a session of Claude
# Code's, kept as its transcript, the user's hooks run on it (a transcript
# renderer, say), with a debug log beside it when MUGEN_DEBUG_DIR says where;
# a compaction keeps none, unless MUGEN_TRANSCRIPTS=all.
#
# Every def is prefixed `cc.` (a program's defs share one namespace).

# Settings ------------------------------------------------------------------

# the wire (0 the API by curl, 1 Claude Code), the program, the debug logs'
# dir ("" none), whose transcripts are kept (0 none, 1 the chat's calls, 2
# all), run/ (the calls' files), the work dir
type cc.Cfg is Data:
  cc.Cfg{wire: U32, prog: String, debug: String, trans: U32, run: String, work: String}

def cc.cfg.wire(c: cc.Cfg) -> U32:
  match c:
    case cc.Cfg{w, p, d, t, r, k}:
      w

def cc.cfg.prog(c: cc.Cfg) -> String:
  match c:
    case cc.Cfg{w, p, d, t, r, k}:
      p

def cc.cfg.debug(c: cc.Cfg) -> String:
  match c:
    case cc.Cfg{w, p, d, t, r, k}:
      d

def cc.cfg.trans(c: cc.Cfg) -> U32:
  match c:
    case cc.Cfg{w, p, d, t, r, k}:
      t

def cc.cfg.run(c: cc.Cfg) -> String:
  match c:
    case cc.Cfg{w, p, d, t, r, k}:
      r

def cc.cfg.work(c: cc.Cfg) -> String:
  match c:
    case cc.Cfg{w, p, d, t, r, k}:
      k

def cc.on(+c: cc.Cfg) -> Bool:
  U32.is_eq(cc.cfg.wire(c), 1)

# Claude Code's sign-in, from `claude auth status --json` (no API key in its
# environment, as mugen runs it): 0 no answer (not there to run), 1 signed
# out, 2 signed in (Main.bend at the start, /login after a sign-in)
def cc.signed(+out: String) -> Nat:
  +j = J.js.read(out)
  Bool.pick(Nat, Maybe.is_none(&2, J.Json, j), 0n,
    Bool.pick(Nat, Maybe.default(&2, Bool, J.js.bool(Maybe.default(&2, J.Json, j, J.JObj{[]}), "loggedIn"), False{}), 2n, 1n))

# who Claude Code is signed in as: the account, its plan
def cc.acct(+j: J.Json) -> String:
  +email = Maybe.default(&2, String, J.js.str(j, "email"), "")
  +plan = Maybe.default(&2, String, J.js.str(j, "subscriptionType"), "")
  Bool.pick(String, String.is_empty(email), "signed in", email)
    ++ Bool.pick(String, String.is_empty(plan), "", " · " ++ String.to_upper(String.take(plan, 1n)) ++ String.drop(plan, 1n) ++ " plan") ++ ", on Claude Code"

# a call keeps its transcript: a chat call's (ctl, its control files, set)
# unless none are kept, a compaction's when all are
def cc.keeps(+c: cc.Cfg, +chat: Bool) -> Bool:
  Bool.or(U32.is_eq(cc.cfg.trans(c), 2), Bool.and(chat, U32.is_eq(cc.cfg.trans(c), 1)))

# Ids -----------------------------------------------------------------------

# the n lowest hex digits of w
def cc.hexn(n: Nat, +w: U32, +acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+k:
      cc.hexn(k, U32.shrn(w, 4n), SCon{Chr{J.js.hex(U32.and(w, 15))}, acc})

# a version 4 UUID of four random words
def cc.uuid.of(+a: U32, +b: U32, +c: U32, +d: U32) -> String:
  cc.hexn(8n, a, "") ++ "-" ++ cc.hexn(4n, b, "") ++ "-4" ++ cc.hexn(3n, U32.shrn(b, 16n), "") ++ "-"
    ++ cc.hexn(1n, (U32.and(c, 3) + 8 : U32), "") ++ cc.hexn(3n, U32.shrn(c, 2n), "") ++ "-" ++ cc.hexn(4n, U32.shrn(c, 14n), "") ++ cc.hexn(8n, d, "")

def cc.word(r: Result<&1, &1, U32 & String, U32>) -> U32:
  match r:
    case Done{w}:
      w
    case Fail{e}:
      0

def cc.rand() -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, U32>, U32, IO.random_u32(), r => IO.pure(U32, cc.word(r)))

def cc.uuid() -> IO(String):
  do IO<String>:
    +a : U32 <- cc.rand()
    +b : U32 <- cc.rand()
    +c : U32 <- cc.rand()
    +d : U32 <- cc.rand()
    return cc.uuid.of(a, b, c, d)

# a debug log's name as the user's wrapper names them: the local minute, the
# caller, the session's first eight
def cc.stamp(+shown: String) -> String:
  String.take(shown, 10n) ++ "_" ++ String.take(String.drop(shown, 11n), 2n) ++ String.take(String.drop(shown, 14n), 2n)

def cc.debug.at(+dir: String, +who: String, +sid: String) -> IO(String):
  do IO<String>:
    +now : Nat <- S.mu.wall()
    tz : U32 <- S.mu.tzoff(now)
    return dir ++ "/" ++ cc.stamp(K.ck.show(now, tz)) ++ "-mugen-" ++ who ++ "-" ++ String.take(sid, 8n) ++ ".debug.log"

def cc.debug.file(+c: cc.Cfg, +who: String, +sid: String) -> IO(String):
  Bool.pick(IO(String), String.is_empty(cc.cfg.debug(c)), IO.pure(String, ""), cc.debug.at(cc.cfg.debug(c), who, sid))

# Arguments -----------------------------------------------------------------

def cc.list(xs: List<&2, String>) -> List<String>:
  match xs:
    case []:
      []
    case x <> t:
      x <> cc.list(t)

def cc.opt(b: Bool, xs: List<&2, String>) -> List<&2, String>:
  match b:
    case True{}:
      xs
    case False{}:
      []

# Claude Code's settings for our calls (run through env): no API key (the
# plan's login), none of the user's context in the prompt, hour-long marks,
# every tool sent whole (no tool search), and no other model than the one
# asked: Claude Code switches a session to an earlier model when the
# model's safeguards refuse (Opus 5.5 to Opus 5, Opus 5 to Opus 4.8; seen
# 10-31 and 11-16) or it is overloaded or unavailable;
# CLAUDE_CODE_NO_MODEL_FALLBACK forbids every such switch (2.1.325), and
# CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK the refusal's. A refusal then ends
# the call (its retry on the same model, "continuing once with that noted",
# still runs); an outage is waited, as any busy service is.
def cc.env() -> List<&2, String>:
  ["-u", "ANTHROPIC_API_KEY", "-u", "ANTHROPIC_AUTH_TOKEN",
    "CLAUDE_CODE_NO_MODEL_FALLBACK=1", "CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK=1",
    "CLAUDE_CODE_DISABLE_CLAUDE_MDS=1", "CLAUDE_CODE_DISABLE_AUTO_MEMORY=1", "CLAUDE_CODE_DISABLE_ATTACHMENTS=1",
    "CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1", "CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off", "CLAUDE_CODE_PROMPT_CACHE_TTL=1h",
    "CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=1h", "ENABLE_TOOL_SEARCH=false", "DISABLE_AUTOUPDATER=1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"]

# A call's arguments to env: the model's id and effort, the system prompt's
# file, Claude Code's own tools ("" none: WebSearch when it searches), the MCP
# config ("" none), the session's id ("" no transcript), the debug log ("" none),
# one turn only (a call with no tools). A call with tools asks for its
# thoughts summarized (Claude Code's hidden --thinking-display), so the
# screen can show them; else they come empty.
type cc.Run is Data:
  cc.Run{id: String, effort: String, sys: String, tools: String, mcp: String, sid: String, debug: String, once: Bool}

def cc.args(+c: cc.Cfg, r: cc.Run) -> List<String>:
  match r:
    case cc.Run{id, effort, sys, tools, +mcp, +sid, +debug, +once}:
      cc.list(List.concat(&2, String, [cc.env(),
        [cc.cfg.prog(c), "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--replay-user-messages",
          "--model", id, "--effort", effort, "--system-prompt-file", sys, "--strict-mcp-config", "--disable-slash-commands", "--tools", tools],
        cc.opt(Bool.not(String.is_empty(mcp)), ["--mcp-config", mcp, "--allowedTools", "mcp__mugen__*,WebSearch"]),
        cc.opt(Bool.not(String.is_empty(sid)), ["--setting-sources", "user", "--session-id", sid]),
        cc.opt(String.is_empty(sid), ["--no-session-persistence", "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}"]),
        cc.opt(Bool.not(String.is_empty(debug)), ["--debug-file", debug]),
        cc.opt(once, ["--max-turns", "1"]),
        cc.opt(Bool.not(once), ["--thinking-display", "summarized"])]))

# Messages ------------------------------------------------------------------

def cc.mark() -> J.Json:
  J.JObj{[J.JKv{"type", J.JStr{"ephemeral"}}, J.JKv{"ttl", J.JStr{"1h"}}]}

# A text Claude Code keeps the user's words. Claude Code (2.1.319) runs a
# message whose last text block starts with "/" and a name of its own
# commands (/goal, /model, /status, /help, ...) as that command, even with
# --disable-slash-commands: in -p it answers "/goal isn't available in this
# environment" itself (a reply the model never gave), never says the message
# back, and one sent during a turn waits for the turn's end. A space before
# the "/" keeps it a message (the model reads " /goal ..."); a text that
# starts any other way is sent as it is.
def cc.safe.go(slash: Bool, +text: String) -> String:
  match slash:
    case True{}:
      SCon{Chr{32}, text}
    case False{}:
      text

def cc.safe(+text: String) -> String:
  cc.safe.go(String.starts_with(text, "/"), text)

def cc.text(+text: String, mark: Bool) -> J.Json:
  match mark:
    case True{}:
      J.JObj{[J.JKv{"type", J.JStr{"text"}}, J.JKv{"text", J.JStr{cc.safe(text)}}, J.JKv{"cache_control", cc.mark()}]}
    case False{}:
      J.JObj{[J.JKv{"type", J.JStr{"text"}}, J.JKv{"text", J.JStr{cc.safe(text)}}]}

# the blocks with text, the first mark kept (seen: one was)
def cc.parts(bs: List<&2, V.vw.B>, +seen: Bool) -> List<&2, J.Json>:
  match bs:
    case []:
      []
    case V.vw.B{SNil{}, mark} <> t:
      cc.parts(t, seen)
    case V.vw.B{SCon{Chr{1}, p}, mark} <> t:
      Pc.pc.json(p) <> cc.parts(t, seen)
    case V.vw.B{text, +mark} <> t:
      cc.text(text, Bool.and(mark, Bool.not(seen))) <> cc.parts(t, Bool.or(seen, mark))

# a user message as stream-json takes it, its id said back as it is taken
def cc.user(content: List<&2, J.Json>, +uuid: String) -> String:
  J.js.write(J.JObj{[J.JKv{"type", J.JStr{"user"}}, J.JKv{"message", J.JObj{[J.JKv{"role", J.JStr{"user"}}, J.JKv{"content", J.JArr{content}}]}},
    J.JKv{"parent_tool_use_id", J.JNull{}}, J.JKv{"uuid", J.JStr{uuid}}]}) ++ "\n"

def cc.say(+text: String, +uuid: String) -> String:
  cc.user([cc.text(text, False{})], uuid)

# Lines -----------------------------------------------------------------------

# a chunk read: the lines it ends, in order; the line cut short (reversed)
type cc.Fed is Data:
  cc.Fed{lines: List<&2, String>, cur: String}

def cc.feed(s: String, +cur: String, +acc: List<&2, String>) -> cc.Fed:
  match s:
    case SNil{}:
      cc.Fed{List.reverse(&2, String, acc), cur}
    case SCon{Chr{10}, t}:
      cc.feed(t, "", String.reverse(cur) <> acc)
    case SCon{c, t}:
      cc.feed(t, SCon{c, cur}, acc)

def cc.fed.lines(f: cc.Fed) -> List<&2, String>:
  match f:
    case cc.Fed{ls, c}:
      ls

def cc.fed.cur(f: cc.Fed) -> String:
  match f:
    case cc.Fed{ls, c}:
      c

# the line our wrapper adds once Claude Code is gone (or a stop, for it)
def cc.gone(+code: String) -> String:
  "{\"type\":\"mugen_exit\",\"code\":" ++ code ++ "}\n"

def cc.is.gone(+line: String) -> Bool:
  String.starts_with(line, "{\"type\":\"mugen_exit\"")

# Events ----------------------------------------------------------------------

def cc.s(+j: J.Json, +k: String) -> String:
  Maybe.default(&2, String, J.js.str(j, k), "")

def cc.n(+j: J.Json, +k: String) -> Nat:
  Maybe.default(&2, Nat, J.js.num(j, k), 0n)

def cc.ty(+j: J.Json) -> String:
  cc.s(j, "type")

def cc.message(+j: J.Json) -> J.Json:
  Maybe.default(&2, J.Json, J.js.field(j, "message"), J.JObj{[]})

# Another model ----------------------------------------------------------------
#
# mugen takes answers only from the model it asked (cc.env forbids Claude
# Code's switches; this is what holds if one comes anyway): Claude Code's
# notice that it switched (model_refusal_fallback), or an output of another
# model's, ends the call with no reply. Claude Code's own outputs
# (<synthetic>: a limit, an API error) are not a model's. Only a full id
# (claude-...) is compared: an alias (opus) or a variant ([1m]) answers
# under another name.

def cc.checked(+id: String) -> Bool:
  Bool.and(String.starts_with(id, "claude-"), Bool.not(String.contains(id, "[")))

def cc.other.out(+id: String, +m: String) -> String:
  Bool.pick(String, Bool.or(Bool.or(String.is_empty(m), String.eq(m, "<synthetic>")), Bool.or(String.eq(m, id), Bool.not(cc.checked(id)))), "", m)

# the model an event says answers instead of id ("" none)
def cc.other(+id: String, +j: J.Json) -> String:
  +ty = cc.ty(j)
  +fb = cc.s(j, "fallback_model")
  +sw = Bool.and(String.eq(ty, "system"), String.eq(cc.s(j, "subtype"), "model_refusal_fallback"))
  Bool.pick(String, sw, Bool.pick(String, String.is_empty(fb), "another model", fb),
    Bool.pick(String, String.eq(ty, "assistant"), cc.other.out(id, cc.s(cc.message(j), "model")), ""))

# the stop it makes (a call's end with no reply)
def cc.other.stop(+id: String, +m: String) -> String:
  "another model: " ++ m ++ ", not " ++ id ++ " (mugen takes no other)"

# an event's message's content blocks
def cc.blocks(+j: J.Json) -> List<&2, J.Json>:
  J.js.arr(cc.message(j), "content")

# n tokens, as 14.2k
def cc.k(+n: Nat) -> String:
  +u = U32.from_nat(n)
  Bool.pick(String, U32.is_lt(u, 1000), U32.show(u), U32.show(U32.div(u, 1000)) ++ "." ++ U32.show(U32.div(U32.mod(u, 1000), 100)) ++ "k")

# a result's tokens: read from the cache, written to it, sent anew, written out
def cc.usage(+u: J.Json) -> String:
  "cache: " ++ cc.k(cc.n(u, "cache_read_input_tokens")) ++ " read, " ++ cc.k(cc.n(u, "cache_creation_input_tokens")) ++ " written, "
    ++ cc.k(cc.n(u, "input_tokens")) ++ " new in, " ++ cc.k(cc.n(u, "output_tokens")) ++ " out"

# What a run said, its result's: whether one came, it succeeded, the API's
# status of an error (0 none), its stop reason, its errors' words
type cc.Res is Data:
  cc.Res{got: Bool, ok: Bool, status: U32, stop: String, why: String}

def cc.none() -> cc.Res:
  cc.Res{False{}, False{}, 0, "", ""}

def cc.texts(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case []:
      []
    case J.JStr{s} <> t:
      s <> cc.texts(t)
    case x <> t:
      J.js.write(x) <> cc.texts(t)

# an array of strings (a result's user_message_uuids)
def cc.strs(+j: J.Json, +k: String) -> List<&2, String>:
  cc.texts(J.js.arr(j, k))

def cc.res.of(+j: J.Json) -> cc.Res:
  +err = Maybe.default(&2, Bool, J.js.bool(j, "is_error"), False{})
  +sub = cc.s(j, "subtype")
  +ok = Bool.and(Bool.not(err), String.eq(sub, "success"))
  +why = Bool.pick(String, ok, "", Bool.pick(String, List.is_empty(&2, J.Json, J.js.arr(j, "errors")), cc.s(j, "result"), T.tx.join(cc.texts(J.js.arr(j, "errors")), "; ")))
  cc.Res{True{}, ok, U32.from_nat(cc.n(j, "api_error_status")), cc.s(j, "stop_reason"), Bool.pick(String, String.is_empty(why), sub, why)}

# a turn's end: no stop reason, or one of a turn ended as asked
def cc.fine(+stop: String) -> Bool:
  Bool.or(Bool.or(String.is_empty(stop), String.eq(stop, "end_turn")), Bool.or(String.eq(stop, "tool_use"), String.eq(stop, "stop_sequence")))

def cc.res.fine(r: cc.Res) -> Bool:
  match r:
    case cc.Res{g, ok, st, +sp, w}:
      Bool.and(ok, cc.fine(sp))

def cc.res.ok(r: cc.Res) -> Bool:
  match r:
    case cc.Res{g, ok, st, sp, w}:
      ok

# A run read whole (a call of one turn): its output blocks, in order (each
# assistant event holds one or more), and its result. Another model than id
# (cc.other) ends it there: its stop the result, no block after it taken.
type cc.Once is Data:
  cc.Once{out: List<&2, J.Json>, res: cc.Res}

def cc.res.stop(r: cc.Res) -> String:
  match r:
    case cc.Res{g, ok, st, sp, w}:
      sp

# a stop for another model's answer (cc.other.stop)
def cc.res.other(+r: cc.Res) -> Bool:
  String.starts_with(cc.res.stop(r), "another model: ")

def cc.once.on(+id: String, +j: J.Json, +out: List<&2, J.Json>, +res: cc.Res) -> cc.Once:
  +ty = cc.ty(j)
  +m = cc.other(id, j)
  Bool.pick(cc.Once, Bool.not(String.is_empty(m)), cc.Once{out, cc.Res{True{}, True{}, 0, cc.other.stop(id, m), ""}},
    Bool.pick(cc.Once, String.eq(ty, "assistant"), cc.Once{List.append(&2, J.Json, out, cc.blocks(j)), res},
      Bool.pick(cc.Once, String.eq(ty, "result"), cc.Once{out, cc.res.of(j)}, cc.Once{out, res})))

# (a stop already read, by another model: the lines after it are not read)
def cc.once.line(+id: String, +line: String, o: cc.Once) -> cc.Once:
  match o:
    case cc.Once{+out, +res}:
      Bool.pick(cc.Once, cc.res.other(res), cc.Once{out, res}, cc.once.on(id, Maybe.default(&2, J.Json, J.js.read(line), J.JObj{[]}), out, res))

def cc.once.go(+id: String, ls: List<&2, String>, +o: cc.Once) -> cc.Once:
  match ls:
    case []:
      o
    case l <> t:
      cc.once.go(id, t, cc.once.line(id, l, o))

def cc.once.read(+id: String, +out: String) -> cc.Once:
  cc.once.go(id, String.lines(out), cc.Once{[], cc.none()})

# The plan's limits as the latest call said them (its rate_limit_event's
# info), kept in run/limits.json with when they were said, for the status
def cc.limits.save(+c: cc.Cfg, +info: J.Json) -> IO(Unit):
  do IO<Unit>:
    +now : Nat <- S.mu.wall()
    r : Result<&1, &1, U32 & String, Unit> <- S.mu.save(cc.cfg.run(c) ++ "/limits.json", J.js.write(J.JObj{[J.JKv{"at", J.js.nat(now)}, J.JKv{"info", info}]}), 0)
    return Unit{}

def cc.limits.keep(+c: cc.Cfg, m: Maybe<&2, J.Json>) -> IO(Unit):
  match m:
    case Some{info}:
      cc.limits.save(c, info)
    case None{}:
      IO.pure(Unit, Unit{})

def cc.limits.of(hit: Bool, +line: String, +acc: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match hit:
    case True{}:
      J.js.field(Maybe.default(&2, J.Json, J.js.read(line), J.JObj{[]}), "rate_limit_info")
    case False{}:
      acc

# the last rate_limit_event's info in a run's output
def cc.limits.find(ls: List<&2, String>, +acc: Maybe<&2, J.Json>) -> Maybe<&2, J.Json>:
  match ls:
    case []:
      acc
    case +l <> t:
      cc.limits.find(t, cc.limits.of(String.starts_with(l, "{\"type\":\"rate_limit_event\""), l, acc))

def cc.out.text(o: S.mu.Out) -> String:
  match o:
    case S.mu.Out{st, out, err}:
      out

# One call of one turn, no tools: its message on stdin, its output whole
# (Process.run; 64 MiB at most, 16 minutes), run in the work dir. ctl: the
# caller's control files ("" a compaction's: the system prompt in run/once).
def cc.once(+c: cc.Cfg, +id: String, +effort: String, +system: String, +blocks: List<&2, V.vw.B>, +ctl: String) -> IO(S.mu.Out):
  +sys = Bool.pick(String, String.is_empty(ctl), cc.cfg.run(c) ++ "/once", ctl ++ ".once") ++ ".system"
  +keep = cc.keeps(c, Bool.not(String.is_empty(ctl)))
  do IO<S.mu.Out>:
    r : Result<&1, &1, U32 & String, Unit> <- S.mu.save(sys, system, 0)
    +u : String <- cc.uuid()
    +sid : String = Bool.pick(String, keep, u, "")
    +debug : String <- Bool.pick(IO(String), keep, cc.debug.file(c, Bool.pick(String, String.is_empty(ctl), "compact", "goal"), u), IO.pure(String, ""))
    +m : String <- cc.uuid()
    +o : S.mu.Out <- S.mu.run("sh", List.append(&1, String, ["-c", "cd \"$0\" && exec \"$@\"", cc.cfg.work(c) ++ "/main", "env"],
      cc.args(c, cc.Run{id, effort, sys, "", "", sid, debug, True{}})), cc.user(cc.parts(blocks, False{}), m), 67108864, 960000)
    Unit <- cc.limits.keep(c, cc.limits.find(String.lines(cc.out.text(o)), None{}))
    return o

# Claude Code at work -----------------------------------------------------------
#
# A call with tools runs in the background, so its events are read as they
# come: its stdin the FIFO ctl.cc.in (we hold its other end: closed, the
# call ends), its stdout and stderr ctl.cc.out and ctl.cc.err, its process
# group's leader in ctl.cc.pid and run/groups (killed by a stop or a quit;
# a watchdog in it kills the group if mugen dies; the groups file has its
# start time too, /proc/PID/stat's field 22, so that no other group that
# took its number is killed). Once it is gone the wrapper adds a last line
# (cc.gone) with its exit status. The wrapper is bash's: its `set -m` gives
# the call a group of its own and leaves the terminal to mugen, where dash's
# takes the terminal for itself (issue #1)
#
#   $0 ctl, $1 run/groups, $2 the work dir, the rest env's arguments

def cc.launch() -> String:
  "set -m\nm=$PPID c=$0 g=$1 d=$2\nshift 2\n(\n  set +m\n  ( while kill -0 \"$m\" 2> /dev/null; do sleep 2; done; kill -TERM 0 ) &\n  w=$!\n  exec 3< \"$c.cc.in\"\n  cd \"$d\" && \"$@\" <&3 >> \"$c.cc.out\" 2> \"$c.cc.err\"\n  echo \"{\\\"type\\\":\\\"mugen_exit\\\",\\\"code\\\":$?}\" >> \"$c.cc.out\"\n  kill \"$w\" 2> /dev/null\n) < /dev/null > /dev/null 2>&1 &\necho $! > \"$c.cc.pid\"\necho \"$! $(cut -d' ' -f22 /proc/$!/stat 2> /dev/null)\" >> \"$g\"\n"

# Our MCP server, as Claude Code starts it: a relay of two processes, its
# requests copied to ctl.cc.mcp.in, our answers in ctl.cc.mcp.out followed to it
# (while Claude Code, its parent, lives)
def cc.mcp(+ctl: String) -> String:
  J.js.write(J.JObj{[J.JKv{"mcpServers", J.JObj{[J.JKv{"mugen", J.JObj{[J.JKv{"type", J.JStr{"stdio"}}, J.JKv{"command", J.JStr{"sh"}},
    J.JKv{"args", J.JArr{[J.JStr{"-c"}, J.JStr{"tail -n +1 -s 0.05 -f --pid=$PPID \"$1\" & exec cat >> \"$0\""}, J.JStr{ctl ++ ".cc.mcp.in"}, J.JStr{ctl ++ ".cc.mcp.out"}]}},
    J.JKv{"alwaysLoad", J.JBool{True{}}}]}}]}}]})

# the call started in the background: env's arguments
def cc.start(+c: cc.Cfg, +ctl: String, +cwd: String, args: List<String>) -> IO(S.mu.Out):
  S.mu.run("bash", List.append(&1, String, ["-c", cc.launch(), ctl, cc.cfg.run(c) ++ "/groups", cwd, "env"], args), "", 65536, 30000)
