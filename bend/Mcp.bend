
import Base
import ./Json.bend as J

# Mcp: our tools as an MCP server, for Claude Code's calls (UniiChat's
# Tools.answer): JSON-RPC, a message a line, read and answered by the call
# that runs them (Agent.bend ag.cc), through the relay Claude Code starts
# (Code.bend cc.mcp). A notification gets no answer; a tool's result is its
# text, whether it failed.
#
# Every def is prefixed `mc.` (a program's defs share one namespace).

def mc.s(+j: J.Json, +k: String) -> String:
  Maybe.default(&2, String, J.js.str(j, k), "")

# a tool's definition, as MCP lists it (the API's input_schema, inputSchema)
def mc.tool(+d: J.Json) -> J.Json:
  J.JObj{[J.JKv{"name", J.JStr{mc.s(d, "name")}}, J.JKv{"description", J.JStr{mc.s(d, "description")}},
    J.JKv{"inputSchema", Maybe.default(&2, J.Json, J.js.field(d, "input_schema"), J.JObj{[]})}]}

def mc.tools(ds: List<&2, J.Json>) -> List<&2, J.Json>:
  match ds:
    case []:
      []
    case +d <> t:
      mc.tool(d) <> mc.tools(t)

def mc.id(+m: J.Json) -> J.Json:
  Maybe.default(&2, J.Json, J.js.field(m, "id"), J.JNull{})

def mc.params(+m: J.Json) -> J.Json:
  Maybe.default(&2, J.Json, J.js.field(m, "params"), J.JObj{[]})

# 0 a notification (no answer), 1 initialize, 2 tools/list, 3 tools/call, 4
# ping, 5 none such
def mc.kind(+m: J.Json) -> Nat:
  +method = mc.s(m, "method")
  Bool.pick(Nat, Maybe.is_none(&2, J.Json, J.js.field(m, "id")), 0n,
    Bool.pick(Nat, String.eq(method, "initialize"), 1n, Bool.pick(Nat, String.eq(method, "tools/list"), 2n,
      Bool.pick(Nat, String.eq(method, "tools/call"), 3n, Bool.pick(Nat, String.eq(method, "ping"), 4n, 5n)))))

def mc.answer(+id: J.Json, +result: J.Json) -> String:
  J.js.write(J.JObj{[J.JKv{"jsonrpc", J.JStr{"2.0"}}, J.JKv{"id", id}, J.JKv{"result", result}]}) ++ "\n"

def mc.none(+id: J.Json, +method: String) -> String:
  J.js.write(J.JObj{[J.JKv{"jsonrpc", J.JStr{"2.0"}}, J.JKv{"id", id},
    J.JKv{"error", J.JObj{[J.JKv{"code", J.JNum{"-32601"}}, J.JKv{"message", J.JStr{"no method " ++ method}}]}}]}) ++ "\n"

def mc.init(+params: J.Json) -> J.Json:
  J.JObj{[J.JKv{"protocolVersion", J.JStr{Maybe.default(&2, String, J.js.str(params, "protocolVersion"), "2025-06-18")}},
    J.JKv{"capabilities", J.JObj{[J.JKv{"tools", J.JObj{[]}}]}},
    J.JKv{"serverInfo", J.JObj{[J.JKv{"name", J.JStr{"mugen"}}, J.JKv{"version", J.JStr{"1"}}]}}]}

def mc.listed(ds: List<&2, J.Json>) -> J.Json:
  J.JObj{[J.JKv{"tools", J.JArr{mc.tools(ds)}}]}

def mc.out(+text: String, fail: Bool) -> J.Json:
  J.JObj{[J.JKv{"content", J.JArr{[J.JObj{[J.JKv{"type", J.JStr{"text"}}, J.JKv{"text", J.JStr{text}}]}]}}, J.JKv{"isError", J.JBool{fail}}]}

# a tools/call's tool and input
def mc.name(+m: J.Json) -> String:
  mc.s(mc.params(m), "name")

def mc.input(+m: J.Json) -> J.Json:
  Maybe.default(&2, J.Json, J.js.field(mc.params(m), "arguments"), J.JObj{[]})

# a tool's name as Claude Code calls it, its server's prefix dropped
# (UniiChat's Call.ts MCP)
def mc.bare(+name: String) -> String:
  Bool.pick(String, String.starts_with(name, "mcp__mugen__"), String.drop(name, 12n), name)
