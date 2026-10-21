// Goldens for bend/Diff.bend from UniiChat's own text_diff (by Machine.write,
// which answers it): `bun tools/golden/diff.ts UNIICHAT_DIR > diff.jsonl`.
// Each line is {"fn": "diff", "in": [was, now], "out": diff}; small texts,
// so no clip cuts one.
import * as fs from "node:fs";
import * as os from "node:os";
const dir = process.argv[2];
process.env.UNII_DIR ??= "/tmp/mugen-golden-unii";
const { Machine } = await import(dir + "/Machine.ts");
const tmp = fs.mkdtempSync(os.tmpdir() + "/mugen-diff-");
const file = tmp + "/f.txt";

let x = 7;
const rnd = () => {
  x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0;
  return x;
};
const WORDS = ["a", "b", "c", "x", "}", "", "  return 1;", "fn main() {", "é", "🎉 z"];
const text = (n: number) => Array.from({ length: n }, () => WORDS[rnd() % WORDS.length]).join("\n") + (rnd() % 3 === 0 ? "" : "\n");
const edit = (t: string) => {
  const ls = t.split("\n");
  for (let k = rnd() % 4; k >= 0; k--) {
    const at = rnd() % (ls.length + 1);
    const r = rnd() % 3;
    if (r === 0) ls.splice(at, 1);
    else if (r === 1) ls.splice(at, 0, WORDS[rnd() % WORDS.length]);
    else ls[at] = "changed " + at;
  }
  return ls.join("\n");
};
const pairs: Array<[string, string]> = [
  ["", ""], ["", "a\n"], ["a\n", ""], ["a\n", "a\n"], ["a", "a\n"], ["a\n", "a"], ["a\nb\nc\n", "a\nc\n"],
  ["1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n", "1\n2\nX\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\nY\n15\n16\n"],
  ["1\n2\n3\n4\n5\n6\n7\n8\n9\n", "1\n2\nX\n4\n5\n6\n7\n8\nY\n"],
];
for (let k = 0; k < 150; k++) {
  const was = text(rnd() % 25);
  pairs.push([was, k % 10 === 0 ? text(rnd() % 25) : edit(was)]);
}
for (const [was, now] of pairs) {
  fs.rmSync(file, { force: true });
  if (was !== "" || rnd() % 2 === 0) fs.writeFileSync(file, was);
  const out = Machine.write(file, "f.txt", now);
  console.log(JSON.stringify({ fn: "diff", in: [was, now], out: out.text }));
}
fs.rmSync(tmp, { recursive: true });
