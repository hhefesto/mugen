# S2: a forked stdin reader runs beside a ticker; the hub prints both.
# S8: idle CPU while the reader is parked on stdin (measured outside).
import Base

type Ev is Data:
  Chunk{text: String}
  Eof{}
  Tick{n: U32}

# the reader: the last read's answer is a parameter, so the loop matches it
def reader(fuel: Nat, +out: Chan(Ev), r: File & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match fuel r:
    case 0n Tuple{file, _}:
      File.close(file)
    case 1n+f Tuple{file, Fail{e}}:
      do IO<Unit>:
        Result<&1, &1, Ev, Unit> <- Chan.send(Ev, out, Eof{})
        File.close(file)
    case 1n+f Tuple{file, Done{SNil{}}}:
      do IO<Unit>:
        Result<&1, &1, Ev, Unit> <- Chan.send(Ev, out, Eof{})
        File.close(file)
    case 1n+f Tuple{file, Done{text}}:
      do IO<Unit>:
        Result<&1, &1, Ev, Unit> <- Chan.send(Ev, out, Chunk{text})
        r2 : File & Result<&1, &1, U32 & String, String> <- File.read(file, 65536)
        reader(f, out, r2)

def ticker(n: Nat, +out: Chan(Ev), +k: U32) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+m:
      do IO<Unit>:
        IO.sleep(300)
        Result<&1, &1, Ev, Unit> <- Chan.send(Ev, out, Tick{k})
        ticker(m, out, (k + 1 : U32))

def hub.on(m: Maybe<&1, Ev>) -> IO(Bool):
  match m:
    case None{}:
      IO.pure(Bool, False{})
    case Some{Eof{}}:
      IO.pure(Bool, False{})
    case Some{Chunk{text}}:
      do IO<Bool>:
        IO.write("got: " ++ text)
        return True{}
    case Some{Tick{n}}:
      do IO<Bool>:
        IO.print("tick " ++ U32.show(n))
        return True{}

def hub(fuel: Nat, +inbox: Chan(Ev), go: Bool) -> IO(Unit):
  match fuel go:
    case 0n _:
      IO.pure(Unit, Unit{})
    case 1n+f False{}:
      IO.print("hub: eof")
    case 1n+f True{}:
      do IO<Unit>:
        m : Maybe<&1, Ev> <- Chan.recv(Ev, inbox)
        g : Bool <- hub.on(m)
        hub(f, inbox, g)

def main() -> IO(Unit):
  do IO<Unit>:
    +inbox : Chan(Ev) <- Chan.new(Ev, 64)
    f : File <- IO.try(File, File.open("/dev/stdin", "r"))
    r : File & Result<&1, &1, U32 & String, String> <- File.read(f, 65536)
    Unit <- IO.spawn(Unit, reader(1000n, inbox, r))
    Unit <- IO.spawn(Unit, ticker(5n, inbox, 0))
    hub(1000n, inbox, True{})
