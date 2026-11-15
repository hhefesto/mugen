#!/usr/bin/env bun
// A stand-in for Claude Code's CLI in mugen's tests (MUGEN_CLAUDE): it takes
// `claude -p --input-format stream-json --output-format stream-json ...` as
// mugen runs it (Code.bend) and plays tools/fakeapi.ts's scripts as Claude
// Code would run them. Each step's request is the conversation so far, the
// API path's body (logged to MUGEN_FAKE_LOG, as fakeapi.ts logs one, with
// "wire": "claude"); a retry status is asked again, told as an api_retry
// event; a tool call runs on mugen's MCP server (--mcp-config); the user
// messages that come meanwhile follow the next tool results, each said back
// by its id as it is taken; a turn ends with a result event (the ids of the
// messages it took, user_message_uuids), and a message left waiting starts
// the next. Scripts, defaults and @LASTAGENT@ are fakeapi.ts's.
//
// As Claude Code 2.1.319 does, a message whose last text block starts with
// "/" and one of its own commands' names (/goal, /model, ...) is that
// command, --disable-slash-commands or not: it never follows tool results
// (it waits for the turn's end), and its turn is Claude Code's own answer,
// "/goal isn't available in this environment." (an output with
// local_command_source), and a result naming it, the message never said
// back. With MUGEN_FAKE_TRIM, a text's leading spaces don't count (a Claude
// Code that would see a command where mugen's escape put a space). With
// MUGEN_FAKE_DROP, a message past the call's first that has that text is
// lost: never taken, never answered (a Claude Code that takes no message,
// for mugen's wait on one).
import * as fs from "node:fs";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const argv = process.argv.slice(2);
if (argv.includes("--version")) {
  console.log("2.1.304 (Claude Code, fake)");
  process.exit(0);
}
// `auth status` signed in, unless MUGEN_FAKE_SIGNED_OUT; `auth login` and
// `auth logout` say so. With MUGEN_FAKE_LOGIN (a code), `auth login` plays
// the real one's way without a browser (mugen's /login): a link, then a
// line of stdin, the code; the right one signs in as fresh@example.com
// (MUGEN_FAKE_LOG.acct, which `auth status` says from then on)
if (argv[0] === "auth") {
  const out = !!process.env.MUGEN_FAKE_SIGNED_OUT;
  const acct = (process.env.MUGEN_FAKE_LOG ?? "/nonexistent") + ".acct";
  const code = process.env.MUGEN_FAKE_LOGIN;
  if (argv[1] === "login" && code) {
    process.stdout.write("Opening browser to sign in…\nIf the browser didn't open, visit: \x1b]8;;https://claude.example/oauth?code=true&state=s1\x07https://claude.example/oauth?code=true&state=s1\x1b]8;;\x07\nPaste code here if prompted > ");
    for await (const line of console) {
      if (line.trim() === code) {
        fs.writeFileSync(acct, "fresh@example.com");
        console.log("Login successful.");
        process.exit(0);
      }
      console.log("Login failed: That code wasn't accepted. It may be incomplete, expired, already used, or from an earlier sign-in attempt. Sign in again to get a new code.");
      process.exit(1);
    }
    process.exit(1);
  }
  const email = fs.existsSync(acct) ? fs.readFileSync(acct, "utf8") : undefined;
  console.log(argv[1] === "status" ? JSON.stringify({ loggedIn: !out, authMethod: out ? "none" : "claude.ai", ...(email ? { email, subscriptionType: "max" } : {}) }) : "fake " + argv.slice(1).join(" "));
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
const agent = system.startsWith("You are a subagent of mugen");
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

// Claude Code's own commands, as it knows a message for one: its last text
// block's start ("/goal x" is one, " /goal x" and "/goalx" are not)
const commands = new Set(["goal", "model", "status", "plan", "login", "logout", "help", "compact", "clear", "cost", "config", "context", "doctor", "effort", "exit", "export", "init", "memory", "mcp", "permissions", "resume", "review", "version", "usage"]);
const lastText = (m: any) => {
  const c = m.message.content;
  const ts = typeof c === "string" ? [c] : c.filter((b: any) => b.type === "text").map((b: any) => b.text);
  return ts.length === 0 ? "" : ts[ts.length - 1];
};
const command = (m: any) => {
  const t = lastText(m);
  const w = /^\/([a-z][a-z-]*)(\s|$)/.exec(env.MUGEN_FAKE_TRIM ? t.trimStart() : t);
  return w !== null && commands.has(w[1]) ? w[1] : undefined;
};
// a message mugen's wait is tried on: lost as it comes during a turn
const dropped = (m: any) => !!env.MUGEN_FAKE_DROP && lastText(m).includes(env.MUGEN_FAKE_DROP);

// the ids of the turn's messages, for its result
let took: string[] = [];

// the user messages waiting, said back as taken; a command waits on
const take = () => {
  const blocks: any[] = [];
  const keep: any[] = [];
  while (queue.length > 0) {
    const m = queue.shift();
    if (command(m) !== undefined) {
      keep.push(m);
      continue;
    }
    if (dropped(m)) {
      continue;
    }
    out({ type: "user", message: m.message, uuid: m.uuid, isReplay: true });
    took.push(m.uuid);
    blocks.push(...m.message.content);
  }
  queue.unshift(...keep);
  return blocks;
};

// a turn: steps till one ends it, its result last
const turn = async () => {
  let tries = 0;
  let replies = "";
  for (;;) {
    const body = { model, max_tokens: 128000, system: [{ type: "text", text: system }], output_config: { effort }, ...(chat ? { tools } : {}), messages: structuredClone(messages) };
    const a = await ask(body);
    // a usage limit hit, as Claude Code says it: the limits rejected till a
    // time (resetsIn seconds from now), its words as a reply, a failed result
    if (a.limit) {
      const at = Math.floor(Date.now() / 1000) + Number(a.limit.resetsIn ?? 0);
      out({ type: "rate_limit_event", rate_limit_info: { status: "rejected", resetsAt: at, rateLimitType: "five_hour", unifiedWindows: { five_hour: { utilization: 1, resetsAt: at, status: "rejected" } } } });
      out({ type: "assistant", message: { id: "msg_limit", type: "message", role: "assistant", model: "<synthetic>", content: [{ type: "text", text: a.limit.text }], stop_reason: "stop_sequence", usage } });
      out({ type: "result", subtype: "success", is_error: true, result: a.limit.text, stop_reason: null, usage });
      return;
    }
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
      out({ type: "result", subtype: "success", is_error: false, result: replies, stop_reason: m.stop_reason, num_turns: 1, usage, user_message_uuids: took });
      return;
    }
    const results: any[] = [];
    for (const u of uses) {
      const r = await rpc("tools/call", { name: u.name, arguments: u.input });
      const parts: any[] = r.result?.content ?? [];
      const text = parts.filter((c: any) => c.type !== "image").map((c: any) => c.text).join("");
      // images pass on as Claude Code passes an MCP image: an image block
      const pics = parts.filter((c: any) => c.type === "image").map((c: any) => ({ type: "image", source: { type: "base64", media_type: c.mimeType, data: c.data } }));
      results.push({ type: "tool_result", tool_use_id: u.id, content: [...(text === "" ? [] : [{ type: "text", text }]), ...pics], is_error: r.result?.isError === true });
    }
    out({ type: "user", message: { role: "user", content: results }, uuid: crypto.randomUUID() });
    // (a message mugen writes as it answers the tool comes with the results,
    // as Claude Code's next request takes it: stdin read first)
    await Bun.sleep(100);
    messages.push({ role: "user", content: [...results, ...take()] });
  }
};

// each message a turn of its own; those that come during one follow its
// next tool results; a command answered by Claude Code itself; a lost one
// (MUGEN_FAKE_DROP, past the first) nothing
let firstOne = true;
for (let m = await next(); m !== undefined; m = await next()) {
  if (!firstOne && dropped(m)) {
    continue;
  }
  firstOne = false;
  const name = command(m);
  if (name !== undefined) {
    const said = "/" + name + " isn't available in this environment.";
    out({ type: "assistant", message: { id: crypto.randomUUID(), type: "message", role: "assistant", model: "<synthetic>", content: [{ type: "text", text: said }], stop_reason: "end_turn", usage }, parent_tool_use_id: null, local_command_source: "<local-command-stdout>" + said + "</local-command-stdout>", local_command_outcome: { kind: "unavailable_headless" } });
    out({ type: "result", subtype: "success", is_error: false, result: said, stop_reason: null, num_turns: 0, usage, user_message_uuids: [m.uuid] });
    continue;
  }
  out({ type: "user", message: m.message, uuid: m.uuid, isReplay: true });
  took = [m.uuid];
  messages.push({ role: "user", content: m.message.content });
  await turn();
}
process.exit(0);
