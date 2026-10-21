# S1: an event carrying a reply channel survives a send through a channel;
# S4: try_recv(c, 0) answers Ready{Some}, Wait{} and Ready{None}.
import Base

type Ev is Data:
  Ask{n: U32, reply: Chan(U32)}
  Stop{}

# What the hub does with one event: Some{()} to go on, None{} to stop.
def hub.on(m: Maybe<&1, Ev>) -> IO(Maybe<&1, Unit>):
  match m:
    case None{}:
      do IO<Maybe<&1, Unit>>:
        IO.print("hub: closed")
        return None{}
    case Some{Stop{}}:
      do IO<Maybe<&1, Unit>>:
        IO.print("hub: stop")
        return None{}
    case Some{Ask{n, reply}}:
      do IO<Maybe<&1, Unit>>:
        Result<&1, &1, U32, Unit> <- Chan.send(U32, reply, (n * 2 : U32))
        return Some{Unit{}}

# The hub's loop: the previous event's verdict is a parameter, so the
# loop matches it (Bend matches parameters, never computed values).
def hub(fuel: Nat, inbox: Chan(Ev), go: Maybe<&1, Unit>) -> IO(Unit):
  match fuel go:
    case 0n _:
      IO.pure(Unit, Unit{})
    case 1n+f None{}:
      IO.pure(Unit, Unit{})
    case 1n+f Some{u}:
      +c = inbox
      do IO<Unit>:
        m : Maybe<&1, Ev> <- Chan.recv(Ev, c)
        g : Maybe<&1, Unit> <- hub.on(m)
        hub(f, c, g)

def show(r: Poll<&1, &1, Maybe<&1, U32>, Unit>) -> String:
  match r:
    case Ready{Some{v}}:
      "ready some " ++ U32.show(v)
    case Ready{None{}}:
      "ready none"
    case Wait{u}:
      "wait"

def main() -> IO(Unit):
  do IO<Unit>:
    +inbox : Chan(Ev) <- Chan.new(Ev, 16)
    Unit <- IO.spawn(Unit, hub(100n, inbox, Some{Unit{}}))
    +r : Chan(U32) <- Chan.new(U32, 1)
    Result<&1, &1, Ev, Unit> <- Chan.send(Ev, inbox, Ask{21, r})
    a : Maybe<&1, U32> <- Chan.recv(U32, r)
    IO.print(Maybe.show(&1, U32, U32.show, a))
    Result<&1, &1, U32, Unit> <- Chan.send(U32, r, 5)
    p : Poll<&1, &1, Maybe<&1, U32>, Unit> <- Chan.try_recv(U32, r, 0)
    IO.print(show(p))
    q : Poll<&1, &1, Maybe<&1, U32>, Unit> <- Chan.try_recv(U32, r, 0)
    IO.print(show(q))
    Unit <- Chan.close(U32, r)
    z : Poll<&1, &1, Maybe<&1, U32>, Unit> <- Chan.try_recv(U32, r, 0)
    IO.print(show(z))
    Result<&1, &1, Ev, Unit> <- Chan.send(Ev, inbox, Stop{})
    IO.pure(Unit, Unit{})
