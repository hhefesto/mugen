#!/usr/bin/env python3
# Bend binds a def only after it is written. `order.py FILE` lists the calls
# in FILE to defs written below them; `order.py --fix FILE` moves each such
# def (with the comment above it) up, just before its first caller.
import re, sys

HEAD = re.compile(r'^(?:@unsafe )?def ([A-Za-z0-9_.]+)\??\(|^(type|law|import) ', re.M)


def chunks(src):
    """Top-level blocks, each with the comment lines right above it."""
    lines = src.split("\n")
    starts = [k for k, l in enumerate(lines) if HEAD.match(l)]
    out, prev = [], 0
    for n, s in enumerate(starts):
        c = s
        while c > prev and lines[c - 1].startswith("#"):
            c -= 1
        if n == 0:
            out.append(("pre", "\n".join(lines[:c])))
        else:
            out[-1] = (out[-1][0], "\n".join(lines[prev:c]))
        prev = c
        m = HEAD.match(lines[s])
        out.append((m.group(1) or "", None))
    if out:
        out[-1] = (out[-1][0], "\n".join(lines[prev:]))
    return out


def calls(text, names, self):
    found = []
    for c in re.finditer(r'(?<![A-Za-z0-9_.])([A-Za-z_][A-Za-z0-9_.]*)\(', text):
        n = c.group(1)
        if n in names and n != self and n not in found:
            found.append(n)
    return found


def main():
    fix = sys.argv[1] == "--fix"
    path = sys.argv[-1]
    cs = chunks(open(path).read())
    names = {name for name, _ in cs if name and name != "pre"}
    index = {name: k for k, (name, _) in enumerate(cs) if name and name != "pre"}
    if not fix:
        for k, (name, text) in enumerate(cs):
            if name and name != "pre":
                for d in calls(text.split("\n", 1)[1] if "\n" in text else "", names, name):
                    if index[d] > k:
                        print(f"{name} calls {d} (below it)")
        return
    done, out = set(), []

    def emit(k, stack=()):
        name, text = cs[k]
        if k in done or k in stack:
            return
        if name and name != "pre":
            for d in calls(text.split("\n", 1)[1] if "\n" in text else "", names, name):
                if index[d] > k:
                    emit(index[d], stack + (k,))
        done.add(k)
        out.append(text)

    for k in range(len(cs)):
        emit(k)
    open(path, "w").write("\n".join(out))


main()
