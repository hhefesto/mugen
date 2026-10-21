// The TypeScript side of the differential test: UniiChat's own Memory.ts
// runs steps [FROM, TO) of a stream (gen.ts) on DIR, printing a trace the
// Bend side (bend/tests/MemDrive.bend) prints too, line for line:
//
//   bun harness.ts UNIICHAT_DIR DIR STREAM_DIR FROM TO > trace
//
// The compactor is a fake whose answers both sides compute alike (`answer`),
// its jobs finished oldest first as each step says. The clock is the
// stream's. Run with TZ=UTC (a day file is named by the local date).
//
//   R                        the memory loaded (at the start and each reload)
//   P k                      step k's message pushed
//   J l i blocks bytes       a job started: node (l,i), a hash of its call's
//                            blocks with their marks, its source's bytes
//   D l i                    node (l,i)'s job finished
//   V ...                    the state after each of those: count open, the
//                            chat's view (size batch lines hash), the
//                            compactions' alike, the nodes kept, the jobs
//                            running, the first message not built
//   W whole turn             Memory.whole(0), Memory.turn
//   Z id n at hash           a zoom's answer, hashed
//   T id date                Memory.date
import * as fs from "node:fs";

const [uniichat, dir, streams, from, to] = process.argv.slice(2);
process.env.UNII_DIR ??= dir + "/.unii";

// the clock: `new Date()` is the step's time
const RealDate = Date;
let NOW = 0;
class FakeDate extends RealDate {
  constructor(...args: any[]) {
    if (args.length === 0) {
      super(NOW);
    } else {
      super(...(args as [any]));
    }
  }
  static now() {
    return NOW;
  }
}
(globalThis as any).Date = FakeDate;

const { Memory } = await import(uniichat + "/Memory.ts");
const { Disk } = await import(uniichat + "/Disk.ts");
Disk.wrote = () => Promise.resolve();

// FNV-1a over code points (or any u32 units)
const BASIS = 2166136261;
const fu = (h: number, x: number) => Math.imul((h ^ x) >>> 0, 16777619) >>> 0;
const fs_ = (h: number, s: string) => {
  for (const ch of s) {
    h = fu(h, ch.codePointAt(0)!);
  }
  return h;
};
const hparts = (parts: Array<{ l: number; i: number }>) => parts.reduce((h, p) => fu(fu(h, p.l), p.i), BASIS);
const hblocks = (blocks: Array<{ text: string; mark: boolean }>) => blocks.reduce((h, b) => fs_(fu(h, b.mark ? 77 : 85), b.text), BASIS);

// the fake compactor's answer to try `t` of node (l,i), `nh` the hash of the
// note a retry adds (0 on the first): by a hash of (l,i), white space only
// (no line: the source is clipped), always too long (the shortest is kept),
// too long twice, or the source flattened and cut to 300 bytes
const answer = (l: number, i: number, text: string, t: number, nh: number) => {
  const h = fu(fu(BASIS, l), i);
  const tag = "L" + l + "/" + i + " t" + t + " n" + nh;
  if (h % 13 === 0) {
    return " \n\t ";
  }
  if (h % 17 === 0) {
    return "  " + tag + " " + "ζ".repeat(300 - 10 * t) + "\n";
  }
  if (h % 7 === 0 && t <= 2) {
    return tag + " " + "ζ".repeat(280);
  }
  return "\n " + cut(tag + ": " + Memory.flat(text), 300) + " ";
};
const cut = (s: string, n: number) => Buffer.from(s, "utf8").subarray(0, n).toString("utf8").replace(/�+$/, "");

const lines: string[] = [];
const say = (line: string) => lines.push(line);

type Job = { l: number; i: number; text: string; resolve: (end: object) => void };
let fifo: Job[] = [];
let current: { l: number; i: number; t: number } | null = null;

// a first try waits in the queue; a retry (the job being finished) answers
// at once
Memory.ask = (_mem: unknown, l: number, i: number, text: string, blocks: Array<{ text: string; mark: boolean }>) => {
  if (current !== null && current.l === l && current.i === i) {
    current.t += 1;
    const nh = fs_(BASIS, blocks[blocks.length - 1].text) % 1000;
    return { done: Promise.resolve({ ok: true, text: answer(l, i, text, current.t, nh), left: [] }), stop() {} };
  }
  say("J " + l + " " + i + " " + hblocks(blocks) + " " + Memory.bytes(text));
  let resolve: (end: object) => void = () => {};
  const done = new Promise<object>((ok) => (resolve = ok));
  fifo.push({ l, i, text, resolve });
  return { done, stop() {} };
};

const state = (mem: any) => {
  const [v, s] = [mem.view, mem.seen];
  const view = (w: any) => w.size + " " + (w.batch ? 1 : 0) + " " + w.parts.length + " " + hparts(w.parts);
  say("V " + mem.count + " " + mem.open + " " + view(v) + " " + view(s) + " " + mem.nodes.size + " " + mem.busy.size + " " + Memory.first(mem));
};

const tick = () => new Promise((ok) => setTimeout(ok, 0));

const share = () => ({});
let mem = Memory.load(dir, share);
say("R");
state(mem);

const idx = fs.readFileSync(streams + "/stream.idx");
const fd = fs.openSync(streams + "/stream.jsonl", "r");
for (let k = Number(from); k < Number(to); k++) {
  const [at, len] = [idx.readUInt32LE(16 * k), idx.readUInt32LE(16 * k + 4)];
  const buf = Buffer.alloc(len);
  fs.readSync(fd, buf, 0, len, at);
  const rec = JSON.parse(buf.toString("utf8"));
  NOW = rec.now;
  const msg: Record<string, unknown> = { kind: rec.kind, text: rec.text };
  if (rec.line !== undefined) {
    msg.line = rec.line;
  }
  if (rec.more === true) {
    msg.more = true;
  }
  say("P " + k);
  Memory.push(mem, [msg]);
  state(mem);
  for (let d = 0; d < rec.drain && fifo.length > 0; d++) {
    const job = fifo.shift()!;
    say("D " + job.l + " " + job.i);
    current = { l: job.l, i: job.i, t: 1 };
    job.resolve({ ok: true, text: answer(job.l, job.i, job.text, 1, 0), left: [] });
    await tick();
    current = null;
    state(mem);
  }
  if (rec.zoom !== undefined) {
    const [id, n, at] = rec.zoom;
    say("W " + Memory.whole(mem, 0) + " " + Memory.turn(mem));
    // a page from inside a surrogate pair starts with half of it, which a
    // Bend string (code points) holds as U+FFFD, as toWellFormed does
    say("Z " + id + " " + n + " " + at + " " + fs_(BASIS, Memory.zoom(mem, id, n, at).toWellFormed()));
    say("T " + rec.date + " " + Memory.date(mem, rec.date));
  }
  if (rec.reload) {
    mem = Memory.load(dir, share);
    fifo = [];
    say("R");
    state(mem);
  }
  if (lines.length > 4096) {
    process.stdout.write(lines.splice(0).map((line) => line + "\n").join(""));
  }
}
process.stdout.write(lines.map((line) => line + "\n").join(""));
