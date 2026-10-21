// The stream both sides of the differential test run: `bun gen.ts SEED N
// OUT` writes OUT/stream.jsonl, one step a line, and OUT/stream.idx, each
// line's [offset, length, 0, 0] as four little-endian u32 (the Bend driver
// reads its lines one at a time, never the whole file).
//
// A step: the message to push (kind, text, its own line, more pages to
// follow), the time it comes ("now", ms), how many of the oldest jobs then
// finish ("drain"; 65535: all; 0 through an outage), whether the memory then loads anew
// ("reload"), and what to read back ("zoom": [id, n, at], "date": id).
import * as fs from "node:fs";

const [seed, n, out] = [Number(process.argv[2] ?? 1), Number(process.argv[3] ?? 5000), process.argv[4] ?? "."];

let x = seed >>> 0 || 1;
const rnd = () => {
  x ^= x << 13;
  x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5;
  x >>>= 0;
  return x;
};
const pick = <T>(xs: T[]) => xs[rnd() % xs.length];

// words with what the text functions must get right: UTF-8 widths, astral
// characters (two UTF-16 units, so a page may end inside one), JSON escapes
// (quotes, backslashes, control characters, U+2028, DEL), the white space
// JS's \s holds
const WORDS = [
  "the", "chat", "tree", "node", "merge", "line", "view", "memory", "summary", "zoom", "x", "2026", "a",
  "héllo", "wörld", "naïve", "日本語", "テキスト", "🎉", "ζήτα", "€100", "—", "…", "a\"quote\"", "back\\slash",
  "ctrl\u0001x", "del\u007f", "sep x", "nbsp x", "ideo　x", "bom﻿x", "𝔘𝔫𝔦𝔦", "é",
];
const SEPS = [" ", " ", " ", " ", " ", " ", "  ", "\n", " \n ", "\n\n", "\t", " \t\n\t ", "\r\n", "\u000b"];
const KINDS = ["user", "user", "unii", "unii", "unii", "tool", "tool", "echo", "echo", "work", "note"];

// about `units` UTF-16 units of words and separators
const text = (units: number) => {
  const parts: string[] = [];
  for (let k = 0; k < units; ) {
    const [w, s] = [pick(WORDS), pick(SEPS)];
    parts.push(w, s);
    k += w.length + s.length;
  }
  return parts.join("");
};

const size = () => {
  const r = rnd() % 100;
  return r < 70 ? 5 + (rnd() % 395) : r < 97 ? 400 + (rnd() % 2600) : 3000 + (rnd() % 77000);
};

fs.mkdirSync(out, { recursive: true });
const lines: string[] = [];
let now = Date.UTC(2026, 0, 1, 9, 0, 0);
let out_end = 0;
for (let k = 0; k < n; k++) {
  const gap = rnd() % 50 === 0 ? 86400 + (rnd() % 172800) : 1 + (rnd() % 900);
  now += gap * 1000 + (rnd() % 1000);
  const rec: Record<string, unknown> = { kind: pick(KINDS), text: text(size()) };
  if (rnd() % 33 === 0) {
    rec.line = "line " + k + ": " + text(5 + (rnd() % 560));
  }
  if (rnd() % 33 === 0) {
    rec.more = true;
  }
  rec.now = now;
  // now and then an outage: no job finishes for a while, so the chat's view
  // passes its high with parents not built and a batch stays under way
  if (out_end <= k && rnd() % 1000 < 1) {
    out_end = k + 100 + (rnd() % 400);
  }
  // and one long, early: the chat's view grows to its high mostly of lines
  // whose parents no compaction built, so its batch can't reach half
  if (k === Math.floor(n / 10)) {
    out_end = k + 900;
  }
  rec.drain = k === n - 1 || k === out_end ? 65535 : k < out_end ? 0 : rnd() % 100 < 2 ? 65535 : rnd() % 4;
  rec.reload = k % 997 === 996;
  if (k % 37 === 36) {
    const m = 2 ** (rnd() % 6);
    const id = rnd() % (k + 2);
    rec.zoom = [Math.max(0, id - (rnd() % 5 === 0 ? 1 : id % m)), m, pick([0, 0, 1, 30000, 12345])];
    rec.date = rnd() % (k + 2);
  }
  lines.push(JSON.stringify(rec));
}
const idx = Buffer.alloc(16 * n);
let at = 0;
lines.forEach((line, k) => {
  const len = Buffer.byteLength(line, "utf8");
  idx.writeUInt32LE(at, 16 * k);
  idx.writeUInt32LE(len, 16 * k + 4);
  at += len + 1;
});
fs.writeFileSync(out + "/stream.jsonl", lines.map((line) => line + "\n").join(""));
fs.writeFileSync(out + "/stream.idx", idx);
