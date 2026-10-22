# The README's demo: a real Claude session, recorded with vhs.
#   nix run nixpkgs#vhs -- docs/demo.tape
# It runs mugen in a fresh MUGEN_DIR, its work dir a copy of bend/. mugen
# launches two agents; their blocks and tabs show while they work, and
# their reports come back to it.
Output docs/demo.gif
Set Shell bash
Set FontSize 15
Set Width 1280
Set Height 760
Set Padding 16
Set TypingSpeed 30ms
Set PlaybackSpeed 2
Set Theme "Catppuccin Mocha"

Hide
Type "rm -rf /tmp/mugen-demo && mkdir -p /tmp/mugen-demo/w/main && cp -r bend/*.bend /tmp/mugen-demo/w/main/ && clear"
Enter
Type "MUGEN_DIR=/tmp/mugen-demo/d MUGEN_WORK=/tmp/mugen-demo/w mugen"
Enter
Sleep 3s
Show
Sleep 1s
Type "Launch two agents at once: one finds the biggest of these Bend files, the other counts the defs in Hub.bend. Then sum up in one line beginning with 'Together:'"
Sleep 500ms
Enter
Wait+Screen@180s /at work/
Sleep 3s
Wait+Screen@400s /Together: [A-Za-z0-9`*]/
Sleep 6s
