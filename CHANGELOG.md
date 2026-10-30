# Changelog

A version changes when surface behavior does (AGENTS.md, Versions).

## 0.10.1 (2026-10-30)

- `M-p` (`M-↑`, `M-{`) goes on back through every answer of the chat: it
  stopped at the oldest answer the screen still had, the newest 400
  blocks (60 messages when mugen opens), so a turn of many tool calls hid
  the answers before it. The chat now keeps its messages and answers past
  those 400 blocks (tool calls still go), and past the oldest it has,
  `M-p` reads the answer before it, and the message it answers, from the
  chat's log.

## 0.10.0 (2026-10-30)

- `M-p` and `M-n` (as in Emacs; or `M-↑` and `M-↓`, or `M-{` and `M-}`)
  go to mugen's answer before and after the one you read, past its
  thoughts, its tool calls and what they said: the answer comes to the
  chat's top, under the pinned message it answers. Past the last one,
  `M-n` goes to the end; on an agent's tab they go through that agent's
  answers. The pinned message is now the newest at or above the chat's top
  row (it was the newest above it), so an answer's own message is the one
  pinned over it.
- `/login` signs Claude Code in again from inside the chat, to switch
  accounts: it runs `claude auth login` in the background and shows its
  link (copied too, on the full screen); sign in there with the account you
  want, and if the page shows a code, paste it as `/login CODE`. mugen says
  who is signed in once it ends (and `/status` names that account); the
  chat's next call goes with it. A wrong code fails and changes nothing; a
  sign-in waits half an hour at most, and a new `/login` ends the one
  before it.

## 0.9.0 (2026-10-25)

- `mugen logout` signs Claude Code out (`claude auth logout`). `mugen
  login` first says who is signed in now, if anyone (the email, the plan),
  and that signing in again switches to the account you sign in with
  (issue #2).
- Copying a selection outside tmux also sends it to the terminal's own
  clipboard, as an OSC 52, so copying works where there is no xclip or no
  X: Windows Terminal (WSL; issue #2), kitty, WezTerm, foot, iTerm2, and
  over ssh. The line under the chat says `✓ sent 3 lines to the
  terminal's clipboard` when that is the only place it went (a terminal
  that refuses OSC 52 gives no sign). In tmux, tmux's buffer carries it to
  the terminal as before.

## 0.8.2 (2026-10-25)

- mugen no longer quits at a key or a click while a shell tool runs where
  `sh` is dash (Ubuntu, Debian; issue #1). Under dash, `set -m` in the
  shell tool's wrapper took mugen's terminal, mugen's next read of it
  failed, and that was taken for the end of input. The shell tool now runs
  without job control under `setsid`: a session of its own, so stopping
  it still kills all of it, and no terminal, so nothing it runs can take
  mugen's, read its keys or draw over the screen (a prompt for a password
  fails at once instead of waiting). Claude Code's launch and the watchdog
  keep `set -m`, run by bash. And a failed read of the terminal ends
  mugen only when the terminal is gone: while another process group holds
  it, mugen waits for it back (the keys typed meanwhile come then), and
  takes it back if that group died holding it. The Nix package puts bash
  and util-linux (`setsid`) after the PATH it is given, for systems
  without them.

## 0.8.1 (2026-10-24)

- A markdown table in a reply is drawn as a table: box lines, each column
  as wide as its widest cell, the header bold, the colons of its row of
  dashes aligning a column (`--:` right, `:-:` centered). Too wide for
  the screen, its widest columns are narrowed and their cells wrap, a
  line between rows; on a screen too narrow even for that, its lines show
  as they came, as before.

## 0.8.0 (2026-10-23)

- Your words for the spellcheck: `M-a` on a red word adds it to them (its
  underline goes at once), `M-a` on a word of yours takes it out again,
  and the suggestions' box has a `+ add` row that does the same. They are
  hunspell's own list, `~/.hunspell_en_US`, so every mugen chat (and
  anything else running hunspell) shares them; a word is kept in
  lowercase unless it has a capital after its first letter. `/words`
  lists them, `/words add WORD…` and `/words rm WORD…` change them (`Tab`
  completes the words of `/words rm`). mugen never writes a `*word` line
  (one marking a dictionary word wrong), nor takes one out.
- `/help` is remade: alone, the keys used most and nine topics (`writing`,
  `working`, `reading`, `spell`, `modes`, `agents`, `shell`, `commands`,
  `setup`); `/help TOPIC` one (`Tab` completes it), `/help all` every one.
  It shows as markdown wrapped to the screen (it was cut at the screen's
  width), in a block a click or `M-o` folds; `M-?` opens it. A test
  (`help`) fails when a command or a key has no word in it.

## 0.7.0 (2026-10-23)

- The input is spellchecked as you write: a word hunspell (en_US) doesn't
  know is underlined in red (curly where the terminal draws it). Not
  checked: the word being written, code in backticks, `!` commands, paths,
  URLs, addresses, words with digits, `_` or camelCase. The mouse on a red
  word (or the cursor in it) shows up to five suggestions in a box over it:
  `M-s` takes the first, `M-1`..`M-5` or a click the one numbered, `Esc`
  closes the box; `M-S` replaces every red word with its first suggestion.
  `/spell on|off`. The package brings hunspell and its dictionary; without
  them the spellcheck turns itself off and says so once. mugen now asks the
  terminal for the mouse's moves (mode 1003) too.
- `Shift-Tab` switches plan and auto mode (`/plan`, `/auto`), as in Claude
  Code.
- `Home` on an empty input goes to the chat's top (as `M-<`), the mirror of
  `End`; in a text it is still its line's start. `M-<` reached the top no
  more (the rows scrolled up wrapped a U32); it does again. An agent's tab
  shows the agent's whole log, read as the tab opens, so `Home` there
  reaches its first message however long it ran.
- Alt-Shift and a letter in kitty's keys (CSI u) is `M-` and the upper
  letter, as `ESC S` says it plain.

- Bend is upstream's (bendlang/bend 2.0.38) instead of the ft-kernels fork,
  behind a wrapper that turns telemetry off. The app is unchanged, so the
  version is too. (A move to ekapkgs, 93835a8, was reverted: too green yet.)

## 0.6.0 (2026-10-22)

(0.5.0 is the frozen `openai` branch's, never on master.)

- Scrolled up, the view holds: the chat's top row stays put while output
  comes below it (a result filling in under its call moved it before; a
  new block did not). At the end, the chat follows as before.
- A copy by dragging says where it went, in green under the chat (`✓
  copied 3 lines to the clipboard`, or to tmux's buffer only), or in red
  that it went nowhere (no X display for xclip, no tmux).
- Conduit noticed: when mugen starts, or a client of another width takes
  over, it asks tmux for the client's terminal type; Conduit has none, and
  mugen says `Conduit noticed: swipe to scroll` (or to turn `/mouse` on
  first) under the chat.

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
