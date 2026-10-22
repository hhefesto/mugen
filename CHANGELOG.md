# Changelog

A version changes when surface behavior does (AGENTS.md, Versions).

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
  guide is served by GitHub Pages: https://hhefesto.github.io/mugen/guide.html.

## 0.2.1 (2026-10-21)

- `M-o` folds or opens all blocks (`C-o` still does, unless tmux takes it as
  its prefix, as it does on olimpo).

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
