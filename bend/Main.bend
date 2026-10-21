
import Base
import ./Sys.bend as S
import ./Text.bend as T
import ./Api.bend as A
import ./Hub.bend as H
import ./Tools.bend as L

# mugen: one chat with an AI that never ends, in the terminal (UniiChat, in
# Bend). Its settings come from the environment:
#
#   ANTHROPIC_API_KEY     the API key (curl reads it; it is never in argv)
#   MUGEN_DIR          the data dir (~/.mugen): the chat's logs, tree, view
#   MUGEN_WORK         the tools' work dir (DIR/work), a dir per agent
#   MUGEN_PICK         the chat's model:effort[:speed] (opus-5.5:medium:slow),
#                         till /model or /effort picks another
#   MUGEN_COMPACTOR    the summaries' (haiku-5.5:high:slow)
#   MUGEN_RULES        a file of the user's instructions (DIR/rules.md)
#   MUGEN_JOBS         summaries at once (48)
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

# no key, no call: said at once (with a curl of its own, a test's, none is needed)
def mn.key(+curl: String, r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Done{k}:
      IO.pure(Unit, Unit{})
    case Fail{e}:
      Bool.pick(IO(Unit), String.eq(curl, "curl"), IO.die(Unit, 1, "mugen: set ANTHROPIC_API_KEY (curl reads it from the environment)"), IO.pure(Unit, Unit{}))

def mn.run(+home: String) -> IO(Unit):
  do IO<Unit>:
    +dir : String <- S.mu.env("MUGEN_DIR", home ++ "/.mugen")
    +work : String <- S.mu.env("MUGEN_WORK", dir ++ "/work")
    pick : String <- S.mu.env("MUGEN_PICK", "opus-5.5:medium:slow")
    comp : String <- S.mu.env("MUGEN_COMPACTOR", "haiku-5.5:high:slow")
    rpath : String <- S.mu.env("MUGEN_RULES", dir ++ "/rules.md")
    rules : Result<&1, &1, U32 & String, String> <- S.mu.read_file(rpath)
    jobs : String <- S.mu.env("MUGEN_JOBS", "48")
    sync : String <- S.mu.env("MUGEN_SYNC", "1")
    max : String <- S.mu.env("MUGEN_MAX_TOKENS", "16000")
    web : String <- S.mu.env("MUGEN_WEB_SEARCH", "web_search_20260209")
    +curl : String <- S.mu.env("MUGEN_CURL", "curl")
    key : Result<&1, &1, U32 & String, String> <- IO.get_env("ANTHROPIC_API_KEY")
    Unit <- mn.key(curl, key)
    url : String <- S.mu.env("MUGEN_API_URL", "https://api.anthropic.com/v1/messages")
    unit : String <- S.mu.env("MUGEN_UNIT", "1000")
    shell : String <- S.mu.env("SHELL", "/bin/sh")
    host : String <- S.mu.host()
    i : U32 <- S.mu.isatty(0)
    o : U32 <- S.mu.isatty(1)
    +api : A.ap.Cfg = A.ap.Cfg{curl, url, mn.nat(max, 16000), web, mn.nat(unit, 1000)}
    +cfg : H.hb.Cfg = H.hb.Cfg{api, dir, work, host, shell, mn.text.of(rules), mn.pick(comp), Bool.and(U32.is_eq(i, 1), U32.is_eq(o, 1)), mn.nat(jobs, 48), mn.nat(sync, 1)}
    H.hb.start(cfg, mn.pick(pick))

def main() -> IO(Unit):
  do IO<Unit>:
    home : String <- S.mu.env("HOME", "/tmp")
    mn.run(home)
