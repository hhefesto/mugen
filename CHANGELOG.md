# Changelog

A version changes when surface behavior does (AGENTS.md, Versions).

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
