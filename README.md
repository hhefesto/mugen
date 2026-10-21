# mugen (無限)

One chat with an AI that never ends, in your terminal: *mugen* (無限) is
Japanese for "endless". It is Victor Taelin's
[UniiChat](https://github.com/VictorTaelin/uniichat) written in
[Bend 2](https://github.com/HigherOrderCO/bend).

Every message is logged verbatim, forever. A cheap model folds the log into a
binary tree of one-line summaries (at most 512 bytes each). Each turn is a
fresh API call that sees a 64 to 128 KB *view* of that tree, with recent
messages in detail and old ones coarse, and it `zoom`s into the tree whenever
it needs more. The chat runs tools on this computer (`shell`, `read`,
`write`, `edit`), starts subagents (`spawn`, `tell`), works toward a `/goal`,
and searches the web.

## Run

```sh
export ANTHROPIC_API_KEY=...   # curl reads it; it never appears in argv
nix run github:hhefesto/mugen  # or `nix run .` in a checkout
```

Status: every test runs offline, against a stand-in for the API (see
Develop); mugen has not yet talked to the live API.

Type a message and press Enter. A message of many lines goes between two
lines of `"""`. Commands: `/stop [name]` (an empty line stops the turn),
`/goal TEXT`, `/halt`, `/model opus-5.5|sonnet-5.5|haiku-5.5`, `/effort
low..max`, `/status`, `/help`, `/quit`. Whatever is running when you quit
resumes at the next start.

From a pipe (stdin not a terminal), each line is a message, and mugen
exits once stdin ends and nothing is running.

Leave with `/quit` (or Ctrl-D): it kills every process the tools started.
Ctrl-C kills mugen at once, and a shell job running then (in its own
process group) can outlive it.

## Settings (environment)

| Variable | Default | |
|---|---|---|
| `MUGEN_DIR` | `~/.mugen` | the chat: `main/`, `tree/`, `view.json`, agents' logs |
| `MUGEN_WORK` | `$MUGEN_DIR/work` | the tools' work dir, a dir per agent |
| `MUGEN_PICK` | `opus-5.5:medium:slow` | the chat's model, effort and speed |
| `MUGEN_COMPACTOR` | `haiku-5.5:high:slow` | the summaries' model |
| `MUGEN_RULES` | `$MUGEN_DIR/rules.md` | your instructions, appended to the system prompt |
| `MUGEN_JOBS` | `48` | summaries at once |
| `MUGEN_SYNC` | `1` | fsync each log write |
| `MUGEN_MAX_TOKENS` | `16000` | a reply's most tokens |
| `MUGEN_WEB_SEARCH` | `web_search_20260209` | the web search tool's type |

The data dir is UniiChat's format (`users/<id>/` there), so either program
can open the other's chat.

## Develop

`nix develop`, then see [AGENTS.md](AGENTS.md) for the layout, the tests
(`nix flake check` runs them all, including a step-for-step differential
test against UniiChat's own `Memory.ts`), and the Bend 2 pitfalls that shaped
the code.

## License

Apache 2.0, like UniiChat. mugen ports UniiChat's design and code to Bend 2
and carries its prompts verbatim (`bend/Prompts.bend`, generated from
UniiChat's `prompt.txt`).
