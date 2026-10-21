# S3: 8 parallel Process.run("sleep 1") finish in about 1 s on a native build.
# S6: 1 MB through Process.run cat, timed.
import Base

def nap() -> IO(Result<&1, &1, U32 & String, U32 & (String & String)>):
  Process.run("sleep", ["1"], "", 1024, 10000)

def forks(n: Nat) -> IO(List<&1, Chan(Result<&1, &1, U32 & String, U32 & (String & String)>)>):
  match n:
    case 0n:
      IO.pure(List<&1, Chan(Result<&1, &1, U32 & String, U32 & (String & String)>)>, [])
    case 1n+k:
      do IO<List<&1, Chan(Result<&1, &1, U32 & String, U32 & (String & String)>)>>:
        c : Chan(Result<&1, &1, U32 & String, U32 & (String & String)>) <- IO.fork(Result<&1, &1, U32 & String, U32 & (String & String)>, nap())
        cs : List<&1, Chan(Result<&1, &1, U32 & String, U32 & (String & String)>)> <- forks(k)
        return c <> cs

def joins(cs: List<&1, Chan(Result<&1, &1, U32 & String, U32 & (String & String)>)>) -> IO(Nat):
  match cs:
    case []:
      IO.pure(Nat, 0n)
    case c <> rest:
      do IO<Nat>:
        r : Result<&1, &1, U32 & String, U32 & (String & String)> <- IO.join(Result<&1, &1, U32 & String, U32 & (String & String)>, c)
        n : Nat <- joins(rest)
        return 1n+n

def big(n: Nat, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+k:
      big(k, "0123456789abcdef" ++ acc)

def outlen(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Nat:
  match r:
    case Fail{(code, msg)}:
      0n
    case Done{(code, (out, err))}:
      String.length(out)

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    cs : List<&1, Chan(Result<&1, &1, U32 & String, U32 & (String & String)>)> <- forks(8n)
    n : Nat <- joins(cs)
    t1 : Nat <- IO.now()
    IO.print("S3: " ++ Nat.show(n) ++ " sleeps in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    s : String = big(65536n, "")
    t2 : Nat <- IO.now()
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("cat", [], s, 4194304, 10000)
    t3 : Nat <- IO.now()
    IO.print("S6: " ++ Nat.show(outlen(r)) ++ " chars back in " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms")
