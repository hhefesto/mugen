#!/usr/bin/env bun
// A stand-in for Claude Code's CLI in mugen's tests (MUGEN_CLAUDE): it takes
// `claude -p --input-format stream-json --output-format stream-json ...` as
// mugen runs it (Code.bend) and plays tools/fakeapi.ts's scripts as Claude
// Code would run them. Each step's request is the conversation so far, the
// API path's body (logged to MUGEN_FAKE_LOG, as fakeapi.ts logs one, with
// "wire": "claude"); a retry status is asked again, told as an api_retry
// event; a tool call runs on mugen's MCP server (--mcp-config); the user
// messages that come meanwhile follow the next tool results, each said back
// by its id as it is taken; a turn ends with a result event, and a message
// left waiting starts the next. Scripts, defaults and @LASTAGENT@ are
// fakeapi.ts's.
import * as fs from "node:fs";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const argv = process.argv.slice(2);
if (argv.includes("--version")) {
  console.log("2.1.304 (Claude Code, fake)");
  process.exit(0);
}
// `auth status` signed in, unless MUGEN_FAKE_SIGNED_OUT; `auth login` says so
if (argv[0] === "auth") {
  const out = !!process.env.MUGEN_FAKE_SIGNED_OUT;
  console.log(argv[1] === "status" ? JSON.stringify({ loggedIn: !out, authMethod: out ? "none" : "claude.ai" }) : "fake login: " + argv.slice(1).join(" "));
  process.exit(argv[1] === "status" && out ? 1 : 0);
}
const flag = (name: string) => {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
};
const system = fs.readFileSync(flag("--system-prompt-file")!, "utf8");
const model = flag("--model");
const effort = flag("--effort");
const conf = flag("--mcp-config");
const env = process.env;
const sid = flag("--session-id") ?? crypto.randomUUID();
const out = (o: object) => process.stdout.write(JSON.stringify({ ...o, session_id: sid }) + "\n");

// which script answers (fakeapi.ts): a goal check's, a call with tools' (a
// turn's or an agent's), else any
const goal = system.startsWith("You check a goal.");
const agent = system.startsWith("You are a subagent of Unii");
const chat = conf !== undefined;
const script = goal ? env.MUGEN_FAKE_GOAL : agent ? env.MUGEN_FAKE_AGENT ?? env.MUGEN_FAKE_CHAT : chat ? env.MUGEN_FAKE_CHAT ?? env.MUGEN_FAKE : env.MUGEN_FAKE_CHAT ? undefined : env.MUGEN_FAKE;

// stdin: the user's messages, one a line, as they come
const queue: any[] = [];
let eof = false;
let wake: (() => void) | null = null;
const lines = createInterface({ input: process.stdin });
lines.on("line", (l) => {
  if (l.trim() !== "") {
    queue.push(JSON.parse(l));
    wake?.();
  }
});
lines.on("close", () => {
  eof = true;
  wake?.();
});
const next = async () => {
  while (queue.length === 0 && !eof) {
    await new Promise<void>((r) => (wake = r));
  }
  wake = null;
  return queue.shift();
};

// mugen's MCP server, as Claude Code starts it
let tools: any[] = [];
let rpc = async (method: string, params: object): Promise<any> => ({});
if (conf !== undefined) {
  const srv = JSON.parse(conf).mcpServers.mugen;
  const p = spawn(srv.command, srv.args, { stdio: ["pipe", "pipe", "inherit"] });
  const waiting = new Map<number, (m: any) => void>();
  createInterface({ input: p.stdout! }).on("line", (l) => {
    const m = JSON.parse(l);
    waiting.get(m.id)?.(m);
    waiting.delete(m.id);
  });
  let id = 0;
  rpc = (method, params) =>
    new Promise((res) => {
      id += 1;
      waiting.set(id, res);
      p.stdin!.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
  await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "fakeclaude", version: "1" } });
  p.stdin!.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  const listed = await rpc("tools/list", {});
  tools = listed.result.tools.map((t: any) => ({ name: t.name, description: t.description, input_schema: t.inputSchema }));
}
out({ type: "system", subtype: "init", model, tools: tools.map((t) => "mcp__mugen__" + t.name), mcp_servers: chat ? [{ name: "mugen", status: "connected" }] : [] });
// the plan's limits, as Claude Code reports them before a turn
out({ type: "rate_limit_event", rate_limit_info: { status: "allowed", resetsAt: 1792621200, rateLimitType: "five_hour", unifiedWindows: { five_hour: { utilization: 0.25, resetsAt: 1792621200 }, seven_day: { utilization: 0.11, resetsAt: 1793088000 } } } });

const usage = { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
const message = (content: object[], stop = "end_turn") => ({ id: "msg_fake", type: "message", role: "assistant", model, content, stop_reason: stop, usage });
const cut = (s: string, n: number) => Buffer.from(s, "utf8").subarray(0, n).toString("utf8").replace(/�+$/, "");

// the conversation, as the API path sends it
const messages: any[] = [];
let k = 0;
const log = (body: object) => {
  const dir = env.MUGEN_FAKE_LOG;
  if (dir) {
    fs.mkdirSync(dir, { recursive: true });
    k += 1;
    const name = String(Date.now()).padStart(15, "0") + "-" + process.pid + "-" + String(k).padStart(4, "0");
    fs.writeFileSync(dir + "/" + name + ".json", JSON.stringify({ argv, wire: "claude", body }));
  }
};

// a compactor's line, or a chat's reply (fakeapi.ts answer)
const answer = (body: any) => {
  const last = body.messages[body.messages.length - 1].content;
  const text = last.filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
  const input = /<input>\n([\s\S]*)\n<\/input>/.exec(text)?.[1] ?? text;
  const reply = chat ? "fake reply" : cut("S: " + input.replace(/\s*\n\s*/g, " "), 300);
  return message([{ type: "thinking", thinking: "fake thought", signature: "fake-signature" }, { type: "text", text: reply }]);
};

// one request's answer: the script's next (counted beside it), else the default
const ask = async (body: any) => {
  log(body);
  let a: any = { code: 200, body: null };
  if (goal && !script) {
    a = { code: 200, body: message([{ type: "text", text: "yes" }]) };
  }
  if (script) {
    const list = JSON.parse(fs.readFileSync(script, "utf8"));
    const count = script + ".n";
    const n = fs.existsSync(count) ? Number(fs.readFileSync(count, "utf8")) : 0;
    fs.writeFileSync(count, String(n + 1));
    a = list[Math.min(n, list.length - 1)];
  }
  if (!chat && !goal && !agent && !script && env.MUGEN_FAKE_COMPACT_SLEEP) {
    a.sleep = Number(env.MUGEN_FAKE_COMPACT_SLEEP);
  }
  if (a.sleep) {
    await Bun.sleep(a.sleep * 1000);
  }
  const started = [...JSON.stringify(body).matchAll(/Started ([A-Z][A-Za-z]+)[.,]/g)].map((m) => m[1]);
  const fill = (x: any) => (started.length === 0 ? x : JSON.parse(JSON.stringify(x).replaceAll("@LASTAGENT@", started[started.length - 1])));
  return { ...a, body: a.body ? fill(a.body) : answer(body) };
};

const passing = (code: number) => code === 408 || code === 409 || code === 429 || code >= 500;

// the user messages waiting, said back as taken
const take = () => {
  const blocks: any[] = [];
  while (queue.length > 0) {
    const m = queue.shift();
    out({ type: "user", message: m.message, uuid: m.uuid, isReplay: true });
    blocks.push(...m.message.content);
  }
  return blocks;
};

// a turn: steps till one ends it, its result last
const turn = async () => {
  let tries = 0;
  let replies = "";
  for (;;) {
    const body = { model, max_tokens: 128000, system: [{ type: "text", text: system }], output_config: { effort }, ...(chat ? { tools } : {}), messages: structuredClone(messages) };
    const a = await ask(body);
    const code = (a.exit ?? 0) !== 0 ? 0 : a.code ?? 200;
    if (code !== 200 && (code === 0 || passing(code)) && tries < 10) {
      tries += 1;
      const wait = Number(a.after || 0) > 0 ? Number(a.after) : 2 ** tries;
      out({ type: "system", subtype: "api_retry", attempt: tries, max_retries: 10, retry_delay_ms: wait * 1000, error_status: code || null });
      continue;
    }
    if (code !== 200) {
      out({ type: "result", subtype: "error_during_execution", is_error: true, api_error_status: code || null, result: a.body?.error?.message ?? "API error", stop_reason: null, usage });
      return;
    }
    const m = a.body;
    for (const b of m.content) {
      const shown = b.type === "tool_use" ? { ...b, name: "mcp__mugen__" + b.name } : b;
      out({ type: "assistant", message: { id: m.id, type: "message", role: "assistant", model, content: [shown], stop_reason: null, usage } });
    }
    messages.push({ role: "assistant", content: m.content });
    replies = m.content.filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
    if (m.stop_reason === "pause_turn") {
      continue;
    }
    const uses = m.content.filter((b: any) => b.type === "tool_use");
    if (m.stop_reason !== "tool_use" || uses.length === 0) {
      out({ type: "result", subtype: "success", is_error: false, result: replies, stop_reason: m.stop_reason, num_turns: 1, usage });
      return;
    }
    const results: any[] = [];
    for (const u of uses) {
      const r = await rpc("tools/call", { name: u.name, arguments: u.input });
      const text = (r.result?.content ?? []).map((c: any) => c.text).join("");
      results.push({ type: "tool_result", tool_use_id: u.id, content: text === "" ? [] : [{ type: "text", text }], is_error: r.result?.isError === true });
    }
    out({ type: "user", message: { role: "user", content: results }, uuid: crypto.randomUUID() });
    messages.push({ role: "user", content: [...results, ...take()] });
  }
};

// each message a turn of its own; those that come during one follow its
// next tool results
for (let m = await next(); m !== undefined; m = await next()) {
  out({ type: "user", message: m.message, uuid: m.uuid, isReplay: true });
  messages.push({ role: "user", content: m.message.content });
  await turn();
}
process.exit(0);
