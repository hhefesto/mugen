# Changelog

A version changes when surface behavior does (AGENTS.md, Versions).

## 0.5.0 (2026-10-22)

- OpenAI's models: a pick of one (`/model gpt-6.1-sol`, `gpt-6-astra`,
  `gpt-6-luna` or an OpenAI id; `MUGEN_PICK`, `MUGEN_AGENTS`,
  `MUGEN_COMPACTOR`) runs on OpenAI's Responses API by curl, on either
  backend, in mugen's own tool loop (UniiChat's `openai-api`): store off,
  reasoning kept across turns, the view's mark a prompt-cache breakpoint,
  `fast` the priority tier. Its key: `OPENAI_API_KEY`, or the file
  `MUGEN_OPENAI_KEY_FILE` names (`~/.mugen/openai.key`), read by curl at
  each call; with none, a call says so and makes none. The chat's pick is
  saved with vendor `openai-api`. Claude's picks run as before.
- `MUGEN_AGENTS`: the agents' model, effort and speed (unset: the chat's,
  as before).
- `/status` says which picks run on OpenAI's API, and the agents' pick;
  `/model` and `/effort` say where an OpenAI pick's key comes from.

## 0.4.0 (2026-10-21)

- `!COMMAND` runs a shell command of the user's, at once, in the directory
  mugen started in. Its output shows as a block of the user's (`[you]
  shell`), and the chat logs it as the user's message (the command, then
  its output, clipped as the shell tool's), for mugen to read at its next
  turn; it starts none. One at a time; `/stop !` (or `/stop`) kills it.
- A swipe scrolls on phones whose terminal reports the wheel with modifier
  bits set (Conduit and other xterm.dart apps send 68/69, a Shift-wheel):
  the mouse's Shift, Meta and Ctrl bits are dropped.

## 0.3.0 (2026-10-21)

- A message sent while mugen works is held, not logged, until mugen reads
  it (at its next tool call, its turn's end, or `/now`); `↑` on an empty
  input takes the newest back to edit (`/back`), so only the version sent
  at last is logged and shown (the history file keeps both). A message shows
  in the chat once it is logged.
- Diffs: each line taken out is on red, each one added on green (tool
  diffs and ```diff code in replies).
- Agent tabs: while subagents work, `all · mugen · each agent` follow the
  status line; a click on one, or `M-←` / `M-→`, shows only its blocks.
- Docs: `Alt-Enter` is the new line that works everywhere (`Shift-Enter`
  and `C-j` only where the terminal sends them apart from `Enter`). The
  guide is served by GitHub Pages: https://mugen.hhefesto.dev/guide.html.

## 0.2.1 (2026-10-21)

- `M-o` folds or opens all blocks (`C-o` still does, unless tmux takes it as
  its prefix, as with `set -g prefix C-o`).

## 0.2.0 (2026-10-21)

- Images: `/image PATH` (or `/image` alone, the clipboard's) attaches one to
  the message being written; the turn's call sends the images its new
  messages name, `zoom(id, 1)` gives a message's images, and `read` gives an
  image file whole (png, jpeg, gif, webp, 5 MB at most).
- Blocks on the full screen come open (unfolded); a click or `C-o` folds.

## 0.1.0 (2026-10-21)

The first numbered version: everything up to it, plus:

- `mugen --version` (or `-V`) says the version.
- The status line above the prompt no longer shows the work dir (always
  `~/.mugen/work/main`); `/status` still does.
