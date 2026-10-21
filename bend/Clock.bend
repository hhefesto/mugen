
import Base

# Clock: dates as UniiChat writes them. A message's date is
# toISOString() ("2026-10-20T21:40:00.000Z"); a log's day file is named by
# the local date (toLocaleDateString("sv-SE")), and the date tool answers
# local time (toLocaleString("sv-SE"): "2026-10-20 15:40:00"). Times are
# milliseconds since the Unix epoch; a zone's offset is minutes east of UTC
# plus 1440 (Sys.bend mu.tzoff), so it is never negative.
#
# Every def is prefixed `ck.` (a program's defs share one namespace).

def ck.day() -> Nat:
  U32.to_nat(86400000)

def ck.pad.go(n: Nat, s: String) -> String:
  match n:
    case 0n:
      s
    case 1n+k:
      "0" ++ ck.pad.go(k, s)

def ck.pad(+w: Nat, +x: U32) -> String:
  ck.pad.go(Nat.sub(w, String.length(U32.show(x))), U32.show(x))

# days since 1970-01-01 as YYYY-MM-DD (Hinnant's civil_from_days; every
# intermediate is nonnegative, so U32 subtraction is exact)
def ck.civil(+z0: U32) -> String:
  +z = (z0 + 719468 : U32)
  +era = U32.div(z, 146097)
  +doe = (z - era * 146097 : U32)
  +yoe = U32.div(((doe + U32.div(doe, 36524) : U32) - (U32.div(doe, 1460) + U32.div(doe, 146096) : U32) : U32), 365)
  +doy = (doe - ((365 * yoe : U32) + U32.div(yoe, 4) - U32.div(yoe, 100) : U32) : U32)
  +mp = U32.div((5 * doy + 2 : U32), 153)
  +d = ((doy - U32.div((153 * mp + 2 : U32), 5) : U32) + 1 : U32)
  +m = Bool.pick(U32, U32.is_lt(mp, 10), (mp + 3 : U32), (mp - 9 : U32))
  +y = ((yoe + era * 400 : U32) + Bool.pick(U32, U32.is_le(m, 2), 1, 0) : U32)
  ck.pad(4n, y) ++ "-" ++ ck.pad(2n, m) ++ "-" ++ ck.pad(2n, d)

def ck.millis(ms: Bool, +t: Nat) -> String:
  match ms:
    case True{}:
      "." ++ ck.pad(3n, U32.from_nat(Nat.mod(t, 1000n)))
    case False{}:
      ""

# the time of day: HH:MM:SS, then (when ms) .mmm
def ck.clock(+t: Nat, ms: Bool) -> String:
  +s = U32.from_nat(Nat.div(Nat.mod(t, ck.day()), 1000n))
  ck.pad(2n, U32.div(s, 3600)) ++ ":" ++ ck.pad(2n, U32.div(U32.mod(s, 3600), 60)) ++ ":" ++ ck.pad(2n, U32.mod(s, 60)) ++ ck.millis(ms, t)

# the day number of a time (UTC)
def ck.days(+t: Nat) -> U32:
  U32.from_nat(Nat.div(t, ck.day()))

# Date.toISOString
def ck.iso(+t: Nat) -> String:
  ck.civil(ck.days(t)) ++ "T" ++ ck.clock(t, True{}) ++ "Z"

# a time moved to its zone's wall clock
def ck.local(+t: Nat, +tz: U32) -> Nat:
  Bool.pick(Nat, U32.is_ge(tz, 1440), Nat.add(t, Nat.mul(U32.to_nat((tz - 1440 : U32)), 60000n)),
    Nat.sub(t, Nat.mul(U32.to_nat((1440 - tz : U32)), 60000n)))

# the local day of a time: its file's day number (Memory.log)
def ck.local_day(+t: Nat, +tz: U32) -> U32:
  ck.days(ck.local(t, tz))

# toLocaleString("sv-SE")
def ck.show(+t: Nat, +tz: U32) -> String:
  +l = ck.local(t, tz)
  ck.civil(ck.days(l)) ++ " " ++ ck.clock(l, False{})

# Reading an ISO date back: YYYY-MM-DDTHH:MM:SS.mmmZ to milliseconds.

def ck.digits(n: Nat, s: String, +acc: Nat) -> Nat:
  match n s:
    case 0n _:
      acc
    case 1n+k SCon{Chr{+c}, t}:
      ck.digits(k, t, Nat.add(Nat.mul(acc, 10n), U32.to_nat((c - 48 : U32))))
    case 1n+k SNil{}:
      acc

def ck.field(+s: String, +at: Nat, +n: Nat) -> Nat:
  ck.digits(n, String.drop(s, at), 0n)

# days from civil (Hinnant's days_from_civil)
def ck.days_of(+y0: U32, +m: U32, +d: U32) -> U32:
  +y = Bool.pick(U32, U32.is_le(m, 2), (y0 - 1 : U32), y0)
  +era = U32.div(y, 400)
  +yoe = (y - era * 400 : U32)
  +mp = Bool.pick(U32, U32.is_gt(m, 2), (m - 3 : U32), (m + 9 : U32))
  +doy = ((U32.div((153 * mp + 2 : U32), 5) + d : U32) - 1 : U32)
  +doe = ((yoe * 365 + U32.div(yoe, 4) : U32) - U32.div(yoe, 100) + doy : U32)
  ((era * 146097 + doe : U32) - 719468 : U32)

def ck.parse(+s: String) -> Nat:
  +days = ck.days_of(U32.from_nat(ck.field(s, 0n, 4n)), U32.from_nat(ck.field(s, 5n, 2n)), U32.from_nat(ck.field(s, 8n, 2n)))
  +secs = Nat.add(Nat.add(Nat.mul(ck.field(s, 11n, 2n), 3600n), Nat.mul(ck.field(s, 14n, 2n), 60n)), ck.field(s, 17n, 2n))
  Nat.add(Nat.mul(U32.to_nat(days), ck.day()), Nat.add(Nat.mul(secs, 1000n), ck.field(s, 20n, 3n)))

# a day file's day number from its name (YYYY-MM-DD...)
def ck.day_of(+name: String) -> U32:
  ck.days_of(U32.from_nat(ck.field(name, 0n, 4n)), U32.from_nat(ck.field(name, 5n, 2n)), U32.from_nat(ck.field(name, 8n, 2n)))
