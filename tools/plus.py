#!/usr/bin/env python3
# Bend's checker refuses a variable used twice unless it is marked `+`.
# `plus.py FILE` checks FILE over and over, each time marking the variable
# an error names "consumed more than once", where the error points (a
# parameter in a def's signature, or a binder in a pattern or a let), and
# stops at the first error of any other kind, which it prints.
import re, subprocess, sys

BEND = "/nix/store/js8k6x6sxz3176p6qfwb2k743mzmwfsc-bend/bin/bend"
path = sys.argv[1]
for _ in range(200):
    out = subprocess.run([BEND, path, "--check-only"], capture_output=True, text=True)
    text = out.stdout + out.stderr
    m = re.search(r"observed : (\S+) \(consumed more than once\)", text)
    loc = re.search(r"^ *(\d+)>\|(.*)$\n^ *\|( *)\^", text, re.M)
    if not m or not loc:
        print("\n".join(l for l in text.splitlines() if not l.startswith("defs that depend")))
        break
    name, lineno, col = m.group(1), int(loc.group(1)), len(loc.group(3))
    src = open(text and path).read().split("\n")
    line = src[lineno - 1]
    at = col - 1 if col > 0 else 0
    # the binder at the caret, else the first unmarked binder of that name
    hit = re.compile(r"(?<![\w.+])" + re.escape(name) + r"(?![\w.])")
    spans = [x for x in hit.finditer(line)]
    pick = next((x for x in spans if x.start() <= at < x.end()), spans[0] if spans else None)
    if pick is None:
        print("cannot place +", name, "at line", lineno)
        print(text)
        break
    src[lineno - 1] = line[: pick.start()] + "+" + line[pick.start():]
    open(path, "w").write("\n".join(src))
    print(f"+{name} at line {lineno}")
