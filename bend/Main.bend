
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Json.bend as J
import ./Api.bend as A
import ./Hub.bend as H
import ./Tools.bend as L
import ./Code.bend as C

# mugen: one chat with an AI that never ends, in the terminal (UniiChat, in
# Bend). It runs on Claude Code's CLI (`claude -p`, the login of a Claude
# plan), or with --api on the Messages API (an API key); `mugen login` signs
# Claude Code in (claude auth login). Its settings come from the
# environment:
#
#   ANTHROPIC_API_KEY     with --api, the API key (curl reads it; it is never
#                         in argv); Claude Code's calls never see it
#   MUGEN_WIRE         api: as --api
#   MUGEN_CLAUDE       the claude to run (claude)
#   MUGEN_DEBUG_DIR    where a chat call's Claude Code debug log goes (none)
#   MUGEN_TRANSCRIPTS  whose calls Claude Code keeps as sessions: chat (the
#                         turns', agents', goal checks'), all, none
#   MUGEN_DIR          the data dir (~/.mugen): the chat's logs, tree, view
#   MUGEN_WORK         the tools' work dir (DIR/work), a dir per agent
#   MUGEN_PICK         the chat's model:effort[:speed] (opus-5.5:medium:slow),
#                         till /model or /effort picks another
#   MUGEN_COMPACTOR    the summaries' (haiku-5.5:high:slow)
#   MUGEN_RULES        a file of the user's instructions (DIR/rules.md)
#   MUGEN_JOBS         summaries at once (8 on Claude Code, 48 with --api)
#   MUGEN_SYNC         1 (default): each log write is fsynced; 0: not
#   MUGEN_MAX_TOKENS   a reply's most tokens (16000)
#   MUGEN_WEB_SEARCH   the web search tool's type (web_search_20260209)
#   MUGEN_CURL, MUGEN_API_URL, MUGEN_UNIT   for tests: the curl to
#                         run, the endpoint, the ms a second of waiting takes
#
# Every def is prefixed `mn.`.

def mn.nat(+s: String, +d: U32) -> U32:
  U32.from_nat(Maybe.default(&2, Nat, Nat.read(s), U32.to_nat(d)))

def mn.part(+ps: List<&2, String>, +k: Nat, +d: String) -> String:
  +x = Maybe.default(&2, String, List.get(&2, String, ps, k), "")
  Bool.pick(String, String.is_empty(x), d, x)

# model:effort[:speed]
def mn.pick(+s: String) -> A.ap.Pick:
  +ps = L.tl.split(s, ":")
  A.ap.Pick{mn.part(ps, 0n, "opus-5.5"), mn.part(ps, 1n, "medium"), mn.part(ps, 2n, "slow")}

def mn.text.of(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{s}:
      s
    case Fail{e}:
      ""

# no key, no call: said at once (with a curl of its own, a test's, none is
# needed; on Claude Code, none is)
def mn.key(+api: Bool, +curl: String, r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Done{k}:
      IO.pure(Unit, Unit{})
    case Fail{e}:
      Bool.pick(IO(Unit), Bool.and(api, String.eq(curl, "curl")), IO.die(Unit, 1, "mugen: set ANTHROPIC_API_KEY (curl reads it from the environment), or run mugen without --api, on Claude Code"), IO.pure(Unit, Unit{}))

def mn.usage() -> String:
  "usage: mugen [--api | login]\n  mugen        runs on Claude Code's CLI (claude -p), signed in with a Claude plan\n  mugen --api  runs on the Messages API, with ANTHROPIC_API_KEY\n  mugen login  signs Claude Code in to your Claude plan (claude auth login)"

# what the arguments ask: 0 Claude Code, 1 the API (--api), 2 the usage
# (anything else), 3 a sign-in (login, alone)
def mn.flag(+v: U32, +x: String) -> U32:
  Bool.pick(U32, String.eq(x, "--api"), Bool.pick(U32, U32.is_eq(v, 3), 2, U32.max(v, 1)),
    Bool.pick(U32, String.eq(x, "login"), Bool.pick(U32, U32.is_eq(v, 0), 3, 2), 2))

def mn.flags(xs: List<String>, +v: U32) -> U32:
  match xs:
    case []:
      v
    case +x <> t:
      mn.flags(t, mn.flag(v, x))

def mn.argv(xs: List<String>) -> U32:
  match xs:
    case []:
      0
    case x <> t:
      mn.flags(t, 0)

# Claude Code there to run and signed in (its auth status, without an API
# key, as mugen runs it), else said at once
def mn.signed(+out: String) -> Nat:
  +j = J.js.read(out)
  Bool.pick(Nat, Maybe.is_none(&2, J.Json, j), 0n,
    Bool.pick(Nat, Maybe.default(&2, Bool, J.js.bool(Maybe.default(&2, J.Json, j, J.JObj{[]}), "loggedIn"), False{}), 2n, 1n))

def mn.claude.say(k: Nat, +prog: String, +err: String) -> IO(Unit):
  match k:
    case 2n:
      IO.pure(Unit, Unit{})
    case 1n:
      IO.die(Unit, 1, "mugen: Claude Code is not signed in. Run `mugen login`, then `mugen` again (or `mugen --api` with ANTHROPIC_API_KEY).")
    case _:
      IO.die(Unit, 1, "mugen: cannot run " ++ prog ++ " (MUGEN_CLAUDE): " ++ err ++ "\nInstall Claude Code and run `mugen login`, or run `mugen --api` with ANTHROPIC_API_KEY.")

def mn.claude.got(+prog: String, o: S.mu.Out) -> IO(Unit):
  match o:
    case S.mu.Out{status, +out, +err}:
      mn.claude.say(mn.signed(out), prog, T.tx.trim(err))

def mn.claude(on: Bool, +prog: String) -> IO(Unit):
  match on:
    case True{}:
      IO.bind(S.mu.Out, Unit, S.mu.run("env", ["-u", "ANTHROPIC_API_KEY", "-u", "ANTHROPIC_AUTH_TOKEN", prog, "auth", "status", "--json"], "", 65536, 60000), o => mn.claude.got(prog, o))
    case False{}:
      IO.pure(Unit, Unit{})

def mn.trans(+s: String) -> U32:
  Bool.pick(U32, String.eq(s, "none"), 0, Bool.pick(U32, String.eq(s, "all"), 2, 1))

def mn.run(+home: String, +api: Bool) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- S.mu.env("MUGEN_DIR", home ++ "/.mugen")
    +work : String <- S.mu.env("MUGEN_WORK", dir ++ "/work")
    pick : String <- S.mu.env("MUGEN_PICK", "opus-5.5:medium:slow")
    comp : String <- S.mu.env("MUGEN_COMPACTOR", "haiku-5.5:high:slow")
    rpath : String <- S.mu.env("MUGEN_RULES", dir ++ "/rules.md")
    rules : Result<&1, &1, U32 & String, String> <- S.mu.read_file(rpath)
    jobs : String <- S.mu.env("MUGEN_JOBS", Bool.pick(String, api, "48", "8"))
    sync : String <- S.mu.env("MUGEN_SYNC", "1")
    max : String <- S.mu.env("MUGEN_MAX_TOKENS", "16000")
    web : String <- S.mu.env("MUGEN_WEB_SEARCH", "web_search_20260209")
    +curl : String <- S.mu.env("MUGEN_CURL", "curl")
    key : Result<&1, &1, U32 & String, String> <- IO.get_env("ANTHROPIC_API_KEY")
    Unit <- mn.key(api, curl, key)
    +claude : String <- S.mu.env("MUGEN_CLAUDE", "claude")
    Unit <- mn.claude(Bool.not(api), claude)
    debug : String <- S.mu.env("MUGEN_DEBUG_DIR", "")
    trans : String <- S.mu.env("MUGEN_TRANSCRIPTS", "chat")
    url : String <- S.mu.env("MUGEN_API_URL", "https://api.anthropic.com/v1/messages")
    unit : String <- S.mu.env("MUGEN_UNIT", "1000")
    shell : String <- S.mu.env("SHELL", "/bin/sh")
    host : String <- S.mu.host()
    i : U32 <- S.mu.isatty(0)
    o : U32 <- S.mu.isatty(1)
    +cc : C.cc.Cfg = C.cc.Cfg{Bool.pick(U32, api, 0, 1), claude, debug, mn.trans(trans), dir ++ "/run", work}
    +wire : A.ap.Cfg = A.ap.Cfg{curl, url, mn.nat(max, 16000), web, mn.nat(unit, 1000), cc}
    +cfg : H.hb.Cfg = H.hb.Cfg{wire, dir, work, host, shell, mn.text.of(rules), mn.pick(comp), Bool.and(U32.is_eq(i, 1), U32.is_eq(o, 1)), mn.nat(jobs, 48), mn.nat(sync, 1)}
    H.hb.start(cfg, mn.pick(pick))

# `mugen login`: this process becomes Claude Code's sign-in, on the
# terminal (no API key, which would take its place)
def mn.login(+prog: String) -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print("mugen: signing Claude Code in to your Claude plan (" ++ prog ++ " auth login). Run `mugen` once it says you are in.")
    e : U32 <- S.mu.exec("env", ["-u", "ANTHROPIC_API_KEY", "-u", "ANTHROPIC_AUTH_TOKEN", prog, "auth", "login"])
    IO.die(Unit, 1, "mugen: cannot run " ++ prog ++ " (MUGEN_CLAUDE), error " ++ U32.show(e))

def mn.go(+v: U32, +home: String, +wire: String, +prog: String) -> IO(Unit):
  Bool.pick(IO(Unit), U32.is_eq(v, 2), IO.print(mn.usage()),
    Bool.pick(IO(Unit), U32.is_eq(v, 3), mn.login(prog), mn.run(home, Bool.or(U32.is_eq(v, 1), String.eq(wire, "api")))))

def main() -> IO(Unit):
  do IO<Unit>:
    home : String <- S.mu.env("HOME", "/tmp")
    wire : String <- S.mu.env("MUGEN_WIRE", "")
    prog : String <- S.mu.env("MUGEN_CLAUDE", "claude")
    args : List<String> <- IO.args()
    mn.go(mn.argv(args), home, wire, prog)
