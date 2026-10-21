// Random views merged by UniiChat's own Memory.merge, as cases for
// bend/tests/MergeCheck.bend: `bun merge.ts UNIICHAT_DIR SEED N > merge.jsonl`.
// The differential test (run.sh) merges only views a chat grows; these are
// any shape: lines of any level, some not built, parents built or not, so
// pairs are offered, refused and found stale in every order.
//
// Each line: {"parts": [[l, i]...], "nodes": [[slot, bytes]...], "high": n,
// "out": {"parts", "size", "gone"}}, `gone` sorted (a set to the caller).
const [uniichat, seed, n] = [process.argv[2], Number(process.argv[3] ?? 1), Number(process.argv[4] ?? 300)];
process.env.UNII_DIR ??= "/tmp/mugen-merge-unii";
const { Memory } = await import(uniichat + "/Memory.ts");

let x = seed >>> 0 || 1;
const rnd = () => {
  x ^= x << 13;
  x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5;
  x >>>= 0;
  return x;
};

const out: string[] = [];
for (let c = 0; c < n; c++) {
  const t = 1 + (rnd() % (c < 50 ? 40 : 2500));
  const parts: Array<{ l: number; i: number }> = [];
  for (let p = 0; p < t; ) {
    let top = 0;
    while (top < 10 && p % 2 ** (top + 1) === 0 && p + 2 ** (top + 1) <= t) {
      top += 1;
    }
    const l = rnd() % 3 === 0 ? top : rnd() % (top + 1);
    parts.push({ l, i: p / 2 ** l });
    p += 2 ** l;
  }
  const nodes = new Map<number, string>();
  const built = rnd() % 100;
  const up = rnd() % 100;
  for (const { l, i } of parts) {
    if (rnd() % 100 < built) {
      nodes.set(Memory.slot(l, i), "x".repeat(1 + (rnd() % 600)));
    }
    for (let k = 1; k <= 12; k++) {
      const s = Memory.slot(l + k, i >> k);
      if (!nodes.has(s) && rnd() % 100 < up) {
        nodes.set(s, "y".repeat(1 + (rnd() % (rnd() % 4 === 0 ? 40 : 600))));
      }
    }
  }
  const mem = { nodes };
  const size = parts.reduce((s, part) => s + Memory.size(mem, part), 0);
  const high = 2 * Math.floor(size * (0.2 + (rnd() % 150) / 100));
  const view = { parts, size, batch: false, high };
  const res = Memory.merge(mem, view);
  const pairs = (ps: Array<{ l: number; i: number }>) => ps.map((p) => [p.l, p.i]);
  const gone = pairs(res.gone).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  out.push(JSON.stringify({ parts: pairs(parts), nodes: [...nodes].map(([s, t]) => [s, t.length]), high, out: { parts: pairs(res.parts), size: res.size, gone } }));
}
process.stdout.write(out.join("\n") + "\n");
