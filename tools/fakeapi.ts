#!/usr/bin/env bun
// A stand-in for curl in mugen's tests (MUGEN_CURL=tools/fakeapi.ts):
// it reads a request's body on stdin and answers as curl does with the -w
// mugen passes (Api.bend ap.args): the response's body, a newline, then
// "status retry-after x-should-retry".
//
// MUGEN_FAKE: a JSON file of answers, taken in order (the last repeats),
// for every request (MUGEN_FAKE_CHAT: only a turn's or an agent's, the
// compactions answered as below; MUGEN_FAKE_AGENT: a subagent's;
// MUGEN_FAKE_GOAL: a goal check's, "yes" unless scripted),
// how many were taken kept beside it (FILE.n). Each answer: {"code": 200,
// "body": {...} or "text", "after": "", "should": "", "exit": 0, "stderr": "",
// "sleep": seconds before it}
// (a nonzero exit is curl failing: no response). Unset, a request is answered
// as a compactor would (its input flattened and cut) or, with tools, a chat.
//
// MUGEN_FAKE_LOG: a directory each request is written to, {argv, body}.
import * as fs from "node:fs";

const body = await Bun.stdin.text();
const log = process.env.MUGEN_FAKE_LOG;
if (log) {
  fs.mkdirSync(log, { recursive: true });
  const req = { argv: process.argv.slice(2), body: JSON.parse(body) };
  fs.writeFileSync(log + "/" + String(Date.now()).padStart(15, "0") + "-" + process.pid + ".json", JSON.stringify(req));
}

const message = (req: any, content: object[], stop = "end_turn") => ({
  id: "msg_fake",
  type: "message",
  role: "assistant",
  model: req.model,
  content,
  stop_reason: stop,
  stop_sequence: null,
  usage: { input_tokens: 1, output_tokens: 1 },
});

const cut = (s: string, n: number) => Buffer.from(s, "utf8").subarray(0, n).toString("utf8").replace(/�+$/, "");

// a compactor's line: its input, flattened, cut to 300 bytes
const answer = (req: any) => {
  const last = req.messages[req.messages.length - 1].content;
  const text = last.filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
  const input = /<input>\n([\s\S]*)\n<\/input>/.exec(text)?.[1] ?? text;
  const reply = req.tools === undefined ? cut("S: " + input.replace(/\s*\n\s*/g, " "), 300) : "fake reply";
  return message(req, [{ type: "thinking", thinking: "fake thought", signature: "fake-signature" }, { type: "text", text: reply }]);
};

// which script answers: a goal check's (MUGEN_FAKE_GOAL), a call with
// tools' (a turn or an agent: MUGEN_FAKE_CHAT), else any (MUGEN_FAKE)
const req = JSON.parse(body);
const system = String(req.system?.[0]?.text ?? "");
const goal = system.startsWith("You check a goal.");
const agent = system.startsWith("You are a subagent of Unii");
const chat = req.tools !== undefined;
let out: any = { code: 200, body: null };
const env = process.env;
const script = goal ? env.MUGEN_FAKE_GOAL : agent ? env.MUGEN_FAKE_AGENT ?? env.MUGEN_FAKE_CHAT : chat ? env.MUGEN_FAKE_CHAT ?? env.MUGEN_FAKE : env.MUGEN_FAKE_CHAT ? undefined : env.MUGEN_FAKE;
if (goal && !script) {
  out = { code: 200, body: message(req, [{ type: "text", text: "yes" }]) };
}
if (script) {
  const list = JSON.parse(fs.readFileSync(script, "utf8"));
  const count = script + ".n";
  const n = fs.existsSync(count) ? Number(fs.readFileSync(count, "utf8")) : 0;
  fs.writeFileSync(count, String(n + 1));
  out = list[Math.min(n, list.length - 1)];
}
// a compactor slow by MUGEN_FAKE_COMPACT_SLEEP seconds
if (!chat && !goal && !agent && !script && env.MUGEN_FAKE_COMPACT_SLEEP) {
  out.sleep = Number(env.MUGEN_FAKE_COMPACT_SLEEP);
}
if (out.sleep) {
  await Bun.sleep(out.sleep * 1000);
}
if ((out.exit ?? 0) !== 0) {
  process.stderr.write(out.stderr ?? "curl: (7) Failed to connect to api.anthropic.com port 443 after 0 ms: Could not connect to server\n");
  process.stdout.write("\n000  ");
  process.exit(out.exit);
}
// @LASTAGENT@ in a scripted answer: the last agent the request says started
const started = [...body.matchAll(/Started ([A-Z][A-Za-z]+)[.,]/g)].map((m) => m[1]);
const fill = (x: any) => (started.length === 0 ? x : JSON.parse(JSON.stringify(x).replaceAll("@LASTAGENT@", started[started.length - 1])));
const reply = out.body ? fill(out.body) : answer(req);
process.stdout.write((typeof reply === "string" ? reply : JSON.stringify(reply)) + "\n" + (out.code ?? 200) + " " + (out.after ?? "") + " " + (out.should ?? ""));
