// Goldens for bend/Tools.bend from UniiChat's own Machine.run: `bun
// tools/golden/tools.ts UNIICHAT_DIR > tools.jsonl`. A sequence of jobs on
// one work dir (each sees what those before left), each line {"job", "out"},
// a shell's time and the work dir masked (as "T" and "<work>").
import * as fs from "node:fs";
import * as os from "node:os";
const dir = process.argv[2];
process.env.UNII_DIR ??= "/tmp/mugen-golden-unii";
const { Machine } = await import(dir + "/Machine.ts");
const work = fs.realpathSync(fs.mkdtempSync(os.tmpdir() + "/mugen-tools-"));
const big = (n: number) => Array.from({ length: n }, (_, k) => "line " + k + " " + "é🎉x".repeat(k % 7)).join("\n");
const jobs: Array<[string, object]> = [
  ["write", { path: "a.txt", content: "one\ntwo\nthree\n" }],
  ["write", { path: "a.txt", content: "one\n2\nthree\nfour" }],
  ["write", { path: "a.txt", content: "one\n2\nthree\nfour" }],
  ["write", { path: "sub/dir/b.txt", content: "" }],
  ["read", { path: "a.txt" }],
  ["read", { path: "a.txt", offset: 2, limit: 2 }],
  ["read", { path: "a.txt", offset: 9 }],
  ["read", { path: "nope.txt" }],
  ["write", { path: "big.txt", content: big(4000) }],
  ["read", { path: "big.txt" }],
  ["read", { path: "big.txt", offset: 1500 }],
  ["read", { path: "big.txt", offset: 1, at: 5 }],
  ["write", { path: "long.txt", content: "z".repeat(70000) + "\nend\n" }],
  ["read", { path: "long.txt" }],
  ["read", { path: "long.txt", offset: 1, at: 30000 }],
  ["edit", { edits: [{ path: "a.txt", old: "2", new: "two" }] }],
  ["edit", { edits: [{ path: "a.txt", old: "o", new: "0" }] }],
  ["edit", { edits: [{ path: "a.txt", old: "o", new: "0", all: true }] }],
  ["edit", { edits: [{ path: "a.txt", old: "missing", new: "x" }] }],
  ["edit", { edits: [{ path: "none.txt", old: "a", new: "b" }] }],
  ["edit", { edits: [] }],
  ["edit", { edits: [{ path: "a.txt", old: "three", new: "3" }, { path: "a.txt", old: "3", new: "III" }, { path: "sub/dir/b.txt", old: "", new: "x" }] }],
  ["edit", { edits: [{ path: "a.txt", old: "f0ur", new: "4" }, { path: "big.txt", old: "line 2000 ", new: "LINE 2000 " }] }],
  ["shell", { command: "echo hi; echo err >&2; exit 3" }],
  ["shell", { command: "printf 'no newline'" }],
  ["shell", { command: "true" }],
  ["shell", { command: "cat a.txt; pwd" }],
  ["shell", { command: "seq 1 20000" }],
  ["shell", { command: "printf '\\000\\001' > bin.dat; ls" }],
  ["read", { path: "bin.dat" }],
  ["shell", { command: "ls # a comment" }],
];
for (const [name, input] of jobs) {
  const out = await Machine.run({ name, input, cwd: "main" }, work, new AbortController().signal);
  const text = out.text.replaceAll(work, "<work>").replace(/ in \d+\.\d s\)$/, " in T s)");
  console.log(JSON.stringify({ job: { name, input }, out: { text, fail: out.fail } }));
}
fs.rmSync(work, { recursive: true });
