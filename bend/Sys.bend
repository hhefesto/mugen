import Base

# Sys: the system calls mugen needs that Base does not have, each a C
# effect in bend/effs/mu.c (bend guide effects), plus Process.run helpers.
# Every def is prefixed `mu.` (a program's defs share one namespace).
#
# The effects are native only: mugen runs as a compiled binary, where
# Process.run and File.read leave the event loop free; the JS lane runs only
# the pure modules' tests. A def outside Base with a foreign body is a
# promise to the proof gate, so LAWS.bend imports no module that uses Sys.

type mu.Err is Data:
  mu.Err{code: U32, text: String}

# milliseconds since the Unix epoch
def mu.wall() -> IO(Nat):
  import "./effs/mu.c"

# the local zone's offset from UTC at that instant, minutes east, plus 1440
def mu.tzoff(ms: Nat) -> IO(U32):
  import "./effs/mu.c"

# text's UTF-8 at the end of the file (made if missing; fsynced when sync is
# 1): the offset it starts at
def mu.append(path: String, text: String, sync: U32) -> IO(Result<&1, &1, U32 & String, Nat>):
  import "./effs/mu.c"

# up to max bytes at a byte offset, decoded as UTF-8
def mu.pread_text(path: String, offset: Nat, max: U32) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/mu.c"

# the whole file, decoded as UTF-8
def mu.read_file(path: String) -> IO(Result<&1, &1, U32 & String, String>):
  import "./effs/mu.c"

# the file replaced whole, atomically (path.new, fsync when sync is 1, rename)
def mu.save(path: String, text: String, sync: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/mu.c"

def mu.size(path: String) -> IO(Result<&1, &1, U32 & String, Nat>):
  import "./effs/mu.c"

# mkdir -p
def mu.mkdirs(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/mu.c"

# a directory's names (no . and ..), sorted bytewise
def mu.ls(dir: String) -> IO(Result<&1, &1, U32 & String, List<&2, String>>):
  import "./effs/mu.c"

# the u32 words of n 16-byte slots from slot `first` on, four per slot,
# little-endian; slots past the end (or of a missing file) read 0
def mu.slots(path: String, first: Nat, n: U32) -> IO(Result<&1, &1, U32 & String, List<&2, U32>>):
  import "./effs/mu.c"

# one 16-byte slot written in place (fsynced when sync is 1)
def mu.slot_put(path: String, slot: Nat, a: U32, b: U32, c: U32, d: U32, sync: U32) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/mu.c"

def mu.truncate(path: String, size: Nat) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/mu.c"

# flock(LOCK_EX | LOCK_NB), held until the process exits
def mu.lock(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/mu.c"

# 1 when the descriptor is a terminal
def mu.isatty(fd: U32) -> IO(U32):
  import "./effs/mu.c"

def mu.host() -> IO(String):
  import "./effs/mu.c"

# signal sig to a pid (group 0) or its process group (group 1): 0, or the errno
def mu.kill(pid: U32, group: U32, sig: U32) -> IO(U32):
  import "./effs/mu.c"

# the file written whole in place (its mode kept), as a tool's write does
def mu.put(path: String, text: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/mu.c"

def mu.unlink(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  import "./effs/mu.c"

# the file's length in UTF-16 units, its bytes read as UTF-8
def mu.units(path: String) -> IO(Result<&1, &1, U32 & String, Nat>):
  import "./effs/mu.c"

# Results -------------------------------------------------------------------

# a fallible effect's answer, or exit 1 with "mugen: <what>: <error>"
def mu.must.got(-A: Type, +what: String, r: Result<&1, &1, U32 & String, A>) -> IO(A):
  match r:
    case Done{x}:
      IO.pure(A, x)
    case Fail{(code, text)}:
      IO.die(A, 1, "mugen: " ++ what ++ ": " ++ text)

def mu.must(-A: Type, +what: String, act: IO(Result<&1, &1, U32 & String, A>)) -> IO(A):
  IO.bind(Result<&1, &1, U32 & String, A>, A, act, mu.must.got(A, what))

# an environment variable, or a default when unset
def mu.env.got(+dflt: String, r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{x}:
      IO.pure(String, x)
    case Fail{e}:
      IO.pure(String, dflt)

def mu.env(name: String, +dflt: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, String>, String, IO.get_env(name), mu.env.got(dflt))

# Processes -----------------------------------------------------------------

# A finished child: its exit status, stdout and stderr; status 999 when it
# could not run (start failure, timeout or output past the limit), with the
# reason in err.
type mu.Out is Data:
  mu.Out{status: U32, out: String, err: String}

def mu.run.got(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> mu.Out:
  match r:
    case Done{(status, (out, err))}:
      mu.Out{status, out, err}
    case Fail{(code, text)}:
      mu.Out{999, "", text}

# Process.run, its answer as an Out
def mu.run(program: String, args: List<String>, input: String, max: U32, ms: U32) -> IO(mu.Out):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, mu.Out,
    Process.run(program, args, input, max, ms), r => IO.pure(mu.Out, mu.run.got(r)))
