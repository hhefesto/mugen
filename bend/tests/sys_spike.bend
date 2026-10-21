# S5: the mu effects compile against the pinned bend2 and work.
import Base
import ../Sys.bend as S

def show(o: S.mu.Out) -> String:
  match o:
    case S.mu.Out{st, out, err}:
      "status " ++ U32.show(st) ++ " out " ++ out ++ " err " ++ err

def main() -> IO(Unit):
  do IO<Unit>:
    +d : String <- S.mu.env("MU_TEST_DIR", "/tmp/mu-test")
    Unit <- S.mu.must(Unit, "mkdirs", S.mu.mkdirs(d ++ "/a/b"))
    o1 : Nat <- S.mu.must(Nat, "append", S.mu.append(d ++ "/a/x.txt", "héllo\n", 1))
    +o2 : Nat <- S.mu.must(Nat, "append", S.mu.append(d ++ "/a/x.txt", "wörld 🎉\n", 0))
    IO.print("offsets " ++ Nat.show(o1) ++ " " ++ Nat.show(o2))
    t : String <- S.mu.must(String, "pread", S.mu.pread_text(d ++ "/a/x.txt", o2, 100))
    IO.write("pread: " ++ t)
    Unit <- S.mu.must(Unit, "save", S.mu.save(d ++ "/v.json", "{\"a\":1}", 1))
    v : String <- S.mu.must(String, "read", S.mu.read_file(d ++ "/v.json"))
    IO.print("read: " ++ v)
    n : Nat <- S.mu.must(Nat, "size", S.mu.size(d ++ "/a/x.txt"))
    IO.print("size " ++ Nat.show(n))
    ls : List<&2, String> <- S.mu.must(List<&2, String>, "ls", S.mu.ls(d))
    IO.print("ls " ++ String.join(ls, ","))
    Unit <- S.mu.must(Unit, "slot", S.mu.slot_put(d ++ "/i.idx", 3n, 1, 2, 4294967295, 7, 0))
    ws : List<&2, U32> <- S.mu.must(List<&2, U32>, "slots", S.mu.slots(d ++ "/i.idx", 2n, 3))
    IO.print("slots " ++ List.show(&2, U32, U32.show, ws))
    Unit <- S.mu.must(Unit, "lock", S.mu.lock(d ++ "/lock"))
    +ms : Nat <- S.mu.wall()
    tz : U32 <- S.mu.tzoff(ms)
    h : String <- S.mu.host()
    tty : U32 <- S.mu.isatty(0)
    IO.print("wall>0 " ++ Bool.show(Nat.is_gt(ms, 0n)) ++ " tz " ++ U32.show(tz) ++ " host " ++ h ++ " tty " ++ U32.show(tty))
    o : S.mu.Out <- S.mu.run("sh", ["-c", "echo out; echo err >&2; exit 3"], "", 1000, 5000)
    IO.write(show(o))
