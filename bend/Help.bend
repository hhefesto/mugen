
import Base

# Help: /help's pages, as markdown (the screen wraps them to its width, a
# block a click or M-o folds; off the full screen they print as they are).
# /help alone is the index: the keys used most, and the topics; /help
# TOPIC one topic (Tab completes it); /help all every one. M-? opens the
# index. bend/tests/HelpCheck.bend fails when a command (Edit.bend
# ed.words) or a key the screen takes (Screen.bend sc.key.k) is named
# nowhere here.
#
# Every def is prefixed `hl.`.

# a topic: its name (/help NAME), what it covers in a few words, its text
type hl.Topic is Data:
  hl.Topic{name: String, about: String, text: String}

def hl.topic.name(t: hl.Topic) -> String:
  match t:
    case hl.Topic{n, a, x}:
      n

def hl.topic.about(t: hl.Topic) -> String:
  match t:
    case hl.Topic{n, a, x}:
      a

def hl.topic.text(t: hl.Topic) -> String:
  match t:
    case hl.Topic{n, a, x}:
      x

def hl.lines(+ls: List<&2, String>) -> String:
  String.join(ls, "\n")

# The topics ---------------------------------------------------------------------

def hl.writing() -> String:
  hl.lines([
    "## Writing",
    "- `Enter` sends. `Alt-Enter` makes a new line: that one works in every terminal. `Shift-Enter` and `C-j` do too where the terminal sends them apart from `Enter` (many don't), and so does a `\\` at the end of the text before `Enter`.",
    "- A paste comes whole, as one message, newlines and all.",
    "- Emacs keys: `C-a`, `C-e`, `C-k`, `C-u`, `C-w`, `C-y`, `M-b`, `M-f`, `M-d`; `Home` and `End` in a text go to its line's start and end.",
    "- History: `↑`, `↓`, `C-p`, `C-n`; `C-r` searches it (`C-r` again finds an older match, `C-g` or `Esc` gives up, any other key keeps what it found). It is kept in `$MUGEN_DIR/history`.",
    "- `Tab` completes a command (`/he` → `/help`), and a topic of `/help` or a word of yours for `/words rm`.",
    "- `C-c` clears the text (`C-y` brings it back); on an empty input it leaves.",
    "- `/image PATH` (or `/image` alone, for the clipboard's image) puts an image in the message being written, as a line `[image docs/images/NAME]`.",
    "- The input is spellchecked as you write: `/help spell`."])

def hl.working() -> String:
  hl.lines([
    "## While mugen works",
    "- A message you send while mugen works waits, and the line `⧗ 1 waiting` under the chat says so. mugen reads it at its next tool call or when its turn ends.",
    "- `↑` on an empty input takes a waiting message back to edit, until mugen reads it. Only the version you send at last is logged.",
    "- `C-s` (`/now`) sends the waiting messages now: a shell command mugen runs is cut, and mugen gets its output with your messages; else its turn stops and a new one starts with them.",
    "- `C-g` (`/stop`) stops mugen's turn and its agents; `/stop NAME` one agent, `/stop !` your own `!` command.",
    "- `/goal TEXT`: mugen works toward it, turn after turn, until a check finds it met. `/halt` drops it.",
    "- Under the chat: what runs and for how long, the messages waiting, the status line (the model, its effort, the context left, the mode), then the input.",
    "- Whatever is running when you leave goes on at the next start."])

def hl.reading() -> String:
  hl.lines([
    "## Reading the chat",
    "- `PgUp`, `PgDn` and the wheel scroll. On an empty input `Home` (or `M-<` anywhere) goes to the top, `End` (or `M->`) back to the end.",
    "- While you are scrolled up, nothing new moves what you read; `M->` follows the end again.",
    "- A click on a block folds or opens it; `M-o` (or `C-o`, unless tmux takes it as its prefix) folds or opens all of them.",
    "- Drag over the chat to select text: letting go copies it to the clipboard (by xclip) and to tmux's buffer, and a line says how much. `Shift`-drag is the terminal's own selection.",
    "- `/mouse` hands the mouse to the terminal, and back.",
    "- `C-l` draws the screen anew.",
    "- `/tree` writes the memory tree as a page (`$MUGEN_DIR/tree.html`); `/export` the memory as `./mugen-memory.json`."])

def hl.spell() -> String:
  hl.lines([
    "## Spellcheck",
    "- As you write, a word hunspell (en_US) doesn't know is underlined in red. Not checked: the word being written, code in backticks, a `!` command, paths, URLs, addresses, and words with a digit, a `_` or camelCase.",
    "- Point at a red word with the mouse, or put the cursor in it, and a box over it shows up to five suggestions, the first lit. `M-s` takes that one, `M-1` to `M-5` (or a click) the one numbered, `Esc` closes the box. `M-S` fixes every red word with its first suggestion.",
    "- **Your words.** `M-a` on a red word adds it to your words, and its red underline goes away; `M-a` on a word of yours takes it out again. The box's `+ add` row does what `M-a` does. A word in the dictionary already stays as it is.",
    "- Your words are hunspell's own list, `~/.hunspell_en_US` (one word a line), so they count in every mugen chat. A word is kept in lowercase, which lets it come capitalized too, as `Telomare` at a sentence's start; one with a capital after its first letter, as `GitHub` or `OAuth`, is kept as written.",
    "- `/words` lists your words; `/words add WORD…` and `/words rm WORD…` add and take out words you can't put the cursor on; `Tab` completes the words of `/words rm`.",
    "- `/spell off` and `/spell on` turn the spellcheck off and on; `/spell` alone switches it. It needs `hunspell` and its `en_US` dictionary (mugen's package brings both), and says once if it can't run them.",
    "- In tmux the underline is curly where tmux knows the terminal draws it (`/help setup`), else straight."])

def hl.modes() -> String:
  hl.lines([
    "## Modes and models",
    "- `/plan`: plan mode, mugen reads and proposes, changing nothing. `/auto`: auto mode, it runs its tools as it needs them. `Shift-Tab` switches between them; the status line shows which.",
    "- `/model LABEL`: `opus-5.5`, `sonnet-5.5`, `haiku-5.5`, or a model id.",
    "- `/effort low|medium|high|xhigh|max`: how hard it thinks.",
    "- `/goal TEXT` and `/halt`: `/help working`.",
    "- `/status`: the account, the plan's limits, the chat and its view, the model and the mode, the summaries and the agents."])

def hl.agents() -> String:
  hl.lines([
    "## Agents",
    "- mugen starts subagents for work it can split (when you ask it to). While they work, tabs follow the status line: `all`, `mugen`, and one for each agent (`●` while it works).",
    "- A click on a tab, or `M-←` and `M-→`, shows only that one's blocks; `all` shows the whole chat again.",
    "- An agent's tab shows its whole log, read as the tab opens, so `Home` there reaches its first message however long it ran.",
    "- Each agent's report comes back to the chat as a block of its own.",
    "- `/stop NAME` stops one agent; `C-g` stops them all with the turn."])

def hl.shell() -> String:
  hl.lines([
    "## Your own shell commands",
    "- `!COMMAND` runs a shell command of yours at once, whether mugen works or not, in the directory you started mugen in, by a fresh `$SHELL` (a `cd` doesn't last).",
    "- Its output shows as a block of yours, and goes into the chat as your message, so mugen reads it at its next turn. It starts no turn by itself.",
    "- One runs at a time; `/stop !` (or `/stop`) kills it."])

def hl.commands() -> String:
  hl.lines([
    "## Commands",
    "- `!COMMAND`: run a shell command of yours (`/help shell`)",
    "- `/stop [NAME]`: stop the turn, or one agent (`!`: your command); `C-g`",
    "- `/now`: send the waiting messages now; `C-s`",
    "- `/goal TEXT`, `/halt`: set a goal mugen works toward, or drop it",
    "- `/model LABEL`, `/effort LEVEL`: the chat's model and its effort",
    "- `/plan`, `/auto`: plan mode, auto mode; `Shift-Tab`",
    "- `/status`: the account, limits, view, model, mode, summaries and agents",
    "- `/tree`: the memory tree as a page; `/export`: the memory as `./mugen-memory.json`",
    "- `/mouse`: the mouse to the terminal (and back)",
    "- `/image [PATH]`: an image with the message being written",
    "- `/spell [on|off]`: the spellcheck",
    "- `/words`, `/words add WORD…`, `/words rm WORD…`: your words (`/help spell`)",
    "- `/help [TOPIC|all]`: this help; `M-?`",
    "- `/quit`: leave; `Esc Esc`, `C-d`, or `C-c` on an empty input",
    "`/mouse`, `/image`, `/spell` and `/words` work on the full screen only, not with `MUGEN_PLAIN`."])

def hl.setup() -> String:
  hl.lines([
    "## Setup",
    "- `mugen login` signs Claude Code in (the default backend, on a Claude plan); `mugen --api` uses the Messages API with `ANTHROPIC_API_KEY`. `mugen --version` says the version.",
    "- `MUGEN_DIR` (default `~/.mugen`) is one chat, and one mugen holds it. For another chat beside it: `MUGEN_DIR=~/.mugen-2 mugen`.",
    "- `MUGEN_PLAIN=1` (or `TERM=dumb`, as in Emacs' shell) goes without the full screen: lines as they come, and a message of many lines between two lines of `\"\"\"`. From a pipe, each line is a message.",
    "- `MUGEN_PICK`, `MUGEN_RULES` (your instructions, default `$MUGEN_DIR/rules.md`) and the other settings: the README's Settings table.",
    "- tmux: mugen names its window, rings its bell when a reply comes while you look elsewhere, and turns `extended-keys` on. For the spellcheck's curly underline tmux needs its `usstyle` feature, e.g. `set -as terminal-features ',xterm-256color:usstyle'`; a client that attached before the setting needs to attach again.",
    "- From a phone: ssh or mosh into tmux (the README's Tailscale section). A swipe scrolls the chat.",
    "- The guide covers all of it: https://mugen.hhefesto.dev/guide.html"])

def hl.topics() -> List<&2, hl.Topic>:
  [hl.Topic{"writing", "the input: new lines, pastes, emacs keys, history, Tab", hl.writing()},
   hl.Topic{"working", "while mugen works: waiting messages, `↑`, `C-s`, `C-g`, goals", hl.working()},
   hl.Topic{"reading", "scrolling, `Home` and `End`, folding, selecting to copy", hl.reading()},
   hl.Topic{"spell", "the spellcheck, and your words (`M-a`, `/words`)", hl.spell()},
   hl.Topic{"modes", "plan and auto, `Shift-Tab`, the model, the effort", hl.modes()},
   hl.Topic{"agents", "the agents' tabs", hl.agents()},
   hl.Topic{"shell", "`!COMMAND`, your own shell commands", hl.shell()},
   hl.Topic{"commands", "every command, in a list", hl.commands()},
   hl.Topic{"setup", "`MUGEN_DIR`, `MUGEN_PLAIN`, tmux, the phone", hl.setup()}]

# The pages ------------------------------------------------------------------------

def hl.toc(ts: List<&2, hl.Topic>) -> List<&2, String>:
  match ts:
    case []:
      []
    case +t <> rest:
      ("- `" ++ hl.topic.name(t) ++ "`: " ++ hl.topic.about(t)) <> hl.toc(rest)

def hl.index() -> String:
  hl.lines(List.append(&2, String, [
    "## mugen: one chat that never ends",
    "Write a message and press `Enter`. The keys you'll use most:",
    "- `Enter` sends; `Alt-Enter` makes a new line",
    "- `C-g` stops mugen; `C-s` sends the messages waiting now",
    "- `↑` on an empty input takes a waiting message back to edit",
    "- `PgUp`, `PgDn` and the wheel scroll; on an empty input `Home` goes to the top, `End` to the end",
    "- a click folds or opens a block; `M-o` all of them",
    "- `Shift-Tab` switches plan and auto mode",
    "- `M-s` fixes a red word; `M-a` adds it to your words",
    "- `Esc Esc` leaves (what runs goes on at the next start)",
    "`/help TOPIC` for more (`Tab` completes it), `/help all` for everything, `M-?` for this page again:"], hl.toc(hl.topics())))

def hl.texts(ts: List<&2, hl.Topic>) -> List<&2, String>:
  match ts:
    case []:
      []
    case +t <> rest:
      hl.topic.text(t) <> hl.texts(rest)

# every topic, one after another
def hl.all() -> String:
  String.join(hl.texts(hl.topics()), "\n\n")

def hl.find(ts: List<&2, hl.Topic>, +name: String) -> Maybe<&2, hl.Topic>:
  match ts:
    case []:
      None{}
    case +t <> rest:
      Bool.pick(Maybe<&2, hl.Topic>, String.eq(hl.topic.name(t), name), Some{t}, hl.find(rest, name))

def hl.names(ts: List<&2, hl.Topic>) -> List<&2, String>:
  match ts:
    case []:
      []
    case +t <> rest:
      hl.topic.name(t) <> hl.names(rest)

def hl.page.of(m: Maybe<&2, hl.Topic>, +arg: String) -> String:
  match m:
    case Some{t}:
      hl.topic.text(t)
    case None{}:
      "No help topic `" ++ arg ++ "`; the topics are " ++ String.join(hl.names(hl.topics()), ", ") ++ ", and `all`.\n\n" ++ hl.index()

# /help ARG's page: "" the index, "all" everything, else the topic named
def hl.page(+arg: String) -> String:
  +a = String.trim(arg)
  Bool.pick(String, String.is_empty(a), hl.index(), Bool.pick(String, String.eq(a, "all"), hl.all(), hl.page.of(hl.find(hl.topics(), a), a)))

def hl.cmds.of(ns: List<&2, String>) -> List<&2, String>:
  match ns:
    case []:
      []
    case +n <> rest:
      ("/help " ++ n) <> hl.cmds.of(rest)

# what Tab completes after /help
def hl.cmds() -> List<&2, String>:
  List.append(&2, String, hl.cmds.of(hl.names(hl.topics())), ["/help all"])
