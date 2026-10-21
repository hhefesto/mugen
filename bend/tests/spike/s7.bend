# S7: JSON on big inputs: parse a file, write it back, time both.
import Base
import ../../Sys.bend as S
import ../../Json.bend as J

def len(m: Maybe<&2, J.Json>) -> Nat:
  match m:
    case Some{j}:
      String.length(J.js.write(j))
    case None{}:
      0n

def main() -> IO(Unit):
  do IO<Unit>:
    argv : List<String> <- IO.args()
    path : String = Maybe.default(&1, String, List.get(&1, String, argv, 1n), "big.json")
    text : String <- S.mu.must(String, "read", S.mu.read_file(path))
    t0 : Nat <- IO.now()
    +n : Nat = len(J.js.read(text))
    t1 : Nat <- IO.now()
    IO.print("S7: parse + write " ++ Nat.show(n) ++ " chars in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
